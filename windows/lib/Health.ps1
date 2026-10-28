#Requires -Version 5.1
<#
.SYNOPSIS
Health evaluation helpers for the Windows IceWarp Health Agent.

.DESCRIPTION
Part 1 of the port of the Linux lib/health.sh engine: shared state and the
primitive helpers used by every rule. The rule evaluation itself is added in
Part 2 and Part 3.

The bash engine keeps two associative arrays (HEALTH, HEALTH_MSG) and writes
each result straight into collector data via collector_set. This port keeps
the same two tables in script scope and writes the same
health.<name>.result / health.<name>.message keys into the supplied data
dictionary, so the JSON output stays identical to Linux.

Helper map (lib/health.sh -> Health.ps1):
    _health_set          -> Set-HealthResult
    _is_num              -> Test-HealthNumber
    _days_ago            -> Get-DaysAgo
    _health_worst        -> Get-HealthWorst
    _health_messages_for -> Get-HealthMessagesFor

Result values are intentionally lowercase (pass, warn, fail, critical, skip,
info) because health.json must match the Linux output byte for byte.
#>

# Mirrors bash's global HEALTH / HEALTH_MSG associative arrays. Reset before
# each evaluation so a repeated run cannot leak stale results.
$script:HealthResults = @{}
$script:HealthMessages = @{}

function Reset-HealthState {
    [CmdletBinding()]
    param()

    $script:HealthResults = @{}
    $script:HealthMessages = @{}
}

function ConvertTo-HealthText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    # Treat explicit 'null' / 'N/A' as missing for decision logic
    if ($Value -ieq 'null' -or $Value -ieq 'N/A') { return '' }
    return [string]$Value
}

function Set-HealthResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [ValidateSet('pass', 'warn', 'fail', 'critical', 'skip', 'info')]
        [string]$Result,
        [AllowEmptyString()]
        [string]$Message,
        [System.Collections.IDictionary]$Data
    )

    $script:HealthResults[$Name] = $Result
    if (-not [string]::IsNullOrWhiteSpace($Message)) {
        $script:HealthMessages[$Name] = $Message
    } else {
        [void]$script:HealthMessages.Remove($Name)
    }

    # bash _health_set writes health.<name>.result and, when non-empty,
    # health.<name>.message straight into collector data.
    if ($null -ne $Data) {
        $resultKey = 'health.{0}.result' -f $Name
        $messageKey = 'health.{0}.message' -f $Name
        $Data[$resultKey] = $Result
        if (-not [string]::IsNullOrWhiteSpace($Message)) {
            $Data[$messageKey] = $Message
        } elseif ($Data.Contains($messageKey)) {
            [void]$Data.Remove($messageKey)
        }
    }
}

function Get-HealthResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Default = 'skip'
    )

    if ($script:HealthResults.ContainsKey($Name)) {
        return $script:HealthResults[$Name]
    }
    return $Default
}

function Get-HealthMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($script:HealthMessages.ContainsKey($Name)) {
        return $script:HealthMessages[$Name]
    }
    return ''
}

function Test-HealthNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    # Matches ^-?[0-9]+(\.[0-9]+)?$ â€” integer or decimal, optional minus
    return ($Value -match '^-?[0-9]+(\.[0-9]+)?$')
}

function ConvertTo-HealthNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    if (-not (Test-HealthNumber -Value $Value)) { return $null }
    return [double]$Value
}

function Get-DaysAgo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$DateString,
        [datetime]$ReferenceDate = (Get-Date)
    )

    # Supported formats: yyyy-MM-dd, yyyy-MM-dd HH:mm:ss
    # If parsing fails, return 999 (same as Linux bash fallback)
    [datetime]$parsed = [datetime]::MinValue
    $parsedOk = $false
    $formats = @('yyyy-MM-dd HH:mm:ss', 'yyyy-MM-dd')
    foreach ($fmt in $formats) {
        if ([datetime]::TryParseExact($DateString, $fmt, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            $parsedOk = $true
            break
        }
    }
    if (-not $parsedOk) {
        # Try loose parse as last resort; an unparseable date must yield the
        # bash 999 fallback rather than throw under $ErrorActionPreference=Stop.
        try {
            $parsed = [datetime]::Parse($DateString, [System.Globalization.CultureInfo]::InvariantCulture)
            $parsedOk = $true
        } catch {
            return 999
        }
    }
    if (-not $parsedOk) {
        return 999
    }
    return [int][Math]::Truncate(($ReferenceDate - $parsed).TotalDays)
}

function Get-HealthValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [AllowEmptyString()]
        [string]$Default = ''
    )

    if (-not $Data.Contains($Key)) { return $Default }
    $val = $Data[$Key]
    if ($null -eq $val) { return $Default }
    if ($val -is [bool]) {
        if ($val) { return 'true' } else { return 'false' }
    }
    $text = [string]$val
    if ([string]::IsNullOrEmpty($text)) { return $Default }
    return $text
}

function Test-HealthMissing {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    # Linux treats empty, 'null', 'N/A' as missing
    return ([string]::IsNullOrWhiteSpace($Value) -or $Value -ieq 'null' -or $Value -ieq 'N/A')
}

function Test-HealthFlag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    # '1', 'true', 'TRUE', 'True' -> true
    return ($Value -eq '1' -or $Value -ieq 'true')
}

function Test-HealthEmail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    return ($Value -match '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
}

function Get-HealthWorst {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Results
    )

    # Priority: fail/critical > warn > pass/info > skip
    $worst = 'pass'
    $any   = $false
    foreach ($r in $Results) {
        switch ($r) {
            'fail'     { $worst = 'fail';  $any = $true; break }
            'critical' { $worst = 'fail';  $any = $true; break }
            'warn'     { if ($worst -ne 'fail') { $worst = 'warn' } $any = $true }
            'pass'     { $any = $true }
            'info'     { $any = $true }
            default    { }  # skip
        }
    }
    if (-not $any) { return 'skip' }
    return $worst
}

