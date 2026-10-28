#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp SMTP settings.

.DESCRIPTION
Maps to the smtp.* section of the Linux health.json schema. Produces
exactly the same keys the Linux collectors produce, nothing more and
nothing less. Each setting is read through the shared IceWarp tool
wrapper, so the configured timeout applies and an unavailable tool.exe
yields an empty string rather than a crash.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

# --- Simple 1:1 setting reads ---
$settings = @(
    @{ Key = 'smtp.add_return_path';          Name = 'C_Mail_SMTP_Delivery_ReturnPath' },
    @{ Key = 'smtp.dedupe';                   Name = 'C_Mail_SMTP_Other_Dedupe' },
    @{ Key = 'smtp.deny_vrfy';                Name = 'c_mail_security_protocols_denyvrfy' },
    @{ Key = 'smtp.enforce_tls_secondary_port'; Name = 'C_Mail_SMTP_Delivery_EnforceTlsOnSecondarySmtpPort' },
    @{ Key = 'smtp.global_pop_before_smtp';   Name = 'C_Mail_Security_Relay_POPSMTPGlobal' },
    @{ Key = 'smtp.greeting_delay_seconds';   Name = 'C_Mail_Security_Protection_SMTPWait' },
    @{ Key = 'smtp.header_footer_active';     Name = 'C_Mail_SMTP_HeaderFooter_Enable' },
    @{ Key = 'smtp.hide_ip';                  Name = 'C_Mail_SMTP_Delivery_HideIP' },
    @{ Key = 'smtp.hide_server_version';      Name = 'C_Mail_SMTP_Delivery_HideServerVersion' },
    @{ Key = 'smtp.incoming_queue_threads';   Name = 'C_Mail_SMTP_Delivery_IncomingQueueSize' },
    @{ Key = 'smtp.max_client_recipients';    Name = 'C_Mail_SMTP_Other_MaxMTARecipients' },
    @{ Key = 'smtp.max_hop_count';            Name = 'C_Mail_SMTP_Other_MaxHopCount' },
    @{ Key = 'smtp.max_incoming_connections'; Name = 'C_System_Services_SMTP_MaxInConn' },
    @{ Key = 'smtp.max_outgoing_connections'; Name = 'C_System_Services_SMTP_MaxOutConn' },
    @{ Key = 'smtp.max_server_recipients';    Name = 'C_Mail_SMTP_Other_MaxRecipients' },
    @{ Key = 'smtp.mda_internal_delivery';   Name = 'C_Mail_SMTP_Delivery_MDAInternal' },
    @{ Key = 'smtp.parallel_ip_limit';        Name = 'C_Mail_SMTP_General_ParallelIPConnectionsLimit' },
    @{ Key = 'smtp.rdns_in_received';         Name = 'C_Mail_SMTP_Delivery_RDNSLookup' },
    @{ Key = 'smtp.reject_auth_sender_mismatch'; Name = 'C_Mail_Security_Protection_RejectSMTPAuthSender' },
    @{ Key = 'smtp.relay.allowed_ips';        Name = 'C_Mail_Security_Relay_IPList' },
    @{ Key = 'smtp.relay.local_domain_only';  Name = 'C_Mail_Security_Protection_LocalDomain' },
    @{ Key = 'smtp.relay.mode';               Name = 'C_Mail_Security_Relay_RelayMode' },
    @{ Key = 'smtp.relay.server';             Name = 'C_Mail_SMTP_General_RelayMailServer' },
    @{ Key = 'smtp.require_helo_ehlo';        Name = 'C_Mail_Security_Protection_HELOEHLO' },
    @{ Key = 'smtp.thread_cache';             Name = 'C_System_Services_SMTP_ThreadCache' },
    @{ Key = 'smtp.use_incoming_queue';       Name = 'C_Mail_SMTP_Delivery_UseIncomingQueue' },
    @{ Key = 'smtp.use_tls_ssl';              Name = 'C_Mail_SMTP_Delivery_UseTLSSSL' },
    @{ Key = 'smtp.max_per_domain_outgoing.enabled'; Name = 'C_System_Services_SMTP_MaxOutgoingLimitPerDomainEnabled' },
    @{ Key = 'smtp.max_per_domain_outgoing.value';  Name = 'C_System_Services_SMTP_MaxOutgoingLimitPerDomainValue' },
    @{ Key = 'smtp.max_per_domain_sender.enabled';  Name = 'C_System_Services_SMTP_MaxSenderLimitPerDomainEnabled' },
    @{ Key = 'smtp.max_per_domain_sender.value';   Name = 'C_System_Services_SMTP_MaxSenderLimitPerDomainValue' }
)

