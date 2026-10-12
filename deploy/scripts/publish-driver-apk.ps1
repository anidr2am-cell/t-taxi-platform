[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ApkPath,
  [Parameter(Mandatory = $true)][string]$VersionName,
  [Parameter(Mandatory = $true)][int]$VersionCode,
  [string]$SshHost = 'tride-staging',
  [string]$RemoteDirectory = '/srv/tride/downloads',
  [string]$ExpectedCertificateSha256 = 'E250C0FCF3EA61DF09D9AEE86242159321EECAED6E7DE7B425E6EB34812892B5'
)

$ErrorActionPreference = 'Stop'

function Get-ApkSignerPath {
  if (Get-Command apksigner -ErrorAction SilentlyContinue) {
    return (Get-Command apksigner).Source
  }
  $androidRoot = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { $env:ANDROID_SDK_ROOT }
  if (-not $androidRoot) { throw 'ANDROID_HOME or ANDROID_SDK_ROOT is required to locate apksigner.' }
  $candidate = Get-ChildItem -Path (Join-Path $androidRoot 'build-tools') -Filter 'apksigner.bat' -Recurse |
    Sort-Object { [version]$_.Directory.Name } -Descending |
    Select-Object -First 1
  if (-not $candidate) { throw 'apksigner was not found in the Android SDK build-tools.' }
  return $candidate.FullName
}

function Normalize-Fingerprint([string]$Value) {
  return ($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
}

$resolvedApk = (Resolve-Path -LiteralPath $ApkPath).Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$templateRoot = Join-Path $repoRoot 'deploy\downloads'
$apksigner = Get-ApkSignerPath
$verification = & $apksigner verify --verbose --print-certs $resolvedApk 2>&1
if ($LASTEXITCODE -ne 0) { throw 'APK signature verification failed.' }
$digestLine = $verification | Where-Object { $_ -match 'certificate SHA-256 digest:\s*(.+)$' } | Select-Object -First 1
if (-not $digestLine) { throw 'APK signer certificate SHA-256 was not reported.' }
$digestMatch = [regex]::Match([string]$digestLine, 'certificate SHA-256 digest:\s*(.+)$')
if (-not $digestMatch.Success) { throw 'APK signer certificate SHA-256 could not be parsed.' }
$actualCertificate = Normalize-Fingerprint $digestMatch.Groups[1].Value
$expectedCertificate = Normalize-Fingerprint $ExpectedCertificateSha256
if ($actualCertificate -ne $expectedCertificate) {
  throw "APK signing certificate mismatch. Expected $expectedCertificate, got $actualCertificate."
}

$file = Get-Item -LiteralPath $resolvedApk
$sha256 = (Get-FileHash -LiteralPath $resolvedApk -Algorithm SHA256).Hash.ToUpperInvariant()
$bangkokNow = [DateTimeOffset]::Now.ToOffset([TimeSpan]::FromHours(7))
$publishedAt = $bangkokNow.ToString('yyyy-MM-ddTHH:mm:sszzz')
$publishedAtDisplay = $bangkokNow.ToString('yyyy-MM-dd HH:mm')
$fileSize = '{0:N1} MB' -f ($file.Length / 1MB)

$staging = Join-Path ([IO.Path]::GetTempPath()) ("trider-apk-publish-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $staging | Out-Null
try {
  $replacements = @{
    '{{VERSION_NAME}}' = $VersionName
    '{{VERSION_CODE}}' = [string]$VersionCode
    '{{FILE_SIZE}}' = $fileSize
    '{{FILE_SIZE_BYTES}}' = [string]$file.Length
    '{{SHA256}}' = $sha256
    '{{CERT_SHA256}}' = $actualCertificate
    '{{PUBLISHED_AT}}' = $publishedAt
    '{{PUBLISHED_AT_DISPLAY}}' = $publishedAtDisplay
  }
  foreach ($templateName in @('index.template.html', 'release.template.json')) {
    $content = Get-Content -LiteralPath (Join-Path $templateRoot $templateName) -Raw -Encoding UTF8
    foreach ($entry in $replacements.GetEnumerator()) { $content = $content.Replace($entry.Key, $entry.Value) }
    $outputName = $templateName.Replace('.template', '')
    Set-Content -LiteralPath (Join-Path $staging $outputName) -Value $content -Encoding UTF8 -NoNewline
  }

  ssh $SshHost "install -d -m 0755 '$RemoteDirectory'"
  if ($LASTEXITCODE -ne 0) { throw 'Unable to prepare the remote download directory.' }
  scp $resolvedApk "${SshHost}:${RemoteDirectory}/driver-app.apk.part"
  if ($LASTEXITCODE -ne 0) { throw 'Unable to upload the APK.' }
  scp (Join-Path $staging 'index.html') "${SshHost}:${RemoteDirectory}/index.html.part"
  if ($LASTEXITCODE -ne 0) { throw 'Unable to upload the download page.' }
  scp (Join-Path $staging 'release.json') "${SshHost}:${RemoteDirectory}/release.json.part"
  if ($LASTEXITCODE -ne 0) { throw 'Unable to upload the release metadata.' }

  $remoteCommand = @"
set -eu
actual=`$(sha256sum '$RemoteDirectory/driver-app.apk.part' | awk '{print `$1}' | tr '[:lower:]' '[:upper:]')
test "`$actual" = '$sha256'
chmod 0644 '$RemoteDirectory/driver-app.apk.part' '$RemoteDirectory/index.html.part' '$RemoteDirectory/release.json.part'
mv -f '$RemoteDirectory/driver-app.apk.part' '$RemoteDirectory/driver-app.apk'
mv -f '$RemoteDirectory/index.html.part' '$RemoteDirectory/index.html'
mv -f '$RemoteDirectory/release.json.part' '$RemoteDirectory/release.json'
"@
  ssh $SshHost $remoteCommand
  if ($LASTEXITCODE -ne 0) { throw 'Remote SHA-256 verification or atomic publish failed.' }
  Write-Output "Published version $VersionName+$VersionCode"
  Write-Output "SHA256=$sha256"
  Write-Output "CERT_SHA256=$actualCertificate"
} finally {
  Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
