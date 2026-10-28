#Requires -Version 5.1
<#
.SYNOPSIS
Shared helpers for the Windows IceWarp Health Agent.
#>

function Get-AgentVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $versionPath = Join-Path $Root 'VERSION'
    if (Test-Path -LiteralPath $versionPath -PathType Leaf) {
        $version = (Get-Content -LiteralPath $versionPath -Raw -ErrorAction Stop).Trim()
        if ($version) {
            return $version
        }
    }

    return 'unknown'
}

function Resolve-AgentPath {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $Root $Path))
}

function ConvertTo-AgentHostName {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ''
    }

    $hostName = $Value.Trim()
    $hostName = $hostName -replace '^[A-Za-z][A-Za-z0-9+.-]*://', ''
    $hostName = ($hostName -split '[/\\]', 2)[0]
    $hostName = ($hostName -split '\?', 2)[0]
    if ($hostName -match '^(.+):([0-9]{1,5})$') {
        $hostName = $Matches[1]
    }
    $hostName = $hostName.Trim().TrimEnd('.').ToLowerInvariant()

    if ($hostName.Length -lt 1 -or $hostName.Length -gt 253) {
        return ''
    }
    if ($hostName -notmatch '^(?=.{1,253}$)[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)*$') {
        return ''
    }

    return $hostName
}

function ConvertTo-AgentNumericFlag {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return ''
    }

    $text = [string]$Value
    if ($text -ieq 'true') { return '1' }
    if ($text -ieq 'false') { return '0' }
    return $Value
}

function Test-IceWarpDomainName {    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    $candidate = $Name.Trim().TrimEnd('.')
    if ($candidate.Length -lt 1 -or $candidate.Length -gt 253) {
        return $false
    }

    return ($candidate -match '^(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$')
}

function Initialize-AgentContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $hostName = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($hostName)) {
        try {
            $hostName = [System.Net.Dns]::GetHostName()
        } catch {
            $hostName = 'unknown'
        }
    }

    # Only the three agent.* keys that exist in the 411-key schema. Debug or
    # operational metadata must never leak into health.json.
    $data = [ordered]@{}
    $data['agent.version'] = $Version
    $data['agent.hostname'] = $hostName
    $data['agent.time'] = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $data['general.technician'] = [string]$Config.Technician
    $data['general.company'] = [string]$Config.CompanyName

    return @{
        Root        = $Root
        ProjectRoot = Split-Path -Parent $Root
        Config      = $Config
        Data        = $data
        Version     = $Version
    }
}

function Enter-AgentLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [int]$StaleMinutes = 120
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and
        -not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $lockPid = 0
        $firstField = ''
        try {
            $firstField = ((Get-Content -LiteralPath $Path -Raw -ErrorAction Stop).Trim() -split '\s+')[0]
        } catch { }

        [void][int]::TryParse($firstField, [ref]$lockPid)
        $owner = $null
        if ($lockPid -gt 0) {
            $owner = Get-Process -Id $lockPid -ErrorAction SilentlyContinue
        }

        if ($owner) {
            throw ('Another agent run is already in progress (PID {0}, lock {1}).' -f $lockPid, $Path)
        }

        if ($lockPid -gt 0) {
            # The owning process is gone (crash or reboot): the lock is stale
            # even if it is recent, so remove it and continue.
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        } else {
            $lockItem = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
            $ageMinutes = 0
            if ($lockItem) {
                $ageMinutes = ((Get-Date) - $lockItem.LastWriteTime).TotalMinutes
            }
            if ($ageMinutes -lt $StaleMinutes) {
                throw ('Agent lock {0} is unreadable and recent. Remove it if no agent is running.' -f $Path)
            }
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        }
    }

    $content = ('{0} {1}' -f $PID, (Get-Date).ToString('o'))
    [System.IO.File]::WriteAllText($Path, $content + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
}

