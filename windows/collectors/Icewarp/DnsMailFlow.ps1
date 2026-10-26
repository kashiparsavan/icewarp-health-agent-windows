#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp DNS mail-flow checks.

.DESCRIPTION
Maps to the dns.* section of the Linux health.json schema. Produces
exactly the same keys the Linux collectors produce, nothing more and
nothing less. PTR, SPF, DKIM, DMARC and external resolver tests are run
with PowerShell's Resolve-DnsName cmdlet. A missing or unresolvable name
yields an empty string rather than a crash.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

# The mail hostname is the domain used for SPF/DKIM/DMARC lookups.
$hostname = [string]$Context.Config.MailHostname
if ([string]::IsNullOrEmpty($hostname)) {
    $hostname = [string]$Context.Config.MailDomain
}
if ([string]::IsNullOrEmpty($hostname)) {
    $hostname = $env:COMPUTERNAME
}

# --- dns.configured_server - the DNS servers IceWarp was told to use ---
$data['dns.configured_server'] = (Get-IceWarpSetting -Name 'C_Mail_SMTP_General_DNSServer' -Context $Context)

# --- Public IP of this server (used by PTR and SPF) ---
$publicIp = ''
try {
    $publicIp = (Invoke-WebRequest -Uri 'https://api.ipify.org' -UseBasicParsing -TimeoutSec 5).Content.Trim()
} catch {
    try {
        $publicIp = (Invoke-WebRequest -Uri 'https://ident.me' -UseBasicParsing -TimeoutSec 5).Content.Trim()
    } catch { }
}

# --- dns.ptr.* ---
if ([string]::IsNullOrEmpty($publicIp)) {
    $data['dns.ptr.checked'] = 'false'
    $data['dns.ptr.ip'] = ''
    $data['dns.ptr.result'] = ''
    $data['dns.ptr.exists'] = 'false'
    $data['dns.ptr.matches_hostname'] = 'false'
} else {
    $data['dns.ptr.checked'] = 'true'
    $data['dns.ptr.ip'] = $publicIp
    $ptrResult = ''
    try {
        $ptr = (Resolve-DnsName -Name $publicIp -Type PTR -ErrorAction SilentlyContinue |
            Where-Object { $_.Type -eq 'PTR' } | Select-Object -ExpandProperty Name -First 1)
        if ($ptr) { $ptrResult = $ptr.TrimEnd('.') }
    } catch { }
    $data['dns.ptr.result'] = $ptrResult
    $data['dns.ptr.exists'] = (-not [string]::IsNullOrEmpty($ptrResult)).ToString().ToLower()
    $data['dns.ptr.matches_hostname'] = ($ptrResult -ieq $hostname).ToString().ToLower()
}

# --- External resolver tests ---
$data['dns.resolver.external_test_host'] = 'google.com'
$data['dns.resolver.external_test_ok'] = 'false'
$data['dns.resolver.external_test_ok_google_com'] = 'false'
$data['dns.resolver.external_test_ok_icewarp_com'] = 'false'
$data['dns.resolver.external_test_ok_parsavan_com'] = 'false'
$anyOk = $false
foreach ($extHost in @('google.com', 'icewarp.com', 'parsavan.com')) {
    $ok = $false
    try {
        $r = (Resolve-DnsName -Name $extHost -Type A -ErrorAction SilentlyContinue |
            Where-Object { $_.Type -eq 'A' } | Select-Object -First 1)
        if ($r) { $ok = $true }
    } catch { }
    # Sanitize the host name for the key: dots become underscores, matching
    # the Linux schema (dns.resolver.external_test_ok_google_com etc.).
    $safeHost = $extHost -replace '\.', '_'
    $data["dns.resolver.external_test_ok_${safeHost}"] = $ok.ToString().ToLower()
    if ($ok) { $anyOk = $true }
}
$data['dns.resolver.external_test_ok'] = $anyOk.ToString().ToLower()

# --- dns.lookup_test.* ---
$lookupHost = $hostname
$data['dns.lookup_test.host'] = $lookupHost
$data['dns.lookup_test.ok'] = 'false'
$data['dns.lookup_test.result'] = ''
try {
    $r = (Resolve-DnsName -Name $lookupHost -Type A -ErrorAction SilentlyContinue |
        Where-Object { $_.Type -eq 'A' } | Select-Object -First 1)
    if ($r) {
        $data['dns.lookup_test.ok'] = 'true'
        $data['dns.lookup_test.result'] = $r.IPAddress
    }
} catch { }

