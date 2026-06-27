param(
    [string]$DbHost = "127.0.0.1",
    [int]$Port = 3307,
    [string]$User = "root",
    [string]$Password = "",
    [string]$DatabaseDir = $PSScriptRoot,
    [string]$DefaultsFile = "",
    [string]$MysqlPath = ""
)

if (-not $MysqlPath) {
    $candidates = @(
        "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe",
        "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            $MysqlPath = $candidate
            break
        }
    }
    if (-not $MysqlPath) {
        $MysqlPath = "mysql"
    }
}

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
    "11_seed.sql",
    "12_schema_fixes.sql",
    "13_driver_assignment_constraints.sql",
    "14_pricing_integrity.sql",
    "15_pricing_architecture.sql",
    "16_booking_qr_settlement.sql",
    "17_settlement_settings_seed.sql"
)

function Invoke-MysqlFile {
    param([string]$Path)

    $sql = Get-Content -Path $Path -Raw -Encoding UTF8

    if ($DefaultsFile) {
        $output = $sql | & $MysqlPath --defaults-file=$DefaultsFile -u $User --default-character-set=utf8mb4 2>&1
    } elseif ($Password) {
        $output = $sql | & $MysqlPath -h $DbHost -P $Port -u $User "-p$Password" --default-character-set=utf8mb4 2>&1
    } else {
        $output = $sql | & $MysqlPath -h $DbHost -P $Port -u $User --default-character-set=utf8mb4 2>&1
    }

    foreach ($line in $output) {
        if ($line -match 'ERROR (\d+) .* at line (\d+)') {
            throw "$Path : line $($Matches[2])"
        }
        if ($line -is [System.Management.Automation.ErrorRecord]) {
            throw "$Path : $($line.Exception.Message)"
        }
        if ($line -match '^ERROR') {
            throw "$Path : $line"
        }
    }
    if ($LASTEXITCODE -ne 0) {
        throw "$Path : exit $LASTEXITCODE"
    }
}

foreach ($file in $files) {
    $path = Join-Path $DatabaseDir $file
    if (-not (Test-Path $path)) {
        Write-Error "Missing file: $path"
        exit 1
    }
    Write-Host "Running $file ..."
    try {
        Invoke-MysqlFile -Path $path
    } catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}

Write-Host "Database migration completed."
