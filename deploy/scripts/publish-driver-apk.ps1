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

$resolvedApk = (Resolve-Path -LiteralPath $ApkPath).Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$templateRoot = Join-Path $repoRoot 'deploy\downloads'
$remoteReleaseJson = ssh $SshHost "cat '$RemoteDirectory/release.json'"
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the currently published release metadata.' }
$publishedRelease = ($remoteReleaseJson -join "`n") | ConvertFrom-Json
$previousVersionCode = [int]$publishedRelease.versionCode
$previousVersionName = [string]$publishedRelease.versionName
if ($VersionCode -le $previousVersionCode) {
  throw "VersionCode $VersionCode must be greater than published versionCode $previousVersionCode."
}
if ($VersionName -notmatch '^[0-9A-Za-z._-]+$' -or $previousVersionName -notmatch '^[0-9A-Za-z._-]+$') {
  throw 'Release version names contain unsupported characters.'
}
$verification = & (Join-Path $repoRoot 'driver_app\scripts\verify-release-apk.ps1') `
  -ApkPath $resolvedApk `
  -ExpectedVersionName $VersionName `
  -ExpectedVersionCode $VersionCode `
  -PreviousVersionCode $previousVersionCode `
  -ExpectedCertificateSha256 $ExpectedCertificateSha256
if ($LASTEXITCODE -ne 0) { throw 'APK release verification failed before publish.' }
$verification | Write-Output
$certificateLine = $verification | Where-Object { $_ -like 'CERT_SHA256=*' } | Select-Object -First 1
if (-not $certificateLine) { throw 'Verified certificate fingerprint was not reported.' }
$actualCertificate = $certificateLine.Substring('CERT_SHA256='.Length)

$file = Get-Item -LiteralPath $resolvedApk
$sha256 = (Get-FileHash -LiteralPath $resolvedApk -Algorithm SHA256).Hash.ToUpperInvariant()
$bangkokNow = [DateTimeOffset]::Now.ToOffset([TimeSpan]::FromHours(7))
$publishedAt = $bangkokNow.ToString('yyyy-MM-ddTHH:mm:sszzz')
$publishedAtDisplay = $bangkokNow.ToString('yyyy-MM-dd HH:mm')
$fileSize = '{0:N1} MB' -f ($file.Length / 1MB)
$remoteParent = [regex]::Replace($RemoteDirectory.TrimEnd('/'), '/[^/]+$', '')
if (-not $remoteParent -or $remoteParent -eq $RemoteDirectory) { throw 'RemoteDirectory must be an absolute POSIX path.' }
$backupRoot = "$remoteParent/downloads-backup"
$backupStamp = $bangkokNow.ToString('yyyyMMdd-HHmmss')
$backupDirectory = "$backupRoot/$previousVersionName+$previousVersionCode-$backupStamp"

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
install -d -m 0755 '$backupDirectory'
ln '$RemoteDirectory/driver-app.apk' '$backupDirectory/driver-app.apk'
test -f '$backupDirectory/driver-app.apk'
if [ -f '$RemoteDirectory/index.html' ]; then cp '$RemoteDirectory/index.html' '$backupDirectory/index.html'; fi
if [ -f '$RemoteDirectory/release.json' ]; then cp '$RemoteDirectory/release.json' '$backupDirectory/release.json'; fi
mv -f '$RemoteDirectory/driver-app.apk.part' '$RemoteDirectory/driver-app.apk'
mv -f '$RemoteDirectory/index.html.part' '$RemoteDirectory/index.html'
mv -f '$RemoteDirectory/release.json.part' '$RemoteDirectory/release.json'
"@
  # PowerShell here-strings use CRLF on Windows. Normalize before passing the
  # script to a POSIX shell so carriage returns never become filename bytes.
  $remoteCommand = $remoteCommand.Replace("`r`n", "`n")
  ssh $SshHost $remoteCommand
  if ($LASTEXITCODE -ne 0) { throw 'Remote SHA-256 verification or atomic publish failed.' }
  Write-Output "Published version $VersionName+$VersionCode"
  Write-Output "SHA256=$sha256"
  Write-Output "CERT_SHA256=$actualCertificate"
  Write-Output "PREVIOUS_APK_BACKUP=$backupDirectory/driver-app.apk"
} finally {
  Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