###############################################################################
# Part 2 - core rule evaluation
#
# Memory, Disk, CPU, Backup, Security (password policy, login blocking, TLS,
# DIGEST-MD5), Intrusion and Admin Email. Part 3 adds the remaining rules and
# the nine executive roll-ups.
###############################################################################

$script:HealthMinPasswordLength = 8
$script:HealthMaxLoginAttempts = 10
$script:HealthIntrusionConnectionsPerMinute = 50
$script:HealthIntrusionBlockDurationMinutes = 360

function Invoke-HealthMemoryCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $availableKb = Get-HealthValue -Data $Data -Key 'os.memory.available_kb'
    $totalKb = Get-HealthValue -Data $Data -Key 'os.memory.total_kb'

    # STRICT NOTE FORMAT: Total(KB)=<total> / Available KB=<available>
    # Missing sides render as 0, exactly like ${VAR:-0} in bash.
    $availableNote = $availableKb
    if ([string]::IsNullOrEmpty($availableNote)) {
        $availableNote = '0'
    }
    $totalNote = $totalKb
    if ([string]::IsNullOrEmpty($totalNote)) {
        $totalNote = '0'
    }
    $note = 'Total(KB)={0} / Available KB={1}' -f $totalNote, $availableNote

    $available = ConvertTo-HealthNumber -Value $availableKb
    $total = ConvertTo-HealthNumber -Value $totalKb

    if ($null -ne $available -and $null -ne $total -and $total -gt 0) {
        $usedPercent = (($total - $available) / $total) * 100
        if ($usedPercent -gt 90) {
            Set-HealthResult -Name 'memory' -Result 'critical' -Message $note -Data $Data
        } elseif ($usedPercent -gt 40) {
            Set-HealthResult -Name 'memory' -Result 'warn' -Message $note -Data $Data
        } else {
            Set-HealthResult -Name 'memory' -Result 'pass' -Message $note -Data $Data
        }
    } else {
        Set-HealthResult -Name 'memory' -Result 'warn' -Message $note -Data $Data
    }
}

function Invoke-HealthDiskCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $diskFloorMb = ConvertTo-HealthNumber -Value (Get-HealthValue -Data $Data -Key 'monitor.disk.alert_below_mb')
    $worst = 'pass'
    $seen = @{}

    # Snapshot the keys: health.* results are added to the same dictionary
    # while iterating, which would invalidate a live enumeration.
    [string[]]$keys = @($Data.Keys | ForEach-Object { [string]$_ })

    foreach ($key in $keys) {
        if ($key -notmatch '^storage\.(.+)\.free_gb$') {
            continue
        }
        $mountName = $Matches[1]

        $device = Get-HealthValue -Data $Data -Key ('storage.{0}.device' -f $mountName)
        $mount = Get-HealthValue -Data $Data -Key ('storage.{0}.mount' -f $mountName)
        $dedupeKey = '{0}|{1}' -f $device, $mount

        # Same device+mount seen twice (e.g. root_fs and root_home on /):
        # write only the marker result, matching collector_set in bash.
        if ($seen.ContainsKey($dedupeKey)) {
            $Data[('health.disk.{0}.result' -f $mountName)] = ('same_as:{0}' -f $seen[$dedupeKey])
            $messageKey = 'health.disk.{0}.message' -f $mountName
            if ($Data.Contains($messageKey)) {
                [void]$Data.Remove($messageKey)
            }
            continue
        }
        $seen[$dedupeKey] = $mountName

        $freeGbText = Get-HealthValue -Data $Data -Key $key
        $freeGb = ConvertTo-HealthNumber -Value $freeGbText
        if ($null -eq $freeGb) {
            continue
        }
        $freeMb = [int][Math]::Truncate($freeGb * 1024)

        $totalGbText = Get-HealthValue -Data $Data -Key ('storage.{0}.total_gb' -f $mountName)
        $usedPercentText = Get-HealthValue -Data $Data -Key ('storage.{0}.used_percent' -f $mountName)

        # STRICT NOTE FORMAT: Total(GB)=<total> / Used %=<used>
        $totalNote = $totalGbText
        if ([string]::IsNullOrEmpty($totalNote)) {
            $totalNote = '0'
        }
        $usedNote = $usedPercentText
        if ([string]::IsNullOrEmpty($usedNote)) {
            $usedNote = '0'
        }
        $note = 'Total(GB)={0} / Used %={1}' -f $totalNote, $usedNote

        $healthName = 'disk.{0}' -f $mountName

        if ($null -eq $diskFloorMb -or $diskFloorMb -le 0) {
            Set-HealthResult -Name $healthName -Result 'warn' -Message $note -Data $Data
            continue
        }

        $totalGb = ConvertTo-HealthNumber -Value $totalGbText
        if ($null -ne $totalGb) {
            $totalMb = [int][Math]::Truncate($totalGb * 1024)
            if ($diskFloorMb -gt $totalMb) {
                Set-HealthResult -Name $healthName -Result 'warn' -Message $note -Data $Data
                if ($worst -eq 'pass') {
                    $worst = 'warn'
                }
                continue
            }
        }

        if ($freeMb -lt $diskFloorMb) {
            Set-HealthResult -Name $healthName -Result 'fail' -Message $note -Data $Data
            $worst = 'fail'
        } else {
            Set-HealthResult -Name $healthName -Result 'pass' -Message $note -Data $Data
        }
    }

    switch ($worst) {
        'fail' {
            Set-HealthResult -Name 'disk.overall' -Result 'fail' -Message 'One or more monitored disks are below the configured free-space threshold' -Data $Data
        }
        'warn' {
            Set-HealthResult -Name 'disk.overall' -Result 'warn' -Message 'Disk alert thresholds need review' -Data $Data
        }
        default {
            Set-HealthResult -Name 'disk.overall' -Result 'pass' -Message 'All monitored disks have adequate free space' -Data $Data
        }
    }

    # The schema sample always carries a message for the first disk label
    # (health.disk.root_fs.message). When root_fs is a dedupe of another
    # label, copy that label's note across so the key is present.
    if ($Data.Contains('health.disk.root_fs.result') -and
        -not $Data.Contains('health.disk.root_fs.message')) {
        $firstLabel = $null
        foreach ($label in $seen.Values) {
            $firstLabel = $label
            break
        }
        if ($firstLabel) {
            $sourceKey = 'health.disk.{0}.message' -f $firstLabel
            if ($Data.Contains($sourceKey)) {
                $Data['health.disk.root_fs.message'] = $Data[$sourceKey]
            } else {
                $Data['health.disk.root_fs.message'] = 'Disk status could not be determined'
            }
        }
    }
}

