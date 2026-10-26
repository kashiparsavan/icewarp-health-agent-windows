#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp domain and user information.

.DESCRIPTION
Maps to checklist items "Daily Send Email limit", "Disk Quota", and the
domain-level limits. Domains are auto-discovered via "tool list domain",
with the internal service domain ("##internalservicedomain.icewarp.com##")
filtered out automatically. Per-domain limits are read for the first real
domain only, since the checklist report needs one stable key to point at
regardless of the real domain name.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$domains = @(Get-IceWarpDomainList -Context $Context)
if ($domains.Count -eq 0) {
    $data['domain.checked'] = $false
    $data['domain.reason'] = 'no domains returned by "tool list domain" (or tool.exe unavailable)'
    $data['domain.count'] = 0
    return $data
}

$data['domain.checked'] = $true
$data['domain.count'] = $domains.Count
$data['domain.list'] = ($domains -join ';')

$count = 0
foreach ($domain in @($domains)) {
    $count++
    $keySafe = ($domain -replace '[^A-Za-z0-9]', '')

    $data["domain.${keySafe}.daily_send_messages_limit"] = `
        (Get-IceWarpDomainSetting -Domain $domain -Name 'D_NumberLimit' -Context $Context)
    $data["domain.${keySafe}.disk_quota_kb"] = `
        (Get-IceWarpDomainSetting -Domain $domain -Name 'D_DiskQuota' -Context $Context)
    $data["domain.${keySafe}.user_send_data_limit_mb_per_day"] = `
        (Get-IceWarpDomainSetting -Domain $domain -Name 'D_UserMB' -Context $Context)

    # Fixed alias for the first domain seen, since the checklist report needs
    # one stable key to point at regardless of the real domain name.
    if ($count -eq 1) {
        $data['domain.primary.name'] = $domain
        $data['domain.primary.daily_send_messages_limit'] = `
            $data["domain.${keySafe}.daily_send_messages_limit"]
    }
}

# Per-user data is not collected here: "tool list domain" returns domain
# names only, and reading user-level settings (U_*) requires a username.
# User listing is a separate follow-up. Domain-level limits (D_*) are the
# checklist items this collector maps to.

return $data
