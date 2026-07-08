param(
    [string]$SmokeDatabase = "",
    [string]$DbHost = "",
    [int]$Port = 0,
    [string]$User = "",
    [string]$Password = "",
    [string]$EnvFile = (Join-Path $PSScriptRoot "..\backend\.env"),
    [string]$MysqlPath = ""
)

$ErrorActionPreference = "Stop"

function Read-DotEnvFile {
    param([string]$Path)

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $values
    }

    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }
        $separator = $trimmed.IndexOf("=")
        if ($separator -le 0) {
            continue
        }
        $key = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()
        if (
            ($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$key] = $value
    }
    return $values
}

function Get-ValueOrDefault {
    param(
        [hashtable]$Values,
        [string]$Key,
        [string]$Default
    )

    if ($Values.ContainsKey($Key) -and $Values[$Key] -ne $null -and $Values[$Key] -ne "") {
        return $Values[$Key]
    }
    return $Default
}

function Resolve-MysqlPath {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        return $RequestedPath
    }
    $candidates = @(
        "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysql.exe",
        "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return "mysql"
}

function New-TempDefaultsFile {
    param(
        [string]$DbHost,
        [int]$Port,
        [string]$User,
        [string]$Password
    )

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("ttaxi-smoke-mysql-{0}.cnf" -f ([guid]::NewGuid().ToString("N")))
    $lines = @(
        "[client]",
        "host=$DbHost",
        "port=$Port",
        "user=$User",
        "default-character-set=utf8mb4"
    )
    if ($Password) {
        $lines += "password=$Password"
    }
    Set-Content -LiteralPath $path -Value $lines -Encoding ASCII
    return $path
}

function Invoke-MysqlScalar {
    param(
        [string]$Sql,
        [string]$DefaultsFile,
        [string]$MysqlPath
    )

    $output = $Sql | & $MysqlPath --defaults-extra-file=$DefaultsFile --batch --raw --skip-column-names 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if ($exitCode -ne 0 -or $text -match '(?m)^ERROR\s+\d+') {
        throw $text
    }
    return $text.Trim()
}

function Assert-Equals {
    param(
        [string]$Name,
        [string]$Actual,
        [string]$Expected
    )

    if ($Actual -ne $Expected) {
        throw "$Name expected $Expected but got $Actual"
    }
    Write-Host "OK: $Name = $Actual"
}

$envValues = Read-DotEnvFile -Path $EnvFile
if (-not $DbHost) { $DbHost = Get-ValueOrDefault -Values $envValues -Key "DB_HOST" -Default "127.0.0.1" }
if (-not $Port) { $Port = [int](Get-ValueOrDefault -Values $envValues -Key "DB_PORT" -Default "3306") }
if (-not $User) { $User = Get-ValueOrDefault -Values $envValues -Key "DB_USER" -Default "root" }
if (-not $Password) { $Password = Get-ValueOrDefault -Values $envValues -Key "DB_PASSWORD" -Default "" }
if (-not $SmokeDatabase) {
    $SmokeDatabase = "ttaxi_migration_smoke_{0}" -f (Get-Date -Format "yyyyMMddHHmmss")
}

if ($SmokeDatabase -notmatch '^[A-Za-z0-9_]+$') {
    Write-Error "Invalid smoke database name '$SmokeDatabase'. Use letters, numbers, and underscore only."
    exit 1
}

$MysqlPath = Resolve-MysqlPath -RequestedPath $MysqlPath
$defaults = $null

