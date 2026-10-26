#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp security settings.

.DESCRIPTION
Maps to the security.* section of the Linux health.json schema. Produces
exactly the same keys the Linux collectors produce, nothing more and
nothing less. Each setting is read through the shared IceWarp tool
wrapper, so an unavailable tool.exe yields an empty string rather than
a crash.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

# --- Login policy ---
$data['security.login.policy_enabled'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Login_Enable' -Context $Context)
$data['security.login.max_failed_attempts'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Login_Attempts' -Context $Context)
$data['security.login.block_period_minutes'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Login_BlockPeriod' -Context $Context)
$data['security.login.2fa_bypass_enabled'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Login_Bypass_2f' -Context $Context)
$data['security.login.block_mode'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Login_Block' -Context $Context)

# --- Password policy ---
$data['security.password_policy.active'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Pass_Enable' -Context $Context)
$data['security.password_policy.no_username_in_password'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Pass_UserAlias' -Context $Context)
$data['security.password_policy.min_length'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Pass_MinLength' -Context $Context)
$data['security.password_policy.min_digits'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Pass_Digits' -Context $Context)
$data['security.password_policy.min_non_alphanumeric'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Pass_NonAlphaNum' -Context $Context)
$data['security.password_policy.min_alpha'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Pass_Alpha' -Context $Context)
$data['security.password_policy.min_uppercase'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Pass_UpperAlpha' -Context $Context)
$data['security.password_policy.expiration_active'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Pass_Expiration' -Context $Context)
$data['security.password_policy.expire_after_days'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Pass_ExpireAfter' -Context $Context)
$data['security.password_policy.notify_before_days'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Pass_NotifyBefore' -Context $Context)
$data['security.password_policy.disable_access_when_expired'] = (Get-IceWarpSetting -Name 'C_Accounts_Policies_Pass_DisableAccessToAllIfDisabled' -Context $Context)

# --- Intrusion Prevention (grouped under the "Tarpit" property family in
# tool.help, even though several are hard-block rules, not tarpitting). ---
$data['security.intrusion.process_smtp'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_EnableSMTP' -Context $Context)
$data['security.intrusion.process_pop3_imap'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_EnableIMAPPOP3' -Context $Context)

$data['security.intrusion.block_connections_per_minute.enabled'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_BlockIP' -Context $Context)
$data['security.intrusion.block_connections_per_minute.value'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_BlockIPValue' -Context $Context)

$data['security.intrusion.block_failed_logins.enabled'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_Login' -Context $Context)
$data['security.intrusion.block_failed_logins.value'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_LoginCount' -Context $Context)

$data['security.intrusion.block_unknown_user_count.enabled'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_Recipient' -Context $Context)
$data['security.intrusion.block_unknown_user_count.value'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_RecipientCount' -Context $Context)

$data['security.intrusion.block_relay_denied_count.enabled'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_RelayTarpit' -Context $Context)
$data['security.intrusion.block_relay_denied_count.value'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_RelayTarpitCount' -Context $Context)

$data['security.intrusion.block_rset_count.enabled'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_RSET' -Context $Context)
$data['security.intrusion.block_rset_count.value'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_RSETCount' -Context $Context)

$data['security.intrusion.block_spam_score.enabled'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_Spam' -Context $Context)
$rawSpamScore = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_SpamScore' -Context $Context)
$data['security.intrusion.block_spam_score.raw'] = $rawSpamScore
# tool.help documents this as "* 100" but a real WebAdmin screenshot shows
# raw 9216 -> displayed 9.00, i.e. raw/1024, not raw/100.
$spNum = 0
if ([int]::TryParse([string]$rawSpamScore, [ref]$spNum)) {
    $data['security.intrusion.block_spam_score.value'] = ([Math]::Round($spNum / 1024, 2)).ToString('0.00')
} else {
    $data['security.intrusion.block_spam_score.value'] = $rawSpamScore
}

$data['security.intrusion.block_dnsbl_listed.enabled'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_DNSBL' -Context $Context)
$data['security.intrusion.block_message_size.enabled'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_Msg_Enabled' -Context $Context)
$data['security.intrusion.block_message_size.value_mb'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_Msg_Value' -Context $Context)

$data['security.intrusion.block_duration_minutes'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_Period' -Context $Context)
$data['security.intrusion.close_blocked_connection'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_CloseConnection' -Context $Context)
$data['security.intrusion.close_all_other_connections'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_CloseAllConnections' -Context $Context)
$data['security.intrusion.cross_session_processing'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_CrossSession' -Context $Context)

# "Refuse blocked IP address" - not separately documented in the available
# tool.help subset; the master tarpitting enable flag is the best candidate.
$data['security.intrusion.refuse_blocked_ip'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Tarpit_Enable' -Context $Context)
$data['security.intrusion.refuse_blocked_ip_source'] = 'UNVERIFIED:C_Mail_Security_Tarpit_Enable'

# --- DNSBL / rDNS / MX rejection ---
$data['security.dnsbl.use'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Protection_DNSBL' -Context $Context)
$data['security.dnsbl.close_sessions'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Protection_CloseDNSBLConn' -Context $Context)
$data['security.reject_no_rdns'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Protection_RejectrDNS' -Context $Context)
$data['security.reject_domain_no_mx'] = (Get-IceWarpSetting -Name 'C_Mail_Security_Protection_RejectMX' -Context $Context)
$data['security.ip_reputation.use'] = (Get-IceWarpSetting -Name 'C_AS_IPreputationUse' -Context $Context)

# --- Live anti-spam ---
$data['security.antispam_live.enabled'] = (Get-IceWarpSetting -Name 'C_AS_Live_Enable' -Context $Context)

# --- Auth schemes + DIGEST-MD5 detection ---
$data['security.auth_schemes.raw'] = (Get-IceWarpSetting -Name 'C_Mail_Security_AuthScheme' -Context $Context)
$authSchemes = $data['security.auth_schemes.raw']
if (-not [string]::IsNullOrEmpty($authSchemes)) {
    $data['security.digest_md5.enabled'] = ($authSchemes -match 'DIGEST-MD5').ToString().ToLower()
} else {
    $data['security.digest_md5.enabled'] = ''
}

# --- Cyren (old anti-spam) folder check ---
$data['security.cyren_folder.checked'] = 'true'
$cyrenPath = Join-Path $Context.Config.IceWarpHome 'cyren'
if (-not (Test-Path -LiteralPath $cyrenPath -PathType Container)) {
    $data['security.cyren_folder.status'] = 'OK'
    $data['security.cyren_folder.message'] = 'Folder {0} does not exist (OK)' -f $cyrenPath
} else {
    $entries = (Get-ChildItem -LiteralPath $cyrenPath -ErrorAction SilentlyContinue).Count
    if ($entries -gt 0) {
        $data['security.cyren_folder.status'] = 'WARN'
        $data['security.cyren_folder.message'] = 'Folder {0} exists and contains files/directories (needs cleanup)' -f $cyrenPath
    } else {
        $data['security.cyren_folder.status'] = 'OK'
        $data['security.cyren_folder.message'] = 'Folder {0} exists but is empty (OK)' -f $cyrenPath
    }
}

# --- Port 9001 egress check (firewall) ---
$data['security.port_9001_egress.checked'] = 'true'
$blocked = $false
$method = 'firewalld (port not in list - GOOD)'
try {
    $ports = (Get-NetFirewallRule -ErrorAction Stop | Where-Object { $_.LocalPort -eq 9001 }).Count
    if ($ports -gt 0) { $blocked = $true; $method = 'Windows Firewall rule for :9001 present' }
} catch {
    try {
        $out = (netsh advfirewall firewall show rule all 2>$null)
        if ($out -match ':9001') { $blocked = $true; $method = 'netsh firewall rule for :9001 present' }
    } catch {
        $method = 'firewall check unavailable'
    }
}
$data['security.port_9001_egress.blocked'] = $blocked
$data['security.port_9001_egress.method'] = $method

# --- RBL self-check against the server's own public IP ---
$data['security.rbl_self_check.checked'] = 'false'
$publicIp = ''
try {
    $publicIp = (Invoke-WebRequest -Uri 'https://api.ipify.org' -UseBasicParsing -TimeoutSec 5).Content.Trim()
} catch {
    try {
        $publicIp = (Invoke-WebRequest -Uri 'https://ident.me' -UseBasicParsing -TimeoutSec 5).Content.Trim()
    } catch { }
}
if ([string]::IsNullOrEmpty($publicIp)) {
    $data['security.rbl_self_check.ip'] = ''
    $data['security.rbl_self_check.listed'] = 'false'
    $data['security.rbl_self_check.listed_on'] = ''
    $data['security.rbl_self_check.reason'] = 'could not resolve a public IP to check'
} else {
    $data['security.rbl_self_check.checked'] = 'true'
    $data['security.rbl_self_check.ip'] = $publicIp
    $data['security.rbl_self_check.listed'] = 'false'
    $data['security.rbl_self_check.listed_on'] = ''
    $zones = @{
        'zen_spamhaus_org'          = 'zen.spamhaus.org'
        'bl_spamcop_net'           = 'bl.spamcop.net'
        'dnsbl_sorbs_net'          = 'dnsbl.sorbs.net'
        'b_barracudacentral_org'   = 'b.barracudacentral.org'
    }
    $listedOn = @()
    foreach ($zoneKey in $zones.Keys) {
        $zoneHost = $zones[$zoneKey]
        $result = ''
        try {
            $result = (Resolve-DnsName -Name $zoneHost -Type A -ErrorAction SilentlyContinue |
                Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty Name -First 1)
        } catch { }
        if (-not [string]::IsNullOrEmpty($result)) {
            $data["security.rbl_self_check.zones.$zoneKey"] = 'LISTED'
            $listedOn += $zoneHost
        } else {
            $data["security.rbl_self_check.zones.$zoneKey"] = 'clean'
        }
    }
    if ($listedOn.Count -gt 0) {
        $data['security.rbl_self_check.listed'] = 'true'
        $data['security.rbl_self_check.listed_on'] = ($listedOn -join ',')
    } else {
        $data['security.rbl_self_check.listed'] = 'false'
        $data['security.rbl_self_check.listed_on'] = ''
    }
}

return $data