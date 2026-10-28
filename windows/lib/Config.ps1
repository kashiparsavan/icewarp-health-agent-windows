#Requires -Version 5.1
<#
.SYNOPSIS
Configuration loading for the Windows IceWarp Health Agent.
#>

function Get-AgentConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [string]$ConfigPath
    )

    $defaults = @{
        IceWarpHome             = 'C:\Program Files\IceWarp'
        ToolPath                = 'C:\Program Files\IceWarp\tool.exe'
        ToolTimeoutSeconds      = 10
        CollectorTimeoutSeconds = 120
        NetworkTimeoutSeconds   = 10
        OutputJson              = 'output\health.json'
        LogDirectory            = 'logs'
        CompanyName             = ''
        Technician              = 'Parsavan'
        ChecklistVersion        = '1.14'
        MailHostname            = ''
        MailDomain              = ''
    }

    $examplePath = Join-Path $Root 'config\agent.example.psd1'
    $localPath = Join-Path $Root 'config\agent.local.psd1'
    $candidate = ''

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $candidate = Resolve-AgentPath -Path $ConfigPath -Root $Root
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            throw "Configuration file not found: $candidate"
        }
    } elseif (Test-Path -LiteralPath $localPath -PathType Leaf) {
        $candidate = $localPath
    } elseif (Test-Path -LiteralPath $examplePath -PathType Leaf) {
        $candidate = $examplePath
    } else {
        throw 'No Windows agent configuration found. Copy config\agent.example.psd1 to config\agent.local.psd1.'
    }

    $loaded = Import-PowerShellDataFile -LiteralPath $candidate -ErrorAction Stop
    $config = @{}
    $unknownKeys = @()

    foreach ($key in $defaults.Keys) {
        $config[$key] = $defaults[$key]
    }
    foreach ($key in $loaded.Keys) {
        if ($defaults.ContainsKey($key)) {
            $config[$key] = $loaded[$key]
        } else {
            $unknownKeys += [string]$key
        }
    }

    foreach ($timeoutKey in @('ToolTimeoutSeconds', 'CollectorTimeoutSeconds', 'NetworkTimeoutSeconds')) {
        $timeout = 0
        if (-not [int]::TryParse([string]$config[$timeoutKey], [ref]$timeout) -or $timeout -lt 1) {
            throw ('{0} must be a positive integer.' -f $timeoutKey)
        }
        $config[$timeoutKey] = $timeout
    }

    if ([string]::IsNullOrWhiteSpace([string]$config.ChecklistVersion)) {
        throw 'ChecklistVersion must not be empty.'
    }
    $config.ChecklistVersion = ([string]$config.ChecklistVersion).Trim()

    foreach ($key in @('IceWarpHome', 'ToolPath', 'OutputJson', 'LogDirectory')) {
        if ([string]::IsNullOrWhiteSpace([string]$config[$key])) {
            throw "Configuration value '$key' must not be empty."
        }
        $config[$key] = Resolve-AgentPath -Path ([string]$config[$key]) -Root $Root
    }

    foreach ($hostKey in @('MailHostname', 'MailDomain')) {
        $rawValue = [string]$config[$hostKey]
        if ([string]::IsNullOrWhiteSpace($rawValue)) {
            $config[$hostKey] = ''
            continue
        }
        $normalized = ConvertTo-AgentHostName -Value $rawValue
        if ([string]::IsNullOrEmpty($normalized)) {
            throw ("Configuration value '{0}' is not a valid DNS hostname: {1}" -f $hostKey, $rawValue)
        }
        $config[$hostKey] = $normalized
    }

    $config['ConfigPath'] = $candidate
    $config['ConfigUsedExample'] = [string]::Equals($candidate, $examplePath, [System.StringComparison]::OrdinalIgnoreCase)
    $config['UnknownConfigKeys'] = @($unknownKeys)

    return $config
}
