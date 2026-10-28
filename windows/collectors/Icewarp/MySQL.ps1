#Requires -Version 5.1
<#
.SYNOPSIS
Collect MySQL server details when the IceWarp database is MySQL.

.DESCRIPTION
Maps to the mysql.* section of the Linux health.json schema. Always emits
every mysql.* key, even when MySQL is not applicable, so the report has a
complete schema. For a local MySQL server it checks the Windows service,
the binary version and whether port 3306 is listening, and cross-references
the already-collected OS version. For a remote server it reports the host
and an honest "we cannot inspect that box" note.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$data['mysql.host'] = ''
$data['mysql.scope'] = 'unknown'
$data['mysql.service_active'] = 0
$data['mysql.service_name'] = ''
$data['mysql.version_raw'] = ''
$data['mysql.port_3306_listening'] = 0
$data['mysql.os_version'] = ''
$data['mysql.os_note'] = 'database scope could not be determined (see database.* keys)'

$dbType = [string]$Context.Data['database.type']
if ($dbType -ne 'mysql') {
    $data['mysql.applicable'] = $false
    return $data
}

$data['mysql.applicable'] = $true
$scope = [string]$Context.Data['database.scope']
if ([string]::IsNullOrEmpty($scope)) { $scope = 'unknown' }
$host = [string]$Context.Data['database.host']

$data['mysql.scope'] = $scope
$data['mysql.host'] = $host

if ($scope -eq 'local') {
    $serviceActive = 0
    $serviceName = ''
    foreach ($candidate in @('MySQL', 'MariaDB', 'mysqld', 'mariadb')) {
        try {
            $svc = Get-Service -Name $candidate -ErrorAction Stop
            if ($svc.Status -eq 'Running') {
                $serviceActive = 1
                $serviceName = $candidate
                break
            }
        } catch { }
    }
    $data['mysql.service_active'] = $serviceActive
    $data['mysql.service_name'] = $serviceName

    $version = ''
    foreach ($candidate in @('mysqld', 'mysql')) {
        try {
            $out = & $candidate --version 2>$null
            if (-not [string]::IsNullOrEmpty($out)) {
                $version = $out
                break
            }
        } catch { }
    }
    $data['mysql.version_raw'] = $version

    $listening = 0
    try {
        $connections = Get-NetTCPConnection -State Listen -ErrorAction Stop
        foreach ($conn in $connections) {
            if ($conn.LocalPort -eq 3306) {
                $listening = 1
                break
            }
        }
    } catch { }
    $data['mysql.port_3306_listening'] = $listening

    $osVersion = [string]$Context.Data['general.os.pretty']
    if ([string]::IsNullOrEmpty($osVersion)) {
        $osVersion = [string]$Context.Data['general.os.name']
    }
    $data['mysql.os_version'] = $osVersion
    $data['mysql.os_note'] = 'same host as IceWarp - see general.os.* / os.* / storage.* for OS/disk/CPU/RAM detail'
} elseif ($scope -eq 'remote') {
    $data['mysql.os_note'] = 'remote MySQL server - OS/disk/CPU/RAM/repo/time-sync require running this agent on {0} directly, or SSH access this agent does not have' -f $host
} else {
    $data['mysql.os_note'] = 'database scope could not be determined (see database.* keys)'
}

return $data