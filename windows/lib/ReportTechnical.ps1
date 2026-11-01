<#
.SYNOPSIS
Technical PDF report writer (report.pdf) for the Windows IceWarp Health Agent.

.DESCRIPTION
Layout-for-layout port of the Linux technical report (lib/pdf.sh, agent
0.7.x): navy cover band with identity rows, overall banner and legend, the
nine-pillar Health Summary, the checklist (one row per item with an italic
"note:" line), a Collector Status section, a grouped KEY/VALUE appendix, and
an "IceWarp Health Check Report / Page N of M" footer on every page after
the cover.

Statuses are never recalculated here. A checklist row whose control is
evaluated by the health engine takes its badge from health.<name>.result
($script:PDF_HEALTH_ROW_MAP lists the candidate keys, Linux-granular keys
first). Rows without a health key use the checklist kind rule from
config\checklist.conf.pdf, exactly as the Linux renderer does.
#>
Set-StrictMode -Version 2.0

$script:PDF_PAGE_W = 612; $script:PDF_PAGE_H = 792
$script:PDF_MARGIN = 36; $script:PDF_TOP_Y = 756; $script:PDF_BOTTOM_Y = 44
$script:PDF_CONTENT_RIGHT = $script:PDF_PAGE_W - $script:PDF_MARGIN
$script:PDF_CONTENT_W = $script:PDF_CONTENT_RIGHT - $script:PDF_MARGIN
$script:PDF_C_NAVY='0.102 0.235 0.369'; $script:PDF_C_WHITE='1 1 1'
$script:PDF_C_TEXT='0.15 0.17 0.2'; $script:PDF_C_GRAY_LIGHT='0.955 0.96 0.965'
$script:PDF_C_GREEN='0.118 0.518 0.286'; $script:PDF_C_RED='0.753 0.224 0.169'
$script:PDF_C_AMBER='0.83 0.53 0.06'; $script:PDF_C_BLUEGRAY='0.30 0.42 0.55'
$script:PDF_C_GRAY='0.5 0.53 0.56'; $script:PDF_C_VALUE='0.30 0.33 0.36'
$script:PDF_C_GROUP_BG='0.93 0.95 0.97'; $script:PDF_C_RULE='0.80 0.83 0.87'
$script:PDF_CHECKLIST_VERSION = '1.14'

$script:_PDF_PAGES=[System.Collections.Generic.List[string]]::new()
$script:_PDF_CUR=""; $script:_PDF_Y=$script:PDF_TOP_Y
$script:_PDF_ROW_INDEX=0; $script:DATA=$null
$script:_NL = "`n"
$script:CHECKLIST_ROWS=$null
$script:CHECKLIST_CAPTURED=$null
$script:CHECKLIST_CAPTURE_SECTION=""

# --- Primitives ---------------------------------------------------------------

