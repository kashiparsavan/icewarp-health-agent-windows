#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp anti-spam update status.

.DESCRIPTION
Maps to the icewarp.antispam.* section of the Linux health.json schema.
The update date, version and size are read through the shared IceWarp tool
wrapper first; the ever_updated flag is derived from the returned date so
the report can distinguish "never updated" from "could not collect".
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$lastUpdate = (Get-IceWarpSetting -Name 'C_AS_Info_UpdateDate' -Context $Context)
$version = (Get-IceWarpSetting -Name 'C_AS_Info_UpdateVersion' -Context $Context)
$size = (Get-IceWarpSetting -Name 'C_AS_Info_UpdateSize' -Context $Context)

$data['icewarp.antispam.last_update'] = $lastUpdate
$data['icewarp.antispam.last_update_source'] = if ([string]::IsNullOrEmpty($lastUpdate)) { 'not_found' } else { 'tool_sh' }
$data['icewarp.antispam.update_version'] = $version
$data['icewarp.antispam.last_update_size_bytes'] = $size

if (-not [string]::IsNullOrEmpty($lastUpdate) -and $lastUpdate -ne '-/-/-') {
    $data['icewarp.antispam.ever_updated'] = $true
} else {
    $data['icewarp.antispam.ever_updated'] = $false
}

return $data