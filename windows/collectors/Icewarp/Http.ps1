#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp HTTP settings.

.DESCRIPTION
Maps to the http.* section of the Linux health.json schema. The port is
read through the shared IceWarp tool wrapper with a 443 fallback; the max
connections value is read from the webserver.dat config file when present.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$port = (Get-IceWarpSetting -Name 'C_System_Services_Control_SslPort' -Context $Context)
$portNum = 0
if ([int]::TryParse([string]$port, [ref]$portNum)) {
    $data['http.port'] = [int]$portNum
} else {
    $data['http.port'] = 443
}

$maxConnections = ''
$configFile = Join-Path $Context.Config.IceWarpHome 'config\webserver.dat'
if (Test-Path -LiteralPath $configFile -PathType Leaf) {
    try {
        foreach ($line in (Get-Content -LiteralPath $configFile -ErrorAction Stop)) {
            if ($line -match '(?i)^\s*MaxConnections\s*=\s*(\S+)') {
                $maxConnections = $Matches[1]
                break
            }
        }
    } catch { }
}
$data['http.max_connections'] = $maxConnections

return $data