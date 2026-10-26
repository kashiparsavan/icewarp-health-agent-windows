$ErrorActionPreference = 'Stop'

# Simulate the real list output: internal domain + blank + one real domain.
$raw = "`r`n##internalservicedomain.icewarp.com##`r`n`r`nmtitc.ir`r`n"

function Get-IceWarpDomainList {
    $domains = @()
    foreach ($line in ($raw -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $trimmed = $line.Trim()
        if ($trimmed -match '^##.*##$') { continue }
        if ($trimmed -match '^-{3,}$' -or $trimmed -match '^={3,}$') { continue }
        if ($trimmed -match '^(Domain|Name|Account|Type|ID)\s*$' -or
            $trimmed -match '^(Domain|Name|Account|Type)\s+(.+)') { continue }
        $domains += ($trimmed -split '\s+')[0]
    }
    return , $domains
}

function Get-IceWarpDomainSetting {
    param([string]$Domain, [string]$Name)
    if ([string]::IsNullOrWhiteSpace($Domain)) { return '' }
    return "value-for-$Domain-$Name"
}

Write-Output "=== exact collector chain ==="
$domains = @(Get-IceWarpDomainList)
Write-Output "after @(): type=$($domains.GetType().FullName) count=$($domains.Count)"
foreach ($i in 0..($domains.Count-1)) {
    $e = $domains[$i]
    Write-Output "  [$i] elem type=$($e.GetType().FullName) isArray=$($e -is [System.Array]) value='$e'"
}

Write-Output "=== foreach and call ==="
$count = 0
foreach ($domain in @($domains)) {
    $count++
    Write-Output "loop iter $count : domain type=$($domain.GetType().FullName) isArray=$($domain -is [System.Array]) value='$domain'"
    try {
        $r = Get-IceWarpDomainSetting -Domain $domain -Name 'D_NumberLimit'
        Write-Output "  OK result='$r'"
    } catch {
        Write-Output "  FAILED: $($_.Exception.Message)"
    }
}