function Exit-AgentLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }

    try {
        $firstField = ((Get-Content -LiteralPath $Path -Raw -ErrorAction Stop).Trim() -split '\s+')[0]
        if ($firstField -eq [string]$PID) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        }
    } catch {
        # Never let lock cleanup mask the real result.
    }
}

function Get-AgentPublicIpAddress {
    [CmdletBinding()]
    param(
        [int]$TimeoutSeconds = 5
    )

    if ($TimeoutSeconds -lt 1) {
        $TimeoutSeconds = 1
    }

    foreach ($endpoint in @('https://api.ipify.org', 'https://ident.me')) {
        try {
            $content = (Invoke-WebRequest -Uri $endpoint -UseBasicParsing -TimeoutSec $TimeoutSeconds -ErrorAction Stop).Content
            $candidate = ([string]$content -split "`r?`n")[0].Trim()
            $address = $null
            if ([System.Net.IPAddress]::TryParse($candidate, [ref]$address)) {
                return $address.ToString()
            }
        } catch {
            # Try the next endpoint.
        }
    }

    return ''
}

function Resolve-AgentDnsName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Type = 'A'
    )

    if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($Type)) {
        return @()
    }

    $parameters = @{
        Name        = $Name
        Type        = $Type
        ErrorAction = 'SilentlyContinue'
    }

    $command = Get-Command -Name Resolve-DnsName -ErrorAction SilentlyContinue
    if ($command -and $command.Parameters.ContainsKey('QuickTimeout')) {
        $parameters['QuickTimeout'] = $true
    }

    try {
        return @(Resolve-DnsName @parameters)
    } catch {
        return @()
    }
}

function Get-DnsTxtValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Record
    )

    if ($null -eq $Record) {
        return ''
    }

    if ($Record.PSObject.Properties['Strings'] -and $null -ne $Record.Strings) {
        return ((@($Record.Strings) | ForEach-Object { [string]$_ }) -join '')
    }
    if ($Record.PSObject.Properties['Text'] -and $null -ne $Record.Text) {
        return [string]$Record.Text
    }

    return ''
}

function Get-AgentDnsTxtValues {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Records
    )

    $values = @()
    foreach ($record in @($Records)) {
        if ($null -eq $record) { continue }
        if ($record.PSObject.Properties['Type'] -and [string]$record.Type -ne 'TXT') { continue }
        $value = Get-DnsTxtValue -Record $record
        if (-not [string]::IsNullOrEmpty($value)) {
            $values += $value
        }
    }

    return @($values)
}

function Test-AgentIpInCidr {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Ip,
        [Parameter(Mandatory = $true)]
        [string]$Cidr
    )

    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($Ip, [ref]$address)) {
        return $false
    }

    $parts = $Cidr.Split('/', 2)
    $network = $null
    if (-not [System.Net.IPAddress]::TryParse($parts[0], [ref]$network)) {
        return $false
    }
    if ($address.AddressFamily -ne $network.AddressFamily) {
        return $false
    }

    $maximumPrefix = if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) { 32 } else { 128 }
    $prefix = $maximumPrefix
    if ($parts.Count -eq 2) {
        if (-not [int]::TryParse($parts[1], [ref]$prefix) -or $prefix -lt 0 -or $prefix -gt $maximumPrefix) {
            return $false
        }
    }

    $addressBytes = $address.GetAddressBytes()
    $networkBytes = $network.GetAddressBytes()
    $wholeBytes = [int][Math]::Floor($prefix / 8)
    $remainingBits = $prefix % 8

    for ($index = 0; $index -lt $wholeBytes; $index++) {
        if ($addressBytes[$index] -ne $networkBytes[$index]) {
            return $false
        }
    }

    if ($remainingBits -gt 0 -and $wholeBytes -lt $addressBytes.Length) {
        $mask = (0xFF -shl (8 - $remainingBits)) -band 0xFF
        if (($addressBytes[$wholeBytes] -band $mask) -ne ($networkBytes[$wholeBytes] -band $mask)) {
            return $false
        }
    }

    return $true
}

