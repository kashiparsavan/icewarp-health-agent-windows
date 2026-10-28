#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp database type and scope.

.DESCRIPTION
Maps to the database.* section of the Linux health.json schema. Reads the
Accounts ODBC connection string through the shared IceWarp tool wrapper and
classifies it as sqlite, mysql or unknown, deriving the host, scope and the
MySQL-section applicability flag the same way the Linux collector does.

Note: the mysql.* keys are emitted by the MySQL collector when applicable,
not here. This collector only sets database.type, database.scope,
database.host, database.connection_string_raw and
database.mysql_server_section_applicable.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$data['database.host'] = ''
$data['database.connection_string_raw'] = ''
$conn = (Get-IceWarpSetting -Name 'C_System_Storage_Accounts_ODBCConnString_Real' -Context $Context)
$data['database.connection_string_raw'] = $conn

if ([string]::IsNullOrEmpty($conn)) {
    $data['database.type'] = 'sqlite'
    $data['database.scope'] = 'local'
    $data['database.mysql_server_section_applicable'] = $false
    return $data
}

if ($conn -imatch 'sqlite') {
    $data['database.type'] = 'sqlite'
    $data['database.scope'] = 'local'
    $data['database.mysql_server_section_applicable'] = $false
    return $data
}

if ($conn -imatch '\.db(;|$)') {
    $data['database.type'] = 'sqlite'
    $data['database.scope'] = 'local'
    $data['database.mysql_server_section_applicable'] = $false
    return $data
}

if ($conn -imatch 'mysql|mariadb') {
    $data['database.type'] = 'mysql'
    $host = ''
    if ($conn -match '(?i)(?:host|server)\s*=\s*([^;]+)') {
        $host = $Matches[1].Trim()
    }
    $data['database.host'] = $host
    if ([string]::IsNullOrEmpty($host) -or $host -in @('127.0.0.1', 'localhost', '::1')) {
        $data['database.scope'] = 'local'
        $data['database.mysql_server_section_applicable'] = $false
    } else {
        $data['database.scope'] = 'remote'
        $data['database.mysql_server_section_applicable'] = $true
    }
    return $data
}

# Positional MySQL DSN: "accounts;user;password;host;..." with no .db extension.
$parts = $conn -split ';'
$f1 = if ($parts.Length -gt 0) { $parts[0] } else { '' }
$f4 = if ($parts.Length -gt 3) { $parts[3] } else { '' }

if (-not [string]::IsNullOrEmpty($f4) -and
    $f1 -notlike '*.db' -and
    $f4 -match '^[a-zA-Z0-9.-]+$') {
    $data['database.type'] = 'mysql'
    $data['database.host'] = $f4
    if ($f4 -in @('127.0.0.1', 'localhost', '::1')) {
        $data['database.scope'] = 'local'
        $data['database.mysql_server_section_applicable'] = $false
    } else {
        $data['database.scope'] = 'remote'
        $data['database.mysql_server_section_applicable'] = $true
    }
    return $data
}

$data['database.type'] = 'unknown'
$data['database.scope'] = 'unknown'
$data['database.mysql_server_section_applicable'] = $false
return $data