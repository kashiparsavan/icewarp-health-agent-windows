#Requires -Version 5.1
<#
.SYNOPSIS
IceWarp tool.exe wrapper for the Windows Health Agent.

.DESCRIPTION
Every external call is bounded by a timeout. The wrapper never logs setting
values, because some IceWarp settings can contain sensitive data.
#>

function Test-IceWarpTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolPath
    )

    return (Test-Path -LiteralPath $ToolPath -PathType Leaf)
}

function ConvertFrom-IceWarpToolOutput {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Output
    )

    if ([string]::IsNullOrWhiteSpace($Output)) {
        return ''
    }

    $fallback = ''
    foreach ($line in ($Output -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -match '^\s*[^:]+:\s*(.*)$') {
            return $Matches[1].Trim()
        }

        if (-not $fallback) {
            $fallback = $line.Trim()
        }
    }

    return $fallback
}

function Invoke-IceWarpTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolPath,
        [Parameter(Mandatory = $true)]
        [string]$Arguments,
        [int]$TimeoutSeconds = 10
    )

    if (-not (Test-IceWarpTool -ToolPath $ToolPath)) {
        throw "IceWarp tool not found: $ToolPath"
    }

    if ($TimeoutSeconds -lt 1) {
        $TimeoutSeconds = 1
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ToolPath
    $startInfo.Arguments = $Arguments
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.WorkingDirectory = Split-Path -Parent $ToolPath

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                $process.Kill()
            } catch {
                # The process may have exited between the timeout check and Kill().
            }
            [void]$process.WaitForExit(1000)
            throw "IceWarp tool timed out after $TimeoutSeconds seconds: $Arguments"
        }

        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result

        if ($process.ExitCode -ne 0) {
            $errorText = $stderr.Trim()
            if (-not $errorText) {
                $errorText = $stdout.Trim()
            }
            if (-not $errorText) {
                $errorText = 'no error output'
            }
            throw "IceWarp tool exited with code $($process.ExitCode): $errorText"
        }

        return $stdout
    } finally {
        $process.Dispose()
    }
}

function Invoke-IceWarpToolList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ToolPath,
        [Parameter(Mandatory = $true)]
        [string]$ListType,
        [int]$TimeoutSeconds = 10
    )

    if (-not (Test-IceWarpTool -ToolPath $ToolPath)) {
        throw "IceWarp tool not found: $ToolPath"
    }

    if ($TimeoutSeconds -lt 1) {
        $TimeoutSeconds = 1
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ToolPath
    $startInfo.Arguments = ('list {0}' -f $ListType)
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.WorkingDirectory = Split-Path -Parent $ToolPath

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo

    try {
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                $process.Kill()
            } catch {
                # The process may have exited between the timeout check and Kill().
            }
            [void]$process.WaitForExit(1000)
            throw "IceWarp tool timed out after $TimeoutSeconds seconds: list $ListType"
        }

        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result

        if ($process.ExitCode -ne 0) {
            $errorText = $stderr.Trim()
            if (-not $errorText) {
                $errorText = $stdout.Trim()
            }
            if (-not $errorText) {
                $errorText = 'no error output'
            }
            throw "IceWarp tool exited with code $($process.ExitCode): $errorText"
        }

        return $stdout
    } finally {
        $process.Dispose()
    }
}

function Get-IceWarpDomainList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $config = $Context.Config
    if (-not (Test-IceWarpTool -ToolPath $config.ToolPath)) {
        return @()
    }

    try {
        $raw = Invoke-IceWarpToolList -ToolPath $config.ToolPath `
            -ListType 'domain' `
            -TimeoutSeconds ([int]$config.ToolTimeoutSeconds)
    } catch {
        Write-AgentLog -Level WARN -Message ('Could not list IceWarp domains: {0}' -f $_.Exception.Message)
        return @()
    }

    $domains = @()
    foreach ($line in ($raw -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        # IceWarp marks its internal service domain with ##...## delimiters.
        # It is not a real customer domain and must be skipped.
        if ($line -match '^##.*##$') {
            continue
        }
        $domains += $line.Trim()
    }

    return $domains
}

function Get-IceWarpDomainSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Domain,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    if ([string]::IsNullOrWhiteSpace($Domain)) {
        return ''
    }

    $config = $Context.Config
    if (-not (Test-IceWarpTool -ToolPath $config.ToolPath)) {
        return ''
    }

    try {
        $raw = Invoke-IceWarpTool -ToolPath $config.ToolPath `
            -Arguments ('display domain "{0}" {1}' -f $Domain, $Name) `
            -TimeoutSeconds ([int]$config.ToolTimeoutSeconds)
    } catch {
        Write-AgentLog -Level WARN -Message ('Could not read domain setting {0} for {1}: {2}' -f $Name, $Domain, $_.Exception.Message)
        return ''
    }

    # tool.exe prints "D_NumberLimit: 5" - take the value after the first
    # colon on the first non-empty line.
    foreach ($line in ($raw -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        if ($line -match '^\s*[^:]+:\s*(.*)$') {
            return $Matches[1].Trim()
        }
        return $line.Trim()
    }

    return ''
}

function Get-IceWarpSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    $config = $Context.Config
    if (-not (Test-IceWarpTool -ToolPath $config.ToolPath)) {
        Write-AgentLog -Level DEBUG -Message ('IceWarp tool not available; skipping setting {0}.' -f $Name)
        return ''
    }

    try {
        $raw = Invoke-IceWarpTool -ToolPath $config.ToolPath `
            -Arguments ('display system {0}' -f $Name) `
            -TimeoutSeconds ([int]$config.ToolTimeoutSeconds)
        $value = ConvertFrom-IceWarpToolOutput -Output $raw
        Write-AgentLog -Level DEBUG -Message ('Read IceWarp setting {0}.' -f $Name)
        return $value
    } catch {
        Write-AgentLog -Level WARN -Message ('Could not read IceWarp setting {0}: {1}' -f $Name, $_.Exception.Message)
        return ''
    }
}
