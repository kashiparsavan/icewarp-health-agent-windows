#Requires -Version 5.1
<#
.SYNOPSIS
Collect IceWarp user account information.

.DESCRIPTION
Accounts are auto-discovered via "tool list account". Per-account settings
are read through the shared IceWarp tool wrapper, so the configured
timeout applies. Only a bounded number of accounts are inspected by
default; set Config.MaxAccountsInspected to raise the cap.

Note: "tool list account" returns email addresses, and reading account
settings requires that exact address, so the two calls are paired.
#>

param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

$data = [ordered]@{}

$accounts = @(Get-IceWarpAccountList -Context $Context)
# Flatten any nesting that the list helper may have introduced and coerce
# every entry to a plain string, so the account-setting call always gets a
# System.String regardless of how tool.exe formatted its output.
$flattened = @()
foreach ($entry in $accounts) {
    if ($entry -is [System.Array]) {
        foreach ($sub in $entry) {
            if (-not [string]::IsNullOrWhiteSpace([string]$sub)) {
                $flattened += [string]$sub
            }
        }
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$entry)) {
        $flattened += [string]$entry
    }
}
$accounts = $flattened

$data['account.checked'] = $accounts.Count -gt 0
$data['account.count'] = $accounts.Count
$data['account.list'] = ($accounts -join ';')

if ($accounts.Count -eq 0) {
    $data['account.reason'] = 'no accounts returned by "tool list account" (or tool.exe unavailable)'
    return $data
}

# Cap the number of accounts we actually inspect, so a large mailbox
# cannot blow the run's timeout. Missing config values are read safely
# with the hashtable accessor and default to 50.
$maxInspect = [int]$Context.Config['MaxAccountsInspected']
if ($maxInspect -lt 1) {
    $maxInspect = 50
}
$data['account.inspect_limit'] = $maxInspect
$data['account.inspected'] = [Math]::Min($accounts.Count, $maxInspect)

$count = 0
foreach ($account in $accounts) {
    if ($count -ge $maxInspect) {
        break
    }
    $count++
    $keySafe = ($account -replace '[^A-Za-z0-9@._-]', '_')

    $data["account.${keySafe}.name"] = (Get-IceWarpAccountSetting -Account $account -Name 'U_Name' -Context $Context)
    $data["account.${keySafe}.account_type"] = (Get-IceWarpAccountSetting -Account $account -Name 'U_AccountType' -Context $Context)
    $data["account.${keySafe}.account_disabled"] = (Get-IceWarpAccountSetting -Account $account -Name 'U_AccountDisabled' -Context $Context)
    $data["account.${keySafe}.domain_admin"] = (Get-IceWarpAccountSetting -Account $account -Name 'U_DomainAdmin' -Context $Context)

    # Fixed alias for the first account seen, so the checklist report has
    # one stable key to point at regardless of the real account name.
    if ($count -eq 1) {
        $data['account.primary.name'] = $account
        $data['account.primary.account_type'] = $data["account.${keySafe}.account_type"]
    }
}

return $data