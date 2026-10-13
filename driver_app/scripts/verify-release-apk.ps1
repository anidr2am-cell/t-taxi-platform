[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ApkPath,
  [Parameter(Mandatory = $true)][string]$ExpectedVersionName,
  [Parameter(Mandatory = $true)][int]$ExpectedVersionCode,
  [Parameter(Mandatory = $true)][int]$PreviousVersionCode,
  [string]$ExpectedPackage = 'com.trider.driver',
  [string]$ExpectedCertificateSha256 = 'E250C0FCF3EA61DF09D9AEE86242159321EECAED6E7DE7B425E6EB34812892B5'
)

$ErrorActionPreference = 'Stop'

function Enable-AndroidJava {
  if (Get-Command java -ErrorAction SilentlyContinue) { return }
  $candidates = @(
    'C:\Program Files\Android\Android Studio\jbr',
    'C:\Program Files\Android\Android Studio\jre'
  )
  $javaHome = $candidates | Where-Object { Test-Path (Join-Path $_ 'bin\java.exe') } | Select-Object -First 1
  if (-not $javaHome) { throw 'Java was not found. Install Android Studio or set JAVA_HOME.' }
  $env:JAVA_HOME = $javaHome
  $env:Path = "$(Join-Path $javaHome 'bin');$env:Path"
}

function Get-AndroidSdkRoot {
  if ($env:ANDROID_HOME) { return $env:ANDROID_HOME }
  if ($env:ANDROID_SDK_ROOT) { return $env:ANDROID_SDK_ROOT }
  $defaultRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
  if (Test-Path $defaultRoot) { return $defaultRoot }
  throw 'ANDROID_HOME or ANDROID_SDK_ROOT is required.'
}

function Get-LatestAndroidTool([string]$Root, [string]$RelativeRoot, [string]$Name) {
  $tool = Get-ChildItem -Path (Join-Path $Root $RelativeRoot) -Filter $Name -Recurse -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending |
    Select-Object -First 1
  if (-not $tool) { throw "$Name was not found in the Android SDK." }
  return $tool.FullName
}

function Invoke-AndroidTool([string]$Tool, [string[]]$Arguments) {
  $output = & $Tool @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "$([IO.Path]::GetFileName($Tool)) failed: $($output -join ' ')" }
  return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function Normalize-Fingerprint([string]$Value) {
  return ($Value -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()
}

function Count-Literal([string[]]$Values, [string]$Needle) {
  $count = 0
  foreach ($value in $Values) {
    if ($value.IndexOf($Needle, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $count++ }
  }
  return $count
}

$resolvedApk = (Resolve-Path -LiteralPath $ApkPath).Path
Enable-AndroidJava
$androidRoot = Get-AndroidSdkRoot
$apkAnalyzer = Get-LatestAndroidTool $androidRoot 'cmdline-tools' 'apkanalyzer.bat'
$apkSigner = Get-LatestAndroidTool $androidRoot 'build-tools' 'apksigner.bat'

$actualPackage = Invoke-AndroidTool $apkAnalyzer @('manifest', 'application-id', $resolvedApk)
$actualVersionName = Invoke-AndroidTool $apkAnalyzer @('manifest', 'version-name', $resolvedApk)
$actualVersionCodeText = Invoke-AndroidTool $apkAnalyzer @('manifest', 'version-code', $resolvedApk)
$actualVersionCode = 0
if (-not [int]::TryParse($actualVersionCodeText, [ref]$actualVersionCode)) {
  throw "APK versionCode is not an integer: $actualVersionCodeText"
}
if ($actualPackage -ne $ExpectedPackage) { throw "APK package mismatch. Expected $ExpectedPackage, got $actualPackage." }
if ($actualVersionName -ne $ExpectedVersionName) { throw "APK versionName mismatch. Expected $ExpectedVersionName, got $actualVersionName." }
if ($actualVersionCode -ne $ExpectedVersionCode) { throw "APK versionCode mismatch. Expected $ExpectedVersionCode, got $actualVersionCode." }
if ($actualVersionCode -le $PreviousVersionCode) {
  throw "APK versionCode $actualVersionCode must be greater than published versionCode $PreviousVersionCode."
}

$signatureOutput = Invoke-AndroidTool $apkSigner @('verify', '--verbose', '--print-certs', $resolvedApk)
$digestMatch = [regex]::Match($signatureOutput, 'certificate SHA-256 digest:\s*([0-9A-Fa-f:]+)')
if (-not $digestMatch.Success) { throw 'APK signer certificate SHA-256 could not be parsed.' }
$actualCertificate = Normalize-Fingerprint $digestMatch.Groups[1].Value
$expectedCertificate = Normalize-Fingerprint $ExpectedCertificateSha256
if ($actualCertificate -ne $expectedCertificate) {
  throw "APK signing certificate mismatch. Expected $expectedCertificate, got $actualCertificate."
}

$requiredStrings = @('https://trider.taxi')
$forbiddenStrings = @(
  '10.0.2.2',
  'localhost',
  '127.0.0.1',
  '103.60.127.213',
  'taxi.kecosystem.com',
  '159.89.192.55'
)
$counts = @{}
foreach ($value in $requiredStrings + $forbiddenStrings) { $counts[$value] = 0 }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($resolvedApk)
$scannedEntryCount = 0
try {
  foreach ($entry in $archive.Entries) {
    $isRuntimeEntry =
      ($entry.FullName -match '^lib/[^/]+/libapp\.so$') -or
      ($entry.FullName -match '^classes\d*\.dex$') -or
      ($entry.FullName -like 'assets/flutter_assets/*')
    if (-not $isRuntimeEntry -or $entry.Length -eq 0) { continue }
    $stream = $entry.Open()
    $memory = New-Object IO.MemoryStream
    try {
      $stream.CopyTo($memory)
      $text = [Text.Encoding]::ASCII.GetString($memory.ToArray())
      # Inspect URL-shaped runtime values. Flutter itself contains an unrelated
      # symbol named "localhost"; treating arbitrary symbols as endpoints would
      # reject every valid production build while adding no endpoint protection.
      $runtimeUrls = @([regex]::Matches($text, 'https?://[^\x00-\x20"''<>]+') | ForEach-Object { $_.Value })
      foreach ($value in @($counts.Keys)) { $counts[$value] += Count-Literal $runtimeUrls $value }
      $scannedEntryCount++
    } finally {
      $memory.Dispose()
      $stream.Dispose()
    }
  }
} finally {
  $archive.Dispose()
}
if ($scannedEntryCount -eq 0) { throw 'No APK runtime entries were available for endpoint inspection.' }
foreach ($value in $requiredStrings) {
  if ($counts[$value] -lt 1) { throw "Required APK string was not found: $value" }
}
foreach ($value in $forbiddenStrings) {
  if ($counts[$value] -ne 0) { throw "Forbidden APK string was found: $value (count=$($counts[$value]))" }
}

Write-Output "PACKAGE=$actualPackage"
Write-Output "VERSION_NAME=$actualVersionName"
Write-Output "VERSION_CODE=$actualVersionCode"
Write-Output "PREVIOUS_VERSION_CODE=$PreviousVersionCode"
Write-Output "CERT_SHA256=$actualCertificate"
Write-Output "SCANNED_ENTRY_COUNT=$scannedEntryCount"
foreach ($value in $requiredStrings + $forbiddenStrings) {
  Write-Output "STRING_COUNT[$value]=$($counts[$value])"
}

