#Requires -Version 5.1
<#
.SYNOPSIS
Flat, type-aware JSON output for the Windows IceWarp Health Agent.

.DESCRIPTION
Mirrors the Linux lib/json.sh writer exactly:

  * keys are sorted (ordinal, the same order as `sort` under the C locale);
  * an empty string becomes JSON null;
  * a string matching ^-?[0-9]+(\.[0-9]+)?$ is emitted as a number, keeping
    its original textual form (e.g. "0.40" stays 0.40);
  * the exact strings "true" and "false" become JSON booleans;
  * every other string is quoted and escaped (backslash, quote, tab, newline,
    carriage return removed);
  * native booleans and numbers are emitted natively.

The file is written to a temporary sibling and then moved into place, so a
reader never sees a half-written health.json.
#>

function ConvertTo-AgentJsonEscapedString {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    $builder = New-Object System.Text.StringBuilder
    foreach ($character in $Value.ToCharArray()) {
        switch ($character) {
            '\' { [void]$builder.Append('\\') }
            '"' { [void]$builder.Append('\"') }
            "`t" { [void]$builder.Append('\t') }
            "`r" { } # Linux json.sh removes carriage returns entirely.
            "`n" { [void]$builder.Append('\n') }
            default { [void]$builder.Append($character) }
        }
    }

    return $builder.ToString()
}

function Format-AgentJsonNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Value
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Value -is [double] -or $Value -is [single]) {
        if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) {
            return $null
        }
        return ([double]$Value).ToString('R', $culture)
    }
    if ($Value -is [decimal]) {
        return ([decimal]$Value).ToString($culture)
    }

    return ([System.Convert]::ToInt64($Value, $culture)).ToString($culture)
}

function Format-AgentJsonScalar {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return 'null'
    }

    if ($Value -is [bool]) {
        if ($Value) { return 'true' }
        return 'false'
    }

    if ($Value -is [string]) {
        if ($Value.Length -eq 0) {
            return 'null'
        }
        if ($Value -match '^-?[0-9]+(\.[0-9]+)?$') {
            return $Value
        }
        if ($Value -ceq 'true' -or $Value -ceq 'false') {
            return $Value
        }
        return ('"{0}"' -f (ConvertTo-AgentJsonEscapedString -Value $Value))
    }

    if ($Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64] -or
        $Value -is [double] -or $Value -is [single] -or
        $Value -is [decimal]) {
        $number = Format-AgentJsonNumber -Value $Value
        if ($null -ne $number) {
            return $number
        }
    }

    return ('"{0}"' -f (ConvertTo-AgentJsonEscapedString -Value ([string]$Value)))
}

function ConvertTo-AgentJsonText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    # Linux sorts the key list with `sort`; ordinal gives the same stable,
    # case-sensitive byte ordering for the dotted ASCII keys in this schema.
    [string[]]$keys = @($Data.Keys | ForEach-Object { [string]$_ })
    [Array]::Sort($keys, [System.StringComparer]::Ordinal)

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append("{`n")

    for ($index = 0; $index -lt $keys.Length; $index++) {
        $key = $keys[$index]
        [void]$builder.Append('  "')
        [void]$builder.Append((ConvertTo-AgentJsonEscapedString -Value $key))
        [void]$builder.Append('":')
        [void]$builder.Append((Format-AgentJsonScalar -Value $Data[$key]))

        if ($index -lt ($keys.Length - 1)) {
            [void]$builder.Append(',')
        }
        [void]$builder.Append("`n")
    }

    [void]$builder.Append('}')
    return $builder.ToString()
}

function Write-AgentJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and
        -not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $json = ConvertTo-AgentJsonText -Data $Data
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $temporaryPath = ('{0}.tmp.{1}' -f $Path, $PID)

    try {
        [System.IO.File]::WriteAllText($temporaryPath, $json + [Environment]::NewLine, $encoding)

        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            try {
                [System.IO.File]::Replace($temporaryPath, $Path, $null)
            } catch {
                # File.Replace can fail on some network/container filesystems.
                # Move-Item -Force is still an atomic same-volume rename.
                Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
            }
        } else {
            Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
        }
    } finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }

    Write-AgentLog -Level INFO -Message ('Wrote JSON output: {0}' -f $Path)
}