function Get-AgentRblQueryName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Ip,
        [Parameter(Mandatory = $true)]
        [string]$Zone
    )

    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($Ip, [ref]$address) -or [string]::IsNullOrWhiteSpace($Zone)) {
        return ''
    }

    $bytes = $address.GetAddressBytes()
    if ($address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
        $reversed = (($bytes[3], $bytes[2], $bytes[1], $bytes[0]) -join '.')
        return ('{0}.{1}' -f $reversed, $Zone.Trim().TrimEnd('.'))
    }

    $hex = [System.BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
    $builder = New-Object System.Text.StringBuilder
    for ($index = $hex.Length - 1; $index -ge 0; $index--) {
        [void]$builder.Append($hex[$index])
        [void]$builder.Append('.')
    }
    [void]$builder.Append($Zone.Trim().TrimEnd('.'))
    return $builder.ToString()
}

function Read-SmtpResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.TextReader]$Reader
    )

    $lines = @()
    $code = 0

    while ($true) {
        $line = $Reader.ReadLine()
        if ($null -eq $line) {
            break
        }
        $lines += $line
        if ($line -match '^([0-9]{3})([ -])(.*)$') {
            $code = [int]$Matches[1]
            if ($Matches[2] -eq ' ') {
                break
            }
        } else {
            break
        }
    }

    $supportsStartTls = $false
    foreach ($line in $lines) {
        if ($line -match '^250[ -]STARTTLS(?:\s|$)') {
            $supportsStartTls = $true
            break
        }
    }

    return [pscustomobject]@{
        Code             = $code
        Lines            = $lines
        Text             = ($lines -join "`n")
        SupportsStartTls = $supportsStartTls
    }
}

function Test-SmtpStartTls {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Server,
        [int]$Port = 25,
        [int]$TimeoutSeconds = 10
    )

    $hostName = ConvertTo-AgentHostName -Value $Server
    if ([string]::IsNullOrEmpty($hostName)) {
        return $false
    }
    if ($TimeoutSeconds -lt 1) {
        $TimeoutSeconds = 1
    }

    $timeoutMs = $TimeoutSeconds * 1000
    $tcp = New-Object System.Net.Sockets.TcpClient
    $ssl = $null
    $reader = $null
    $writer = $null

    try {
        $connect = $tcp.ConnectAsync($hostName, $Port)
        if (-not $connect.Wait($timeoutMs)) {
            return $false
        }

        $tcp.ReceiveTimeout = $timeoutMs
        $tcp.SendTimeout = $timeoutMs
        $stream = $tcp.GetStream()
        $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
        $writer = New-Object System.IO.StreamWriter($stream, [System.Text.Encoding]::ASCII, 1024, $true)
        $writer.NewLine = "`r`n"
        $writer.AutoFlush = $true

        $banner = Read-SmtpResponse -Reader $reader
        if ($banner.Code -ne 220) {
            return $false
        }

        $ehloName = $env:COMPUTERNAME
        if ([string]::IsNullOrWhiteSpace($ehloName)) { $ehloName = 'health-agent' }
        $writer.WriteLine(('EHLO {0}' -f $ehloName))
        $ehlo = Read-SmtpResponse -Reader $reader
        if ($ehlo.Code -ne 250 -or -not $ehlo.SupportsStartTls) {
            return $false
        }

        $writer.WriteLine('STARTTLS')
        $startTls = Read-SmtpResponse -Reader $reader
        if ($startTls.Code -ne 220) {
            return $false
        }

        # Connectivity-only test: the SMTP STARTTLS ability is what the Linux
        # collector measures, not certificate-chain trust.
        $validationCallback = [System.Net.Security.RemoteCertificateValidationCallback] {
            param($sender, $certificate, $chain, $errors)
            return $true
        }
        $ssl = New-Object System.Net.Security.SslStream($stream, $false, $validationCallback)
        $handshake = $ssl.AuthenticateAsClientAsync($hostName)
        if (-not $handshake.Wait($timeoutMs)) {
            return $false
        }

        return $true
    } catch {
        return $false
    } finally {
        if ($ssl) { try { $ssl.Dispose() } catch { } }
        if ($writer) { try { $writer.Dispose() } catch { } }
        if ($reader) { try { $reader.Dispose() } catch { } }
        try { $tcp.Dispose() } catch { }
    }
}

