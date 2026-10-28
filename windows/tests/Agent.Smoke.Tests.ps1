#Requires -Version 5.1

Describe 'Windows agent contract' {
    BeforeAll {
        $script:testDirectory = Split-Path -Parent $PSCommandPath
        $script:agentRoot = Split-Path -Parent $script:testDirectory
        $libRoot = Join-Path $script:agentRoot 'lib'

        . (Join-Path $libRoot 'Common.ps1')
        . (Join-Path $libRoot 'Logging.ps1')
        . (Join-Path $libRoot 'Config.ps1')
        . (Join-Path $libRoot 'IceWarpTool.ps1')
        . (Join-Path $libRoot 'Json.ps1')
        . (Join-Path $libRoot 'Health.ps1')

        $schemaPath = Join-Path $script:testDirectory 'fixtures\schema-keys.json'
        $script:schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
        $script:schemaKeySet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
        foreach ($schemaKey in $script:schema.keys.PSObject.Properties.Name) {
            [void]$script:schemaKeySet.Add($schemaKey)
        }

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

        function Assert-False {
            param(
                [bool]$Condition,
                [string]$Because = 'Assertion failed.'
            )

            if ($Condition) {
                throw $Because
            }
        }

        function Get-JsonScalarType {
            param($Value)

            if ($null -eq $Value) { return 'null' }
            if ($Value -is [bool]) { return 'boolean' }
            if ($Value -is [string]) { return 'string' }
            return 'number'
        }

        function Test-SchemaKeyAllowed {
            param([string]$Key)

            if ($script:schemaKeySet.Contains($Key)) {
                return $true
            }
            if ($Key -match '^domain\.(?!primary\.)(?:[^.]+\.)+(daily_send_messages_limit|disk_quota_kb|user_send_data_limit_mb_per_day)$') {
                return $true
            }
            if ($Key -match '^storage\.(root_fs|root_home|install|mail|archive)\.(device|mount|path|status|total_gb|used_gb|free_gb|used_percent)$') {
                return $true
            }
            # Disk message keys depend on which mounts share a device; the
            # Linux sample only contains the first mount's message.
            if ($Key -match '^health\.disk\.(root_fs|root_home|install|mail|archive)\.(result|message)$') {
                return $true
            }
            if ($Key -match '^security\.rbl_self_check\.zones\.(zen_spamhaus_org|bl_spamcop_net|dnsbl_sorbs_net|b_barracudacentral_org)$') {
                return $true
            }
            return $false
        }

        function Get-ExpectedSchemaType {
            param([string]$Key)

            $property = $script:schema.keys.PSObject.Properties[$Key]
            if ($property) {
                return [string]$property.Value
            }
            if ($Key -match '^domain\.(?!primary\.)(?:[^.]+\.)+') { return 'number' }
            if ($Key -match '^domain\.primary\.daily_send_messages_limit$') { return 'number' }
            if ($Key -match '^domain\.count$') { return 'number' }
            if ($Key -match '^domain\.checked$') { return 'boolean' }
            if ($Key -match '^domain\.') { return 'string' }
            if ($Key -match '^storage\..+\.(total_gb|used_gb|free_gb|used_percent)$') { return 'number' }
            if ($Key -match '^storage\.') { return 'string' }
            if ($Key -match '^health\.disk\.') { return 'string' }
            if ($Key -match '^security\.rbl_self_check\.zones\.') { return 'string' }
            return 'string'
        }

        function Test-SchemaTypeMatches {
            param([string]$Key, $Value)

            $actual = Get-JsonScalarType -Value $Value
            if ($actual -eq 'null') {
                # Linux emits null for empty values regardless of the sample type.
                return $true
            }

            $expected = Get-ExpectedSchemaType -Key $Key
            if ($expected -eq 'null') {
                return $true
            }
            return ($actual -eq $expected)
        }

        # Shared mocks. Dot-source these in an It block so they shadow the
        # dot-sourced real wrappers for that test only.
        $script:mockFunctions = {
            function Get-IceWarpSetting {
                param([string]$Name, [hashtable]$Context)
                $global:AgentTestSettingNames += $Name
                if ($global:AgentTestSettingOverrides.ContainsKey($Name)) {
                    return [string]$global:AgentTestSettingOverrides[$Name]
                }
                switch -Regex ($Name) {
                    '^C_Version$' { return '14.3.0.13' }
                    '^C_LicenseStatus$' { return '0' }
                    '^C_License_Type$' { return 'onpremise' }
                    '^C_License_TrialExpire$' { return '2026-12-31' }
                    '^C_License_XML$' { return '' }
                    '^C_Accounts_Policies_Auth_Schemes$' { return 'PLAIN,LOGIN' }
                    '^C_Mail_SMTP_General_DNSServer$' { return '8.8.8.8;' }
                    '^C_Mail_SMTP_Delivery_MaxMsgSize$' { return '20971520' }
                    '^C_Mail_Security_Relay_IPList$' { return '127.0.0.1' }
                    '^C_System_Tools_AutoBackup_BackupTo$' { return 'backup/"yyyy-mm-dd-HHnn".zip' }
                    '^C_System_Tools_AutoArchive_Path$' { return 'D:\IceWarp\archive' }
                    '^C_System_Tools_AutoArchive_IMAPArchiveName$' { return 'Archive' }
                    '^C_System_Tools_AutoArchive_TrailerPath$' { return '"yyyy-mm"' }
                    '^c_system_tools_backup_db_(accounts|as|directorycache|gw)$' { return 'dsn' }
                    '^C_Mail_Security_Tarpit_SpamScore$' { return '9216' }
                    '^C_WebAdmin_URL$' { return '' }
                    '^C_System_RemoteConsoleProtocol_Port$' { return '0' }
                    '^C_AS_BypassLocalIPs$' { return '' }
                    '^C_AS_BypassLocalDomains$' { return '' }
                    '^C_AS_SpamMaxThreads$' { return '' }
                    '^C_AS_General_AntispamMode$' { return '' }
                    '^C_AV_Info_UpdateDate$' { return '' }
                    '^C_AV_Info_UpdateVersion$' { return '' }
                    '^C_AV_Info_UpdateSize$' { return '' }
                    '^C_AS_Info_UpdateDate$' { return '' }
                    '^C_AS_Info_UpdateVersion$' { return '' }
                    '^C_AS_Info_UpdateSize$' { return '' }
                    '^C_CloudAPI_AutoConfigure$' { return '' }
                    '^C_System_Tools_Migration_Active$' { return '' }
                    '^C_System_Tools_Migration_Server$' { return '' }
                    '^C_System_Tools_Migration_Stat_Start$' { return '' }
                    '^C_System_Tools_Migration_Stat_Errors$' { return '' }
                    '^C_System_SQLLogType$' { return '' }
                    '^C_Accounts_Global_Accounts_AuthLog$' { return '' }
                    '^C_Accounts_Global_Accounts_MaintenanceLog$' { return '' }
                    '^C_System_Log_MailQueue$' { return '' }
                    '^C_System_Services_Fulltext_Enabled$' { return '' }
                    '^C_System_Services_Fulltext_Scanner_Queues$' { return '' }
                    '^C_System_Services_Control_SslPort$' { return '443' }
                    '^C_Mail_SMTP_Delivery_UseIncomingQueue$' { return '' }
                    '^C_Mail_SMTP_Delivery_IncomingQueueSize$' { return '' }
                    '^C_Mail_SMTP_Other_NoRetryQueue$' { return '' }
                    '^C_Accounts_Global_Accounts_DirectoryCacheConnectionString$' { return '' }
                    '^C_Accounts_Global_Accounts_DirectoryCacheSchedule$' { return '' }
                    '^C_System_Storage_Accounts_ODBCConnString_Real$' { return '' }
                    '^C_System_Storage_Dir_MailPath$' { return '' }
                    '^C_System_Storage_Dir_TempPath$' { return '' }
                    '^C_System_Storage_Dir_LogPath$' { return '' }
                    '^C_System_Tools_AutoArchive_Path$' { return '' }
                    '^C_System_Tools_WatchDog_SMTP$' { return '' }
                    '^C_System_Tools_WatchDog_POP3$' { return '' }
                    '^C_System_Tools_WatchDog_IM$' { return '' }
                    '^C_System_Tools_Watchdog_GW$' { return '' }
                    '^C_System_Tools_Watchdog_Control$' { return '' }
                    '^C_System_Tools_Watchdog_Int$' { return '' }
                    '^C_System_Tools_Watchdog_Check_Protocols$' { return '' }
                    '^C_System_Tools_Watchdog_Check_IPList$' { return '' }
                    '^C_System_Tools_RemoteServer_Enable$' { return '' }
                    '^C_System_Tools_RemoteServer_MoreThan$' { return '' }
                    '^C_System_Tools_RemoteServer_Email$' { return '' }
                    '^C_System_Tools_RemoteServer_NotifyAgain$' { return '' }
                    '^C_System_Ssl_CertFile$' { return '' }
                    '^C_System_Adv_Protocols_SessionTimeOut$' { return '' }
                    default { return '1' }
                }
            }
            function Get-IceWarpDomainList {
                param([hashtable]$Context)
                return , @('mtitc.ir')
            }
            function Get-IceWarpDomainSetting {
                param([string]$Domain, [string]$Name, [hashtable]$Context)
                return '1'
            }
            function Invoke-IceWarpTool {
                param([string]$ToolPath, [string]$Arguments, [int]$TimeoutSeconds)
                return ''
            }
            function Invoke-IceWarpToolList {
                param([string]$ToolPath, [string]$ListType, [int]$TimeoutSeconds)
                return ''
            }
            function Test-IceWarpTool {
                param([string]$ToolPath)
                return $true
            }
            function Test-SmtpStartTls {
                param([string]$Server, [int]$Port = 25, [int]$TimeoutSeconds = 10)
                return $true
            }
            function Get-AgentPublicIpAddress {
                param([int]$TimeoutSeconds = 5)
                return '203.0.113.10'
            }
            function Resolve-AgentDnsName {
                param([string]$Name, [string]$Type = 'A')
                $global:AgentTestDnsQueries += ('{0}|{1}' -f $Type, $Name)
                switch -Regex ($Name) {
                    '^203\.0\.113\.10$' {
                        if ($Type -eq 'PTR') {
                            return @([pscustomobject]@{ Type = 'PTR'; NameHost = 'mail.example.com.' })
                        }
                    }
                    '^example\.com$' {
                        if ($Type -eq 'A') {
                            return @([pscustomobject]@{ Type = 'A'; IPAddress = '203.0.113.10' })
                        }
                        if ($Type -eq 'TXT') {
                            return @([pscustomobject]@{ Type = 'TXT'; Strings = @($global:AgentTestSpfRecord) })
                        }
                        if ($Type -eq 'MX') {
                            return @([pscustomobject]@{ Type = 'MX'; NameExchange = 'mail.example.com.' })
                        }
                    }
                    '^default\._domainkey\.example\.com$' {
                        return @([pscustomobject]@{ Type = 'TXT'; Strings = @('v=DKIM1; k=rsa; p=ABC', 'DEF') })
                    }
                    '^_dmarc\.example\.com$' {
                        return @([pscustomobject]@{ Type = 'TXT'; Strings = @('v=DMARC1; p=none;') })
                    }
                }
                if ($global:AgentTestRblListedZone -and $Name -like ('*.' + $global:AgentTestRblListedZone)) {
                    return @([pscustomobject]@{ Type = 'A'; IPAddress = '127.0.0.2' })
                }
                return @()
            }
            function Get-NetFirewallRule {
                [CmdletBinding()]
                param([string]$Direction, [string]$Action, $Enabled)
                if ($global:AgentTestFirewallBlocked) {
                    return @([pscustomobject]@{ Name = 'Test block 9001' })
                }
                return @()
            }
            function Get-NetFirewallPortFilter {
                [CmdletBinding()]
                param($AssociatedNetFirewallRule)
                if ($global:AgentTestFirewallBlocked) {
                    return @([pscustomobject]@{ RemotePort = '9001'; Protocol = 'TCP' })
                }
                return @()
            }
            function Get-CimInstance {
                [CmdletBinding()]
                param([string]$ClassName)
                switch ($ClassName) {
                    'Win32_OperatingSystem' {
                        return [pscustomobject]@{
                            TotalVisibleMemorySize = [long]8388608
                            FreePhysicalMemory     = [long]2097152
                            Caption               = 'Microsoft Windows Server 2022 Standard'
                            Version               = '10.0.20348'
                        }
                    }
                    'Win32_Processor' {
                        return @(
                            [pscustomobject]@{ NumberOfLogicalProcessors = 4; LoadPercentage = 25 },
                            [pscustomobject]@{ NumberOfLogicalProcessors = 4; LoadPercentage = 25 }
                        )
                    }
                    'Win32_PageFileUsage' {
                        return @([pscustomobject]@{ AllocatedBaseSize = 1024; CurrentUsage = 100 })
                    }
                    'Win32_QuickFixEngineering' {
                        return @([pscustomobject]@{ InstalledOn = (Get-Date).AddDays(-2) })
                    }
                }
                return @()
            }
            function Get-PSDrive {
                [CmdletBinding()]
                param([string]$PSProvider)
                return @(
                    [pscustomobject]@{ Root = 'C:\'; Used = [long]53687091200; Free = [long]53687091200 },
                    [pscustomobject]@{ Root = 'D:\'; Used = [long]42949672960; Free = [long]64424509440 }
                )
            }
            function w32tm {
                param([Parameter(ValueFromRemainingArguments = $true)]$Arguments)
                return 'Source: time.windows.com'
            }
        }
    }

    BeforeEach {
        $script:tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('icewarp-agent-test-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
        Initialize-AgentLogging -LogDirectory (Join-Path $script:tempRoot 'logs') | Out-Null

        $global:AgentTestSettingOverrides = @{}
        $global:AgentTestSettingNames = @()
        $global:AgentTestDnsQueries = @()
        $global:AgentTestSpfRecord = 'v=spf1 ip4:203.0.113.0/24 -all'
        $global:AgentTestRblListedZone = ''
        $global:AgentTestFirewallBlocked = $false
    }

    AfterEach {
        if (Test-Path -LiteralPath $script:tempRoot) {
            Remove-Item -LiteralPath $script:tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'reads the Windows agent version from VERSION' {
        Assert-Equal -Expected '0.1.4' -Actual (Get-AgentVersion -Root $script:agentRoot)
    }

    It 'loads the example PSD1 configuration and rejects unknown keys' {
        $configPath = Join-Path $script:agentRoot 'config\agent.example.psd1'
        $config = Get-AgentConfig -Root $script:agentRoot -ConfigPath $configPath

        Assert-Equal -Expected 10 -Actual $config.ToolTimeoutSeconds
        Assert-Equal -Expected 120 -Actual $config.CollectorTimeoutSeconds
        Assert-Equal -Expected 10 -Actual $config.NetworkTimeoutSeconds
        Assert-Equal -Expected '1.14' -Actual $config.ChecklistVersion
        Assert-Equal -Expected $true -Actual $config.ConfigUsedExample
        Assert-True -Condition ($config.UnknownConfigKeys.Count -eq 0) -Because 'Example config should not have unknown keys.'

        $customPath = Join-Path $script:tempRoot 'custom.psd1'
        @'
@{
    IceWarpHome = 'C:\Program Files\IceWarp'
    ToolPath = 'C:\Program Files\IceWarp\tool.exe'
    OutputJson = 'output\health.json'
    LogDirectory = 'logs'
    NotARealSetting = 'value'
}
'@ | Set-Content -LiteralPath $customPath -Encoding ASCII

        $custom = Get-AgentConfig -Root $script:agentRoot -ConfigPath $customPath
        Assert-True -Condition ($custom.UnknownConfigKeys -contains 'NotARealSetting') -Because 'Unknown keys should be reported.'
        Assert-False -Condition ($custom.ContainsKey('NotARealSetting')) -Because 'Unknown keys must not reach collectors.'
    }

    It 'parses key/value and plain tool output' {
        $keyValue = "C_Version: 14.3.0.12`r`nC_NiceVersion: IceWarp 14.3`r`n"
        Assert-Equal -Expected '14.3.0.12' -Actual (ConvertFrom-IceWarpToolOutput -Output $keyValue)
        Assert-Equal -Expected 'plain value' -Actual (ConvertFrom-IceWarpToolOutput -Output 'plain value')
        Assert-Equal -Expected '' -Actual (ConvertFrom-IceWarpToolOutput -Output '')
    }

    It 'coerces numeric, boolean, empty and native values exactly like the Linux writer' {
        $path = Join-Path $script:tempRoot 'health.json'
        $data = [ordered]@{
            'z.string'   = '14.3.0.12'
            'a.number'   = '42'
            'b.decimal'  = '0.40'
            'c.negative' = '-7'
            'd.true'     = 'true'
            'e.false'    = 'false'
            'f.empty'    = ''
            'g.nullstr'  = 'null'
            'h.bool'     = $true
            'i.int'      = 5
            'j.float'    = 2.5
            'k.path'     = 'C:\Program Files\IceWarp'
            'l.quote'    = 'a"b'
            'm.newline'  = "line1`nline2"
        }

        Write-AgentJson -Path $path -Data $data

        $raw = Get-Content -LiteralPath $path -Raw
        $json = $raw | ConvertFrom-Json

        Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'a.number')
        Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'b.decimal')
        Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'c.negative')
        Assert-Equal -Expected 'boolean' -Actual (Get-JsonScalarType -Value $json.'d.true')
        Assert-Equal -Expected 'boolean' -Actual (Get-JsonScalarType -Value $json.'e.false')
        Assert-True -Condition ($null -eq $json.'f.empty') -Because 'Empty strings must become null.'
        Assert-Equal -Expected 'string' -Actual (Get-JsonScalarType -Value $json.'g.nullstr')
        Assert-Equal -Expected 'null' -Actual $json.'g.nullstr'
        Assert-Equal -Expected 'boolean' -Actual (Get-JsonScalarType -Value $json.'h.bool')
        Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'i.int')
        Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'j.float')
        Assert-Equal -Expected 'C:\Program Files\IceWarp' -Actual $json.'k.path'
        Assert-Equal -Expected 'a"b' -Actual $json.'l.quote'
        Assert-Equal -Expected "line1`nline2" -Actual $json.'m.newline'

        # Linux sorts the keys; "a." must come before "z." and no temp file
        # may be left behind by the atomic write.
        Assert-True -Condition ($raw.IndexOf('"a.number"') -lt $raw.IndexOf('"z.string"')) -Because 'Keys are not sorted.'
        Assert-True -Condition ($raw -match '(?m)^\s*"a\.number":42,?$') -Because '42 is not emitted as a JSON number.'
        Assert-True -Condition ($raw -match '(?m)^\s*"b\.decimal":0\.40,?$') -Because 'Numeric text must be preserved.'
        Assert-Equal -Expected 0 -Actual @(Get-ChildItem -LiteralPath $script:tempRoot -Filter '*.tmp.*').Count
    }

    It 'initializes only schema context keys' {
        $config = Get-AgentConfig -Root $script:agentRoot
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'

        Assert-Equal -Expected '0.1.0' -Actual $context.Data['agent.version']
        foreach ($forbidden in @('agent.platform', 'checklist.version', 'agent.config.path', 'agent.config.example_used')) {
            Assert-False -Condition ($context.Data.Contains($forbidden)) -Because ("Non-schema key {0} was injected." -f $forbidden)
        }
        foreach ($key in $context.Data.Keys) {
            Assert-True -Condition (Test-SchemaKeyAllowed -Key $key) -Because ("Context emitted non-schema key {0}." -f $key)
        }
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

    It 'bounds a hung collector with the per-collector timeout' {
        $collectorPath = Join-Path $script:tempRoot 'slow.ps1'
        @'
param(
    [Parameter(Mandatory = $true)]
    [hashtable]$Context
)

Start-Sleep -Seconds 5
return [ordered]@{ 'sample.value' = 'late' }
'@ | Set-Content -LiteralPath $collectorPath -Encoding ASCII

        $config = Get-AgentConfig -Root $script:agentRoot
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Invoke-AgentCollector -Path $collectorPath -Root $script:agentRoot -Context $context -TimeoutSeconds 1
        $stopwatch.Stop()

        Assert-Equal -Expected 'timeout' -Actual $result.Status
        Assert-True -Condition ($stopwatch.Elapsed.TotalSeconds -lt 5) -Because 'The collector timeout did not stop the run.'
        Assert-False -Condition ($context.Data.Contains('sample.value')) -Because 'Timed-out collector data must not be merged.'
    }

    It 'recovers a stale lock whose owner process is gone' {
        $lockPath = Join-Path $script:tempRoot '.agent.lock'
        [System.IO.File]::WriteAllText($lockPath, ('2147483647 {0}' -f (Get-Date).ToString('o')))

        Enter-AgentLock -Path $lockPath
        try {
            $content = Get-Content -LiteralPath $lockPath -Raw
            Assert-True -Condition ($content.Trim().StartsWith([string]$PID)) -Because 'Lock was not replaced with the current PID.'
        } finally {
            Exit-AgentLock -Path $lockPath
        }
        Assert-False -Condition (Test-Path -LiteralPath $lockPath) -Because 'Lock was not removed.'
    }

    It 'finds and filters the bundled collectors' {
        $collectors = @(Get-CollectorFiles -Root $script:agentRoot)
        $names = @($collectors | ForEach-Object { Get-CollectorName -Root $script:agentRoot -Path $_.FullName })

        Assert-True -Condition ($collectors.Count -ge 9) -Because 'The collector set is incomplete.'
        Assert-True -Condition ($names -contains 'General/Version') -Because 'General/Version was not listed.'
        Assert-Equal -Expected $true -Actual (Test-CollectorFilter -Name 'General/Version' -Filter 'general')
        Assert-Equal -Expected $true -Actual (Test-CollectorFilter -Name 'General/Version' -Filter 'dns,version')
        Assert-Equal -Expected $false -Actual (Test-CollectorFilter -Name 'General/Version' -Filter 'dns')
        Assert-Equal -Expected $true -Actual (Test-CollectorFilter -Name 'General/Version' -Filter '')
    }

    It 'parses tool.exe domain lists without header, summary or progress rows' {
        function Test-IceWarpTool {
            param([string]$ToolPath)
            return $true
        }
        function Invoke-IceWarpToolList {
            param([string]$ToolPath, [string]$ListType, [int]$TimeoutSeconds)
            return @'
Domain Name
-------------
##internalservicedomain.icewarp.com##
1  mtitc.ir
2  example.com
Total: 2
Loading domains...
'@
        }

        $config = Get-AgentConfig -Root $script:agentRoot
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'
        $rawDomains = @(Get-IceWarpDomainList -Context $context)
        $domains = @()
        foreach ($entry in $rawDomains) {
            if ($entry -is [System.Array]) {
                $domains += @($entry)
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$entry)) {
                $domains += [string]$entry
            }
        }

        Assert-Equal -Expected 2 -Actual $domains.Count
        Assert-True -Condition ($domains -contains 'mtitc.ir') -Because 'mtitc.ir was not parsed.'
        Assert-True -Condition ($domains -contains 'example.com') -Because 'example.com was not parsed.'
        Assert-False -Condition ($domains -contains 'Loading') -Because 'A progress word was parsed as a domain.'
        Assert-False -Condition ($domains -contains 'Total:') -Because 'A summary line was parsed as a domain.'
        Assert-False -Condition ($domains -contains '##internalservicedomain.icewarp.com##') -Because 'The internal service domain was not filtered.'
    }

    It 'DomainsUsers produces the Linux key set and post-writer types' {
        . $script:mockFunctions

        $config = Get-AgentConfig -Root $script:agentRoot
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'
        $collectorPath = Join-Path $script:agentRoot 'collectors\Icewarp\DomainsUsers.ps1'

        $data = & $collectorPath -Context $context

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

        $path = Join-Path $script:tempRoot 'domains.json'
        Write-AgentJson -Path $path -Data $data
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json

        Assert-Equal -Expected 'boolean' -Actual (Get-JsonScalarType -Value $json.'domain.checked')
        Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'domain.count')
        Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'domain.mtitc.ir.daily_send_messages_limit')
        Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'domain.mtitc.ir.disk_quota_kb')
        Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'domain.mtitc.ir.user_send_data_limit_mb_per_day')
        Assert-Equal -Expected 'mtitc.ir;' -Actual $json.'domain.list'
        Assert-Equal -Expected 'mtitc.ir' -Actual $json.'domain.primary.name'
        Assert-Equal -Expected 1 -Actual $json.'domain.count'
        Assert-True -Condition ($json.'domain.checked') -Because 'domain.checked should be a JSON true.'
    }

    It 'has a 432-key schema fixture' {
        Assert-Equal -Expected 432 -Actual ([int]($script:schema.key_count))
        Assert-Equal -Expected 432 -Actual $script:schemaKeySet.Count
    }

    It 'collector source contains no literal key outside the 432-key schema' {
        $files = @()
        $files += @(Get-ChildItem -LiteralPath (Join-Path $script:agentRoot 'collectors') -Recurse -File -Filter '*.ps1')
        $files += @(Get-ChildItem -LiteralPath (Join-Path $script:agentRoot 'lib') -File -Filter '*.ps1')
        $files += @(Get-Item -LiteralPath (Join-Path $script:agentRoot 'agent.ps1'))

        $patterns = @(
            '\$data\[\s*''([^'']+)''\s*\]',
            '\$data\[\s*"([^"]+)"\s*\]',
            '\$Context\.Data\[\s*''([^'']+)''\s*\]',
            '(?<![A-Za-z0-9_])Key\s*=\s*''([^'']+)'''
        )

        $violations = @()
        foreach ($file in $files) {
            $content = Get-Content -LiteralPath $file.FullName -Raw
            foreach ($pattern in $patterns) {
                foreach ($match in [regex]::Matches($content, $pattern)) {
                    $key = $match.Groups[1].Value
                    if ($key.Contains('$')) {
                        continue # dynamic key built at runtime
                    }
                    if (-not (Test-SchemaKeyAllowed -Key $key)) {
                        $violations += ('{0}: {1}' -f $file.Name, $key)
                    }
                }
            }
        }

        Assert-Equal -Expected 0 -Actual $violations.Count -Because ("Non-schema keys found: {0}" -f ($violations -join '; '))
    }

    It 'runs every collector with mocks and matches the schema key set and types' {
        . $script:mockFunctions

        $savedSystemDrive = $env:SystemDrive
        try {
            $env:SystemDrive = 'C:'
            $config = Get-AgentConfig -Root $script:agentRoot
            $config.IceWarpHome = 'D:\IceWarp'
            $config.MailHostname = 'example.com'
            $config.LogDirectory = Join-Path $script:tempRoot 'logs'
            $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'

            foreach ($collector in @(Get-CollectorFiles -Root $script:agentRoot)) {
                $result = Invoke-AgentCollector -Path $collector.FullName -Root $script:agentRoot -Context $context
                Assert-Equal -Expected 'ok' -Actual $result.Status -Because (
                    '{0} failed: {1}' -f (Get-CollectorName -Root $script:agentRoot -Path $collector.FullName), $result.Message)
            }

            Invoke-HealthEvaluation -Data $context.Data

            $path = Join-Path $script:tempRoot 'full.json'
            Write-AgentJson -Path $path -Data $context.Data
            $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            $actualKeys = @($json.PSObject.Properties.Name)

            Assert-True -Condition ($actualKeys.Count -gt 200) -Because 'The collector run produced too few keys.'

            $violations = @()
            foreach ($key in $actualKeys) {
                if (-not (Test-SchemaKeyAllowed -Key $key)) {
                    $violations += ('non-schema key {0}' -f $key)
                    continue
                }
                if (-not (Test-SchemaTypeMatches -Key $key -Value $json.$key)) {
                    $violations += ('type mismatch {0}: expected {1}, got {2}' -f $key, (Get-ExpectedSchemaType -Key $key), (Get-JsonScalarType -Value $json.$key))
                }
            }

            Assert-Equal -Expected 0 -Actual $violations.Count -Because ("Schema contract violations: {0}" -f ($violations -join '; '))

            Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'general.os.version')
            Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'os.cpu.count')
            Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'os.memory.available_kb')
            Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'storage.install.total_gb')
            Assert-Equal -Expected 'boolean' -Actual (Get-JsonScalarType -Value $json.'smtp.starttls_live_test')
            Assert-Equal -Expected 'boolean' -Actual (Get-JsonScalarType -Value $json.'security.port_9001_egress.blocked')
            Assert-Equal -Expected 'boolean' -Actual (Get-JsonScalarType -Value $json.'icewarp.license.seats_info_available')
            Assert-Equal -Expected 'mtitc.ir;' -Actual $json.'domain.list'

            $healthKeys = @($actualKeys | Where-Object { $_ -like 'health.*' })
            Assert-True -Condition ($healthKeys.Count -ge 72) -Because (
                'Expected the full health block, got {0} health keys.' -f $healthKeys.Count)
            Assert-Equal -Expected 'string' -Actual (Get-JsonScalarType -Value $json.'health.summary.overall')
            Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'health.summary.total_checks')
        } finally {
            $env:SystemDrive = $savedSystemDrive
        }
    }

    It 'fixes OS and storage math' {
        . $script:mockFunctions

        $savedSystemDrive = $env:SystemDrive
        try {
            $env:SystemDrive = 'C:'
            $config = Get-AgentConfig -Root $script:agentRoot
            $config.IceWarpHome = 'D:\IceWarp'
            $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'
            $collectorPath = Join-Path $script:agentRoot 'collectors\Icewarp\OsStorage.ps1'
            $data = & $collectorPath -Context $context

            Assert-Equal -Expected '8' -Actual $data['os.cpu.count']
            Assert-Equal -Expected '8388608' -Actual $data['os.memory.total_kb']
            Assert-Equal -Expected '2097152' -Actual $data['os.memory.available_kb']
            Assert-Equal -Expected '1048576' -Actual $data['os.swap.total_kb']
            Assert-Equal -Expected '946176' -Actual $data['os.swap.free_kb']
            Assert-Equal -Expected '102400' -Actual $data['system.swap.used_kb']
            Assert-Equal -Expected '9.77' -Actual $data['system.swap.used_percent']
            Assert-Equal -Expected 'CRITICAL' -Actual $data['system.swap.status']

            Assert-Equal -Expected 'D:\' -Actual $data['storage.install.device']
            Assert-Equal -Expected '100.0' -Actual $data['storage.install.total_gb']
            Assert-Equal -Expected '40.0' -Actual $data['storage.install.used_gb']
            Assert-Equal -Expected '60.0' -Actual $data['storage.install.free_gb']
            Assert-Equal -Expected '40' -Actual $data['storage.install.used_percent']
            Assert-Equal -Expected 'OK' -Actual $data['storage.install.status']

            Assert-Equal -Expected 'C:\' -Actual $data['storage.root_fs.device']
            Assert-Equal -Expected '100.0' -Actual $data['storage.root_fs.total_gb']
            Assert-Equal -Expected '50' -Actual $data['storage.root_fs.used_percent']
            Assert-Equal -Expected 'C:\' -Actual $data['storage.root_home.device']
            Assert-Equal -Expected 'D:\IceWarp\mail' -Actual $data['storage.mail.path']

            $path = Join-Path $script:tempRoot 'os.json'
            Write-AgentJson -Path $path -Data $data
            $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
            Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'os.memory.available_kb')
            Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'storage.install.total_gb')
            Assert-Equal -Expected 2097152 -Actual ([long]($json.'os.memory.available_kb'))
            Assert-Equal -Expected 100 -Actual ([double]($json.'storage.install.total_gb'))
        } finally {
            $env:SystemDrive = $savedSystemDrive
        }
    }

    It 'parses DNS PTR, separate TXT records, DKIM _domainkey and DMARC _dmarc' {
        . $script:mockFunctions
        $global:AgentTestSpfRecord = 'v=spf1 a mx -all'

        $config = Get-AgentConfig -Root $script:agentRoot
        $config.MailHostname = 'example.com'
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'
        $collectorPath = Join-Path $script:agentRoot 'collectors\Icewarp\DnsMailFlow.ps1'
        $data = & $collectorPath -Context $context

        Assert-Equal -Expected 'mail.example.com' -Actual $data['dns.ptr.result']
        Assert-Equal -Expected $true -Actual $data['dns.ptr.exists']
        Assert-Equal -Expected $false -Actual $data['dns.ptr.matches_hostname']
        Assert-Equal -Expected 'v=DKIM1; k=rsa; p=ABCDEF' -Actual $data['dns.dkim.record']
        Assert-Equal -Expected 'default' -Actual $data['dns.dkim.selector_found']
        Assert-Equal -Expected 'v=DMARC1; p=none;' -Actual $data['dns.dmarc.record']
        Assert-Equal -Expected 'none' -Actual $data['dns.dmarc.policy']
        Assert-Equal -Expected $true -Actual $data['dns.spf.found']
        Assert-Equal -Expected $true -Actual $data['dns.spf.includes_server_ip']
        Assert-Equal -Expected 'a mechanism (example.com A record matches)' -Actual $data['dns.spf.ip_coverage_via']

        Assert-True -Condition ($global:AgentTestDnsQueries -contains 'TXT|default._domainkey.example.com') -Because 'DKIM queried the wrong name.'
        Assert-True -Condition ($global:AgentTestDnsQueries -contains 'TXT|_dmarc.example.com') -Because 'DMARC queried the wrong name.'
        Assert-True -Condition ($global:AgentTestDnsQueries -contains 'PTR|203.0.113.10') -Because 'PTR lookup did not query the public IP.'
        Assert-False -Condition ($global:AgentTestDnsQueries -contains 'TXT|default._example.com') -Because 'The old broken DKIM query is still used.'

        $path = Join-Path $script:tempRoot 'dns.json'
        Write-AgentJson -Path $path -Data $data
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        Assert-Equal -Expected 'boolean' -Actual (Get-JsonScalarType -Value $json.'dns.spf.includes_server_ip')
        Assert-Equal -Expected 'string' -Actual (Get-JsonScalarType -Value $json.'dns.ptr.result')
    }

    It 'evaluates SPF ip4 CIDR mechanisms without false prefix matches' {
        . $script:mockFunctions
        $global:AgentTestSpfRecord = 'v=spf1 ip4:203.0.113.11/32 -all'

        $config = Get-AgentConfig -Root $script:agentRoot
        $config.MailHostname = 'example.com'
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'
        $collectorPath = Join-Path $script:agentRoot 'collectors\Icewarp\DnsMailFlow.ps1'
        $data = & $collectorPath -Context $context

        Assert-Equal -Expected $true -Actual $data['dns.spf.found']
        Assert-Equal -Expected $false -Actual $data['dns.spf.includes_server_ip']
        Assert-Equal -Expected '' -Actual $data['dns.spf.ip_coverage_via']
    }

    It 'evaluates CIDR and reversed-IP helpers correctly' {
        Assert-Equal -Expected $true -Actual (Test-AgentIpInCidr -Ip '203.0.113.10' -Cidr '203.0.113.0/24')
        Assert-Equal -Expected $false -Actual (Test-AgentIpInCidr -Ip '203.0.113.10' -Cidr '203.0.113.11/32')
        Assert-Equal -Expected $false -Actual (Test-AgentIpInCidr -Ip '203.0.113.10' -Cidr '203.0.114.0/24')
        Assert-Equal -Expected '10.113.0.203.zen.spamhaus.org' -Actual (Get-AgentRblQueryName -Ip '203.0.113.10' -Zone 'zen.spamhaus.org')
    }

    It 'queries RBLs with the reversed IP and detects outbound firewall blocks' {
        . $script:mockFunctions
        $global:AgentTestRblListedZone = 'zen.spamhaus.org'
        $global:AgentTestFirewallBlocked = $true

        $config = Get-AgentConfig -Root $script:agentRoot
        $config.IceWarpHome = Join-Path $script:tempRoot 'icewarp'
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'
        $collectorPath = Join-Path $script:agentRoot 'collectors\Icewarp\Security.ps1'
        $data = & $collectorPath -Context $context

        Assert-Equal -Expected 'PLAIN,LOGIN' -Actual $data['security.auth_schemes.raw']
        Assert-Equal -Expected $false -Actual $data['security.digest_md5.enabled']
        Assert-True -Condition ($global:AgentTestSettingNames -contains 'C_Accounts_Policies_Auth_Schemes') -Because 'The Windows auth-scheme setting was not read.'
        Assert-Equal -Expected 'LISTED' -Actual $data['security.rbl_self_check.zones.zen_spamhaus_org']
        Assert-Equal -Expected $true -Actual $data['security.rbl_self_check.listed']
        Assert-Equal -Expected 'zen.spamhaus.org' -Actual $data['security.rbl_self_check.listed_on']
        Assert-True -Condition ($global:AgentTestDnsQueries -contains 'A|10.113.0.203.zen.spamhaus.org') -Because 'RBL did not query the reversed IP.'
        Assert-False -Condition ($data.Contains('security.rbl_self_check.reason')) -Because 'Non-schema reason key was emitted.'
        Assert-Equal -Expected $true -Actual $data['security.port_9001_egress.blocked']
        Assert-True -Condition ($data['security.port_9001_egress.method'] -match 'Windows Firewall') -Because 'Firewall method is not Windows-specific.'
        Assert-Equal -Expected $true -Actual $data['security.cyren_folder.checked']

        $path = Join-Path $script:tempRoot 'security.json'
        Write-AgentJson -Path $path -Data $data
        $json = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        Assert-Equal -Expected 'number' -Actual (Get-JsonScalarType -Value $json.'security.login.policy_enabled')
        Assert-Equal -Expected 'boolean' -Actual (Get-JsonScalarType -Value $json.'security.port_9001_egress.blocked')
        Assert-Equal -Expected 'boolean' -Actual (Get-JsonScalarType -Value $json.'security.rbl_self_check.listed')
    }

    It 'emits only license schema keys including seats information' {
        . $script:mockFunctions

        $config = Get-AgentConfig -Root $script:agentRoot
        $config.IceWarpHome = Join-Path $script:tempRoot 'icewarp'
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'
        $collectorPath = Join-Path $script:agentRoot 'collectors\Icewarp\License.ps1'
        $data = & $collectorPath -Context $context

        Assert-Equal -Expected $true -Actual $data.Contains('icewarp.license.seats_info_available')
        Assert-Equal -Expected $false -Actual $data['icewarp.license.seats_info_available']
        Assert-Equal -Expected 'ok' -Actual $data['icewarp.license.status']
        Assert-False -Condition ($data.Contains('icewarp.license.file_path')) -Because 'Non-schema file_path key was emitted.'
        Assert-False -Condition ($data.Contains('icewarp.license.trial_expiration_source')) -Because 'Non-schema trial source key was emitted.'
        Assert-Equal -Expected 'ok' -Actual $data['icewarp.license.status']

        foreach ($key in $data.Keys) {
            Assert-True -Condition (Test-SchemaKeyAllowed -Key $key) -Because ("License emitted non-schema key {0}." -f $key)
        }
    }

    It 'reads SMTP multiline responses and requires an advertised STARTTLS command' {
        $reader = New-Object System.IO.StringReader("250-test`r`n250-STARTTLS`r`n250 OK`r`n")
        $response = Read-SmtpResponse -Reader $reader
        Assert-Equal -Expected 250 -Actual $response.Code
        Assert-Equal -Expected $true -Actual $response.SupportsStartTls
        Assert-Equal -Expected 3 -Actual @($response.Lines).Count

        $reader2 = New-Object System.IO.StringReader("250-test`r`n250 OK`r`n")
        $response2 = Read-SmtpResponse -Reader $reader2
        Assert-Equal -Expected $false -Actual $response2.SupportsStartTls
        Assert-Equal -Expected $false -Actual (Test-SmtpStartTls -Server '' -TimeoutSeconds 1)
    }

    It 'evaluates OS update age and missing dates' {
        $data = [ordered]@{}
        $data['os.last_update_date'] = (Get-Date).AddDays(-2).ToString('yyyy-MM-dd')
        Invoke-HealthOsUpdateCheck -Data $data
        Assert-Equal -Expected 'pass' -Actual $data['health.os_update.result']

        $data['os.last_update_date'] = (Get-Date).AddDays(-14).ToString('yyyy-MM-dd')
        Invoke-HealthOsUpdateCheck -Data $data
        Assert-Equal -Expected 'warn' -Actual $data['health.os_update.result']

        $data['os.last_update_date'] = (Get-Date).AddDays(-45).ToString('yyyy-MM-dd')
        Invoke-HealthOsUpdateCheck -Data $data
        Assert-Equal -Expected 'critical' -Actual $data['health.os_update.result']

        $data['os.last_update_date'] = ''
        Invoke-HealthOsUpdateCheck -Data $data
        Assert-Equal -Expected 'skip' -Actual $data['health.os_update.result']
    }

    It 'evaluates MySQL, SQLite and unknown database platforms' {
        $data = [ordered]@{ 'database.type' = 'mysql' }
        Invoke-HealthDatabaseCheck -Data $data
        Assert-Equal -Expected 'pass' -Actual $data['health.database.result']

        $data['database.type'] = 'sqlite'
        Invoke-HealthDatabaseCheck -Data $data
        Assert-Equal -Expected 'warn' -Actual $data['health.database.result']

        $data['database.type'] = ''
        Invoke-HealthDatabaseCheck -Data $data
        Assert-Equal -Expected 'warn' -Actual $data['health.database.result']
        Assert-True -Condition ($data['health.database.message'] -like '*(unknown/empty)*')

        $data['database.type'] = 'postgres'
        Invoke-HealthDatabaseCheck -Data $data
        Assert-True -Condition ($data['health.database.message'] -like '*Unrecognised database type*')
    }

    It 'evaluates mail-flow DNS and STARTTLS checks' {
        $data = [ordered]@{
            'dns.spf.found'              = 'true'
            'dns.dkim.found'             = 'true'
            'dns.dmarc.found'            = 'true'
            'dns.ptr.exists'             = 'true'
            'dns.ptr.matches_hostname'   = 'true'
            'smtp.starttls_live_test'    = 'true'
            'dns.lookup_test.ok'         = 'true'
            'security.rbl_self_check.zones.zen_spamhaus_org' = 'clean'
            'security.rbl_self_check.zones.bl_spamcop_net' = 'clean'
        }
        Invoke-HealthMailFlowCheck -Data $data
        Assert-Equal -Expected 'pass' -Actual $data['health.mail_flow.result']

        # DNSBL zones: absent, then present without a recommended zone, then
        # with a recommended zone. The check uses the schema's per-zone keys.
        $data.Remove('security.rbl_self_check.zones.zen_spamhaus_org')
        $data.Remove('security.rbl_self_check.zones.bl_spamcop_net')
        Invoke-HealthMailFlowCheck -Data $data
        Assert-Equal -Expected 'warn' -Actual $data['health.mail_flow.result']
        Assert-True -Condition ($data['health.mail_flow.message'] -like '*No DNSBL zones configured*')

        $data['security.rbl_self_check.zones.dnsbl_sorbs_net'] = 'clean'
        Invoke-HealthMailFlowCheck -Data $data
        Assert-Equal -Expected 'warn' -Actual $data['health.mail_flow.result']
        Assert-True -Condition ($data['health.mail_flow.message'] -like '*missing recommended*')

        $data['security.rbl_self_check.zones.zen_spamhaus_org'] = 'clean'
        Invoke-HealthMailFlowCheck -Data $data
        Assert-Equal -Expected 'pass' -Actual $data['health.mail_flow.result']

        $data['dns.ptr.matches_hostname'] = 'false'
        Invoke-HealthMailFlowCheck -Data $data
        Assert-Equal -Expected 'warn' -Actual $data['health.mail_flow.result']
        Assert-True -Condition ($data['health.mail_flow.message'] -like '*PTR does not match*')

        $data['dns.ptr.matches_hostname'] = 'true'
        $data['dns.spf.includes_server_ip'] = 'false'
        Invoke-HealthMailFlowCheck -Data $data
        Assert-Equal -Expected 'warn' -Actual $data['health.mail_flow.result']
        Assert-True -Condition ($data['health.mail_flow.message'] -like '*SPF does not include*')

        $data['dns.spf.found'] = 'false'
        Invoke-HealthMailFlowCheck -Data $data
        Assert-Equal -Expected 'fail' -Actual $data['health.mail_flow.result']
        Assert-True -Condition ($data['health.mail_flow.message'] -like '*SPF record*')

        $empty = [ordered]@{}
        Invoke-HealthMailFlowCheck -Data $empty
        Assert-Equal -Expected 'skip' -Actual $empty['health.mail_flow.result']
    }

    It 'evaluates IMAP/POP3 and session-timeout rules' {
        $data = [ordered]@{
            'service.imap.active'          = '1'
            'service.pop3.active'          = 'true'
            'icewarp.session_timeout_minutes' = '30'
        }
        Invoke-HealthImapPop3Check -Data $data
        Invoke-HealthSessionTimeoutCheck -Data $data
        Assert-Equal -Expected 'pass' -Actual $data['health.service.imap.result']
        Assert-Equal -Expected 'pass' -Actual $data['health.service.pop3.result']
        Assert-Equal -Expected 'pass' -Actual $data['health.session_timeout.result']

        $data['service.imap.active'] = '0'
        $data['service.pop3.active'] = 'false'
        $data['icewarp.session_timeout_minutes'] = '0'
        Invoke-HealthImapPop3Check -Data $data
        Invoke-HealthSessionTimeoutCheck -Data $data
        Assert-Equal -Expected 'warn' -Actual $data['health.service.imap.result']
        Assert-Equal -Expected 'warn' -Actual $data['health.service.pop3.result']
        Assert-Equal -Expected 'warn' -Actual $data['health.session_timeout.result']
    }

    It 'rolls up nine executive pillars and computes the summary' {
        $data = [ordered]@{
            'os.memory.total_kb' = '8388608'
            'os.memory.available_kb' = '6291456'
            'os.cpu.load1' = '1.00'
            'os.cpu.count' = '4'
            'monitor.cpu.threshold_percent' = '50'
            'monitor.disk.alert_below_mb' = '5120'
            'storage.root_fs.free_gb' = '100'
            'storage.root_fs.total_gb' = '200'
            'storage.root_fs.used_percent' = '50'
            'storage.root_fs.device' = 'C:'
            'storage.root_fs.mount' = 'C:'
            'icewarp.backup.auto_enabled' = '1'
            'icewarp.backup.last_time' = (Get-Date).AddDays(-1).ToString('yyyy-MM-dd HH:mm:ss')
            'backup.db.accounts.enabled' = '1'
            'backup.db.as.enabled' = '1'
            'backup.db.gw.enabled' = '1'
            'backup.db.cache.enabled' = '1'
            'security.password_policy.active' = '1'
            'security.password_policy.min_length' = '8'
            'security.login.policy_enabled' = '1'
            'security.login.max_failed_attempts' = '5'
            'smtp.use_tls_ssl' = '1'
            'security.digest_md5.enabled' = 'false'
            'security.intrusion.block_connections_per_minute.value' = '50'
            'security.intrusion.block_duration_minutes' = '360'
            'monitor.alert_email' = 'admin@example.com'
            'watchdog.control' = '1'
            'watchdog.smtp' = '1'
            'watchdog.pop3' = '1'
            'watchdog.im' = '1'
            'watchdog.gw' = '1'
            'watchdog.interval_minutes' = '0'
            'monitor.enabled' = '1'
            'monitor.memory.alert_below_kb' = '1048576'
            'os.last_update_date' = (Get-Date).AddDays(-2).ToString('yyyy-MM-dd')
            'directory_cache.schedule_raw' = '0 2 * * *'
            'icewarp.session_timeout_minutes' = '30'
            'service.imap.active' = '1'
            'service.pop3.active' = '1'
            'database.type' = 'mysql'
            'dns.spf.found' = 'true'
            'dns.dkim.found' = 'true'
            'dns.dmarc.found' = 'true'
            'dns.ptr.exists' = 'true'
            'dns.ptr.matches_hostname' = 'true'
            'smtp.starttls_live_test' = 'true'
            'dns.lookup_test.ok' = 'true'
            'icewarp.ssl.days_left' = '120'
            'icewarp.antispam.last_update' = (Get-Date).AddDays(-2).ToString('yyyy-MM-dd')
            'icewarp.antivirus.last_update' = (Get-Date).AddDays(-2).ToString('yyyy-MM-dd')
            'security.rbl_self_check.checked' = 'false'
            'security.rbl_self_check.zones.zen_spamhaus_org' = 'clean'
            'security.rbl_self_check.zones.bl_spamcop_net' = 'clean'
            'security.cyren_folder.status' = 'OK'
        }

        Invoke-HealthEvaluation -Data $data

        foreach ($pillar in @('backup', 'mail_flow', 'tls', 'access', 'threat', 'resources', 'os_update', 'monitoring', 'database')) {
            Assert-Equal -Expected 'pass' -Actual $data[('health.{0}.result' -f $pillar)] -Because ('Pillar {0} should pass.' -f $pillar)
        }
        Assert-Equal -Expected 'pass' -Actual $data['health.summary.overall']
        Assert-Equal -Expected '9' -Actual $data['health.summary.total_checks']
        Assert-Equal -Expected '0' -Actual $data['health.summary.failed']
        Assert-Equal -Expected '0' -Actual $data['health.summary.warnings']

        # A critical memory result must fail the resources pillar and the
        # executive summary while leaving the other eight pillars counted.
        $data['os.memory.available_kb'] = '100'
        Invoke-HealthEvaluation -Data $data
        Assert-Equal -Expected 'critical' -Actual $data['health.memory.result']
        Assert-Equal -Expected 'fail' -Actual $data['health.resources.result']
        Assert-Equal -Expected 'fail' -Actual $data['health.summary.overall']
        Assert-Equal -Expected '9' -Actual $data['health.summary.total_checks']
        Assert-Equal -Expected '1' -Actual $data['health.summary.failed']
        Assert-Equal -Expected '0' -Actual $data['health.summary.warnings']
    }

    It 'Monitor collector emits schema monitor keys and falls back to the domain admin email' {
        . $script:mockFunctions

        $config = Get-AgentConfig -Root $script:agentRoot
        $config.LogDirectory = Join-Path $script:tempRoot 'logs'
        $context = Initialize-AgentContext -Root $script:agentRoot -Config $config -Version '0.1.0'
        $collectorPath = Join-Path $script:agentRoot 'collectors\Icewarp\Monitor.ps1'

        $data = & $collectorPath -Context $context
        foreach ($key in @(
            'monitor.enabled',
            'monitor.alert_email',
            'monitor.disk.alert_below_mb',
            'monitor.cpu.threshold_percent',
            'monitor.cpu.threshold_minutes',
            'monitor.memory.alert_below_kb',
            'monitor.memory.alert_below_gb',
            'monitor.web_threadpool.alert_seconds'
        )) {
            Assert-True -Condition $data.Contains($key) -Because ('Monitor collector missing {0}.' -f $key)
            Assert-True -Condition (Test-SchemaKeyAllowed -Key $key) -Because ('Monitor emitted non-schema key {0}.' -f $key)
        }
        Assert-Equal -Expected '1' -Actual $data['monitor.enabled']
        Assert-Equal -Expected '0' -Actual $data['monitor.cpu.threshold_percent']

        $global:AgentTestSettingOverrides['C_System_Tools_Monitor_ReportAddress'] = ''
        $global:AgentTestSettingOverrides['C_System_Tools_Monitor_FreeMem'] = ''
        $global:AgentTestSettingOverrides['C_System_Tools_Monitor_DiskSize'] = ''
        $global:AgentTestSettingOverrides['C_System_Tools_Monitor_CPUUsagePerc'] = ''
        $global:AgentTestSettingOverrides['C_System_Tools_Monitor_WebThreadPoolThreshold'] = ''
        function Get-IceWarpDomainSetting {
            param([string]$Domain, [string]$Name, [hashtable]$Context)
            return 'admin@example.com'
        }

        $fallback = & $collectorPath -Context $context
        Assert-Equal -Expected 'admin@example.com' -Actual $fallback['monitor.alert_email']
        Assert-Equal -Expected '1048576' -Actual $fallback['monitor.memory.alert_below_kb']
        Assert-Equal -Expected '5120' -Actual $fallback['monitor.disk.alert_below_mb']
        Assert-Equal -Expected '50' -Actual $fallback['monitor.cpu.threshold_percent']
        Assert-Equal -Expected '300' -Actual $fallback['monitor.web_threadpool.alert_seconds']
    }
}