# --- dns.spf.* ---
if ([string]::IsNullOrEmpty($hostname)) {
    $data['dns.spf.checked'] = 'false'
    $data['dns.spf.domain'] = ''
    $data['dns.spf.found'] = 'false'
    $data['dns.spf.record'] = ''
    $data['dns.spf.checked_ip'] = $publicIp
    $data['dns.spf.includes_server_ip'] = 'false'
    $data['dns.spf.ip_coverage_via'] = ''
} else {
    $data['dns.spf.checked'] = 'true'
    $data['dns.spf.domain'] = $hostname
    $data['dns.spf.checked_ip'] = $publicIp
    $spfRecord = ''
    try {
        $txt = (Resolve-DnsName -Name $hostname -Type TXT -ErrorAction SilentlyContinue |
            Where-Object { $_.Type -eq 'TXT' } | Select-Object -ExpandProperty Strings -First 1)
        if ($txt) { $spfRecord = [string]$txt }
    } catch { }
    if ($spfRecord -match 'v=spf1') {
        $data['dns.spf.found'] = 'true'
        $data['dns.spf.record'] = $spfRecord
    } else {
        $data['dns.spf.found'] = 'false'
        $data['dns.spf.record'] = $spfRecord
    }
    $includesIp = $false
    $coverageVia = ''
    if (-not [string]::IsNullOrEmpty($publicIp)) {
        if ($spfRecord -match "ip4:$publicIp" -or $spfRecord -match "ip6:$publicIp") {
            $includesIp = $true
            $coverageVia = 'literal ip4/ip6 mechanism'
        } elseif ($spfRecord -match '\+a\b' -or $spfRecord -match '\+mx\b') {
            $includesIp = $true
            $coverageVia = 'a/mx mechanism'
        }
    }
    $data['dns.spf.includes_server_ip'] = $includesIp.ToString().ToLower()
    $data['dns.spf.ip_coverage_via'] = $coverageVia
}

# --- dns.dkim.* ---
$data['dns.dkim.selectors_tried'] = 'default,dkim,mail,selector1,selector2,k1,s1,google'
if ([string]::IsNullOrEmpty($hostname)) {
    $data['dns.dkim.checked'] = 'false'
    $data['dns.dkim.domain'] = ''
    $data['dns.dkim.found'] = 'false'
    $data['dns.dkim.selector_found'] = ''
    $data['dns.dkim.record'] = ''
} else {
    $data['dns.dkim.checked'] = 'true'
    $data['dns.dkim.domain'] = $hostname
    $dkimRecord = ''
    $dkimSelector = ''
    foreach ($sel in 'default', 'dkim', 'mail', 'selector1', 'selector2', 'k1', 's1', 'google') {
        try {
            $txt = (Resolve-DnsName -Name "$sel._$hostname" -Type TXT -ErrorAction SilentlyContinue |
                Where-Object { $_.Type -eq 'TXT' } | Select-Object -ExpandProperty Strings -First 1)
            if ($txt -and [string]$txt -match 'v=DKIM1') {
                $dkimRecord = [string]$txt
                $dkimSelector = $sel
                break
            }
        } catch { }
    }
    if ($dkimRecord) {
        $data['dns.dkim.found'] = 'true'
        $data['dns.dkim.selector_found'] = $dkimSelector
        $data['dns.dkim.record'] = $dkimRecord
    } else {
        $data['dns.dkim.found'] = 'false'
        $data['dns.dkim.selector_found'] = ''
        $data['dns.dkim.record'] = ''
    }
}

# --- dns.dmarc.* ---
if ([string]::IsNullOrEmpty($hostname)) {
    $data['dns.dmarc.checked'] = 'false'
    $data['dns.dmarc.domain'] = ''
    $data['dns.dmarc.found'] = 'false'
    $data['dns.dmarc.record'] = ''
    $data['dns.dmarc.policy'] = ''
    $data['dns.dmarc.policy_note'] = ''
} else {
    $data['dns.dmarc.checked'] = 'true'
    $data['dns.dmarc.domain'] = $hostname
    $dmarcRecord = ''
    try {
        $txt = (Resolve-DnsName -Name "_$hostname" -Type TXT -ErrorAction SilentlyContinue |
            Where-Object { $_.Type -eq 'TXT' } | Select-Object -ExpandProperty Strings -First 1)
        if ($txt) { $dmarcRecord = [string]$txt }
    } catch { }
    if ($dmarcRecord -match 'v=DMARC1') {
        $data['dns.dmarc.found'] = 'true'
        $data['dns.dmarc.record'] = $dmarcRecord
        if ($dmarcRecord -match 'p=([^;]+)') {
            $policy = $Matches[1].Trim()
            $data['dns.dmarc.policy'] = $policy
            if ($policy -eq 'none') {
                $data['dns.dmarc.policy_note'] = 'p=none - monitoring only, not actually enforcing/blocking anything'
            } else {
                $data['dns.dmarc.policy_note'] = ''
            }
        } else {
            $data['dns.dmarc.policy'] = ''
            $data['dns.dmarc.policy_note'] = ''
        }
    } else {
        $data['dns.dmarc.found'] = 'false'
        $data['dns.dmarc.record'] = $dmarcRecord
        $data['dns.dmarc.policy'] = ''
        $data['dns.dmarc.policy_note'] = ''
    }
}

return $data