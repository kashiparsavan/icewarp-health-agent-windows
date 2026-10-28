#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp admin access settings.

.DESCRIPTION
Maps to the admin.* section of the Linux health.json schema. Reads the
WebAdmin URL and remote-console port through the shared IceWarp tool
wrapper and derives changed_from_default flags using the same heuristics
as the Linux collector.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$url = (Get-IceWarpSetting -Name 'C_WebAdmin_URL' -Context $Context)
$port = (Get-IceWarpSetting -Name 'C_System_RemoteConsoleProtocol_Port' -Context $Context)

$data['admin.url'] = $url

$portNum = 0
if ([int]::TryParse([string]$port, [ref]$portNum)) {
    $data['admin.port_raw'] = [int]$portNum
} else {
    $data['admin.port_raw'] = $port
}

if (-not [string]::IsNullOrEmpty($url)) {
    $path = ($url -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+', '').ToLowerInvariant()
    if ($path -eq '/admin/' -or $path -eq '/admin') {
        $data['admin.url_changed_from_default'] = $false
    } else {
        $data['admin.url_changed_from_default'] = $true
    }
} else {
    $data['admin.url_changed_from_default'] = $false
}

if ([string]::IsNullOrEmpty($port) -or $portNum -eq 0) {
    $data['admin.port_changed_from_default'] = $false
} else {
    $data['admin.port_changed_from_default'] = $true
}

return $data