[CmdletBinding()]
param(
  [string]$PublishedReleaseUrl = 'https://trider.taxi/downloads/release.json'
)

$ErrorActionPreference = 'Stop'
$driverRoot = Split-Path -Parent $PSScriptRoot
$pubspecPath = Join-Path $driverRoot 'pubspec.yaml'
$apkPaths = @(
  (Join-Path $driverRoot 'build\app\outputs\flutter-apk\app-prod-release.apk'),
  (Join-Path $driverRoot 'build\app\outputs\apk\prod\release\app-prod-release.apk')
)
foreach ($path in $apkPaths) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }

$versionLine = Get-Content -LiteralPath $pubspecPath | Where-Object { $_ -match '^version:\s*([^+\s]+)\+(\d+)\s*$' } | Select-Object -First 1
if (-not $versionLine) { throw 'Unable to read versionName and versionCode from driver_app/pubspec.yaml.' }
$versionMatch = [regex]::Match($versionLine, '^version:\s*([^+\s]+)\+(\d+)\s*$')
$versionName = $versionMatch.Groups[1].Value
$versionCode = [int]$versionMatch.Groups[2].Value

$releaseUrl = "${PublishedReleaseUrl}?v=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$published = Invoke-RestMethod -Uri $releaseUrl -Method Get -Headers @{ 'Cache-Control' = 'no-cache' }
$previousVersionCode = [int]$published.versionCode
$previousGradleOpts = $env:GRADLE_OPTS
# Keep enough native memory available on build machines where the repository's
# 8 GiB Gradle daemon setting would otherwise exhaust physical RAM.
$env:GRADLE_OPTS = '-Dorg.gradle.jvmargs="-Xmx4G -XX:MaxMetaspaceSize=2G -XX:ReservedCodeCacheSize=256m"'
Push-Location $driverRoot
try {
  & flutter build apk --release --flavor prod -t lib/main_prod.dart
  if ($LASTEXITCODE -ne 0) { throw 'Flutter production APK build failed.' }
  $primaryApk = $apkPaths[0]
  if (-not (Test-Path -LiteralPath $primaryApk)) { throw "Expected APK was not created: $primaryApk" }
  $verification = & (Join-Path $PSScriptRoot 'verify-release-apk.ps1') `
    -ApkPath $primaryApk `
    -ExpectedVersionName $versionName `
    -ExpectedVersionCode $versionCode `
    -PreviousVersionCode $previousVersionCode
  if ($LASTEXITCODE -ne 0) { throw 'Production APK verification failed.' }
  $verification | Write-Output
  Write-Output "APK_PATH=$primaryApk"
  Write-Output "APK_SHA256=$((Get-FileHash -LiteralPath $primaryApk -Algorithm SHA256).Hash.ToUpperInvariant())"
} catch {
  foreach ($path in $apkPaths) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
  throw
} finally {
  Pop-Location
  if ($null -eq $previousGradleOpts) {
    Remove-Item Env:GRADLE_OPTS -ErrorAction SilentlyContinue
  } else {
    $env:GRADLE_OPTS = $previousGradleOpts
  }
}

