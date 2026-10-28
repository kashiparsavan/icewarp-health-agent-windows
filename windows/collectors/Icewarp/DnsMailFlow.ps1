#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp DNS mail-flow checks.

.DESCRIPTION
Maps to the dns.* section of the Linux health.json schema. PTR, SPF, DKIM,
DMARC and external resolver tests use the shared Resolve-AgentDnsName
helper, so every query has a bounded, mockable entry point. A missing or
unresolvable name yields an empty value rather than a crash.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$networkTimeout = 10
try {
    $parsedTimeout = [int]$Context.Config.NetworkTimeoutSeconds
    if ($parsedTimeout -gt 0) { $networkTimeout = $parsedTimeout }
} catch { }

# The mail hostname is the domain used for SPF/DKIM/DMARC lookups. Normalize
# away a scheme, path, port or trailing dot so every DNS query is valid.
#
# The configured primary IceWarp domain is the authoritative source for
# these lookups (it is what the server actually answers mail for). The
# server hostname / COMPUTERNAME are only a last resort - using them would
# make the checks run against the wrong name (e.g. win-6leqfj5p7er instead
# of mtitc.ir).
$hostname = ConvertTo-AgentHostName -Value ([string]$Context.Config.MailHostname)
if ([string]::IsNullOrEmpty($hostname)) {
    $hostname = ConvertTo-AgentHostName -Value ([string]$Context.Config.MailDomain)
}
if ([string]::IsNullOrEmpty($hostname)) {
    $primaryDomain = (Get-IceWarpDomainList -Context $Context) | Select-Object -First 1
    if ($primaryDomain) {
        $hostname = ConvertTo-AgentHostName -Value ([string]$primaryDomain)
    }
}
if ([string]::IsNullOrEmpty($hostname)) {
    $hostname = ConvertTo-AgentHostName -Value ([string]$env:COMPUTERNAME)
}

# --- dns.configured_server - the DNS servers IceWarp was told to use ---
$data['dns.configured_server'] = (Get-IceWarpSetting -Name 'C_Mail_SMTP_General_DNSServer' -Context $Context)

# --- Public IP of this server (used by PTR and SPF) ---
$publicIp = Get-AgentPublicIpAddress -TimeoutSeconds $networkTimeout

# --- dns.ptr.* ---
$data['dns.ptr.checked'] = $false
$data['dns.ptr.ip'] = $publicIp
$data['dns.ptr.result'] = ''
$data['dns.ptr.exists'] = $false
$data['dns.ptr.matches_hostname'] = $false
if (-not [string]::IsNullOrEmpty($publicIp)) {
    $data['dns.ptr.checked'] = $true
    $ptrResult = ''
    foreach ($record in @(Resolve-AgentDnsName -Name $publicIp -Type PTR)) {
        if ($null -eq $record) { continue }
        if ($record.PSObject.Properties['Type'] -and [string]$record.Type -ne 'PTR') { continue }
        if ($record.PSObject.Properties['NameHost'] -and -not [string]::IsNullOrWhiteSpace([string]$record.NameHost)) {
            $ptrResult = ConvertTo-AgentHostName -Value ([string]$record.NameHost)
            if ($ptrResult) { break }
        }
    }
    $data['dns.ptr.result'] = $ptrResult
    $data['dns.ptr.exists'] = (-not [string]::IsNullOrEmpty($ptrResult))
    if (-not [string]::IsNullOrEmpty($ptrResult) -and -not [string]::IsNullOrEmpty($hostname)) {
        $data['dns.ptr.matches_hostname'] = ($ptrResult -ieq $hostname)
    }
}

# --- External resolver tests ---
$data['dns.resolver.external_test_host'] = 'google.com'
$data['dns.resolver.external_test_ok'] = $false
$anyOk = $false
foreach ($extHost in @('google.com', 'icewarp.com', 'parsavan.com')) {
    $ok = $false
    foreach ($record in @(Resolve-AgentDnsName -Name $extHost -Type A)) {
        if ($null -ne $record -and $record.PSObject.Properties['Type'] -and [string]$record.Type -eq 'A') {
            $ok = $true
            break
        }
    }
    $safeHost = $extHost -replace '\.', '_'
    $data["dns.resolver.external_test_ok_${safeHost}"] = $ok
    if ($ok) { $anyOk = $true }
}
$data['dns.resolver.external_test_ok'] = $anyOk

