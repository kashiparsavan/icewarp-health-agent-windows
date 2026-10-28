#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp directory cache settings.

.DESCRIPTION
Maps to the directory_cache.* section of the Linux health.json schema.
Reads the connection string and schedule through the shared IceWarp tool
wrapper.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$conn = (Get-IceWarpSetting -Name 'C_Accounts_Global_Accounts_DirectoryCacheConnectionString' -Context $Context)
$schedule = (Get-IceWarpSetting -Name 'C_Accounts_Global_Accounts_DirectoryCacheSchedule' -Context $Context)

$data['directory_cache.connection_string'] = $conn

if (-not [string]::IsNullOrEmpty($schedule)) {
    $data['directory_cache.scheduled'] = $true
    $data['directory_cache.schedule_raw'] = $schedule
    $data['directory_cache.next_run'] = 'pending'
} else {
    $data['directory_cache.scheduled'] = $false
    $data['directory_cache.schedule_raw'] = 'not scheduled'
    $data['directory_cache.next_run'] = 'never'
}

return $data