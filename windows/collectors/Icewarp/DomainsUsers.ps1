#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp domain-level limits.

.DESCRIPTION
Port of the Linux collectors/icewarp/domain_limits.sh collector. It maps to
the checklist item "Daily Send Email limit" and produces exactly the same
keys the Linux version produces, nothing more and nothing less.

Domains are auto-discovered via "tool list domain", with the internal
service domain ("##internalservicedomain.icewarp.com##") filtered out
automatically. The domain name is sanitized the same way the Linux version
does - strip spaces and tabs only, so "mtitc.ir" stays "mtitc.ir".
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

# Flatten whatever shape the list helper returns into a plain string[].
$domains = @()
foreach ($entry in @(Get-IceWarpDomainList -Context $Context)) {
    if ($entry -is [System.Array]) {
        foreach ($sub in $entry) {
            if (-not [string]::IsNullOrWhiteSpace([string]$sub)) {
                $domains += [string]$sub
            }
        }
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$entry)) {
        $domains += [string]$entry
    }
}

if ($domains.Count -eq 0) {
    $data['domain.checked'] = $false
    $data['domain.count'] = 0
    $data['domain.list'] = ''
    $data['domain.primary.name'] = ''
    $data['domain.primary.daily_send_messages_limit'] = ''
    # The schema sample always carries these three designhost.ir keys. When
    # no domain is discoverable on this host, emit them as empty (null/N/A)
    # rather than leaving them absent from the schema.
    $data['domain.designhost.ir.daily_send_messages_limit'] = ''
    $data['domain.designhost.ir.disk_quota_kb'] = ''
    $data['domain.designhost.ir.user_send_data_limit_mb_per_day'] = ''
    return $data
}

$data['domain.checked'] = $true

$count = 0
foreach ($domain in $domains) {
    if ([string]::IsNullOrWhiteSpace($domain)) {
        continue
    }
    if (-not (Test-IceWarpDomainName -Name $domain)) {
        Write-AgentLog -Level WARN -Message ('Ignoring invalid domain from tool list: {0}' -f $domain)
        continue
    }
    $count++

    # Match the Linux sanitization exactly: strip spaces and tabs only.
    $keySafe = ($domain -replace '[ \t]', '')

    $data["domain.${keySafe}.daily_send_messages_limit"] = `
        (Get-IceWarpDomainSetting -Domain $domain -Name 'D_NumberLimit' -Context $Context)
    $data["domain.${keySafe}.disk_quota_kb"] = `
        (Get-IceWarpDomainSetting -Domain $domain -Name 'D_DiskQuota' -Context $Context)
    $data["domain.${keySafe}.user_send_data_limit_mb_per_day"] = `
        (Get-IceWarpDomainSetting -Domain $domain -Name 'D_UserMB' -Context $Context)

    # Fixed alias for the first domain seen, since the checklist report
    # needs one stable key to point at regardless of the real domain name.
    if ($count -eq 1) {
        $data['domain.primary.name'] = $domain
        $data['domain.primary.daily_send_messages_limit'] = `
            $data["domain.${keySafe}.daily_send_messages_limit"]
    }
}

$data['domain.count'] = $count
# Linux appends a semicolon after every entry, including the last one.
$data['domain.list'] = (($domains -join ';') + ';')

return $data