try {
    $defaults = New-TempDefaultsFile -DbHost $DbHost -Port $Port -User $User -Password $Password

    Write-Host "Smoke database: $SmokeDatabase"
    Write-Host "Fresh migration run ..."
    & (Join-Path $PSScriptRoot "migrate.ps1") -DbHost $DbHost -Port $Port -User $User -Password $Password -Database $SmokeDatabase -MysqlPath $MysqlPath
    if ($LASTEXITCODE -ne 0) {
        throw "Fresh migration run failed"
    }

    Write-Host "Second migration run ..."
    & (Join-Path $PSScriptRoot "migrate.ps1") -DbHost $DbHost -Port $Port -User $User -Password $Password -Database $SmokeDatabase -MysqlPath $MysqlPath
    if ($LASTEXITCODE -ne 0) {
        throw "Second migration run failed"
    }

    $checks = @"
SELECT
  (SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$SmokeDatabase' AND TABLE_NAME = 'bookings'),
  (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = '$SmokeDatabase' AND TABLE_NAME = 'chat_messages' AND COLUMN_NAME = 'sender_participant_id'),
  (SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = '$SmokeDatabase' AND TABLE_NAME = 'chat_messages' AND COLUMN_NAME = 'client_message_id'),
  (SELECT COUNT(DISTINCT INDEX_NAME) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = '$SmokeDatabase' AND TABLE_NAME = 'bookings' AND INDEX_NAME = 'idx_bookings_active_status_scheduled'),
  (SELECT COUNT(DISTINCT INDEX_NAME) FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = '$SmokeDatabase' AND TABLE_NAME = 'chat_messages' AND INDEX_NAME = 'uk_chat_messages_idempotency'),
  (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = '$SmokeDatabase' AND TABLE_NAME = 'chat_messages' AND CONSTRAINT_NAME = 'fk_chat_messages_sender_participant_id'),
  (SELECT COUNT(*) FROM $SmokeDatabase.service_types WHERE code = 'AIRPORT_PICKUP'),
  (SELECT COUNT(*) FROM $SmokeDatabase.vehicle_types WHERE code = 'SEDAN'),
  (SELECT COUNT(*) FROM $SmokeDatabase.settings WHERE group_name = 'settlement' AND key_name = 'commission_rate_percent'),
  (
    SELECT COUNT(*)
    FROM $SmokeDatabase.routes r
    INNER JOIN $SmokeDatabase.service_types st ON st.id = r.service_type_id
    INNER JOIN $SmokeDatabase.locations lo ON lo.id = r.origin_location_id
    INNER JOIN $SmokeDatabase.locations ld ON ld.id = r.destination_location_id
    WHERE st.code = 'AIRPORT_PICKUP'
      AND lo.code = 'BKK'
      AND ld.code = 'PATTAYA'
      AND r.is_active = 1
      AND r.deleted_at IS NULL
  ),
  (
    SELECT COUNT(*)
    FROM $SmokeDatabase.vehicle_prices vp
    INNER JOIN $SmokeDatabase.routes r ON r.id = vp.route_id
    INNER JOIN $SmokeDatabase.service_types st ON st.id = r.service_type_id
    INNER JOIN $SmokeDatabase.locations lo ON lo.id = r.origin_location_id
    INNER JOIN $SmokeDatabase.locations ld ON ld.id = r.destination_location_id
    WHERE st.code = 'AIRPORT_PICKUP'
      AND lo.code = 'BKK'
      AND ld.code = 'PATTAYA'
      AND vp.is_active = 1
      AND vp.deleted_at IS NULL
  );
"@

    $result = Invoke-MysqlScalar -Sql $checks -DefaultsFile $defaults -MysqlPath $MysqlPath
    $parts = $result -split "`t"
    Assert-Equals -Name "bookings table" -Actual $parts[0] -Expected "1"
    Assert-Equals -Name "sender_participant_id column" -Actual $parts[1] -Expected "1"
    Assert-Equals -Name "client_message_id column" -Actual $parts[2] -Expected "1"
    Assert-Equals -Name "booking scheduled index" -Actual $parts[3] -Expected "1"
    Assert-Equals -Name "chat idempotency unique key" -Actual $parts[4] -Expected "1"
    Assert-Equals -Name "chat sender participant FK" -Actual $parts[5] -Expected "1"
    Assert-Equals -Name "AIRPORT_PICKUP seed count" -Actual $parts[6] -Expected "1"
    Assert-Equals -Name "SEDAN seed count" -Actual $parts[7] -Expected "1"
    Assert-Equals -Name "settlement commission setting count" -Actual $parts[8] -Expected "1"
    Assert-Equals -Name "BKK to Pattaya airport pickup route count" -Actual $parts[9] -Expected "1"
    Assert-Equals -Name "BKK to Pattaya active SEDAN/SUV/VAN price count" -Actual $parts[10] -Expected "3"

    $fareChecks = @"
SELECT
  (
    SELECT CAST(vp.price AS CHAR)
    FROM $SmokeDatabase.vehicle_prices vp
    INNER JOIN $SmokeDatabase.routes r ON r.id = vp.route_id
    INNER JOIN $SmokeDatabase.service_types st ON st.id = r.service_type_id
    INNER JOIN $SmokeDatabase.locations lo ON lo.id = r.origin_location_id
    INNER JOIN $SmokeDatabase.locations ld ON ld.id = r.destination_location_id
    INNER JOIN $SmokeDatabase.vehicle_types vt ON vt.id = vp.vehicle_type_id
    WHERE st.code = 'AIRPORT_PICKUP' AND lo.code = 'BKK' AND ld.code = 'PATTAYA'
      AND vt.code = 'SUV' AND vp.is_active = 1 AND vp.deleted_at IS NULL
    LIMIT 1
  ),
  (
    SELECT CAST(vp.price AS CHAR)
    FROM $SmokeDatabase.vehicle_prices vp
    INNER JOIN $SmokeDatabase.routes r ON r.id = vp.route_id
    INNER JOIN $SmokeDatabase.service_types st ON st.id = r.service_type_id
    INNER JOIN $SmokeDatabase.locations lo ON lo.id = r.origin_location_id
    INNER JOIN $SmokeDatabase.locations ld ON ld.id = r.destination_location_id
    INNER JOIN $SmokeDatabase.vehicle_types vt ON vt.id = vp.vehicle_type_id
    WHERE st.code = 'AIRPORT_PICKUP' AND lo.code = 'BKK' AND ld.code = 'BANGKOK'
      AND vt.code = 'SEDAN' AND vp.is_active = 1 AND vp.deleted_at IS NULL
    LIMIT 1
  ),
  (
    SELECT CAST(vp.price AS CHAR)
    FROM $SmokeDatabase.vehicle_prices vp
    INNER JOIN $SmokeDatabase.routes r ON r.id = vp.route_id
    INNER JOIN $SmokeDatabase.service_types st ON st.id = r.service_type_id
    INNER JOIN $SmokeDatabase.locations lo ON lo.id = r.origin_location_id
    INNER JOIN $SmokeDatabase.locations ld ON ld.id = r.destination_location_id
    INNER JOIN $SmokeDatabase.vehicle_types vt ON vt.id = vp.vehicle_type_id
    WHERE st.code = 'AIRPORT_PICKUP' AND lo.code = 'DMK' AND ld.code = 'PATTAYA'
      AND vt.code = 'VAN' AND vp.is_active = 1 AND vp.deleted_at IS NULL
    LIMIT 1
  ),
  (
    SELECT CAST(vp.price AS CHAR)
    FROM $SmokeDatabase.vehicle_prices vp
    INNER JOIN $SmokeDatabase.routes r ON r.id = vp.route_id
    INNER JOIN $SmokeDatabase.service_types st ON st.id = r.service_type_id
    INNER JOIN $SmokeDatabase.locations lo ON lo.id = r.origin_location_id
    INNER JOIN $SmokeDatabase.locations ld ON ld.id = r.destination_location_id
    INNER JOIN $SmokeDatabase.vehicle_types vt ON vt.id = vp.vehicle_type_id
    WHERE st.code = 'AIRPORT_DROPOFF' AND lo.code = 'PATTAYA' AND ld.code = 'DMK'
      AND vt.code = 'VAN' AND vp.is_active = 1 AND vp.deleted_at IS NULL
    LIMIT 1
  ),
  (
    SELECT CAST(vp.price AS CHAR)
    FROM $SmokeDatabase.vehicle_prices vp
    INNER JOIN $SmokeDatabase.routes r ON r.id = vp.route_id
    INNER JOIN $SmokeDatabase.service_types st ON st.id = r.service_type_id
    INNER JOIN $SmokeDatabase.locations lo ON lo.id = r.origin_location_id
    INNER JOIN $SmokeDatabase.locations ld ON ld.id = r.destination_location_id
    INNER JOIN $SmokeDatabase.vehicle_types vt ON vt.id = vp.vehicle_type_id
    WHERE st.code = 'CITY_TRANSFER' AND lo.code = 'PATTAYA' AND ld.code = 'BANGKOK'
      AND vt.code = 'SUV' AND vp.is_active = 1 AND vp.deleted_at IS NULL
    LIMIT 1
  ),
  (
    SELECT CAST(vp.price AS CHAR)
    FROM $SmokeDatabase.vehicle_prices vp
    INNER JOIN $SmokeDatabase.routes r ON r.id = vp.route_id
    INNER JOIN $SmokeDatabase.service_types st ON st.id = r.service_type_id
    INNER JOIN $SmokeDatabase.locations lo ON lo.id = r.origin_location_id
    INNER JOIN $SmokeDatabase.locations ld ON ld.id = r.destination_location_id
    INNER JOIN $SmokeDatabase.vehicle_types vt ON vt.id = vp.vehicle_type_id
    WHERE st.code = 'CITY_TRANSFER' AND lo.code = 'BANGKOK' AND ld.code = 'PATTAYA'
      AND vt.code = 'VAN' AND vp.is_active = 1 AND vp.deleted_at IS NULL
    LIMIT 1
  ),
  (
    SELECT CAST(vp.price AS CHAR)
    FROM $SmokeDatabase.vehicle_prices vp
    INNER JOIN $SmokeDatabase.routes r ON r.id = vp.route_id
    INNER JOIN $SmokeDatabase.service_types st ON st.id = r.service_type_id
    INNER JOIN $SmokeDatabase.locations lo ON lo.id = r.origin_location_id
    INNER JOIN $SmokeDatabase.locations ld ON ld.id = r.destination_location_id
    INNER JOIN $SmokeDatabase.vehicle_types vt ON vt.id = vp.vehicle_type_id
    WHERE st.code = 'AIRPORT_DROPOFF' AND lo.code = 'BANGKOK' AND ld.code = 'BKK'
      AND vt.code = 'SUV' AND vp.is_active = 1 AND vp.deleted_at IS NULL
    LIMIT 1
  ),
  (
    SELECT COUNT(*)
    FROM $SmokeDatabase.routes r
    INNER JOIN $SmokeDatabase.service_types st ON st.id = r.service_type_id
    INNER JOIN $SmokeDatabase.locations lo ON lo.id = r.origin_location_id
    INNER JOIN $SmokeDatabase.locations ld ON ld.id = r.destination_location_id
    WHERE r.is_active = 1 AND r.deleted_at IS NULL
      AND st.code IN ('AIRPORT_PICKUP', 'AIRPORT_DROPOFF', 'CITY_TRANSFER')
  ),
  (
    SELECT COUNT(*)
    FROM $SmokeDatabase.vehicle_prices vp
    INNER JOIN $SmokeDatabase.routes r ON r.id = vp.route_id
    INNER JOIN $SmokeDatabase.service_types st ON st.id = r.service_type_id
    INNER JOIN $SmokeDatabase.locations lo ON lo.id = r.origin_location_id
    INNER JOIN $SmokeDatabase.locations ld ON ld.id = r.destination_location_id
    INNER JOIN $SmokeDatabase.vehicle_types vt ON vt.id = vp.vehicle_type_id
    WHERE st.code = 'AIRPORT_PICKUP' AND lo.code = 'BKK' AND ld.code = 'PATTAYA'
      AND vt.code IN ('VIP_SUV', 'VIP_VAN', 'LUXURY')
      AND vp.is_active = 1 AND vp.deleted_at IS NULL
  ),
  (
    SELECT COUNT(*)
    FROM $SmokeDatabase.locations
    WHERE code IN ('HUA_HIN', 'RAYONG', 'AYUTTHAYA') AND is_active = 1 AND deleted_at IS NULL
  );
"@

    $fareResult = Invoke-MysqlScalar -Sql $fareChecks -DefaultsFile $defaults -MysqlPath $MysqlPath
    $fareParts = $fareResult -split "`t"
    Assert-Equals -Name "fare table BKK Pattaya SUV" -Actual $fareParts[0] -Expected "1300.00"
    Assert-Equals -Name "fare table BKK Bangkok Sedan" -Actual $fareParts[1] -Expected "550.00"
    Assert-Equals -Name "fare table DMK Pattaya VAN" -Actual $fareParts[2] -Expected "2200.00"
    Assert-Equals -Name "fare table Pattaya DMK VAN" -Actual $fareParts[3] -Expected "2300.00"
    Assert-Equals -Name "fare table Pattaya Bangkok SUV" -Actual $fareParts[4] -Expected "1500.00"
    Assert-Equals -Name "fare table Bangkok Pattaya VAN" -Actual $fareParts[5] -Expected "2000.00"
    Assert-Equals -Name "fare table Bangkok BKK SUV" -Actual $fareParts[6] -Expected "800.00"
    Assert-Equals -Name "fare table active route count" -Actual $fareParts[7] -Expected "14"
    Assert-Equals -Name "fare table VIP/LUXURY inactive on BKK Pattaya" -Actual $fareParts[8] -Expected "0"
    Assert-Equals -Name "fare table extra city locations" -Actual $fareParts[9] -Expected "3"

    Write-Host "Migration smoke test completed."
    Write-Host "Smoke database left in place for inspection: $SmokeDatabase"
} finally {
    if ($defaults -and (Test-Path -LiteralPath $defaults)) {
        Remove-Item -LiteralPath $defaults -Force
    }
}
