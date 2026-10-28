#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp session timeout.

.DESCRIPTION
Maps to the icewarp.session_timeout_minutes schema key.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}
$data['icewarp.session_timeout_minutes'] = (Get-IceWarpSetting -Name 'C_System_Adv_Protocols_SessionTimeOut' -Context $Context)

return $data