function Get-CollectorFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $collectorRoot = Join-Path $Root 'collectors'
    if (-not (Test-Path -LiteralPath $collectorRoot -PathType Container)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $collectorRoot -Recurse -File -Filter '*.ps1' |
        Sort-Object -Property FullName)
}

function Get-CollectorName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $collectorRoot = Join-Path $Root 'collectors'
    $relativePath = $Path

    if ($Path.StartsWith($collectorRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $Path.Substring($collectorRoot.Length).TrimStart([char[]]@('\', '/'))
    }

    $relativePath = $relativePath -replace '\.ps1$', ''
    return ($relativePath -replace '\\', '/')
}

function Test-CollectorFilter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [AllowEmptyString()]
        [string]$Filter
    )

    if ([string]::IsNullOrWhiteSpace($Filter)) {
        return $true
    }

    foreach ($part in $Filter.Split(',')) {
        $candidate = $part.Trim()
        if ($candidate -and $Name.IndexOf($candidate, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            return $true
        }
    }

    return $false
}

function Invoke-AgentCollectorIsolated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,
        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds
    )

    $powerShell = [System.Management.Automation.PowerShell]::Create()
    try {
        [void]$powerShell.AddScript({
            param($CollectorRoot, $CollectorPath, $CollectorConfig, $AgentVersion)

            Set-StrictMode -Version 2.0
            $ErrorActionPreference = 'Stop'
            Set-Location -LiteralPath $CollectorRoot

            foreach ($library in @('Common.ps1', 'Logging.ps1', 'Config.ps1', 'IceWarpTool.ps1', 'Json.ps1')) {
                . (Join-Path (Join-Path $CollectorRoot 'lib') $library)
            }

            $global:IceWarpHealthAgentLogPath = Join-Path ([string]$CollectorConfig.LogDirectory) 'agent.log'

            $collectorContext = Initialize-AgentContext -Root $CollectorRoot -Config $CollectorConfig -Version $AgentVersion
            $result = & $CollectorPath -Context $collectorContext
            return $result
        }).AddArgument($Root).AddArgument($Path).AddArgument($Context.Config).AddArgument($Context.Version)

        $async = $powerShell.BeginInvoke()
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000)) {
            try { $powerShell.Stop() } catch { }
            return [pscustomobject]@{
                Status  = 'timeout'
                Result  = $null
                Message = ('Collector exceeded the {0}-second timeout.' -f $TimeoutSeconds)
            }
        }

        $output = @($powerShell.EndInvoke($async))
        if ($powerShell.Streams.Error.Count -gt 0) {
            $firstError = $powerShell.Streams.Error[0]
            throw $firstError.Exception
        }

        $result = $output | Where-Object { $_ -is [System.Collections.IDictionary] } | Select-Object -Last 1
        if ($null -eq $result) {
            return [pscustomobject]@{
                Status  = 'empty'
                Result  = $null
                Message = 'Collector returned no data.'
            }
        }

        return [pscustomobject]@{
            Status  = 'ok'
            Result  = $result
            Message = ''
        }
    } finally {
        $powerShell.Dispose()
    }
}

