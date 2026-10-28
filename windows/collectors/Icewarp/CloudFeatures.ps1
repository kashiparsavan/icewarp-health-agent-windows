#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp Cloud API auto-configure flag.

.DESCRIPTION
Maps to the icewarp.cloud_api.autoconfigure schema key.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}
$data['icewarp.cloud_api.autoconfigure'] = (Get-IceWarpSetting -Name 'C_CloudAPI_AutoConfigure' -Context $Context)

return $data