function Invoke-HealthCpuCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $loadText = Get-HealthValue -Data $Data -Key 'os.cpu.load1'
    $coresText = Get-HealthValue -Data $Data -Key 'os.cpu.count'
    $thresholdText = Get-HealthValue -Data $Data -Key 'monitor.cpu.threshold_percent'

    $load = ConvertTo-HealthNumber -Value $loadText
    $cores = ConvertTo-HealthNumber -Value $coresText
    $threshold = ConvertTo-HealthNumber -Value $thresholdText

    if ($null -ne $load -and $null -ne $cores -and $null -ne $threshold -and $cores -gt 0) {
        $limit = ($cores * $threshold) / 100
        $limitText = $limit.ToString('0.00', [System.Globalization.CultureInfo]::InvariantCulture)
        if ($load -gt $limit) {
            Set-HealthResult -Name 'cpu' -Result 'warn' -Message ('1-min load ({0}) exceeds threshold approximation ({1})' -f $loadText, $limitText) -Data $Data
        } else {
            Set-HealthResult -Name 'cpu' -Result 'pass' -Message ('1-min load ({0}) within threshold approximation ({1})' -f $loadText, $limitText) -Data $Data
        }
    } else {
        Set-HealthResult -Name 'cpu' -Result 'skip' -Message 'System Monitor CPU threshold missing or load/core data unavailable' -Data $Data
    }
}

function Invoke-HealthBackupCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $autoEnabled = Get-HealthValue -Data $Data -Key 'icewarp.backup.auto_enabled' -Default '0'
    $lastTime = Get-HealthValue -Data $Data -Key 'icewarp.backup.last_time'

    $dbAccounts = Get-HealthValue -Data $Data -Key 'backup.db.accounts.enabled' -Default '0'
    $dbAs = Get-HealthValue -Data $Data -Key 'backup.db.as.enabled' -Default '0'
    $dbGw = Get-HealthValue -Data $Data -Key 'backup.db.gw.enabled' -Default '0'
    $dbCache = Get-HealthValue -Data $Data -Key 'backup.db.cache.enabled' -Default '0'

    if ($autoEnabled -eq '1') {
        Set-HealthResult -Name 'backup.auto' -Result 'pass' -Message 'Automatic system backup is enabled' -Data $Data
    } else {
        Set-HealthResult -Name 'backup.auto' -Result 'critical' -Message 'Automatic system backup is DISABLED (required for production)' -Data $Data
    }

    if ($dbAccounts -eq '1') {
        Set-HealthResult -Name 'backup.db' -Result 'pass' -Message 'Database backup is enabled (Accounts)' -Data $Data
    } else {
        Set-HealthResult -Name 'backup.db' -Result 'critical' -Message 'Database backup is DISABLED (Accounts missing)' -Data $Data
    }

    if ($dbAccounts -eq '1') {
        Set-HealthResult -Name 'backup.db.accounts' -Result 'pass' -Message 'Accounts database backup is enabled' -Data $Data
    } else {
        Set-HealthResult -Name 'backup.db.accounts' -Result 'critical' -Message 'Accounts database backup is DISABLED' -Data $Data
    }

    if ($dbAs -eq '1') {
        Set-HealthResult -Name 'backup.db.as' -Result 'pass' -Message 'Anti-Spam database backup is enabled' -Data $Data
    } else {
        Set-HealthResult -Name 'backup.db.as' -Result 'critical' -Message 'Anti-Spam database backup is DISABLED' -Data $Data
    }

    if ($dbGw -eq '1') {
        Set-HealthResult -Name 'backup.db.gw' -Result 'pass' -Message 'GroupWare database backup is enabled' -Data $Data
    } else {
        Set-HealthResult -Name 'backup.db.gw' -Result 'critical' -Message 'GroupWare database backup is DISABLED' -Data $Data
    }

    # Directory Cache is optional; keep it informational like the Linux engine.
    if ($dbCache -eq '1') {
        Set-HealthResult -Name 'backup.db.cache' -Result 'info' -Message 'Directory Cache database backup is enabled (optional)' -Data $Data
    } else {
        Set-HealthResult -Name 'backup.db.cache' -Result 'info' -Message 'Directory Cache database backup is disabled (optional)' -Data $Data
    }

    if (-not (Test-HealthMissing -Value $lastTime)) {
        $days = Get-DaysAgo -DateString $lastTime
        if ($days -lt 2) {
            Set-HealthResult -Name 'backup.last_time' -Result 'pass' -Message ('Last backup run: {0} ({1} days ago)' -f $lastTime, $days) -Data $Data
        } elseif ($days -lt 7) {
            Set-HealthResult -Name 'backup.last_time' -Result 'warn' -Message ('Last backup run: {0} ({1} days ago) - consider recent backup' -f $lastTime, $days) -Data $Data
        } else {
            Set-HealthResult -Name 'backup.last_time' -Result 'critical' -Message ('Last backup run: {0} ({1} days ago) - too old' -f $lastTime, $days) -Data $Data
        }
    } else {
        Set-HealthResult -Name 'backup.last_time' -Result 'warn' -Message 'No backup history found (manual run never executed)' -Data $Data
    }
}

