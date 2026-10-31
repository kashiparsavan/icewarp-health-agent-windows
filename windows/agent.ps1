#Requires -Version 5.1
<#
.SYNOPSIS
IceWarp Health Agent for Windows.

.DESCRIPTION
Independent Windows PowerShell implementation. It does not call agent.sh or
source any file under the Linux lib/ directory.

.PARAMETER Report
Print collected data and collector issues to the console.

.PARAMETER List
List the collectors that would run, then exit.

.PARAMETER Only
Run only collectors whose relative path contains one of the comma-separated
filters. Matching is case-insensitive.

.PARAMETER Company
Override the company name from the configuration file.

.PARAMETER Technician
Override the technician name from the configuration file.

.PARAMETER ConfigPath
Use an alternate PSD1 configuration file. The default is
config\agent.local.psd1, falling back to config\agent.example.psd1.
#>
[CmdletBinding()]
param(
    [switch]$Report,
    [switch]$List,
    [string]$Only,
    [string]$Company,
    [string]$Technician,
    [Alias('Config')]
    [string]$ConfigPath,
    [switch]$Help
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:AgentRoot = $PSScriptRoot
$script:ProjectRoot = Split-Path -Parent $script:AgentRoot
$libRoot = Join-Path $script:AgentRoot 'lib'
$requiredLibraries = @('Common.ps1', 'Logging.ps1', 'Config.ps1', 'IceWarpTool.ps1', 'Json.ps1', 'Health.ps1', 'ReportTechnical.ps1', 'ReportManagement.ps1')

foreach ($library in $requiredLibraries) {
    $libraryPath = Join-Path $libRoot $library
    if (-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)) {
        throw "Required library not found: $libraryPath"
    }
    . $libraryPath
}

$agentVersion = Get-AgentVersion -Root $script:AgentRoot

if ($Help) {
    Show-AgentHelp -Version $agentVersion
    exit 0
}

try {
    $config = Get-AgentConfig -Root $script:AgentRoot -ConfigPath $ConfigPath
    Initialize-AgentLogging -LogDirectory $config.LogDirectory

    if ($Company) {
        $config.CompanyName = $Company
    }
    if ($Technician) {
        $config.Technician = $Technician
    }

    $collectors = @(Get-CollectorFiles -Root $script:AgentRoot)
    if ($Only) {
        $collectors = @($collectors | Where-Object {
            Test-CollectorFilter -Name (Get-CollectorName -Root $script:AgentRoot -Path $_.FullName) -Filter $Only
        })
    }

    if ($List) {
        if ($collectors.Count -eq 0) {
            Write-Host 'No collectors matched.'
            exit 0
        }
        foreach ($collector in $collectors) {
            Get-CollectorName -Root $script:AgentRoot -Path $collector.FullName
        }
        exit 0
    }

    if ($config.ConfigUsedExample) {
        Write-AgentLog -Level WARN -Message 'Using config\agent.example.psd1. Copy it to config\agent.local.psd1 for site settings.'
    }
    if ($config.UnknownConfigKeys.Count -gt 0) {
        Write-AgentLog -Level WARN -Message ('Ignoring unknown configuration keys: {0}' -f ($config.UnknownConfigKeys -join ', '))
    }

    $lockPath = Join-Path $script:ProjectRoot '.agent.lock'
    Enter-AgentLock -Path $lockPath
    try {
        $context = Initialize-AgentContext -Root $script:AgentRoot -Config $config -Version $agentVersion
        Write-AgentLog -Level INFO -Message ('Running {0} Windows collector(s).' -f $collectors.Count)

        $collectorResults = @()
        foreach ($collector in $collectors) {
            $collectorName = Get-CollectorName -Root $script:AgentRoot -Path $collector.FullName
            Write-Host ('[RUN ] {0}' -f $collectorName)
            $collectorResults += Invoke-AgentCollector -Path $collector.FullName -Root $script:AgentRoot -Context $context `
                -TimeoutSeconds ([int]$config.CollectorTimeoutSeconds)
        }
        $collectorResults = @($collectorResults)

        Write-AgentLog -Level INFO -Message 'Evaluating health rules.'
        Invoke-HealthEvaluation -Data $context.Data
        Write-AgentLog -Level INFO -Message ('Health summary: {0} (failed={1}, warnings={2}, checks={3}).' -f
            $context.Data['health.summary.overall'],
            $context.Data['health.summary.failed'],
            $context.Data['health.summary.warnings'],
            $context.Data['health.summary.total_checks'])

        Write-AgentJson -Path $config.OutputJson -Data $context.Data

        if ($Report) {
            Write-AgentReport -Context $context -CollectorResults $collectorResults
            # Generate PDF reports
            $pdfLib = Join-Path $libRoot 'ReportTechnical.ps1'
            if (Test-Path -LiteralPath $pdfLib -PathType Leaf) { . $pdfLib }
            $pdfLib2 = Join-Path $libRoot 'ReportManagement.ps1'
            if (Test-Path -LiteralPath $pdfLib2 -PathType Leaf) { . $pdfLib2 }
            $outDir = Split-Path $config.OutputJson -Parent
            if (-not $outDir) { $outDir = '.' }
            $techOut = Join-Path $outDir 'report.pdf'
            $mgmtOut = Join-Path $outDir 'management_report.pdf'
            if (Get-Command Build-TechnicalReportPdf -ErrorAction SilentlyContinue) {
                Build-TechnicalReportPdf -Data $context.Data -OutPath $techOut
                Write-AgentLog -Level INFO -Message "Technical PDF written to $techOut"
            }
            if (Get-Command Build-ManagementReportPdf -ErrorAction SilentlyContinue) {
                Build-ManagementReportPdf -Data $context.Data -OutPath $mgmtOut -Version $agentVersion -Date (Get-Date -Format 'yyyy-MM-dd')
                Write-AgentLog -Level INFO -Message "Management PDF written to $mgmtOut"
            }
        }

        $failedCollectors = @($collectorResults | Where-Object { $_.Status -ne 'ok' })
        if ($failedCollectors.Count -gt 0) {
            Write-AgentLog -Level WARN -Message ('{0} collector(s) reported issues.' -f $failedCollectors.Count)
        }

        Write-AgentLog -Level INFO -Message 'Windows agent finished.'
        $exitCode = 0
    } finally {
        Exit-AgentLock -Path $lockPath
    }
} catch {
    if (Get-Command Write-AgentLog -ErrorAction SilentlyContinue) {
        Write-AgentLog -Level ERROR -Message $_.Exception.Message
    } else {
        Write-Error $_.Exception.Message
    }
    $exitCode = 1
}

exit $exitCode
