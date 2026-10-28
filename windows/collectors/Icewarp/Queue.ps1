#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp SMTP incoming queue settings.

.DESCRIPTION
Maps to the queue.smtp.incoming.* section of the Linux health.json schema.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$data['queue.smtp.incoming.enabled'] = (Get-IceWarpSetting -Name 'C_Mail_SMTP_Delivery_UseIncomingQueue' -Context $Context)
$data['queue.smtp.incoming.size'] = (Get-IceWarpSetting -Name 'C_Mail_SMTP_Delivery_IncomingQueueSize' -Context $Context)
$data['queue.smtp.no_retry'] = (Get-IceWarpSetting -Name 'C_Mail_SMTP_Other_NoRetryQueue' -Context $Context)

return $data