# --- dns.lookup_test.* ---
$data['dns.lookup_test.host'] = $hostname
$data['dns.lookup_test.ok'] = $false
$data['dns.lookup_test.result'] = ''
if (-not [string]::IsNullOrEmpty($hostname)) {
    foreach ($record in @(Resolve-AgentDnsName -Name $hostname -Type A)) {
        if ($null -eq $record -or -not $record.PSObject.Properties['Type'] -or [string]$record.Type -ne 'A') {
            continue
        }
        if ($record.PSObject.Properties['IPAddress'] -and -not [string]::IsNullOrWhiteSpace([string]$record.IPAddress)) {
            $data['dns.lookup_test.ok'] = $true
            $data['dns.lookup_test.result'] = [string]$record.IPAddress
            break
        }
    }
}

# --- dns.spf.* ---
$data['dns.spf.checked'] = (-not [string]::IsNullOrEmpty($hostname))
$data['dns.spf.domain'] = $hostname
$data['dns.spf.found'] = $false
$data['dns.spf.record'] = ''
$data['dns.spf.checked_ip'] = $publicIp
$data['dns.spf.includes_server_ip'] = $false
$data['dns.spf.ip_coverage_via'] = ''

if (-not [string]::IsNullOrEmpty($hostname)) {
    $spfRecord = ''
    foreach ($txtValue in @(Get-AgentDnsTxtValues -Records @(Resolve-AgentDnsName -Name $hostname -Type TXT))) {
        if ($txtValue -match '(?i)(?:^|\s)v=spf1(?:\s|$)') {
            $spfRecord = $txtValue
            break
        }
    }

    if (-not [string]::IsNullOrEmpty($spfRecord)) {
        $data['dns.spf.found'] = $true
        $data['dns.spf.record'] = $spfRecord
    }

    if (-not [string]::IsNullOrEmpty($spfRecord) -and -not [string]::IsNullOrEmpty($publicIp)) {
        $covered = $false
        $coverageVia = ''

        foreach ($token in @($spfRecord -split '\s+')) {
            if ($covered) { break }
            if ([string]::IsNullOrWhiteSpace($token)) { continue }

            if ($token -match '^([+\-~?]?)(ip4|ip6):(.+)$') {
                $qualifier = $Matches[1]
                $mechanism = $Matches[2].ToLowerInvariant()
                $network = $Matches[3]
                if ($qualifier -eq '-' -or $qualifier -eq '~' -or $qualifier -eq '?') { continue }
                if ($mechanism -eq 'ip4' -and $publicIp.Contains(':')) { continue }
                if ($mechanism -eq 'ip6' -and -not $publicIp.Contains(':')) { continue }
                if (Test-AgentIpInCidr -Ip $publicIp -Cidr $network) {
                    $covered = $true
                    $coverageVia = 'literal ip4/ip6 mechanism'
                }
                continue
            }

            if ($token -match '^([+\-~?]?)a(?::([^/\s]+))?(?:/([0-9]{1,3}))?$') {
                $qualifier = $Matches[1]
                $target = $Matches[2]
                $prefix = $Matches[3]
                if ($qualifier -eq '-' -or $qualifier -eq '~' -or $qualifier -eq '?') { continue }
                if ([string]::IsNullOrEmpty($target)) { $target = $hostname }

                foreach ($record in @(Resolve-AgentDnsName -Name $target -Type A)) {
                    if ($covered) { break }
                    if ($null -eq $record -or -not $record.PSObject.Properties['IPAddress']) { continue }
                    $address = [string]$record.IPAddress
                    if ([string]::IsNullOrEmpty($address)) { continue }
                    $matchesAddress = if ([string]::IsNullOrEmpty($prefix)) {
                        ($address -eq $publicIp)
                    } else {
                        (Test-AgentIpInCidr -Ip $publicIp -Cidr ('{0}/{1}' -f $address, $prefix))
                    }
                    if ($matchesAddress) {
                        $covered = $true
                        $coverageVia = ('a mechanism ({0} A record matches)' -f $target)
                    }
                }
                continue
            }

            if ($token -match '^([+\-~?]?)mx(?::([^/\s]+))?(?:/([0-9]{1,3}))?$') {
                $qualifier = $Matches[1]
                $target = $Matches[2]
                $prefix = $Matches[3]
                if ($qualifier -eq '-' -or $qualifier -eq '~' -or $qualifier -eq '?') { continue }
                if ([string]::IsNullOrEmpty($target)) { $target = $hostname }

                foreach ($mxRecord in @(Resolve-AgentDnsName -Name $target -Type MX)) {
                    if ($covered) { break }
                    if ($null -eq $mxRecord -or -not $mxRecord.PSObject.Properties['NameExchange']) { continue }
                    $mxHost = ConvertTo-AgentHostName -Value ([string]$mxRecord.NameExchange)
                    if ([string]::IsNullOrEmpty($mxHost)) { continue }

                    foreach ($aRecord in @(Resolve-AgentDnsName -Name $mxHost -Type A)) {
                        if ($covered) { break }
                        if ($null -eq $aRecord -or -not $aRecord.PSObject.Properties['IPAddress']) { continue }
                        $address = [string]$aRecord.IPAddress
                        if ([string]::IsNullOrEmpty($address)) { continue }
                        $matchesAddress = if ([string]::IsNullOrEmpty($prefix)) {
                            ($address -eq $publicIp)
                        } else {
                            (Test-AgentIpInCidr -Ip $publicIp -Cidr ('{0}/{1}' -f $address, $prefix))
                        }
                        if ($matchesAddress) {
                            $covered = $true
                            $coverageVia = ('mx mechanism ({0} A record matches)' -f $mxHost)
                        }
                    }
                }
            }
        }

        $data['dns.spf.includes_server_ip'] = $covered
        $data['dns.spf.ip_coverage_via'] = $coverageVia
    }
}

