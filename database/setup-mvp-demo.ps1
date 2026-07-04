param(
    [switch]$SkipMigrate,
    [switch]$SkipSeed,
    [string]$Scenarios = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

Write-Host "=== T-Ride MVP demo setup ==="

if (-not $SkipMigrate) {
    Write-Host "`n[1/2] Running database migrations ..."
    & (Join-Path $PSScriptRoot "migrate.ps1")
    if ($LASTEXITCODE -ne 0) {
        throw "Migration failed"
    }
} else {
    Write-Host "`n[1/2] Skipping migrations (--SkipMigrate)"
}

if (-not $SkipSeed) {
    Write-Host "`n[2/2] Seeding MVP demo accounts and bookings ..."
    Push-Location (Join-Path $Root "backend")
    try {
        if ($Scenarios) {
            npm run seed:mvp-demo -- --scenarios=$Scenarios
        } else {
            npm run seed:mvp-demo
        }
        if ($LASTEXITCODE -ne 0) {
            throw "Seed failed"
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "`n[2/2] Skipping seed (--SkipSeed)"
}

Write-Host "`nSetup complete."
Write-Host "Docs: docs/MVP_DEV_SETUP.md"
Write-Host "Checklist: docs/MVP_MANUAL_E2E_CHECKLIST.md"
