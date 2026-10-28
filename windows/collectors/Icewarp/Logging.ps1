#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp logging settings.

.DESCRIPTION
Maps to the logging.* section of the Linux health.json schema. Reads the
SQL log type, authentication log level, maintenance log level and the
mail-queue log level through the shared IceWarp tool wrapper.

Note: the task text also mentions logging.log_level, logging.log_file and
logging.log_rotation, but those keys are absent from the 432-key schema
fixture, so they are intentionally NOT emitted.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$data['logging.sql_log_type'] = (Get-IceWarpSetting -Name 'C_System_SQLLogType' -Context $Context)
$data['logging.auth_log_level'] = (Get-IceWarpSetting -Name 'C_Accounts_Global_Accounts_AuthLog' -Context $Context)
$data['logging.maintenance_log_level'] = (Get-IceWarpSetting -Name 'C_Accounts_Global_Accounts_MaintenanceLog' -Context $Context)
$data['logging.mailqueue.level'] = (Get-IceWarpSetting -Name 'C_System_Log_MailQueue' -Context $Context)

return $data