function Invoke-HealthSecurityCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    # --- Password policy ---
    $pwActive = Get-HealthValue -Data $Data -Key 'security.password_policy.active'
    $pwMinText = Get-HealthValue -Data $Data -Key 'security.password_policy.min_length'
    $pwMin = ConvertTo-HealthNumber -Value $pwMinText

    if ($pwActive -eq '1' -and $null -ne $pwMin) {
        if ($pwMin -lt $script:HealthMinPasswordLength) {
            Set-HealthResult -Name 'password_policy' -Result 'warn' -Message ('Password policy active but min length ({0}) below recommended {1}' -f $pwMinText, $script:HealthMinPasswordLength) -Data $Data
        } else {
            Set-HealthResult -Name 'password_policy' -Result 'pass' -Message ('Password policy active, min length {0} meets recommendation' -f $pwMinText) -Data $Data
        }
    } else {
        Set-HealthResult -Name 'password_policy' -Result 'fail' -Message 'Password policy is not active' -Data $Data
    }

    # --- Login blocking (Login Policy lockout or Intrusion Prevention fallback) ---
    $policyEnabled = Get-HealthValue -Data $Data -Key 'security.login.policy_enabled'
    $loginMaxText = Get-HealthValue -Data $Data -Key 'security.login.max_failed_attempts'
    $loginMax = ConvertTo-HealthNumber -Value $loginMaxText

    $intrusionEnabled = Get-HealthValue -Data $Data -Key 'security.intrusion.block_failed_logins.enabled'
    $intrusionValueText = Get-HealthValue -Data $Data -Key 'security.intrusion.block_failed_logins.value'
    $intrusionValue = ConvertTo-HealthNumber -Value $intrusionValueText

    if ($policyEnabled -eq '1' -and $null -ne $loginMax -and $loginMax -gt 0) {
        if ($loginMax -gt $script:HealthMaxLoginAttempts) {
            Set-HealthResult -Name 'login_blocking' -Result 'warn' -Message ('Login Policy lockout threshold ({0}) higher than recommended ({1})' -f $loginMaxText, $script:HealthMaxLoginAttempts) -Data $Data
        } else {
            Set-HealthResult -Name 'login_blocking' -Result 'pass' -Message ('Login Policy lockout active, threshold ({0}) OK' -f $loginMaxText) -Data $Data
        }
    } elseif ($intrusionEnabled -eq '1' -and $null -ne $intrusionValue -and $intrusionValue -gt 0) {
        Set-HealthResult -Name 'login_blocking' -Result 'pass' -Message ('Login Policy lockout is off, but Intrusion Prevention blocks IP after {0} failed logins' -f $intrusionValueText) -Data $Data
    } else {
        Set-HealthResult -Name 'login_blocking' -Result 'fail' -Message 'Neither Login Policy lockout nor Intrusion Prevention failed-login blocking is active' -Data $Data
    }

    # --- TLS/SSL delivery ---
    if ((Get-HealthValue -Data $Data -Key 'smtp.use_tls_ssl') -eq '1') {
        Set-HealthResult -Name 'tls_delivery' -Result 'pass' -Message 'TLS/SSL for delivery is enabled' -Data $Data
    } else {
        Set-HealthResult -Name 'tls_delivery' -Result 'fail' -Message 'TLS/SSL for delivery is NOT enabled' -Data $Data
    }

    # --- DIGEST-MD5 (enabled = CRITICAL, disabled = PASS, missing = CRITICAL) ---
    $digestText = Get-HealthValue -Data $Data -Key 'security.digest_md5.enabled'
    $digest = $digestText.ToLowerInvariant()

    if ($digest -eq 'true') {
        Set-HealthResult -Name 'digest_md5' -Result 'critical' -Message 'DIGEST-MD5 auth scheme is ENABLED (weak, legacy)' -Data $Data
    } elseif ($digest -eq 'false') {
        Set-HealthResult -Name 'digest_md5' -Result 'pass' -Message 'DIGEST-MD5 auth scheme is disabled' -Data $Data
    } else {
        Set-HealthResult -Name 'digest_md5' -Result 'critical' -Message 'Auth scheme list not available - cannot verify DIGEST-MD5 status' -Data $Data
    }
}

function Invoke-HealthIntrusionCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    # STRICT: 50 connections/minute and 360 minutes block duration.
    $connectionsText = Get-HealthValue -Data $Data -Key 'security.intrusion.block_connections_per_minute.value'
    $expectedConnections = [string]$script:HealthIntrusionConnectionsPerMinute

    if ([string]::IsNullOrEmpty($connectionsText)) {
        Set-HealthResult -Name 'intrusion.block_connections' -Result 'critical' -Message 'Block IP - Connections in 1 Minute setting not found' -Data $Data
    } elseif ($connectionsText -eq $expectedConnections) {
        Set-HealthResult -Name 'intrusion.block_connections' -Result 'pass' -Message ('Block IP - Connections in 1 Minute is {0} (expected {1})' -f $connectionsText, $expectedConnections) -Data $Data
    } else {
        Set-HealthResult -Name 'intrusion.block_connections' -Result 'warn' -Message ('Block IP - Connections in 1 Minute is {0} (expected {1})' -f $connectionsText, $expectedConnections) -Data $Data
    }

    $durationText = Get-HealthValue -Data $Data -Key 'security.intrusion.block_duration_minutes'
    $expectedDuration = [string]$script:HealthIntrusionBlockDurationMinutes

    if ([string]::IsNullOrEmpty($durationText)) {
        Set-HealthResult -Name 'intrusion.block_duration' -Result 'critical' -Message 'Amount of Time IP is Blocked setting not found' -Data $Data
    } elseif ($durationText -eq $expectedDuration) {
        Set-HealthResult -Name 'intrusion.block_duration' -Result 'pass' -Message ('Amount of Time IP is Blocked is {0} minutes (expected {1})' -f $durationText, $expectedDuration) -Data $Data
    } else {
        Set-HealthResult -Name 'intrusion.block_duration' -Result 'warn' -Message ('Amount of Time IP is Blocked is {0} minutes (expected {1})' -f $durationText, $expectedDuration) -Data $Data
    }
}

function Invoke-HealthAdminEmailCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $adminEmail = Get-HealthValue -Data $Data -Key 'monitor.alert_email'

    if (Test-HealthMissing -Value $adminEmail) {
        Set-HealthResult -Name 'admin_email' -Result 'critical' -Message 'Admin email is not set' -Data $Data
    } elseif (Test-HealthEmail -Value $adminEmail) {
        Set-HealthResult -Name 'admin_email' -Result 'pass' -Message ('Admin email is configured: {0}' -f $adminEmail) -Data $Data
    } else {
        Set-HealthResult -Name 'admin_email' -Result 'warn' -Message ('Admin email is set but invalid format: {0}' -f $adminEmail) -Data $Data
    }
}

