#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp migration safety status.

.DESCRIPTION
Maps to the icewarp.migration.* section of the Linux health.json schema.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$data['icewarp.migration.active'] = (Get-IceWarpSetting -Name 'C_System_Tools_Migration_Active' -Context $Context)
$data['icewarp.migration.server'] = (Get-IceWarpSetting -Name 'C_System_Tools_Migration_Server' -Context $Context)

$startRaw = (Get-IceWarpSetting -Name 'C_System_Tools_Migration_Stat_Start' -Context $Context)
$data['icewarp.migration.stat_start_raw'] = $startRaw

$startNum = 0
if ([int]::TryParse([string]$startRaw, [ref]$startNum) -and $startNum -gt 0) {
    $data['icewarp.migration.stat_started'] = $true
} else {
    $data['icewarp.migration.stat_started'] = $false
}

$errRaw = (Get-IceWarpSetting -Name 'C_System_Tools_Migration_Stat_Errors' -Context $Context)
$data['icewarp.migration.stat_errors'] = $errRaw

$errNum = 0
if ([int]::TryParse([string]$errRaw, [ref]$errNum) -and $errNum -gt 0) {
    $data['icewarp.migration.has_errors'] = $true
} else {
    $data['icewarp.migration.has_errors'] = $false
}

return $data