function Pdf-Escape([string]$s){
    $o=[System.Text.StringBuilder]::new()
    for($i=0;$i -lt $s.Length;$i++){
        $c=[int]$s[$i]
        if($c -ge 32 -and $c -le 126){
            if($c -eq 92 -or $c -eq 40 -or $c -eq 41){ [void]$o.Append('\') }
            [void]$o.Append($s[$i])
        } else { [void]$o.Append('?') }
    }
    return $o.ToString()
}
function Pdf-IsNum([string]$v){ return $v -match '^-?[0-9]+(\.[0-9]+)?$' }
function Pdf-Trunc([string]$t,[int]$max){
    if($t.Length -gt $max){ $t=$t.Substring(0,$max-1)+'.' }
    return $t
}
function Pdf-Rect([float]$x,[float]$y,[float]$w,[float]$h,[string]$color){
    $script:_PDF_CUR += "${color} rg$($script:_NL)${x} ${y} ${w} ${h} re f$($script:_NL)"
}
function Pdf-Text([float]$x,[float]$y,[string]$txt,[string]$font,[float]$size,[string]$color){
    $esc=Pdf-Escape $txt
    $script:_PDF_CUR += "${color} rg$($script:_NL)BT /${font} ${size} Tf ${x} ${y} Td (${esc}) Tj ET$($script:_NL)"
}
function Pdf-TextTrunc([float]$x,[float]$y,[string]$txt,[string]$font,[float]$size,[string]$color,[int]$max){
    Pdf-Text $x $y (Pdf-Trunc $txt $max) $font $size $color
}
function Pdf-NewPage(){
    if($script:_PDF_CUR){ $script:_PDF_PAGES.Add($script:_PDF_CUR) }
    $script:_PDF_CUR=""; $script:_PDF_Y=$script:PDF_TOP_Y
}
function Pdf-Ensure([float]$needed){
    if(($script:_PDF_Y - $needed) -lt $script:PDF_BOTTOM_Y){ Pdf-NewPage }
}
function Pdf-Finish(){
    if($script:_PDF_CUR){ $script:_PDF_PAGES.Add($script:_PDF_CUR) }
    $script:_PDF_CUR=""
}
function Pdf-SectionHeader([string]$title){
    Pdf-Ensure 100
    $script:_PDF_Y = $script:_PDF_Y - 6
    Pdf-Rect $script:PDF_MARGIN ($script:_PDF_Y - 18) $script:PDF_CONTENT_W 22 $script:PDF_C_NAVY
    Pdf-Text ($script:PDF_MARGIN+8) ($script:_PDF_Y-12) $title F2 11 $script:PDF_C_WHITE
    $script:_PDF_Y = $script:_PDF_Y - 30
}
function Pdf-BadgeColor([string]$k){
    switch($k){ PASS{$script:PDF_C_GREEN} CRITICAL{$script:PDF_C_RED} WARN{$script:PDF_C_AMBER} INFO{$script:PDF_C_BLUEGRAY} default{$script:PDF_C_GRAY} }
}
function Pdf-PlainLine([string]$t){
    Pdf-Ensure 20
    Pdf-Text $script:PDF_MARGIN $script:_PDF_Y $t F1 8.5 $script:PDF_C_TEXT
    $script:_PDF_Y = $script:_PDF_Y - 12
}
# One checklist / summary row: label, value, coloured badge and an italic note.
function Pdf-Row([string]$label,[string]$value,[string]$bkind,[string]$btext,[string]$note){
    if($null -ne $script:CHECKLIST_ROWS){
        [void]$script:CHECKLIST_ROWS.Add([pscustomobject]@{
            section=$script:CHECKLIST_CAPTURE_SECTION
            label=$label
            value=$value
            bkind=$bkind
            btext=$btext
            note=$note
        })
    }
    $rowH=16; if($note){$rowH=27}
    Pdf-Ensure $rowH
    $bg=$script:PDF_C_WHITE
    if(($script:_PDF_ROW_INDEX % 2) -eq 1){ $bg=$script:PDF_C_GRAY_LIGHT }
    $script:_PDF_ROW_INDEX++
    $rowTop=$script:_PDF_Y
    Pdf-Rect $script:PDF_MARGIN ($rowTop-$rowH+4) $script:PDF_CONTENT_W $rowH $bg
    $textY=$rowTop-11
    Pdf-TextTrunc ($script:PDF_MARGIN+8) $textY $label F1 9 $script:PDF_C_TEXT 46
    Pdf-TextTrunc ($script:PDF_MARGIN+240) $textY $value F1 9 $script:PDF_C_VALUE 34
    $badgeW=76; $badgeH=13
    $badgeX=($script:PDF_CONTENT_RIGHT - $badgeW - 4); $badgeY=($rowTop-12)
    Pdf-Rect $badgeX $badgeY $badgeW $badgeH (Pdf-BadgeColor $bkind)
    Pdf-TextTrunc ($badgeX+6) ($badgeY+4) $btext F2 7.5 $script:PDF_C_WHITE 14
    if($note){
        Pdf-TextTrunc ($script:PDF_MARGIN+8) ($textY-11) ("note: " + $note) F3 7.5 $script:PDF_C_GRAY 130
    }
    $script:_PDF_Y = $rowTop - $rowH
}

# --- Data access ----------------------------------------------------------------

# Normalized string form of a data value. Native booleans become 'true' or
# 'false' so they compare correctly with string literals (PowerShell converts
# '0'/'false' to $true when it compares a string against a bool).
function Pdf-Raw([string]$key){
    if($null -eq $script:DATA -or -not $script:DATA.Contains($key)){ return '' }
    $v=$script:DATA[$key]
    if($null -eq $v){ return '' }
    if($v -is [bool]){ if($v){ return 'true' } else { return 'false' } }
    return [string]$v
}
function Pdf-IsTrue([string]$v){ return ($v -eq '1' -or $v -eq 'true') }
function Pdf-IsFalse([string]$v){ return ($v -eq '0' -or $v -eq 'false') }
function Pdf-ClValue([string]$keys){
    if($keys.Contains(',')){
        $parts=@()
        foreach($k in $keys.Split(',')){
            $short=$k.Substring($k.LastIndexOf('.')+1)
            $parts+=("{0}={1}" -f $short, (Pdf-Raw $k))
        }
        return ($parts -join ', ')
    }
    $v=Pdf-Raw $keys
    if([string]::IsNullOrEmpty($v)){ $v='(empty)' }
    return $v
}

# --- Health-engine owned rows ---------------------------------------------------

# Checklist label -> candidate health names. The first name with a result in
# the data wins: the Linux-granular keys come first so the same renderer
# matches the Linux report, then the Windows health engine equivalents.
$script:PDF_HEALTH_ROW_MAP=@{
    'Check PTR'=@('mail.ptr')
    'Check SPF'=@('mail.spf')
    'Check DKIM'=@('mail.dkim')
    'Check DMARC'=@('mail.dmarc')
    'Check TLS and Start TLS'=@('mail.starttls')
    'Test DNS Lookup'=@('mail.dns_lookup')
    'Enable System Backup'=@('backup.auto')
    'Last Backup Date and Time'=@('backup.last_time')
    'Enable Database Backup - Accounts'=@('backup.db.accounts')
    'Enable Database Backup - AntiSpam'=@('backup.db.as')
    'Enable Database Backup - GroupWare'=@('backup.db.gw')
    'Enable Database Backup - Directory Cache'=@('backup.db.cache')
    'Enable System Watchdog'=@('watchdog.control')
    'Enable System Monitor (Mem/Disk/CPU)'=@('monitor.enabled')
    'Check for Certificates'=@('tls.certificate','tls')
    'RBL Valli Check (is our IP blacklisted)'=@('threat.rbl')
    '2FA'=@('access.2fa')
    'Use TLS/SSL (Secured Delivery)'=@('tls_delivery')
    'Maximum Number of Simultaneous Threads'=@('smtp.threads')
    'Set Directory Cache Schedule'=@('directory_cache')
    'Block IP - Connections in 1 Minute'=@('intrusion.block_connections')
    'Block IP - Unknown User Delivery Count'=@('intrusion.unknown_user')
    'Block IP - Denied for Relaying Too Often'=@('intrusion.relay_denied')
    'Block IP - Exceeds RSET Session Count'=@('intrusion.rset')
    'Block IP - Message Spam Score'=@('intrusion.spam_score')
    'Block IP - Exceeds Failed Login Attempts'=@('intrusion.failed_logins')
    'Amount of Time IP is Blocked (minutes)'=@('intrusion.block_duration')
    'Set customers-stat@parsavan.com'=@('access.stats_mailbox')
    'Remove Old AntiSpam Folders'=@('threat.cyren')
    'Set Admin Email'=@('admin_email')
    'Disable DIGEST-MD5'=@('digest_md5')
    'Session Timeout'=@('session_timeout')
    'Enable SSL/TLS'=@('tls_delivery')
    'Disable IMAP'=@('service.imap')
    'Disable POP3'=@('service.pop3')
    'Watchdog - SMTP'=@('watchdog.smtp')
    'Watchdog - POP3/IMAP'=@('watchdog.pop3')
    'Watchdog - IM/VoIP'=@('watchdog.im')
    'Watchdog - GroupWare'=@('watchdog.gw')
    'Watchdog Interval'=@('watchdog.interval')
    'Disk (Total GB / Used %)'=@('disk.overall')
    'CPU Usage'=@('cpu')
    'RAM (Total KB / Available KB)'=@('memory')
    'APP OS Last Update'=@('os_update')
    'Swap Usage (7 days)'=@('swap')
    'Database Type'=@('database.platform','database')
}

function Pdf-HealthBadge([string]$result){
    switch($result){
        'pass'     { return 'PASS' }
        'ok'       { return 'PASS' }
        'warn'     { return 'WARN' }
        'fail'     { return 'CRITICAL' }
        'critical' { return 'CRITICAL' }
        'skip'     { return 'INFO' }
        'info'     { return 'INFO' }
    }
    return ''
}
function Pdf-HealthName([string]$label){
    if(-not $script:PDF_HEALTH_ROW_MAP.ContainsKey($label)){ return '' }
    foreach($candidate in $script:PDF_HEALTH_ROW_MAP[$label]){
        if(Pdf-HealthBadge (Pdf-Raw "health.$candidate.result")){ return $candidate }
    }
    return ''
}
function Pdf-DaysFromMessage([string]$message){
    if($message -match '(\d+) days'){ return $Matches[1] }
    return ''
}
# Certificate expiry as YYYY-MM-DD from the collector's expiry text
# (openssl "Dec 11 09:32:53 2026 GMT" on Linux, .NET date text on Windows).
function Pdf-IsoDate([string]$text){
    if([string]::IsNullOrWhiteSpace($text)){ return '' }
    $clean=($text -replace '\s+',' ').Trim()
    $parsed=[datetime]::MinValue
    $inv=[System.Globalization.CultureInfo]::InvariantCulture
    foreach($fmt in @('MMM d HH:mm:ss yyyy \G\M\T','MMM dd HH:mm:ss yyyy \G\M\T','yyyy-MM-dd','yyyy-MM-dd HH:mm:ss')){
        if([datetime]::TryParseExact($clean,$fmt,$inv,[System.Globalization.DateTimeStyles]::AllowWhiteSpaces,[ref]$parsed)){ return $parsed.ToString('yyyy-MM-dd',$inv) }
    }
    foreach($culture in @($inv,[System.Globalization.CultureInfo]::CurrentCulture)){
        if([datetime]::TryParse($clean,$culture,[System.Globalization.DateTimeStyles]::None,[ref]$parsed)){ return $parsed.ToString('yyyy-MM-dd',$inv) }
    }
    return ''
}
# Row note: the checklist note, with the archive folder appended as on Linux.
function Pdf-RowNote([string]$label,[string]$note){
    if($label -eq 'Integrate Archive with IMAP Folder'){
        $folder=Pdf-Raw 'archive.imap_folder_name'
        if($folder){ return ('{0}: {1}' -f $note, $folder) }
    }
    return $note
}
# Evidence shown in the value column of a health-owned row.
function Pdf-HealthValue([string]$label,[string]$kind,[string]$keys,[string]$result,[string]$name){
    $raw=Pdf-Raw $keys
    $message=Pdf-Raw "health.$name.message"
    if($label -in @('Check PTR','Check SPF','Check DKIM','Check DMARC','Check TLS and Start TLS','Test DNS Lookup')){
        if((Pdf-HealthBadge $result) -eq 'PASS'){ return 'OK' }
        if(Pdf-IsTrue $raw){ return 'Mismatch' }
        return 'Missing'
    }
    if($label -eq 'Last Backup Date and Time' -or $label -eq 'APP OS Last Update'){
        if(-not $raw){ return '(empty)' }
        $days=Pdf-DaysFromMessage $message
        if($days){ return ('{0} ({1} days ago)' -f $raw, $days) }
        return $raw
    }
    switch($label){
        'Check for Certificates' {
            $left=Pdf-Raw 'icewarp.ssl.days_left'
            $expiry=Pdf-Raw 'icewarp.ssl.expiration'
            if($left){
                $iso=Pdf-IsoDate $expiry
                if($iso){ return ('{0} days left ({1})' -f $left, $iso) }
                return ('{0} days left' -f $left)
            }
            if($expiry){ return $expiry }
            return '(empty)'
        }
        'RBL Valli Check (is our IP blacklisted)' {
            if(Pdf-IsTrue $raw){ return 'Yes' }; if(Pdf-IsFalse $raw){ return 'No' }
        }
        '2FA' {
            if(Pdf-IsFalse $raw){ return '2FA active' }; if(Pdf-IsTrue $raw){ return '2FA bypass enabled' }
        }
        'Set Directory Cache Schedule' {
            if(Pdf-IsTrue $raw){ $s=Pdf-Raw 'directory_cache.schedule_raw'; if($s){ return $s }; return 'Scheduled' }
            return 'Not scheduled'
        }
        'Disable DIGEST-MD5' {
            if(Pdf-IsTrue $raw){ return 'Enabled' }; if(Pdf-IsFalse $raw){ return 'Disabled' }
        }
        'Session Timeout' { if($raw){ return ('{0} minutes' -f $raw) } }
        'Disable IMAP' { if(Pdf-IsTrue $raw){ return 'Running' }; if(Pdf-IsFalse $raw){ return 'Disabled' } }
        'Disable POP3' { if(Pdf-IsTrue $raw){ return 'Running' }; if(Pdf-IsFalse $raw){ return 'Disabled' } }
        'Disk (Total GB / Used %)' {
            return ('Total(GB)={0} / Used %={1}' -f (Pdf-Raw 'storage.root_fs.total_gb'), (Pdf-Raw 'storage.root_fs.used_percent'))
        }
        'CPU Usage' {
            # Linux format: "load1 1.01 (limit 2.40)" - no % signs, limit from system monitor threshold
            $load=Pdf-Raw 'os.cpu.load1'
            $limit=Pdf-Raw 'monitor.cpu.threshold_percent'
            if($load -and $limit){ return ('load1 {0} (limit {1})' -f $load, $limit) }
            if($load){ return ('load1 {0}' -f $load) }
            return '(empty)'
        }
        'RAM (Total KB / Available KB)' {
            return ('Total(KB)={0} / Available KB={1}' -f (Pdf-Raw 'os.memory.total_kb'), (Pdf-Raw 'os.memory.available_kb'))
        }
        'Swap Usage (7 days)' {
            $pct=Pdf-Raw 'system.swap.used_percent'; if($pct){ return "$pct%" }
        }
    }
    if($kind -eq 'B'){ if(Pdf-IsTrue $raw){ return 'Enabled' }; return 'Disabled' }
    if($kind -eq 'R'){ if(Pdf-IsTrue $raw){ return 'Yes' }; if(Pdf-IsFalse $raw){ return 'No' } }
    if([string]::IsNullOrEmpty($raw)){ return '(empty)' }
    return $raw
}

# --- Checklist ------------------------------------------------------------------

function Pdf-ChecklistRow([string]$section,[string]$label,[string]$kind,[string]$keys,[string]$note){
    # MySQL rows only apply when MySQL is the database platform.
    if($section -like 'MySQL Server*' -and (Pdf-Raw 'database.scope') -ne 'remote'){
        $why='not applicable - SQLite database in use, no MySQL server to check'
        if((Pdf-Raw 'database.type') -eq 'mysql'){ $why='not applicable - MySQL runs locally on this same server, see the Database section above' }
        Pdf-Row $label 'N/A' 'INFO' 'INFO' $why
        return
    }
    if($section -eq 'Database' -and $label -like 'MySQL*' -and (Pdf-Raw 'mysql.applicable') -ne 'true'){
        Pdf-Row $label 'not applicable' 'INFO' 'INFO' 'MySQL not applicable on this host'
        return
    }

    # Health-engine owned rows: badge from health.*; note is the checklist note
    # on PASS and the health message otherwise (Linux behaviour).
    $name=Pdf-HealthName $label
    if($name){
        $result=Pdf-Raw "health.$name.result"
        $badge=Pdf-HealthBadge $result
        $btext=$badge
        if($result -eq 'skip'){ $btext='SKIP' }
        $rowNote=Pdf-RowNote $label $note
        if($badge -ne 'PASS'){
            $message=Pdf-Raw "health.$name.message"
            if($message){ $rowNote=$message }
        }
        Pdf-Row $label (Pdf-HealthValue $label $kind $keys $result $name) $badge $btext $rowNote
        return
    }

    $raw=Pdf-Raw $keys
    $rowNote=Pdf-RowNote $label $note

    # Rows whose status is reported by a collector (no health key on this host).
    if($label -eq 'Database Scope'){
        $scope=$raw; if(-not $scope){ $scope='unknown' }
        Pdf-Row $label $scope 'PASS' 'PASS' ("Database scope: {0}" -f $scope)
        return
    }
    if($label -eq 'Swap Usage (7 days)'){
        $pct=Pdf-Raw 'system.swap.used_percent'; if(-not $pct){ $pct='0' }
        $status=Pdf-Raw 'system.swap.status'
        $badge=switch($status){ 'PASS'{'PASS'} 'WARN'{'WARN'} 'CRITICAL'{'CRITICAL'} default{'INFO'} }
        $swapNote=$rowNote
        if($badge -ne 'PASS'){ $m=Pdf-Raw 'system.swap.message'; if($m){ $swapNote=$m } }
        Pdf-Row $label "$pct%" $badge $badge $swapNote
        return
    }
    if($label -eq 'Remove Old AntiSpam Folders'){
        $status=Pdf-Raw 'security.cyren_folder.status'
        if($status -eq 'WARN'){
            $m=Pdf-Raw 'security.cyren_folder.message'; if(-not $m){ $m=$rowNote }
            Pdf-Row $label $status 'WARN' 'WARN' $m
        } elseif($status -eq 'OK'){
            Pdf-Row $label $status 'PASS' 'PASS' $rowNote
        } else {
            Pdf-Row $label (Pdf-ClValue $keys) 'INFO' 'INFO' $rowNote
        }
        return
    }

    # "Expected: X" in the checklist note is the checklist's own target value.
    if($kind -eq 'V' -and $note -match 'Expected:\s*([^)\s]+)'){
        $expected=$Matches[1]
        if([string]::IsNullOrEmpty($raw)){ Pdf-Row $label '' 'CRITICAL' 'CRITICAL' 'Setting not found'; return }
        $same=($raw -eq $expected)
        if(-not $same -and (Pdf-IsNum $raw) -and (Pdf-IsNum $expected)){ $same=([double]$raw -eq [double]$expected) }
        if($same){ Pdf-Row $label $raw 'PASS' 'PASS' $rowNote }
        else { Pdf-Row $label $raw 'WARN' 'WARN' ('{0} (current: {1})' -f $rowNote, $raw) }
        return
    }
    if($kind -eq 'V'){
        Pdf-Row $label (Pdf-ClValue $keys) 'INFO' 'INFO' $rowNote
        return
    }

    switch($kind){
        'T' {
            if($raw -eq $note){ Pdf-Row $label $raw 'PASS' 'PASS' "Expected: $note" }
            else { Pdf-Row $label $raw 'WARN' 'WARN' "Expected: $note (current: $raw)" }
        }
        'F' {
            if(Pdf-IsTrue $raw){ Pdf-Row $label 'Found' 'PASS' 'PASS' $rowNote }
            elseif(Pdf-IsFalse $raw){ Pdf-Row $label 'Missing' 'CRITICAL' 'CRITICAL' $rowNote }
            else { Pdf-Row $label 'N/A' 'INFO' 'INFO' $rowNote }
        }
        'B' {
            if($label -eq 'Disable VRFY'){
                if(Pdf-IsTrue $raw){ Pdf-Row $label 'Disabled' 'PASS' 'PASS' $rowNote }
                else { Pdf-Row $label 'Enabled' 'CRITICAL' 'CRITICAL' $rowNote }
            } elseif($label -eq 'Block Outgoing Port 9001'){
                if(Pdf-IsTrue $raw){ Pdf-Row $label 'Blocked' 'PASS' 'PASS' $rowNote }
                else { Pdf-Row $label 'Not blocked' 'CRITICAL' 'CRITICAL' $rowNote }
            } elseif(Pdf-IsTrue $raw){ Pdf-Row $label 'Enabled' 'PASS' 'PASS' $rowNote }
            else { Pdf-Row $label 'Disabled' 'CRITICAL' 'CRITICAL' $rowNote }
        }
        'R' {
            if($label -eq '2FA'){
                if(Pdf-IsFalse $raw){ Pdf-Row $label '2FA active' 'PASS' 'PASS' $rowNote }
                elseif(Pdf-IsTrue $raw){ Pdf-Row $label '2FA bypass enabled' 'CRITICAL' 'CRITICAL' $rowNote }
                else { Pdf-Row $label 'N/A' 'INFO' 'INFO' $rowNote }
            } elseif(Pdf-IsFalse $raw){ Pdf-Row $label 'No' 'PASS' 'PASS' $rowNote }
            elseif(Pdf-IsTrue $raw){ Pdf-Row $label 'Yes' 'CRITICAL' 'CRITICAL' $rowNote }
            else { Pdf-Row $label 'N/A' 'INFO' 'INFO' $rowNote }
        }
        'L' {
            if(-not [string]::IsNullOrEmpty($raw) -and $raw -ne '0'){ Pdf-Row $label "Enabled (level $raw)" 'PASS' 'PASS' $rowNote }
            elseif($raw -eq '0'){ Pdf-Row $label 'Disabled' 'CRITICAL' 'CRITICAL' $rowNote }
            else { Pdf-Row $label 'N/A' 'INFO' 'INFO' $rowNote }
        }
        'Z' {
            if($raw -eq '0'){ Pdf-Row $label 'Disabled' 'WARN' 'WARN' $rowNote }
            elseif(-not [string]::IsNullOrEmpty($raw)){ Pdf-Row $label $raw 'INFO' 'INFO' $rowNote }
            else { Pdf-Row $label 'not collected' 'INFO' 'INFO' $rowNote }
        }
        'M' {
            if(Pdf-IsTrue $raw){ Pdf-Row $label 'Yes' 'WARN' 'WARN' $rowNote }
            else { Pdf-Row $label 'No' 'PASS' 'PASS' $rowNote }
        }
        'G' {
            if(Pdf-IsTrue $raw){ Pdf-Row $label 'Yes' 'PASS' 'PASS' $rowNote }
            else { Pdf-Row $label 'No' 'CRITICAL' 'CRITICAL' $rowNote }
        }
        'P' {
            if(Pdf-IsTrue $raw){ Pdf-Row $label 'Active' 'CRITICAL' 'CRITICAL' $rowNote }
            else { Pdf-Row $label 'Off' 'PASS' 'PASS' $rowNote }
        }
        'D' {
            if($label -eq 'Disable AntiSpam Live'){
                if(Pdf-IsFalse $raw){ Pdf-Row $label 'YES' 'PASS' 'PASS' $rowNote }
                elseif(Pdf-IsTrue $raw){ Pdf-Row $label 'NO' 'WARN' 'WARN' $rowNote }
                else { Pdf-Row $label 'N/A' 'INFO' 'INFO' $rowNote }
            } elseif(Pdf-IsFalse $raw){ Pdf-Row $label 'Disabled' 'PASS' 'PASS' $rowNote }
            elseif(Pdf-IsTrue $raw){ Pdf-Row $label 'Enabled' 'WARN' 'WARN' $rowNote }
            else { Pdf-Row $label 'N/A' 'INFO' 'INFO' $rowNote }
        }
        'W' { Pdf-Row $label $raw 'INFO' 'INFO' $rowNote }
        'H' {
            $worst='pass'; $msgs=@()
            foreach($k in $keys.Split(',')){
                $result=Pdf-Raw "health.$k.result"
                if($result -eq 'fail' -or $result -eq 'critical'){ $worst='fail' }
                elseif($result -eq 'warn' -and $worst -ne 'fail'){ $worst='warn' }
                $m=Pdf-Raw "health.$k.message"
                if($m){ $msgs+=$m }
            }
            $badge=switch($worst){ 'pass'{'PASS'} 'warn'{'WARN'} default{'CRITICAL'} }
            $joined=($msgs -join '; '); if(-not $joined){ $joined=$rowNote }
            Pdf-Row $label '' $badge $badge $joined
        }
        default {
            if(-not [string]::IsNullOrEmpty($raw)){ Pdf-Row $label $raw 'INFO' 'INFO' $rowNote }
            else { Pdf-Row $label 'N/A' 'INFO' 'INFO' $rowNote }
        }
    }
}

function Render-Checklist([hashtable]$Data){
    $script:DATA=$Data
    $script:_PDF_ROW_INDEX=0
    # PS 5.1 Join-Path accepts only one child path; nest the calls.
    $checklistFile=[System.IO.Path]::GetFullPath((Join-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'config') 'checklist.conf.pdf'))
    if(-not (Test-Path -LiteralPath $checklistFile)){
        Pdf-PlainLine "Checklist file not found: $checklistFile"
        return
    }
    $curSection=""
    $script:CHECKLIST_ROWS=[System.Collections.Generic.List[object]]::new()
    $script:CHECKLIST_CAPTURE_SECTION=""
    foreach($rawLine in [System.IO.File]::ReadAllLines($checklistFile)){
        $line=$rawLine.Trim()
        if([string]::IsNullOrEmpty($line)){ continue }
        $parts=$line.Split('~')
        if($parts.Length -lt 4){ continue }
        $section=$parts[0]; $label=$parts[1]; $kind=$parts[2]; $keys=$parts[3]
        $note=if($parts.Length -gt 4){$parts[4]}else{""}
        if($section -ne $curSection){
            Pdf-SectionHeader $section
            $curSection=$section
            $script:CHECKLIST_CAPTURE_SECTION=$section
            $script:_PDF_ROW_INDEX=0
        }
        Pdf-ChecklistRow $section $label $kind $keys $note
    }
    $script:CHECKLIST_CAPTURED=$script:CHECKLIST_ROWS
    $script:CHECKLIST_ROWS=$null
    $script:CHECKLIST_CAPTURE_SECTION=""
}

# --- Cover page and health summary ------------------------------------------------

function Build-TechnicalReport([hashtable]$Data,[string]$OutPath){
    $script:DATA=$Data
    $script:_PDF_PAGES=[System.Collections.Generic.List[string]]::new()
    $script:_PDF_CUR=""; $script:_PDF_Y=$script:PDF_TOP_Y; $script:_PDF_ROW_INDEX=0
    $agentHost=Pdf-Raw 'agent.hostname'; if(-not $agentHost){$agentHost='unknown'}
    $agentTime=Pdf-Raw 'agent.time'; if(-not $agentTime){$agentTime='unknown'}
    $agentVer=Pdf-Raw 'agent.version'; if(-not $agentVer){$agentVer='unknown'}
    $overallStatus=Pdf-Raw 'health.summary.overall'; if(-not $overallStatus){$overallStatus='n/a'}
    $failCount=Pdf-Raw 'health.summary.failed'; if(-not $failCount){$failCount='0'}
    $warnCount=Pdf-Raw 'health.summary.warnings'; if(-not $warnCount){$warnCount='0'}
    $totalChecks=Pdf-Raw 'health.summary.total_checks'; if(-not $totalChecks){$totalChecks='0'}
    Pdf-Rect 0 692 $script:PDF_PAGE_W 100 $script:PDF_C_NAVY
    Pdf-Text $script:PDF_MARGIN 754 "IceWarp Health Check Report" F2 22 $script:PDF_C_WHITE
    Pdf-Text $script:PDF_MARGIN 730 ("Based on IceWarp CheckList v{0}" -f $script:PDF_CHECKLIST_VERSION) F3 12 $script:PDF_C_WHITE
    Pdf-Text $script:PDF_MARGIN 706 ("Host: {0}   Generated: {1}   Agent v{2}" -f $agentHost, $agentTime, $agentVer) F1 9.5 $script:PDF_C_WHITE
    $script:_PDF_Y=660
    $licType=Pdf-Raw 'icewarp.license.type'; if(-not $licType){$licType='unknown'}
    $licExp=Pdf-Raw 'icewarp.license.trial_expiration'
    if($licExp){ $licDisplay=$licExp }
    elseif($licType -eq 'Evaluation'){ $licDisplay='Evaluation (expiration not detected)' }
    else { $licDisplay='N/A (perpetual license)' }
    $infoRows=@(
        @('Company Name', (Pdf-Raw 'general.company')),
        @('Mail Domain', (Pdf-Raw 'domain.primary.name')),
        @('Technician', (Pdf-Raw 'general.technician')),
        @('IceWarp Version', (Pdf-Raw 'icewarp.version')),
        @('Antispam Last Update', (Pdf-Raw 'icewarp.antispam.last_update')),
        @('Antivirus Last Update', (Pdf-Raw 'icewarp.antivirus.last_update')),
        @('Last Backup Date/Time', (Pdf-Raw 'icewarp.backup.last_time')),
        @('License Type', $licType),
        @('License Expiration', $licDisplay),
        @('SSL Expiration', (Pdf-Raw 'icewarp.ssl.expiration'))
    )
    foreach($row in $infoRows){
        Pdf-Text ($script:PDF_MARGIN+8) $script:_PDF_Y ("{0}:" -f $row[0]) F2 9.5 $script:PDF_C_TEXT
        Pdf-TextTrunc ($script:PDF_MARGIN+190) $script:_PDF_Y $row[1] F1 9.5 $script:PDF_C_GRAY 55
        $script:_PDF_Y = $script:_PDF_Y - 16
    }
    $script:_PDF_Y = $script:_PDF_Y - 14
    $bannerColor=$script:PDF_C_GRAY
    switch($overallStatus){ 'pass'{$bannerColor=$script:PDF_C_GREEN} 'warn'{$bannerColor=$script:PDF_C_AMBER} 'fail'{$bannerColor=$script:PDF_C_RED} }
    Pdf-Rect $script:PDF_MARGIN ($script:_PDF_Y-44) $script:PDF_CONTENT_W 44 $bannerColor
    Pdf-Text ($script:PDF_MARGIN+14) ($script:_PDF_Y-20) ("OVERALL: $($overallStatus.ToUpper())") F2 15 $script:PDF_C_WHITE
    Pdf-Text ($script:PDF_MARGIN+14) ($script:_PDF_Y-36) ("{0} checks run  -  {1} failed  -  {2} warnings" -f $totalChecks, $failCount, $warnCount) F1 9.5 $script:PDF_C_WHITE
    $script:_PDF_Y = $script:_PDF_Y - 60
    Pdf-Text $script:PDF_MARGIN $script:_PDF_Y "Legend:" F2 8.5 $script:PDF_C_TEXT
    $lx=$script:PDF_MARGIN+46
    foreach($status in @('PASS','CRITICAL','WARN','INFO')){
        Pdf-Rect $lx ($script:_PDF_Y-3) 26 11 (Pdf-BadgeColor $status)
        Pdf-Text ($lx+30) $script:_PDF_Y $status F1 8 $script:PDF_C_TEXT
        $lx=$lx+30+6*$status.Length+14
    }
    $script:_PDF_Y = $script:_PDF_Y - 20
    Pdf-SectionHeader "Health Summary"
    $script:_PDF_ROW_INDEX=0
    Pdf-PlainLine "Nine executive control areas. Detailed evidence follows in the checklist."
    $summary=@(
        @('backup','Backup & Recovery'), @('mail_flow','Mail Flow & DNS'), @('tls','Transport Security'),
        @('access','Access & Authentication'), @('threat','Threat Protection'), @('resources','Server Resources'),
        @('os_update','OS & Patching'), @('monitoring','Monitoring & Watchdog'), @('database','Database Platform')
    )
    foreach($item in $summary){
        $res=Pdf-Raw ("health.{0}.result" -f $item[0])
        if([string]::IsNullOrEmpty($res) -or $res -eq 'skip'){ continue }
        $bkind=Pdf-HealthBadge $res
        if(-not $bkind){ $bkind='INFO' }
        Pdf-Row $item[1] "" $bkind $bkind (Pdf-Raw ("health.{0}.message" -f $item[0]))
    }
}

function Render-CollectorStatus([object[]]$Results){
    Pdf-SectionHeader "Collector Status"
    if($null -eq $Results){
        Pdf-PlainLine "Collector status not available"
        return
    }
    $issues=@($Results | Where-Object { $null -ne $_ -and [string]$_.Status -ne 'ok' })
    if($issues.Count -eq 0){
        Pdf-PlainLine "All collectors ran OK"
        return
    }
    foreach($issue in $issues){
        Pdf-PlainLine (Pdf-Trunc ("{0}: {1} - {2}" -f $issue.Name, $issue.Status, $issue.Message) 110)
    }
}

# --- Appendix ---------------------------------------------------------------------

$script:PDF_APPENDIX_GROUPS=@(
    [pscustomobject]@{ Title='Agent & General'; Prefixes=@('agent.','general.') },
    [pscustomobject]@{ Title='DNS & Mail Flow'; Prefixes=@('dns.') },
    [pscustomobject]@{ Title='IceWarp Server'; Prefixes=@('icewarp.') },
    [pscustomobject]@{ Title='SMTP & Delivery'; Prefixes=@('queue.','smtp.') },
    [pscustomobject]@{ Title='Security & Intrusion Prevention'; Prefixes=@('antispam.','security.') },
    [pscustomobject]@{ Title='Backup & Archive'; Prefixes=@('archive.','backup.') },
    [pscustomobject]@{ Title='Watchdog & Monitoring'; Prefixes=@('monitor.','watchdog.') },
    [pscustomobject]@{ Title='OS, Storage & Resources'; Prefixes=@('os.','storage.','system.') },
    [pscustomobject]@{ Title='Database'; Prefixes=@('database.','mysql.') },
    [pscustomobject]@{ Title='Services, Logging & Admin'; Prefixes=@('admin.','directory_cache.','fulltext.','logging.') },
    [pscustomobject]@{ Title='Domains'; Prefixes=@('domain.') },
    [pscustomobject]@{ Title='HTTP / API'; Prefixes=@('http.') },
    [pscustomobject]@{ Title='Health Evaluation'; Prefixes=@('health.') },
    [pscustomobject]@{ Title='Other'; Prefixes=@() }
)

# Group header ($top = top edge): light title bar with accent, then the
# navy KEY / VALUE band. Leaves the cursor at the first row's top edge.
function Pdf-AppendixHeader([float]$top,[string]$title){
    Pdf-Rect $script:PDF_MARGIN ($top-16) $script:PDF_CONTENT_W 16 $script:PDF_C_GROUP_BG
    Pdf-Rect $script:PDF_MARGIN ($top-16) 3 16 $script:PDF_C_BLUEGRAY
    Pdf-Text ($script:PDF_MARGIN+7) ($top-11) $title F2 8.5 $script:PDF_C_NAVY
    Pdf-Rect $script:PDF_MARGIN ($top-33) $script:PDF_CONTENT_W 14 $script:PDF_C_NAVY
    Pdf-Text ($script:PDF_MARGIN+5) ($top-29) 'KEY' F2 6.8 $script:PDF_C_WHITE
    Pdf-Text ($script:PDF_MARGIN+225) ($top-29) 'VALUE' F2 6.8 $script:PDF_C_WHITE
    $script:_PDF_Y=$top-30
    $script:_PDF_ROW_INDEX=0
}
function Pdf-AppendixRow([string]$key,[string]$value){
    $y=$script:_PDF_Y
    $bg=$script:PDF_C_WHITE
    if(($script:_PDF_ROW_INDEX % 2) -eq 1){ $bg=$script:PDF_C_GRAY_LIGHT }
    $script:_PDF_ROW_INDEX++
    Pdf-Rect $script:PDF_MARGIN ($y-14) $script:PDF_CONTENT_W 14 $bg
    Pdf-Text ($script:PDF_MARGIN+5) ($y-10) (Pdf-Trunc $key 54) F1 7.2 $script:PDF_C_TEXT
    Pdf-Text ($script:PDF_MARGIN+225) ($y-10) (Pdf-Trunc $value 82) F1 7.2 $script:PDF_C_VALUE
    $script:_PDF_Y=$y-14
}
# Linux sorts the appendix with locale collation, which ignores punctuation
# (e.g. stat_started before stat_start_raw). Compare on letters and digits.
function Pdf-SortKeys([string[]]$keys){
    return @($keys | Sort-Object -Property @{ Expression = { ($_ -replace '[^A-Za-z0-9]', '').ToLowerInvariant() } }, @{ Expression = { $_ } })
}
function Build-TechnicalAppendix([hashtable]$Data){
    $script:DATA=$Data
    [string[]]$allKeys=@($Data.Keys | ForEach-Object { [string]$_ })
    Pdf-SectionHeader ("Appendix: Technical Data ({0} keys)" -f $allKeys.Count)
    Pdf-PlainLine "Grouped by subsystem and sorted alphabetically. Raw keys are preserved for traceability."
    Pdf-PlainLine "Long values are truncated in this appendix; the JSON export contains the complete values."

    $groups=[ordered]@{}
    foreach($g in $script:PDF_APPENDIX_GROUPS){ $groups[$g.Title]=[System.Collections.Generic.List[string]]::new() }
    $groups['Other']=[System.Collections.Generic.List[string]]::new()
    foreach($key in $allKeys){
        # Linux appendix: health.* keys go to Health Evaluation group
        # Allow all other keys to be categorized; "Other" group catches the rest
        $target='Other'
        foreach($g in $script:PDF_APPENDIX_GROUPS){
            foreach($prefix in $g.Prefixes){ if($key.StartsWith($prefix)){ $target=$g.Title; break } }
            if($target -ne 'Other'){ break }
        }
        $groups[$target].Add($key)
    }

    $freshPage=$true
    foreach($title in $groups.Keys){
        $keys=$groups[$title]
        if($keys.Count -eq 0){ continue }
        $top=if($freshPage){ $script:_PDF_Y - 8 } else { $script:_PDF_Y - 17 }
        if(($top - 44) -lt $script:PDF_BOTTOM_Y){ Pdf-NewPage; $top=$script:_PDF_Y - 8 }
        Pdf-AppendixHeader $top ("{0}  ({1} keys)" -f $title, $keys.Count)
        $freshPage=$false
        foreach($key in (Pdf-SortKeys $keys.ToArray())){
            if(($script:_PDF_Y - 14) -lt $script:PDF_BOTTOM_Y){
                Pdf-NewPage
                Pdf-AppendixHeader ($script:_PDF_Y - 8) $title
            }
            # Linux appendix: for storage.root_home.* on same device as root_fs, show "null"
            $val=Pdf-Raw $key
            if($key -like 'storage.root_home.*'){
                $rootVal=Pdf-Raw $key.Replace('root_home','root_fs')
                if($val -eq $rootVal -or [string]::IsNullOrEmpty($val)){
                    $val='null'
                }
            }
            Pdf-AppendixRow $key $val
        }
    }
}

# --- Writer -----------------------------------------------------------------------

function Pdf-Footer([int]$page,[int]$total){
    $nl=$script:_NL
    return ("{0} RG{1}0.5 w{1}36 34 m 576 34 l S{1}{2} rg{1}BT /F1 6.5 Tf 36 24 Td (IceWarp Health Check Report) Tj ET{1}BT /F1 6.5 Tf 536 24 Td (Page {3} of {4}) Tj ET{1}" -f $script:PDF_C_RULE, $nl, $script:PDF_C_GRAY, $page, $total)
}
function Pdf-WriteFile([string]$OutPath){
    $P=$script:_PDF_PAGES.Count
    if($P -eq 0){ Write-Warning "build_pdf: nothing to render"; return $null }
    $F_REG=2+2*$P+1; $F_BOLD=2+2*$P+2; $F_OBL=2+2*$P+3
    $nl=$script:_NL
    $offsets=@{}
    $sb=[System.Text.StringBuilder]::new()
    [void]$sb.Append("%PDF-1.4$nl")
    $offsets[1]=$sb.Length
    [void]$sb.Append("1 0 obj$($nl)<< /Type /Catalog /Pages 2 0 R >>$($nl)endobj$($nl)")
    $kids=""
    for($i=1;$i -le $P;$i++){ $kids+="$(2+$i) 0 R " }
    $offsets[2]=$sb.Length
    [void]$sb.Append("2 0 obj$($nl)<< /Type /Pages /Kids [ ${kids}] /Count ${P} >>$($nl)endobj$($nl)")
    for($i=1;$i -le $P;$i++){
        $pageNum=$i+2; $contentNum=$i+2+$P
        $offsets[$pageNum]=$sb.Length
        [void]$sb.Append("${pageNum} 0 obj$($nl)<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 ${F_REG} 0 R /F2 ${F_BOLD} 0 R /F3 ${F_OBL} 0 R >> >> /MediaBox [0 0 $($script:PDF_PAGE_W) $($script:PDF_PAGE_H)] /Contents ${contentNum} 0 R >>$($nl)endobj$($nl)")
        $stream=$script:_PDF_PAGES[$i-1]
        # Every page after the cover carries the Linux-style footer.
        if($i -gt 1){ $stream += (Pdf-Footer $i $P) }
        $offsets[$contentNum]=$sb.Length
        [void]$sb.Append("${contentNum} 0 obj$($nl)<< /Length $($stream.Length) >>$($nl)stream$($nl)${stream}endstream$($nl)endobj$($nl)")
    }
    $offsets[$F_REG]=$sb.Length
    [void]$sb.Append("${F_REG} 0 obj$($nl)<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>$($nl)endobj$($nl)")
    $offsets[$F_BOLD]=$sb.Length
    [void]$sb.Append("${F_BOLD} 0 obj$($nl)<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>$($nl)endobj$($nl)")
    $offsets[$F_OBL]=$sb.Length
    [void]$sb.Append("${F_OBL} 0 obj$($nl)<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique >>$($nl)endobj$($nl)")
    $total=$F_OBL+1
    $xrefStart=$sb.Length
    [void]$sb.Append("xref$($nl)0 ${total}$($nl)")
    [void]$sb.Append("0000000000 65535 f $($nl)")
    for($n=1;$n -le $F_OBL;$n++){
        $off=[int]$offsets[$n]
        [void]$sb.Append(("{0:D10} 00000 n $($nl)" -f $off))
    }
    [void]$sb.Append("trailer$($nl)<< /Size ${total} /Root 1 0 R >>$($nl)startxref$($nl)${xrefStart}$($nl)%%EOF$($nl)")
    [System.IO.File]::WriteAllText($OutPath, $sb.ToString())
    return $OutPath
}

function Build-TechnicalReportPdf([hashtable]$Data,[string]$OutPath,[object[]]$CollectorResults){
    Build-TechnicalReport $Data $OutPath
    # As on Linux, the checklist starts on page 2 and the appendix on its own page.
    Pdf-NewPage
    Render-Checklist $Data
    Render-CollectorStatus $CollectorResults
    Pdf-NewPage
    Build-TechnicalAppendix $Data
    Pdf-Finish
    return (Pdf-WriteFile $OutPath)
}