function Invoke-HealthCoreChecks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    Invoke-HealthMemoryCheck -Data $Data
    Invoke-HealthDiskCheck -Data $Data
    Invoke-HealthCpuCheck -Data $Data
    Invoke-HealthBackupCheck -Data $Data
    Invoke-HealthSecurityCheck -Data $Data
    Invoke-HealthIntrusionCheck -Data $Data
    Invoke-HealthAdminEmailCheck -Data $Data
}

###############################################################################
# Part 3 - OS, database, mail flow, services, roll-ups and entry point
###############################################################################

function Get-HealthMessagesFor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetResult,
        [Parameter(Mandatory = $true)]
        [string[]]$Keys
    )

    $messages = @()
    foreach ($key in $Keys) {
        $result = Get-HealthResult -Name $key -Default 'skip'
        # Linux maps critical to fail when collecting fail messages.
        if ($result -eq 'critical') { $result = 'fail' }
        if ($result -ne $TargetResult) { continue }
        $message = Get-HealthMessage -Name $key
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            $messages += $message
        }
    }
    return ($messages -join '; ')
}

function Invoke-HealthWatchdogCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $control = Get-HealthValue -Data $Data -Key 'watchdog.control' -Default '0'
    $smtp = Get-HealthValue -Data $Data -Key 'watchdog.smtp' -Default '0'
    $pop3 = Get-HealthValue -Data $Data -Key 'watchdog.pop3' -Default '0'
    $im = Get-HealthValue -Data $Data -Key 'watchdog.im' -Default '0'
    $gw = Get-HealthValue -Data $Data -Key 'watchdog.gw' -Default '0'
    $interval = Get-HealthValue -Data $Data -Key 'watchdog.interval_minutes' -Default '0'

    if ($control -eq '1') {
        Set-HealthResult -Name 'watchdog.control' -Result 'pass' -Message 'System Watchdog is ENABLED' -Data $Data
    } else {
        Set-HealthResult -Name 'watchdog.control' -Result 'critical' -Message 'System Watchdog is DISABLED' -Data $Data
    }

    if ($smtp -eq '1') {
        Set-HealthResult -Name 'watchdog.smtp' -Result 'pass' -Message 'SMTP Watchdog is ENABLED' -Data $Data
    } else {
        Set-HealthResult -Name 'watchdog.smtp' -Result 'critical' -Message 'SMTP Watchdog is DISABLED' -Data $Data
    }

    if ($pop3 -eq '1') {
        Set-HealthResult -Name 'watchdog.pop3' -Result 'pass' -Message 'POP3/IMAP Watchdog is ENABLED' -Data $Data
    } else {
        Set-HealthResult -Name 'watchdog.pop3' -Result 'critical' -Message 'POP3/IMAP Watchdog is DISABLED' -Data $Data
    }

    if ($im -eq '1') {
        Set-HealthResult -Name 'watchdog.im' -Result 'pass' -Message 'IM/VoIP Watchdog is ENABLED' -Data $Data
    } else {
        Set-HealthResult -Name 'watchdog.im' -Result 'critical' -Message 'IM/VoIP Watchdog is DISABLED' -Data $Data
    }

    if ($gw -eq '1') {
        Set-HealthResult -Name 'watchdog.gw' -Result 'pass' -Message 'GroupWare Watchdog is ENABLED' -Data $Data
    } else {
        Set-HealthResult -Name 'watchdog.gw' -Result 'critical' -Message 'GroupWare Watchdog is DISABLED' -Data $Data
    }

    $intervalNumber = ConvertTo-HealthNumber -Value $interval
    if ($null -ne $intervalNumber -and $intervalNumber -eq 0) {
        Set-HealthResult -Name 'watchdog.interval' -Result 'pass' -Message 'Interval: Every minute (0) - optimal' -Data $Data
    } elseif ($null -ne $intervalNumber -and $intervalNumber -ge 1 -and $intervalNumber -le 60) {
        Set-HealthResult -Name 'watchdog.interval' -Result 'pass' -Message ('Interval: {0} minutes (optimal)' -f $interval) -Data $Data
    } elseif ($null -ne $intervalNumber -and $intervalNumber -gt 60 -and $intervalNumber -le 1440) {
        Set-HealthResult -Name 'watchdog.interval' -Result 'warn' -Message ('Interval: {0} minutes (more than 1 hour - consider reducing)' -f $interval) -Data $Data
    } else {
        Set-HealthResult -Name 'watchdog.interval' -Result 'critical' -Message ('Interval: {0} minutes (too long or invalid)' -f $interval) -Data $Data
    }
}

function Invoke-HealthMonitorCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $enabled = Get-HealthValue -Data $Data -Key 'monitor.enabled' -Default '0'
    $cpu = Get-HealthValue -Data $Data -Key 'monitor.cpu.threshold_percent' -Default '50'
    $memory = Get-HealthValue -Data $Data -Key 'monitor.memory.alert_below_kb' -Default '1048576'
    $disk = Get-HealthValue -Data $Data -Key 'monitor.disk.alert_below_mb' -Default '5120'

    if ($enabled -eq '1') {
        $message = 'System Monitor ENABLED (CPU>{0}% | RAM<{1}KB | DISK<{2}MB)' -f $cpu, $memory, $disk
        Set-HealthResult -Name 'monitor.enabled' -Result 'pass' -Message $message -Data $Data
    } else {
        Set-HealthResult -Name 'monitor.enabled' -Result 'critical' -Message 'System Monitor is DISABLED' -Data $Data
    }
}

