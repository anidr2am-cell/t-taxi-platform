param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$ApiBaseUrl,

  [string]$SocketUrl = ''
)

$ErrorActionPreference = 'Stop'

if ($ApiBaseUrl -match '^https?://(localhost|127\.0\.0\.1)(:|/|$)') {
  throw 'Preview API_BASE_URL must not point to localhost.'
}

$frontendDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\frontend')).Path
$flutterArgs = @(
  'build', 'web', '--release', '--no-wasm-dry-run',
  '--dart-define=APP_ENV=preview',
  "--dart-define=API_BASE_URL=$ApiBaseUrl"
)
if (-not [string]::IsNullOrWhiteSpace($SocketUrl)) {
  $flutterArgs += "--dart-define=SOCKET_URL=$SocketUrl"
}

Push-Location $frontendDir
try {
  & flutter @flutterArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter preview build failed with exit code $LASTEXITCODE."
  }
} finally {
  Pop-Location
}
