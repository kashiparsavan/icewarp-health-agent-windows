#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp full-text search settings.

.DESCRIPTION
Maps to the fulltext.* section of the Linux health.json schema.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$data['fulltext.enabled'] = (Get-IceWarpSetting -Name 'C_System_Services_Fulltext_Enabled' -Context $Context)
$data['fulltext.scanner.queues'] = (Get-IceWarpSetting -Name 'C_System_Services_Fulltext_Scanner_Queues' -Context $Context)

return $data