foreach ($s in $settings) {
    $data[$s.Key] = (Get-IceWarpSetting -Name $s.Name -Context $Context)
}

# --- Delivery Reports (DSN) - inverted: c_mail_smtp_other_disable_dsn=1
# means DSN is DISABLED, so delivery_reports_enabled=0. ---
$dsnDisable = (Get-IceWarpSetting -Name 'c_mail_smtp_other_disable_dsn' -Context $Context)
if ($dsnDisable -eq '1') {
    $data['smtp.delivery_reports_enabled'] = '0'
} elseif ($dsnDisable -eq '0') {
    $data['smtp.delivery_reports_enabled'] = '1'
} else {
    $data['smtp.delivery_reports_enabled'] = $dsnDisable
}

# --- Bounceback Mode (raw key, kept verbatim) ---
$data['c_mail_smtp_other_bouncebackmode'] = (Get-IceWarpSetting -Name 'c_mail_smtp_other_bouncebackmode' -Context $Context)

# --- Max message size: bytes + enabled flag + computed MB ---
$limitEnabled = (Get-IceWarpSetting -Name 'C_Mail_SMTP_Delivery_LimitMsgSize' -Context $Context)
$data['smtp.max_message_size.enabled'] = $limitEnabled
$sizeBytes = (Get-IceWarpSetting -Name 'C_Mail_SMTP_Delivery_MaxMsgSize' -Context $Context)
$data['smtp.max_message_size.bytes'] = $sizeBytes
if ([string]::IsNullOrEmpty($sizeBytes)) {
    $data['smtp.max_message_size.mb'] = ''
} else {
    $num = 0
    if ([long]::TryParse([string]$sizeBytes, [ref]$num)) {
        $megabytes = $num / 1MB
        $data['smtp.max_message_size.mb'] = if ($megabytes -eq [Math]::Round($megabytes)) {
            ([long][Math]::Round($megabytes)).ToString([System.Globalization.CultureInfo]::InvariantCulture)
        } else {
            $megabytes.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
        }
    } else {
        $data['smtp.max_message_size.mb'] = $sizeBytes
    }
}

# --- starttls_live_test: a real SMTP STARTTLS negotiation on port 25.
# The shared helper reads the 220 banner, sends EHLO, checks for STARTTLS,
# issues STARTTLS, and bounds both the connect and the TLS handshake. ---
$startTlsHost = ConvertTo-AgentHostName -Value ([string]$Context.Config.MailHostname)
if ([string]::IsNullOrEmpty($startTlsHost)) {
    $startTlsHost = ConvertTo-AgentHostName -Value ([string]$Context.Config.MailDomain)
}
if ([string]::IsNullOrEmpty($startTlsHost)) {
    $startTlsHost = ConvertTo-AgentHostName -Value ([string]$env:COMPUTERNAME)
}
$networkTimeout = 10
try {
    $parsedTimeout = [int]$Context.Config.NetworkTimeoutSeconds
    if ($parsedTimeout -gt 0) { $networkTimeout = $parsedTimeout }
} catch { }
$data['smtp.starttls_live_test'] = [bool](Test-SmtpStartTls -Server $startTlsHost -Port 25 -TimeoutSeconds $networkTimeout)

# tool.exe may print Bool settings as true/false. The 411-key schema stores
# these flags as JSON numbers (1/0), so normalize them before the writer sees
# them.
foreach ($flagKey in @(
    'smtp.add_return_path',
    'smtp.dedupe',
    'smtp.deny_vrfy',
    'smtp.delivery_reports_enabled',
    'smtp.enforce_tls_secondary_port',
    'smtp.global_pop_before_smtp',
    'smtp.header_footer_active',
    'smtp.hide_ip',
    'smtp.hide_server_version',
    'smtp.mda_internal_delivery',
    'smtp.max_message_size.enabled',
    'smtp.rdns_in_received',
    'smtp.reject_auth_sender_mismatch',
    'smtp.relay.local_domain_only',
    'smtp.relay.mode',
    'smtp.require_helo_ehlo',
    'smtp.use_incoming_queue',
    'smtp.use_tls_ssl',
    'smtp.max_per_domain_outgoing.enabled',
    'smtp.max_per_domain_sender.enabled'
)) {
    if ($data.Contains($flagKey)) {
        $data[$flagKey] = ConvertTo-AgentNumericFlag -Value $data[$flagKey]
    }
}

return $data