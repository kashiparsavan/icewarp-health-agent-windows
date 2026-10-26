#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp service status: ports and startup mode.

.DESCRIPTION
Maps to checklist items "Process SMTP", "Process POP3/IMAP", and the
service port checks. Reads one setting per service through the shared
IceWarp tool wrapper, so the configured timeout applies.

Service startup values on Windows (verified live on 14.3.0.13):
  0 = ssAutomatic
  1 = ssManual

Note: there is no C_System_Services_IMAP_Startup on Windows. tool.exe
exits with code 8 for that property, so IMAP has no startup mode and is
read as absent. IMAP is still reported with its port.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

# Setting = startup key; Port = port key (empty string means "no port for this service").
# IMAP deliberately has no startup key - it does not exist on Windows.
$services = @(
    [pscustomobject]@{ Key = 'service.smtp';       Setting = 'C_System_Services_SMTP_Startup';     Port = 'C_System_Services_SMTP_Port' }
    [pscustomobject]@{ Key = 'service.pop3';       Setting = 'C_System_Services_POP3_Startup';     Port = 'C_System_Services_POP3_Port' }
    [pscustomobject]@{ Key = 'service.imap';       Setting = '';                                   Port = 'C_System_Services_IMAP_Port' }
    [pscustomobject]@{ Key = 'service.im';         Setting = 'C_System_Services_IM_Startup';       Port = '' }
    [pscustomobject]@{ Key = 'service.groupware';  Setting = 'C_System_Services_GW_Startup';       Port = '' }
    [pscustomobject]@{ Key = 'service.control';    Setting = 'C_System_Services_Control_Startup';  Port = '' }
    [pscustomobject]@{ Key = 'service.ftp';        Setting = '';                                   Port = 'C_System_Services_FTP_Port' }
)

foreach ($service in $services) {
    $startup = if ($service.Setting) { Get-IceWarpSetting -Name $service.Setting -Context $Context } else { '' }
    $port = if ($service.Port) { Get-IceWarpSetting -Name $service.Port -Context $Context } else { '' }

    $data['{0}.startup' -f $service.Key] = $startup
    if ($service.Port) {
        $data['{0}.port' -f $service.Key] = $port
    }

    # Normalize the startup mode into a readable status.
    # Windows enum order: 0 = ssAutomatic, 1 = ssManual.
    if ($startup -eq '0' -or $startup -eq 0) {
        $data['{0}.startup_mode' -f $service.Key] = 'automatic'
        $data['{0}.active' -f $service.Key] = $true
    } elseif ($startup -eq '1' -or $startup -eq 1) {
        $data['{0}.startup_mode' -f $service.Key] = 'manual'
        $data['{0}.active' -f $service.Key] = $false
    } else {
        $data['{0}.startup_mode' -f $service.Key] = $startup
        $data['{0}.active' -f $service.Key] = $null
    }
}

return $data