function Invoke-HealthOsUpdateCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $lastUpdate = Get-HealthValue -Data $Data -Key 'os.last_update_date'

    if (-not (Test-HealthMissing -Value $lastUpdate)) {
        $days = Get-DaysAgo -DateString $lastUpdate
        if ($days -le 7) {
            Set-HealthResult -Name 'os_update' -Result 'pass' -Message ('OS updated recently ({0} days ago)' -f $days) -Data $Data
        } elseif ($days -le 30) {
            Set-HealthResult -Name 'os_update' -Result 'warn' -Message ('OS update is {0} days old (consider updating within a week)' -f $days) -Data $Data
        } else {
            Set-HealthResult -Name 'os_update' -Result 'critical' -Message ('OS is outdated ({0} days since last update)' -f $days) -Data $Data
        }
    } else {
        Set-HealthResult -Name 'os_update' -Result 'skip' -Message 'OS last update date not available' -Data $Data
    }
}

function Invoke-HealthDirectoryCacheCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $schedule = Get-HealthValue -Data $Data -Key 'directory_cache.schedule_raw'

    if ([string]::IsNullOrWhiteSpace($schedule) -or $schedule -ieq 'not scheduled' -or $schedule -ieq 'null') {
        Set-HealthResult -Name 'directory_cache' -Result 'critical' -Message 'Directory Cache schedule is NOT SET or failed to parse' -Data $Data
    } else {
        Set-HealthResult -Name 'directory_cache' -Result 'pass' -Message ('Directory Cache schedule is configured ({0})' -f $schedule) -Data $Data
    }
}

function Invoke-HealthSessionTimeoutCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $sessionTimeout = Get-HealthValue -Data $Data -Key 'icewarp.session_timeout_minutes'

    if (-not (Test-HealthMissing -Value $sessionTimeout) -and $sessionTimeout -ne '0') {
        Set-HealthResult -Name 'session_timeout' -Result 'pass' -Message ('Session timeout is configured: {0} minutes' -f $sessionTimeout) -Data $Data
    } else {
        Set-HealthResult -Name 'session_timeout' -Result 'warn' -Message 'Session timeout is not set or is 0' -Data $Data
    }
}

function Invoke-HealthImapPop3Check {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $imapActive = Get-HealthValue -Data $Data -Key 'service.imap.active'
    $pop3Active = Get-HealthValue -Data $Data -Key 'service.pop3.active'

    if (Test-HealthFlag -Value $imapActive) {
        Set-HealthResult -Name 'service.imap' -Result 'pass' -Message 'IMAP service is running' -Data $Data
    } else {
        Set-HealthResult -Name 'service.imap' -Result 'warn' -Message 'IMAP service is disabled' -Data $Data
    }

    if (Test-HealthFlag -Value $pop3Active) {
        Set-HealthResult -Name 'service.pop3' -Result 'pass' -Message 'POP3 service is running' -Data $Data
    } else {
        Set-HealthResult -Name 'service.pop3' -Result 'warn' -Message 'POP3 service is disabled' -Data $Data
    }
}

function Invoke-HealthDatabaseCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $databaseType = Get-HealthValue -Data $Data -Key 'database.type'

    if (Test-HealthMissing -Value $databaseType) {
        Set-HealthResult -Name 'database' -Result 'warn' -Message 'Database type could not be determined (unknown/empty)' -Data $Data
        return
    }

    switch ($databaseType.ToLowerInvariant()) {
        'mysql' {
            Set-HealthResult -Name 'database' -Result 'pass' -Message 'MySQL database platform is active' -Data $Data
        }
        'sqlite' {
            Set-HealthResult -Name 'database' -Result 'warn' -Message 'SQLite is in use; MySQL is recommended for production' -Data $Data
        }
        'unknown' {
            Set-HealthResult -Name 'database' -Result 'warn' -Message 'Database type could not be determined (unknown/empty)' -Data $Data
        }
        default {
            Set-HealthResult -Name 'database' -Result 'warn' -Message ('Unrecognised database type: {0}' -f $databaseType) -Data $Data
        }
    }
}

function Invoke-HealthMailFlowCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    $checks = @(
        @{ Key = 'dns.spf.found'; Label = 'SPF record'; Severity = 'fail' },
        @{ Key = 'dns.dkim.found'; Label = 'DKIM record'; Severity = 'fail' },
        @{ Key = 'dns.dmarc.found'; Label = 'DMARC record'; Severity = 'warn' },
        @{ Key = 'dns.ptr.exists'; Label = 'PTR record'; Severity = 'warn' },
        @{ Key = 'smtp.starttls_live_test'; Label = 'STARTTLS'; Severity = 'fail' },
        @{ Key = 'dns.lookup_test.ok'; Label = 'DNS lookup'; Severity = 'fail' }
    )

    $result = 'pass'
    $any = $false
    $issues = @()

    foreach ($check in $checks) {
        $value = Get-HealthValue -Data $Data -Key $check.Key
        if ([string]::IsNullOrEmpty($value)) { continue }
        $any = $true
        if (-not (Test-HealthFlag -Value $value)) {
            $issues += $check.Label
            if ($check.Severity -eq 'fail') {
                $result = 'fail'
            } elseif ($result -ne 'fail') {
                $result = 'warn'
            }
        }
    }

    if ((Get-HealthValue -Data $Data -Key 'dns.ptr.exists') -eq 'true' -and
        (Get-HealthValue -Data $Data -Key 'dns.ptr.matches_hostname') -eq 'false') {
        $issues += 'PTR does not match the mail hostname'
        if ($result -ne 'fail') { $result = 'warn' }
    }

    if ((Get-HealthValue -Data $Data -Key 'dns.spf.found') -eq 'true' -and
        (Get-HealthValue -Data $Data -Key 'dns.spf.includes_server_ip') -eq 'false') {
        $issues += "SPF does not include this server's IP"
        if ($result -ne 'fail') { $result = 'warn' }
    }

    # DNSBL zones. The Linux health script reads security.dnsbl.zones and
    # security.dnsbl.zones.count, but those keys are absent from the 432-key
    # schema. The Windows Security collector exposes the checked zones as
    # security.rbl_self_check.zones.* instead, so accept both shapes without
    # emitting any extra output keys.
    $dnsblZones = [string](Get-HealthValue -Data $Data -Key 'security.dnsbl.zones')
    $dnsblCountText = Get-HealthValue -Data $Data -Key 'security.dnsbl.zones.count'
    $dnsblCount = ConvertTo-HealthNumber -Value $dnsblCountText
    $zoneKeys = @($Data.Keys | Where-Object { [string]$_ -like 'security.rbl_self_check.zones.*' })
    $hasZones = $false
    if (-not [string]::IsNullOrWhiteSpace($dnsblZones) -and
        $null -ne $dnsblCount -and $dnsblCount -gt 0) {
        $hasZones = $true
    }
    if ($zoneKeys.Count -gt 0) {
        $hasZones = $true
    }

    if (-not $hasZones) {
        $issues += 'No DNSBL zones configured'
        if ($result -ne 'fail') { $result = 'warn' }
    } else {
        $hasSpamhaus = ($dnsblZones -match '(?i)zen\.spamhaus\.org') -or
            ($zoneKeys -contains 'security.rbl_self_check.zones.zen_spamhaus_org')
        $hasSpamcop = ($dnsblZones -match '(?i)bl\.spamcop\.net') -or
            ($zoneKeys -contains 'security.rbl_self_check.zones.bl_spamcop_net')
        if (-not $hasSpamhaus -and -not $hasSpamcop) {
            $issues += 'DNSBL zones missing recommended: bl.spamcop.net, zen.spamhaus.org'
            if ($result -ne 'fail') { $result = 'warn' }
        }
    }

    if (-not $any) {
        Set-HealthResult -Name 'mail_flow' -Result 'skip' -Message 'Mail-flow DNS and STARTTLS checks did not return data' -Data $Data
    } elseif ($issues.Count -gt 0) {
        Set-HealthResult -Name 'mail_flow' -Result $result -Message ('Needs attention: {0}' -f ($issues -join ', ')) -Data $Data
    } else {
        Set-HealthResult -Name 'mail_flow' -Result 'pass' -Message 'SPF, DKIM, DMARC, PTR and STARTTLS checks passed' -Data $Data
    }
}