function Invoke-AgentCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,
        [int]$TimeoutSeconds = 0
    )

    $name = Get-CollectorName -Root $Root -Path $Path
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "Collector not found: $Path"
        }

        if ($TimeoutSeconds -gt 0) {
            $isolated = Invoke-AgentCollectorIsolated -Path $Path -Root $Root -Context $Context -TimeoutSeconds $TimeoutSeconds
            $result = $isolated.Result
            if ($isolated.Status -ne 'ok') {
                $stopwatch.Stop()
                if ($isolated.Status -eq 'timeout') {
                    Write-AgentLog -Level ERROR -Message ('Collector {0} timed out after {1} seconds.' -f $name, $TimeoutSeconds)
                }
                return [pscustomobject]@{
                    Name       = $name
                    Path       = $Path
                    Status     = $isolated.Status
                    Message    = $isolated.Message
                    DurationMs = $stopwatch.ElapsedMilliseconds
                }
            }
        } else {
            $result = & $Path -Context $Context
        }

        if ($null -eq $result) {
            $stopwatch.Stop()
            return [pscustomobject]@{
                Name       = $name
                Path       = $Path
                Status     = 'empty'
                Message    = 'Collector returned no data.'
                DurationMs = $stopwatch.ElapsedMilliseconds
            }
        }

        if (-not ($result -is [System.Collections.IDictionary])) {
            throw 'Collector must return an IDictionary (hashtable or ordered dictionary).'
        }

        foreach ($key in $result.Keys) {
            $keyText = [string]$key
            if ([string]::IsNullOrWhiteSpace($keyText)) {
                continue
            }
            if ($Context.Data.Contains($keyText)) {
                Write-AgentLog -Level WARN -Message ('Collector {0} overwrote duplicate key {1}.' -f $name, $keyText)
            }
            $Context.Data[$keyText] = $result[$key]
        }

        $stopwatch.Stop()
        Write-AgentLog -Level DEBUG -Message ("Collector {0} completed in {1} ms ({2} keys)." -f $name, $stopwatch.ElapsedMilliseconds, $result.Count)

        return [pscustomobject]@{
            Name       = $name
            Path       = $Path
            Status     = 'ok'
            Message    = ''
            DurationMs = $stopwatch.ElapsedMilliseconds
        }
    } catch {
        $stopwatch.Stop()
        $message = $_.Exception.Message
        Write-AgentLog -Level ERROR -Message ("Collector {0} failed: {1}" -f $name, $message)

        return [pscustomobject]@{
            Name       = $name
            Path       = $Path
            Status     = 'error'
            Message    = $message
            DurationMs = $stopwatch.ElapsedMilliseconds
        }
    }
}

function Show-AgentHelp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    @"
IceWarp Health Agent (Windows) v$Version

Usage:
  .\agent.ps1 [OPTIONS]

Options:
  -Report                 Run collectors and print a console summary
  -List                   List available collectors
  -Only <filter>          Run only collectors whose path contains a filter
                          (comma-separated, case-insensitive)
  -Company <name>         Override company name
  -Technician <name>      Override technician name
  -ConfigPath <path>      Use an alternate PSD1 configuration file
  -Help                   Show this help

Defaults:
  Configuration           config\agent.local.psd1, then config\agent.example.psd1
  JSON output             output\health.json
  Log file                logs\agent.log
"@ | Write-Host
}

function Write-AgentReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$CollectorResults
    )

    Write-Host ''
    Write-Host '========================================'
    Write-Host 'IceWarp Health Check Report (Windows)'
    Write-Host '========================================'
    Write-Host ''

    [string[]]$keys = @($Context.Data.Keys | ForEach-Object { [string]$_ })
    [Array]::Sort($keys, [System.StringComparer]::Ordinal)
    foreach ($key in $keys) {
        Write-Host ('{0,-40} : {1}' -f $key, $Context.Data[$key])
    }

    Write-Host ''
    Write-Host ('Total Keys : {0}' -f $Context.Data.Count)

    $failed = @($CollectorResults | Where-Object { $_.Status -ne 'ok' })
    if ($failed.Count -gt 0) {
        Write-Host ''
        Write-Host ('Collector issues ({0}):' -f $failed.Count)
        foreach ($item in ($failed | Sort-Object -Property Name)) {
            Write-Host ('  [{0}] {1,-30} {2}' -f $item.Status, $item.Name, $item.Message)
        }
    }

    Write-Host ''
}
