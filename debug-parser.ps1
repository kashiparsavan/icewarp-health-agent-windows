$ErrorActionPreference = 'Stop'

# Exact raw output from the lab server for "tool.exe list domain".
$raw = "`r`n##internalservicedomain.icewarp.com##`r`n`r`nmtitc.ir`r`n"

Write-Output "=== current parser logic ==="
$domains = @()
foreach ($line in ($raw -split "`r?`n")) {
    if ([string]::IsNullOrWhiteSpace($line)) {
        Write-Output "  SKIP blank"
        continue
    }
    $trimmed = $line.Trim()
    if ($trimmed -match '^##.*##$') {
        Write-Output "  SKIP internal: $trimmed"
        continue
    }
    if ($trimmed -match '^-{3,}$' -or $trimmed -match '^={3,}$') {
        Write-Output "  SKIP separator: $trimmed"
        continue
    }
    if ($trimmed -match '^(Domain|Name|Account|Type|ID)\s*$' -or
        $trimmed -match '^(Domain|Name|Account|Type)\s+(.+)') {
        Write-Output "  SKIP header: $trimmed"
        continue
    }
    $token = ($trimmed -split '\s+')[0]
    Write-Output "  ADD token='$token' (full='$trimmed')"
    $domains += $token
}

Write-Output "result type=$($domains.GetType().FullName) count=$($domains.Count)"
foreach ($e in $domains) { Write-Output "  elem type=$($e.GetType().FullName) value='$e'" }

Write-Output "=== @() wrapped ==="
$w = @($domains)
foreach ($e in $w) { Write-Output "  elem type=$($e.GetType().FullName) value='$e'" }

Write-Output "=== simulate Get-IceWarpDomainSetting param binding ==="
foreach ($d in $w) {
    Write-Output "passing type=$($d.GetType().FullName) value='$d'"
}