# --- dns.dkim.* ---
$selectors = @('default', 'dkim', 'mail', 'selector1', 'selector2', 'k1', 's1', 'google')
$data['dns.dkim.selectors_tried'] = ($selectors -join ',')
$data['dns.dkim.checked'] = (-not [string]::IsNullOrEmpty($hostname))
$data['dns.dkim.domain'] = $hostname
$data['dns.dkim.found'] = $false
$data['dns.dkim.selector_found'] = ''
$data['dns.dkim.record'] = ''

# icewarp.dkim.active_flag - the IceWarp-side DKIM toggle, read per domain.
$dkimActive = (Get-IceWarpDomainSetting -Domain $hostname -Name 'D_DKIM_Active' -Context $Context)
$dkimNum = 0
if ([int]::TryParse([string]$dkimActive, [ref]$dkimNum)) {
    $data['icewarp.dkim.active_flag'] = ($dkimNum -eq 1)
} elseif ([string]::IsNullOrEmpty($dkimActive)) {
    $data['icewarp.dkim.active_flag'] = $false
} else {
    $data['icewarp.dkim.active_flag'] = ([bool]($dkimActive -ieq 'true' -or $dkimActive -eq '1'))
}

if (-not [string]::IsNullOrEmpty($hostname)) {
    foreach ($selector in $selectors) {
        $queryName = ('{0}._domainkey.{1}' -f $selector, $hostname)
        foreach ($txtValue in @(Get-AgentDnsTxtValues -Records @(Resolve-AgentDnsName -Name $queryName -Type TXT))) {
            if ($txtValue -match '(?i)^v=DKIM1(?:\s*;|\s|$)') {
                $data['dns.dkim.found'] = $true
                $data['dns.dkim.selector_found'] = $selector
                $data['dns.dkim.record'] = $txtValue
                break
            }
        }
        if ($data['dns.dkim.found']) { break }
    }
}

# --- dns.dmarc.* ---
$data['dns.dmarc.checked'] = (-not [string]::IsNullOrEmpty($hostname))
$data['dns.dmarc.domain'] = $hostname
$data['dns.dmarc.found'] = $false
$data['dns.dmarc.record'] = ''
$data['dns.dmarc.policy'] = ''
$data['dns.dmarc.policy_note'] = ''

if (-not [string]::IsNullOrEmpty($hostname)) {
    $dmarcRecord = ''
    foreach ($txtValue in @(Get-AgentDnsTxtValues -Records @(Resolve-AgentDnsName -Name ('_dmarc.{0}' -f $hostname) -Type TXT))) {
        if ($txtValue -match '(?i)^v=DMARC1(?:\s*;|\s|$)') {
            $dmarcRecord = $txtValue
            break
        }
    }

    if (-not [string]::IsNullOrEmpty($dmarcRecord)) {
        $data['dns.dmarc.found'] = $true
        $data['dns.dmarc.record'] = $dmarcRecord
        if ($dmarcRecord -match '(?i)(?:^|;)\s*p\s*=\s*([^;]+)') {
            $policy = $Matches[1].Trim()
            $data['dns.dmarc.policy'] = $policy
            if ($policy -ieq 'none') {
                $data['dns.dmarc.policy_note'] = 'p=none - monitoring only, not actually enforcing/blocking anything'
            }
        }
    }
}

return $data
