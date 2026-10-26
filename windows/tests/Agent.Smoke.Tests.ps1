#Requires -Version 5.1

Describe 'Windows agent scaffold' {
    BeforeAll {
        $script:testDirectory = Split-Path -Parent $PSCommandPath
        $script:agentRoot = Split-Path -Parent $script:testDirectory
        $libRoot = Join-Path $script:agentRoot 'lib'

        . (Join-Path $libRoot 'Common.ps1')
        . (Join-Path $libRoot 'Logging.ps1')
        . (Join-Path $libRoot 'Config.ps1')
        . (Join-Path $libRoot 'IceWarpTool.ps1')
        . (Join-Path $libRoot 'Json.ps1')

        function Assert-Equal {
            param(
                $Expected,
                $Actual,
                [string]$Because = ''
            )

            if ($null -eq $Expected -and $null -eq $Actual) {
                return
            }
            if ($Expected -ne $Actual) {
                throw ("Expected '{0}' but got '{1}'. {2}" -f $Expected, $Actual, $Because).Trim()
            }
        }

        function Assert-True {
            param(
                [bool]$Condition,
                [string]$Because = 'Assertion failed.'
            )

            if (-not $Condition) {
                throw $Because
            }
        }
    }

    BeforeEach {
        $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('icewarp-agent-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
        Initialize-AgentLogging -LogDirectory (Join-Path $script:tempRoot 'logs') | Out-Null
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:tempRoot) {
            Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reads the Windows agent version from VERSION' {
        Assert-Equal -Expected '0.1.0' -Actual (Get-AgentVersion -Root $script:agentRoot)
    }

    It 'loads the example PSD1 configuration' {
        $configPath = Join-Path $script:agentRoot 'config\agent.example.psd1'
        $config = Get-AgentConfig -Root $script:agentRoot -ConfigPath $configPath

        Assert-Equal -Expected 10 -Actual $config.ToolTimeoutSeconds
        Assert-Equal -Expected '1.14' -Actual $config.ChecklistVersion
        Assert-Equal -Expected $true -Actual $config.ConfigUsedExample
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$config.ToolPath)) -Because 'ToolPath should not be empty.'
        Assert-True -Condition (-not [string]::IsNullOrWhiteSpace([string]$config.OutputJson)) -Because 'OutputJson should not be empty.'
    }

    It 'parses key/value and plain tool output' {
        $keyValue = "C_Version: 14.3.0.12`r`nC_NiceVersion: IceWarp 14.3`r`n"
        Assert-Equal -Expected '14.3.0.12' -Actual (ConvertFrom-IceWarpToolOutput -Output $keyValue)
        Assert-Equal -Expected 'plain value' -Actual (ConvertFrom-IceWarpToolOutput -Output 'plain value')
        Assert-Equal -Expected '' -Actual (ConvertFrom-IceWarpToolOutput -Output '')
    }

    It 'writes valid JSON without changing scalar types' {
        $path = Join-Path $script:tempRoot 'health.json'
        $data = [ordered]@{
            'agent.version' = '0.1.0'
            'number'        = 5
            'enabled'       = $true
            'missing'       = $null
            'empty'         = ''
        }

        Write-AgentJson -Path $path -Data $data

        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        Assert-Equal -Expected '0.1.0' -Actual $json.'agent.version'
        Assert-Equal -Expected 5 -Actual $json.number
        Assert-Equal -Expected $true -Actual $json.enabled
        Assert-True -Condition ($null -eq $json.missing) -Because 'JSON null should remain null.'
        Assert-True -Condition ($null -eq $json.empty) -Because 'Empty strings should become null, matching the Linux JSON contract.'
    }

    It 'invokes a collector and merges its dictionary into agent data' {
        $collectorPath = Join-Path $script:tempRoot 'sample.ps1'
        @'
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

return [ordered]@{ 'sample.value' = 'ok' }
'@ | Set-Content -LiteralPath $collectorPath -Encoding ASCII

        $config = Get-AgentConfig -Root $script:agentRoot
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'
        $result = Invoke-AgentCollector -Path $collectorPath -Root $script:agentRoot -Context $context

        Assert-Equal -Expected 'ok' -Actual $result.Status
        Assert-Equal -Expected 'ok' -Actual $context.Data['sample.value']
    }

    It 'records a collector error without stopping the run' {
        $collectorPath = Join-Path $script:tempRoot 'broken.ps1'
        @'
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

throw 'intentional test failure'
'@ | Set-Content -LiteralPath $collectorPath -Encoding ASCII

        $config = Get-AgentConfig -Root $script:agentRoot
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'
        $result = Invoke-AgentCollector -Path $collectorPath -Root $script:agentRoot -Context $context

        Assert-Equal -Expected 'error' -Actual $result.Status
        Assert-True -Condition ($result.Message -match 'intentional test failure') -Because 'Collector error message was not preserved.'
    }

    It 'finds the bundled Version collector' {
        $collectors = @(Get-CollectorFiles -Root $script:agentRoot)
        $names = @($collectors | ForEach-Object { Get-CollectorName -Root $script:agentRoot -Path $_.FullName })

        Assert-True -Condition ($collectors.Count -gt 0) -Because 'No collectors were found.'
        Assert-True -Condition ($names -contains 'General/Version') -Because 'General/Version was not listed.'
    }

    It 'filters collector names case-insensitively' {
        Assert-Equal -Expected $true -Actual (Test-CollectorFilter -Name 'General/Version' -Filter 'general')
        Assert-Equal -Expected $true -Actual (Test-CollectorFilter -Name 'General/Version' -Filter 'dns,version')
        Assert-Equal -Expected $false -Actual (Test-CollectorFilter -Name 'General/Version' -Filter 'dns')
        Assert-Equal -Expected $true -Actual (Test-CollectorFilter -Name 'General/Version' -Filter '')
    }

    It 'DomainsUsers produces exactly the Linux key set and parses values correctly' {
        # Mock the IceWarp tool helpers with the exact live output shapes.
        # tool.exe prints the entity name on the first line and the setting
        # as "SettingName: Value" on the next line. Defined here (local scope)
        # so they shadow the dot-sourced wrappers for this test only.
        function Get-IceWarpDomainList {
            param([hashtable]$Context)
            # Mirror the real helper: the internal ##...## domain is filtered
            # out inside the wrapper, so the mock returns only real domains.
            return , @('mtitc.ir')
        }
        function Get-IceWarpDomainSetting {
            param([string]$Domain, [string]$Name, [hashtable]$Context)
            if ($Name -eq 'D_NumberLimit') { return '0' }
            if ($Name -eq 'D_DiskQuota')   { return '1024' }
            if ($Name -eq 'D_UserMB')      { return '100' }
            return ''
        }
        function Invoke-IceWarpTool { }
        function Invoke-IceWarpToolList { }
        function Test-IceWarpTool { return $true }
        function Write-AgentLog { }

        $config = Get-AgentConfig -Root $script:agentRoot
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'
        $collectorPath = Join-Path $script:agentRoot 'collectors\Icewarp\DomainsUsers.ps1'

        # Invoke the collector directly so we assert on the dictionary it
        # returns, not the merged agent data (which contains agent.* keys
        # injected by the agent itself and is not the collector's concern).
        $data = & $collectorPath -Context $context

        # The exact key set the Linux collectors/icewarp/domain_limits.sh
        # produces for one real domain. Nothing more, nothing less.
        $expectedKeys = @(
            'domain.checked',
            'domain.mtitc.ir.daily_send_messages_limit',
            'domain.mtitc.ir.disk_quota_kb',
            'domain.mtitc.ir.user_send_data_limit_mb_per_day',
            'domain.primary.name',
            'domain.primary.daily_send_messages_limit',
            'domain.count',
            'domain.list'
        )
        $actualKeys = @($data.Keys)
        $extra = @($actualKeys | Where-Object { $_ -notin $expectedKeys })
        $missing = @($expectedKeys | Where-Object { $_ -notin $actualKeys })

        Assert-True -Condition ($extra.Count -eq 0) -Because ("Unexpected keys: {0}" -f ($extra -join ', '))
        Assert-True -Condition ($missing.Count -eq 0) -Because ("Missing keys: {0}" -f ($missing -join ', '))

        # Values must be parsed from the "SettingName: Value" line, not the
        # entity-name line that tool.exe prints first.
        Assert-Equal -Expected 'true' -Actual $data['domain.checked']
        Assert-Equal -Expected '0' -Actual $data['domain.mtitc.ir.daily_send_messages_limit']
        Assert-Equal -Expected '1024' -Actual $data['domain.mtitc.ir.disk_quota_kb']
        Assert-Equal -Expected '100' -Actual $data['domain.mtitc.ir.user_send_data_limit_mb_per_day']
        Assert-Equal -Expected 'mtitc.ir' -Actual $data['domain.primary.name']
        Assert-Equal -Expected '0' -Actual $data['domain.primary.daily_send_messages_limit']
        Assert-Equal -Expected '1' -Actual $data['domain.count']
        Assert-Equal -Expected 'mtitc.ir' -Actual $data['domain.list']
    }

    It 'new collectors return an IDictionary without throwing when tool.exe is absent' {
        # No tool.exe exists on the dev box, so every Get-IceWarpSetting call
        # must resolve to an empty string and every PowerShell cmdlet must
        # be wrapped in try/catch. This asserts the collector contract:
        # return exactly one IDictionary, never throw.
        $config = Get-AgentConfig -Root $script:agentRoot
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'

        $collectors = @(
            'collectors\Icewarp\SmtpSettings.ps1',
            'collectors\Icewarp\Security.ps1',
            'collectors\Icewarp\BackupArchive.ps1',
            'collectors\Icewarp\OsStorage.ps1',
            'collectors\Icewarp\DnsMailFlow.ps1'
        )

        foreach ($relative in $collectors) {
            $path = Join-Path $script:agentRoot $relative
            $result = & $path -Context $context
            Assert-True -Condition ($result -is [System.Collections.IDictionary]) -Because (
                "$relative must return an IDictionary, got {0}" -f $result.GetType().Name)
        }
    }
}
