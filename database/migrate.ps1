param(
    [string]$DbHost = "",
    [int]$Port = 0,
    [string]$User = "",
    [string]$Password = "",
    [string]$Database = "",
    [string]$DatabaseDir = $PSScriptRoot,
    [string]$EnvFile = (Join-Path $PSScriptRoot "..\backend\.env"),
    [string]$DefaultsFile = "",
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

function Convert-SqlForDatabase {
    param(
        [string]$Sql,
        [string]$DatabaseName
    )

    $quoted = "``$DatabaseName``"
    $converted = $Sql -replace '(?im)^CREATE\s+DATABASE\s+IF\s+NOT\s+EXISTS\s+`?ttaxi`?', "CREATE DATABASE IF NOT EXISTS $quoted"
    $converted = $converted -replace '(?im)^USE\s+`?ttaxi`?\s*;', "USE $quoted;"
    return $converted
}

function New-TempDefaultsFile {
    param(
        [string]$DbHost,
        [int]$Port,
        [string]$User,
        [string]$Password
    )

    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("ttaxi-mysql-{0}.cnf" -f ([guid]::NewGuid().ToString("N")))
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

function Invoke-MysqlSql {
    param(
        [string]$Sql,
        [string]$FileName,
        [string]$DefaultsFile,
        [string]$MysqlPath
    )

    $output = $Sql | & $MysqlPath --defaults-extra-file=$DefaultsFile --default-character-set=utf8mb4 --show-warnings 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    if ($exitCode -ne 0 -or $text -match '(?m)^ERROR\s+\d+') {
        if (-not $text) {
            $text = "mysql exited with code $exitCode"
        }
        throw "$FileName failed:$([Environment]::NewLine)$text"
    }

    return $text
}

$envValues = Read-DotEnvFile -Path $EnvFile

if (-not $DbHost) { $DbHost = Get-ValueOrDefault -Values $envValues -Key "DB_HOST" -Default "127.0.0.1" }
if (-not $Port) { $Port = [int](Get-ValueOrDefault -Values $envValues -Key "DB_PORT" -Default "3306") }
if (-not $User) { $User = Get-ValueOrDefault -Values $envValues -Key "DB_USER" -Default "root" }
if (-not $Password) { $Password = Get-ValueOrDefault -Values $envValues -Key "DB_PASSWORD" -Default "" }
if (-not $Database) { $Database = Get-ValueOrDefault -Values $envValues -Key "DB_NAME" -Default "ttaxi" }

if ($Database -notmatch '^[A-Za-z0-9_]+$') {
    Write-Error "Invalid database name '$Database'. Use letters, numbers, and underscore only."
    exit 1
}

$MysqlPath = Resolve-MysqlPath -RequestedPath $MysqlPath

$migrationFiles = Get-ChildItem -LiteralPath $DatabaseDir -File -Filter "*.sql" |
    Where-Object { $_.Name -match '^\d+_.+\.sql$' } |
    Sort-Object Name

if (-not $migrationFiles) {
    Write-Error "No numbered SQL migration files found in $DatabaseDir"
    exit 1
}

$tempDefaultsFile = $null
$activeDefaultsFile = $DefaultsFile

try {
    if (-not $activeDefaultsFile) {
        $tempDefaultsFile = New-TempDefaultsFile -DbHost $DbHost -Port $Port -User $User -Password $Password
        $activeDefaultsFile = $tempDefaultsFile
    }

    Write-Host "Using database '$Database' on $DbHost`:$Port as $User"

    foreach ($file in $migrationFiles) {
        Write-Host "Running $($file.Name) ..."
        $sql = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        $sql = Convert-SqlForDatabase -Sql $sql -DatabaseName $Database

        try {
            [void](Invoke-MysqlSql -Sql $sql -FileName $file.Name -DefaultsFile $activeDefaultsFile -MysqlPath $MysqlPath)
        } catch {
            Write-Error $_.Exception.Message
            exit 1
        }
    }

    Write-Host "Database migration completed."
} finally {
    if ($tempDefaultsFile -and (Test-Path -LiteralPath $tempDefaultsFile)) {
        Remove-Item -LiteralPath $tempDefaultsFile -Force
    }
}