function Invoke-HealthRollupsAndSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    # --- Backup and recovery ---
    $backupKeys = @('backup.auto', 'backup.db', 'backup.last_time')
    $backupResults = @()
    foreach ($key in $backupKeys) {
        $backupResults += Get-HealthResult -Name $key -Default 'skip'
    }
    $backupResult = Get-HealthWorst -Results $backupResults
    $backupMessage = Get-HealthMessagesFor -TargetResult $backupResult -Keys $backupKeys
    if ([string]::IsNullOrWhiteSpace($backupMessage)) {
        $backupMessage = 'System, database and recent-backup checks are in place'
    }
    Set-HealthResult -Name 'backup' -Result $backupResult -Message $backupMessage -Data $Data

    # --- Transport security (delivery TLS + certificate expiry) ---
    $tlsResult = Get-HealthResult -Name 'tls_delivery' -Default 'skip'
    $tlsMessage = Get-HealthMessage -Name 'tls_delivery'
    $certDaysText = Get-HealthValue -Data $Data -Key 'icewarp.ssl.days_left'
    $certDays = ConvertTo-HealthNumber -Value $certDaysText

    if ($null -ne $certDays) {
        if ($certDays -lt 0) {
            $tlsResult = 'fail'
            $tlsMessage = 'The TLS certificate has expired'
        } elseif ($certDays -lt 30) {
            $tlsResult = 'fail'
            $tlsMessage = 'The TLS certificate expires in {0} days' -f $certDaysText
        } elseif ($certDays -lt 90) {
            if ($tlsResult -ne 'fail') { $tlsResult = 'warn' }
            $tlsMessage = '{0}; certificate expires in {1} days' -f $tlsMessage, $certDaysText
        } elseif ($tlsResult -eq 'pass') {
            $tlsMessage = 'TLS delivery is enabled; certificate valid for {0} days' -f $certDaysText
        }
    } else {
        if (-not [string]::IsNullOrWhiteSpace($tlsMessage)) {
            $tlsMessage = '{0}; certificate expiry unavailable' -f $tlsMessage
        }
        if ([string]::IsNullOrWhiteSpace($tlsMessage)) {
            $tlsMessage = 'TLS certificate expiry is not available'
        }
    }
    if ([string]::IsNullOrWhiteSpace($tlsMessage)) {
        $tlsMessage = 'TLS delivery and certificate validity are in order'
    }
    Set-HealthResult -Name 'tls' -Result $tlsResult -Message $tlsMessage -Data $Data

    # --- Access and authentication ---
    $accessKeys = @('login_blocking', 'password_policy', 'digest_md5', 'admin_email', 'session_timeout')
    $accessResults = @()
    foreach ($key in $accessKeys) {
        $accessResults += Get-HealthResult -Name $key -Default 'skip'
    }
    $accessResult = Get-HealthWorst -Results $accessResults
    $accessMessage = Get-HealthMessagesFor -TargetResult $accessResult -Keys $accessKeys

    if (Test-HealthFlag -Value (Get-HealthValue -Data $Data -Key 'security.login.2fa_bypass_enabled')) {
        if ($accessResult -eq 'pass' -or $accessResult -eq 'skip') {
            $accessResult = 'warn'
        }
        if ([string]::IsNullOrWhiteSpace($accessMessage)) {
            $accessMessage = '2FA bypass is enabled'
        } else {
            $accessMessage = '{0}; 2FA bypass is enabled' -f $accessMessage
        }
    }
    if ([string]::IsNullOrWhiteSpace($accessMessage)) {
        $accessMessage = 'Login lockout, password policy and authentication controls are in order'
    }
    Set-HealthResult -Name 'access' -Result $accessResult -Message $accessMessage -Data $Data

    # --- Threat protection (definition freshness + RBL + Cyren folders) ---
    $threatResult = 'pass'
    $threatAny = $false
    $threatIssues = @()

    $antispamDate = Get-HealthValue -Data $Data -Key 'icewarp.antispam.last_update'
    if (-not (Test-HealthMissing -Value $antispamDate)) {
        $threatAny = $true
        $days = Get-DaysAgo -DateString $antispamDate
        if ($days -gt 30) {
            $threatResult = 'fail'
            $threatIssues += ('antispam definitions are {0} days old' -f $days)
        } elseif ($days -gt 7) {
            if ($threatResult -ne 'fail') { $threatResult = 'warn' }
            $threatIssues += ('antispam definitions are {0} days old' -f $days)
        }
    } else {
        $threatAny = $true
        if ($threatResult -ne 'fail') { $threatResult = 'warn' }
        $threatIssues += 'antispam update date unavailable'
    }

    $antivirusDate = Get-HealthValue -Data $Data -Key 'icewarp.antivirus.last_update'
    if (-not (Test-HealthMissing -Value $antivirusDate)) {
        $threatAny = $true
        $days = Get-DaysAgo -DateString $antivirusDate
        if ($days -gt 30) {
            $threatResult = 'fail'
            $threatIssues += ('antivirus definitions are {0} days old' -f $days)
        } elseif ($days -gt 7) {
            if ($threatResult -ne 'fail') { $threatResult = 'warn' }
            $threatIssues += ('antivirus definitions are {0} days old' -f $days)
        }
    } else {
        $threatAny = $true
        if ($threatResult -ne 'fail') { $threatResult = 'warn' }
        $threatIssues += 'antivirus update date unavailable'
    }

    if ((Get-HealthValue -Data $Data -Key 'security.rbl_self_check.checked') -eq 'true') {
        $threatAny = $true
        if ((Get-HealthValue -Data $Data -Key 'security.rbl_self_check.listed') -eq 'true') {
            $threatResult = 'fail'
            $listedOn = Get-HealthValue -Data $Data -Key 'security.rbl_self_check.listed_on' -Default 'an RBL'
            $threatIssues += ('server IP is listed on {0}' -f $listedOn)
        }
    }

    if ((Get-HealthValue -Data $Data -Key 'security.cyren_folder.status') -eq 'WARN') {
        $threatAny = $true
        if ($threatResult -ne 'fail') { $threatResult = 'warn' }
        $threatIssues += 'old AntiSpam folders need cleanup'
    }

    if (-not $threatAny) {
        Set-HealthResult -Name 'threat' -Result 'skip' -Message 'Threat-protection freshness could not be determined' -Data $Data
    } elseif ($threatIssues.Count -gt 0) {
        Set-HealthResult -Name 'threat' -Result $threatResult -Message ('Needs attention: {0}' -f ($threatIssues -join ', ')) -Data $Data
    } else {
        Set-HealthResult -Name 'threat' -Result 'pass' -Message 'Antispam and antivirus definitions are current; IP is not listed on the checked RBLs' -Data $Data
    }

    # --- Server resources ---
    $resourceKeys = @('memory', 'cpu', 'disk.overall')
    $resourceResults = @()
    foreach ($key in $resourceKeys) {
        $resourceResults += Get-HealthResult -Name $key -Default 'skip'
    }
    $resourceResult = Get-HealthWorst -Results $resourceResults
    if ($resourceResult -eq 'pass') {
        $resourceMessage = 'CPU, RAM and disk headroom are within configured thresholds'
    } else {
        $resourceMessage = Get-HealthMessagesFor -TargetResult $resourceResult -Keys $resourceKeys
        if ([string]::IsNullOrWhiteSpace($resourceMessage)) {
            $resourceMessage = 'One or more resource thresholds need attention'
        }
    }
    Set-HealthResult -Name 'resources' -Result $resourceResult -Message $resourceMessage -Data $Data

    # --- Monitoring and watchdog ---
    $monitoringKeys = @('monitor.enabled', 'watchdog.control', 'watchdog.interval')
    $monitoringResults = @()
    foreach ($key in $monitoringKeys) {
        $monitoringResults += Get-HealthResult -Name $key -Default 'skip'
    }
    $monitoringResult = Get-HealthWorst -Results $monitoringResults
    if ($monitoringResult -eq 'pass') {
        $monitoringMessage = 'System Monitor, Watchdog and the watchdog interval are configured'
    } else {
        $monitoringMessage = Get-HealthMessagesFor -TargetResult $monitoringResult -Keys $monitoringKeys
        if ([string]::IsNullOrWhiteSpace($monitoringMessage)) {
            $monitoringMessage = 'Monitoring or watchdog coverage is incomplete'
        }
    }
    Set-HealthResult -Name 'monitoring' -Result $monitoringResult -Message $monitoringMessage -Data $Data

    # --- Nine executive pillars ---
    $summaryKeys = @(
        'backup',
        'mail_flow',
        'tls',
        'access',
        'threat',
        'resources',
        'os_update',
        'monitoring',
        'database'
    )
    $total = 0
    $failed = 0
    $warnings = 0
    foreach ($key in $summaryKeys) {
        $result = Get-HealthResult -Name $key -Default 'skip'
        if ($result -eq 'skip') { continue }
        $total++
        if ($result -eq 'fail' -or $result -eq 'critical') { $failed++ }
        if ($result -eq 'warn') { $warnings++ }
    }

    $Data['health.summary.total_checks'] = [string]$total
    $Data['health.summary.failed'] = [string]$failed
    $Data['health.summary.warnings'] = [string]$warnings
    if ($failed -gt 0) {
        $Data['health.summary.overall'] = 'fail'
    } elseif ($warnings -gt 0) {
        $Data['health.summary.overall'] = 'warn'
    } else {
        $Data['health.summary.overall'] = 'pass'
    }
}

function Invoke-HealthEvaluation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data
    )

    Reset-HealthState

    Invoke-HealthCoreChecks -Data $Data
    Invoke-HealthWatchdogCheck -Data $Data
    Invoke-HealthMonitorCheck -Data $Data
    Invoke-HealthOsUpdateCheck -Data $Data
    Invoke-HealthDirectoryCacheCheck -Data $Data
    Invoke-HealthSessionTimeoutCheck -Data $Data
    Invoke-HealthImapPop3Check -Data $Data
    Invoke-HealthDatabaseCheck -Data $Data
    Invoke-HealthMailFlowCheck -Data $Data
    Invoke-HealthRollupsAndSummary -Data $Data
}
