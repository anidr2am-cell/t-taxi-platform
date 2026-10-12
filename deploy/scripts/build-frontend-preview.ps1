param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$ApiBaseUrl,

  [string]$SocketUrl = ''
)

$ErrorActionPreference = 'Stop'

function Assert-PreviewOriginUrl {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  $parsed = $null
  if (-not [Uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$parsed) -or
      ($parsed.Scheme -ne 'http' -and $parsed.Scheme -ne 'https')) {
    throw "Preview $Name must be an absolute http(s) origin URL."
  }
  if ($parsed.AbsolutePath -ne '/' -or $parsed.Query -or $parsed.Fragment -or $parsed.UserInfo) {
    throw "Preview $Name must contain only scheme, host, and optional port; paths such as /api are not allowed."
  }
  if ($parsed.Host -in @('localhost', '127.0.0.1', '::1')) {
    throw "Preview $Name must not point to localhost."
  }
}

Assert-PreviewOriginUrl -Name 'API_BASE_URL' -Value $ApiBaseUrl
if (-not [string]::IsNullOrWhiteSpace($SocketUrl)) {
  Assert-PreviewOriginUrl -Name 'SOCKET_URL' -Value $SocketUrl
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
