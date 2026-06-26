# TTaxi — Run database migrations in order (PowerShell)
# Usage: .\migrate.ps1 [-Host localhost] [-User root] [-Password secret]

param(
    [string]$Host = "localhost",
    [int]$Port = 3306,
    [string]$User = "root",
    [string]$Password = "",
    [string]$DatabaseDir = $PSScriptRoot
)

$files = @(
    "00_database.sql",
    "01_identity.sql",
    "02_service_catalog.sql",
    "03_fleet_places.sql",
    "04_booking_core.sql",
    "05_chat.sql",
    "06_notification.sql",
    "07_storage.sql",
    "08_platform.sql",
    "09_indexes.sql",
    "10_views.sql",
    "11_seed.sql"
)

foreach ($file in $files) {
    $path = Join-Path $DatabaseDir $file
    if (-not (Test-Path $path)) {
        Write-Error "Missing file: $path"
        exit 1
    }
    Write-Host "Running $file ..."
    if ($Password) {
        mysql -h $Host -P $Port -u $User -p$Password --default-character-set=utf8mb4 < $path
    } else {
        mysql -h $Host -P $Port -u $User --default-character-set=utf8mb4 < $path
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed on $file"
        exit $LASTEXITCODE
    }
}

Write-Host "Database migration completed."
