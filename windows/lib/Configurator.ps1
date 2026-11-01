#Requires -Version 5.1
<#
.SYNOPSIS
IceWarp Configurator for Windows.

Compares the live IceWarp configuration against a recommended PSD1
and either reports differences (dry-run) or applies them via
tool.exe set system <key> <value>.

The recommended settings live in config/recommended.psd1.
#>

function Get-RecommendedConfig {
    [CmdletBinding()]
    param([string]$ConfigPath)

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Recommended config not found: $ConfigPath"
    }

    $settings = @{}
    foreach ($line in ((Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction Stop) -split "`r?`n")) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrEmpty($trimmed) -or $trimmed.StartsWith('#')) { continue }
        $parts = $trimmed.Split('=', 2)
        if ($parts.Length -ne 2) { continue }
        $key = $parts[0].Trim()
        $val = $parts[1].Trim()
        # Also strip any trailing whitespace from the key (already done by Trim)
        if ([string]::IsNullOrEmpty($key)) { continue }
        if ($val.Length -ge 2 -and $val[0] -eq '"' -and $val[-1] -eq '"') {
            $val = $val.Substring(1, $val.Length - 2)
        }
        $settings[$key] = $val
    }
    return $settings
}

function Get-IceWarpSettingLive {
    [CmdletBinding()]
    param(
        [string]$ToolPath,
        [string]$Key,
        [int]$TimeoutSeconds = 10
    )

    if (-not (Test-IceWarpTool -ToolPath $ToolPath)) {
        return $null
    }

    try {
        $output = Invoke-IceWarpTool -ToolPath $ToolPath -Arguments "get system `"$Key`"" -TimeoutSeconds $TimeoutSeconds
        return (ConvertFrom-IceWarpToolOutput -Output $output)
    } catch {
        return $null
    }
}

function Compare-RecommendedConfig {
    [CmdletBinding()]
    param(
        [hashtable]$Recommended,
        [string]$ToolPath,
        [int]$TimeoutSeconds = 10
    )

    $results = @()
    foreach ($key in $Recommended.Keys) {
        $desired = [string]$Recommended[$key]
        $actual = Get-IceWarpSettingLive -ToolPath $ToolPath -Key $key -TimeoutSeconds $TimeoutSeconds
        $match = ($actual -ne $null -and $actual -eq $desired)
        $results += [pscustomobject]@{
            Key     = $key
            Desired = $desired
            Actual  = if ($actual -eq $null) { '(not set)' } else { $actual }
            Match   = $match
        }
    }
    return $results
}

function Format-ConfigDiff {
    [CmdletBinding()]
    param([object[]]$Results)

    $correct = 0
    $change  = 0

    foreach ($r in $Results) {
        if ($r.Match) {
            Write-Host "[OK]   $($r.Key) = $($r.Actual)" -ForegroundColor Green
            $correct++
        } else {
            Write-Host "[CHG]  $($r.Key) = $($r.Desired)  (currently: $($r.Actual))" -ForegroundColor Yellow
            $change++
        }
    }

    Write-Host ""
    Write-Host "Already correct: $correct"
    Write-Host "Will change:     $change"
    return $correct, $change
}

function Invoke-ApplyConfig {
    [CmdletBinding()]
    param(
        [object[]]$Results,
        [string]$ToolPath,
        [int]$TimeoutSeconds = 10
    )

    $applied = 0
    $errors  = 0

    foreach ($r in $Results) {
        if ($r.Match) { continue }
        try {
            $escVal = $r.Desired -replace '"', '""'
            $null = Invoke-IceWarpTool -ToolPath $ToolPath -Arguments "set system `"$($r.Key)`" `"$escVal`"" -TimeoutSeconds $TimeoutSeconds
            Write-Host "[SET]  $($r.Key) = $($r.Desired)" -ForegroundColor Cyan
            $applied++
        } catch {
            Write-Host "[ERR]  $($r.Key): $($_.Exception.Message)" -ForegroundColor Red
            $errors++
        }
    }

    Write-Host ""
    Write-Host "Applied: $applied"
    Write-Host "Errors:  $errors"
    return $applied, $errors
}