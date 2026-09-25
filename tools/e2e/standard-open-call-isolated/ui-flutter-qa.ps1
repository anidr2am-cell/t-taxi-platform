# Driver web UI against isolated QA API via SSH tunnel (run on dev machine).
# Prerequisite: SSH tunnel to staging QA API container IP:3000 -> local 127.0.0.1:13001 (see run-driver-ui-gate-false.sh KEEP output).
param(
  [string]$SshHost = 'tride-staging',
  [int]$LocalPort = 13001
)

$ErrorActionPreference = 'Stop'
Start-Process ssh -ArgumentList @('-N', "-L${LocalPort}:127.0.0.1:${LocalPort}", $SshHost) | Out-Null
Start-Sleep -Seconds 2

Set-Location (Join-Path $PSScriptRoot '..\..\..\frontend')
flutter run -d chrome `
  --web-port=8088 `
  --dart-define=API_BASE_URL="http://127.0.0.1:${LocalPort}" `
  --dart-define=SOCKET_URL="http://127.0.0.1:${LocalPort}" `
  --dart-define=APP_ENV=development

# Navigate manually to /driver/login — phone 1111111, password from QA seed (not stored in repo).
