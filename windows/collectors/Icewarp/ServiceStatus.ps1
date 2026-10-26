#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp IMAP and POP3 service activation.

.DESCRIPTION
Maps to the service.* section of the Linux health.json schema. The
schema only exposes service.imap.active and service.pop3.active, so
this collector produces exactly those two keys and nothing else. The
activation flags are read through the shared IceWarp tool wrapper.

Note: there is no C_System_Services_IMAP_Startup on Windows (tool.exe
exits with code 8 for that property), so IMAP has no startup mode and
is reported from its activation flag only.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

# service.imap.active - C_Mail_IMAP_Active is a Bool; 1/true = active.
$imapActive = (Get-IceWarpSetting -Name 'C_Mail_IMAP_Active' -Context $Context)
if ($imapActive -eq '1' -or $imapActive -ieq 'true') {
    $data['service.imap.active'] = '1'
} elseif ($imapActive -eq '0' -or $imapActive -ieq 'false') {
    $data['service.imap.active'] = '0'
} else {
    $data['service.imap.active'] = $imapActive
}

# service.pop3.active - same logic for POP3.
$pop3Active = (Get-IceWarpSetting -Name 'C_Mail_POP_Active' -Context $Context)
if ($pop3Active -eq '1' -or $pop3Active -ieq 'true') {
    $data['service.pop3.active'] = '1'
} elseif ($pop3Active -eq '0' -or $pop3Active -ieq 'false') {
    $data['service.pop3.active'] = '0'
} else {
    $data['service.pop3.active'] = $pop3Active
}

return $data