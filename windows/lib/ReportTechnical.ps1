<#
.SYNOPSIS
Technical PDF report writer (report.pdf) for the Windows IceWarp Health Agent.
.DESCRIPTION
Port of Linux lib/pdf.sh manual PDF drawing engine.
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
$script:PDF_CHECKLIST_VERSION = '1.14'

function Pdf-Escape([string]$s){
    $o=[System.Text.StringBuilder]::new()
    for($i=0;$i -lt $s.Length;$i++){
        $c=[int]$s[$i]
        if($c -ge 32 -and $c -le 126){
            if($c -eq 92){$o.Append('\')|Out-Null}
            if($c -eq 40){$o.Append('\')|Out-Null}
            if($c -eq 41){$o.Append('\')|Out-Null}
            $o.Append($s[$i])|Out-Null
        } else { $o.Append('?')|Out-Null }
    }
    return $o.ToString()
}
function Pdf-IsNum([string]$v){ return $v -match '^-?[0-9]+(\.[0-9]+)?$' }
function Pdf-Trunc([string]$t,[int]$max){
    if($t.Length -gt $max){$t=$t.Substring(0,$max-1)+'.'}
    return $t
}
function Pdf-DaysAgo([string]$d){
    if([string]::IsNullOrEmpty($d)){ return 999 }
    try{ $dt=[datetime]::Parse($d); return [int](([DateTime]::UtcNow - $dt).TotalDays) }
    catch { return 999 }
}

$script:_PDF_PAGES=[System.Collections.Generic.List[string]]::new()
$script:_PDF_CUR=""; $script:_PDF_Y=$script:PDF_TOP_Y
$script:_PDF_ROW_INDEX=0; $script:DATA=$null
$script:_NL = "`n"

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
    Pdf-Text $script:PDF_MARGIN $script:_PDF_Y $t F1 9 $script:PDF_C_TEXT
    $script:_PDF_Y = $script:_PDF_Y - 16
}
function Pdf-Row([string]$label,[string]$value,[string]$bkind,[string]$btext,[string]$note){
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
        Pdf-TextTrunc ($script:PDF_MARGIN+8) ($textY-11) $note F1 8 $script:PDF_C_GRAY 90
    }
    $script:_PDF_Y = $rowTop - $rowH
}
function Pdf-ClValue([string]$keys){
    if($keys.Contains(',')){
        $parts=@(); $ks=$keys.Split(',')
        foreach($k in $ks){
            $short=$k.Substring($k.LastIndexOf('.')+1)
            $parts+=("{0}={1}" -f $short, $script:DATA[$k])
        }
        return ($parts -join ', ')
    } else {
        $v=$script:DATA[$keys]
        if([string]::IsNullOrEmpty($v)){ $v='(empty)' }
        return $v
    }
}
function Pdf-IntrusionValidate([string]$key,[string]$value){
    $expected=""
    switch($key){
        'security.intrusion.block_connections_per_minute.value'{ $expected='50' }
        'security.intrusion.block_unknown_user_count.value'{ $expected='5' }
        'security.intrusion.block_relay_denied_count.value'{ $expected='5' }
        'security.intrusion.block_rset_count.value'{ $expected='5' }
        'security.intrusion.block_spam_score.value'{ $expected='9.00' }
        'security.intrusion.block_failed_logins.value'{ $expected='5' }
        'security.intrusion.block_duration_minutes'{ $expected='360' }
    }
    if([string]::IsNullOrEmpty($expected)){ return "WARN|WARN|${value}" }
    if([string]::IsNullOrEmpty($value)){ return "CRITICAL|CRITICAL|Setting not found" }
    if($value -eq $expected){ return "PASS|PASS|Expected: ${expected}" }
    return "WARN|WARN|Expected: ${expected} (current: ${value})"
}

function Pdf-AppendixCategory([string]$title){
    Pdf-Ensure 40
    $script:_PDF_Y = $script:_PDF_Y - 4
    Pdf-Rect $script:PDF_MARGIN ($script:_PDF_Y-14) $script:PDF_CONTENT_W 16 $script:PDF_C_BLUEGRAY
    Pdf-Text ($script:PDF_MARGIN+8) ($script:_PDF_Y-11) $title F2 9 $script:PDF_C_WHITE
    $script:_PDF_Y = $script:_PDF_Y - 22
}

function Build-TechnicalReport([hashtable]$Data,[string]$OutPath){
    $script:DATA=$Data
    $script:_PDF_PAGES=[System.Collections.Generic.List[string]]::new()
    $script:_PDF_CUR=""; $script:_PDF_Y=$script:PDF_TOP_Y; $script:_PDF_ROW_INDEX=0
    $agentHost=$Data['agent.hostname']; if(-not $agentHost){$agentHost='unknown'}
    $agentTime=$Data['agent.time']; if(-not $agentTime){$agentTime='unknown'}
    $agentVer=$Data['agent.version']; if(-not $agentVer){$agentVer='unknown'}
    $overallStatus=$Data['health.summary.overall']; if(-not $overallStatus){$overallStatus='n/a'}
    $failCount=$Data['health.summary.failed']; if(-not $failCount){$failCount='0'}
    $warnCount=$Data['health.summary.warnings']; if(-not $warnCount){$warnCount='0'}
    $totalChecks=$Data['health.summary.total_checks']; if(-not $totalChecks){$totalChecks='0'}
    Pdf-Rect 0 692 $script:PDF_PAGE_W 100 $script:PDF_C_NAVY
    Pdf-Text $script:PDF_MARGIN 754 "IceWarp Health Check Report" F2 22 $script:PDF_C_WHITE
    Pdf-Text $script:PDF_MARGIN 730 ("Based on IceWarp CheckList v{0}" -f $script:PDF_CHECKLIST_VERSION) F3 12 $script:PDF_C_WHITE
    Pdf-Text $script:PDF_MARGIN 706 ("Host: {0}   Generated: {1}   Agent v{2}" -f $agentHost $agentTime $agentVer) F1 9.5 $script:PDF_C_WHITE
    $script:_PDF_Y=660
    $licType=$Data['icewarp.license.type']; if(-not $licType){$licType='unknown'}
    $licExp=$Data['icewarp.license.trial_expiration']
    if($licExp){ $licDisplay=$licExp }
    elseif($licType -eq 'Evaluation'){ $licDisplay='Evaluation (expiration not detected)' }
    else { $licDisplay='N/A (perpetual license)' }
    $infoRows=@(
        "Company Name|$($Data['general.company'])",
        "Mail Domain|$($Data['domain.primary.name'])",
        "Technician|$($Data['general.technician'])",
        "IceWarp Version|$($Data['icewarp.version'])",
        "Antispam Last Update|$($Data['icewarp.antispam.last_update'])",
        "Antivirus Last Update|$($Data['icewarp.antivirus.last_update'])",
        "Last Backup Date/Time|$($Data['icewarp.backup.last_time'])",
        "License Type|$licType",
        "License Expiration|$licDisplay",
        "SSL Expiration|$($Data['icewarp.ssl.expiration'])"
    )
    foreach($row in $infoRows){
        $lbl,$val=$row.Split('|',2)
        Pdf-Text ($script:PDF_MARGIN+8) $script:_PDF_Y "${lbl}:" F2 9.5 $script:PDF_C_TEXT
        Pdf-TextTrunc ($script:PDF_MARGIN+190) $script:_PDF_Y $val F1 9.5 $script:PDF_C_GRAY 55
        $script:_PDF_Y = $script:_PDF_Y - 16
    }
    $script:_PDF_Y = $script:_PDF_Y - 14
    $bannerColor=$script:PDF_C_GRAY
    switch($overallStatus){ 'pass'{$bannerColor=$script:PDF_C_GREEN} 'warn'{$bannerColor=$script:PDF_C_AMBER} 'fail'{$bannerColor=$script:PDF_C_RED} }
    Pdf-Rect $script:PDF_MARGIN ($script:_PDF_Y-44) $script:PDF_CONTENT_W 44 $bannerColor
    Pdf-Text ($script:PDF_MARGIN+14) ($script:_PDF_Y-20) ("OVERALL: $($overallStatus.ToUpper())") F2 15 $script:PDF_C_WHITE
    Pdf-Text ($script:PDF_MARGIN+14) ($script:_PDF_Y-36) ("{0} checks run  -  {1} failed  -  {2} warnings" -f $totalChecks $failCount $warnCount) F1 9.5 $script:PDF_C_WHITE
    $script:_PDF_Y = $script:_PDF_Y - 60
    Pdf-Text $script:PDF_MARGIN $script:_PDF_Y "Legend:" F2 8.5 $script:PDF_C_TEXT
    $lx=$script:PDF_MARGIN+46
    @('PASS:Green','CRITICAL:Red','WARN:Orange','INFO:Purple') | ForEach-Object {
        $status,$col=$_.Split(':')
        $bc=switch($status){ 'PASS'{$script:PDF_C_GREEN} 'CRITICAL'{$script:PDF_C_RED} 'WARN'{$script:PDF_C_AMBER} 'INFO'{$script:PDF_C_BLUEGRAY} }
        Pdf-Rect $lx ($script:_PDF_Y-3) 26 11 $bc
        Pdf-Text ($lx+30) $script:_PDF_Y $status F1 8 $script:PDF_C_TEXT
        $lx=$lx+30+6*$status.Length+14
    }
    $script:_PDF_Y = $script:_PDF_Y - 20
    Pdf-SectionHeader "Health Summary"
    $script:_PDF_ROW_INDEX=0
    Pdf-PlainLine "Nine executive control areas. Detailed evidence follows in the checklist."
    $summary=@(
        "backup|Backup & Recovery","mail_flow|Mail Flow & DNS","tls|Transport Security",
        "access|Access & Authentication","threat|Threat Protection","resources|Server Resources",
        "os_update|OS & Patching","monitoring|Monitoring & Watchdog","database|Database Platform"
    )
    foreach($item in $summary){
        $key,$title=$item.Split('|')
        $res=$Data["health.$key.result"]
        if([string]::IsNullOrEmpty($res)){ $res='skip' }
        if($res -eq 'skip'){ continue }
        $bkind=switch($res){ 'pass'{'PASS'} 'warn'{'WARN'} 'fail'{'CRITICAL'} 'critical'{'CRITICAL'} default{'INFO'} }
        $msg=$Data["health.$key.message"]
        Pdf-Row $title "" $bkind $bkind $msg
    }
}

function Render-Checklist([hashtable]$Data){
    $script:DATA=$Data
    $script:_PDF_ROW_INDEX=0
    $checklistFile=[System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".." "config" "checklist.conf.pdf"))
    if(-not (Test-Path $checklistFile)){
        Pdf-PlainLine "Checklist file not found: $checklistFile"
        return
    }
    $curSection=""
    $lines=[System.IO.File]::ReadAllLines($checklistFile)
    foreach($rawLine in $lines){
        $line=$rawLine.Trim()
        if([string]::IsNullOrEmpty($line)){ continue }
        $parts=$line.Split('~')
        if($parts.Length -lt 4){ continue }
        $section=$parts[0]; $label=$parts[1]; $kind=$parts[2]; $keys=$parts[3]
        $note=if($parts.Length -gt 4){$parts[4]}else{""}
        if($section -ne $curSection){
            Pdf-SectionHeader $section
            $curSection=$section
            $script:_PDF_ROW_INDEX=0
        }
        if($section -like "MySQL Server*"){
            if($Data['database.scope'] -ne 'remote'){
                Pdf-Row $label "not applicable" "INFO" "INFO" "not applicable - SQLite or local MySQL"
                continue
            }
        }
        if($section -eq 'Database' -and $label -like 'MySQL*'){
            if($Data['mysql.applicable'] -ne 'true'){
                Pdf-Row $label "not applicable" "INFO" "INFO" "MySQL not applicable on this host"
                continue
            }
        }
        if($label -eq 'Enable Database Backup'){
            $raw=$Data['icewarp.database_backup.enabled']
            if($raw -eq '1'){ Pdf-Row $label "Enabled" "PASS" "PASS" $note }
            else { Pdf-Row $label "Disabled" "CRITICAL" "CRITICAL" $note }
            continue
        }
        if($label -eq 'Enable System Backup'){
            $raw=$Data['icewarp.backup.auto_enabled']
            if($raw -eq '1'){ Pdf-Row $label "Enabled" "PASS" "PASS" $note }
            else { Pdf-Row $label "Disabled" "CRITICAL" "CRITICAL" $note }
            continue
        }
        if($label -eq 'Maximum Number of Simultaneous Threads'){
            $raw=$Data['smtp.incoming_queue_threads']
            if([string]::IsNullOrEmpty($raw)){ Pdf-Row $label "" "CRITICAL" "CRITICAL" "Setting not found" }
            elseif($raw -eq '10'){ Pdf-Row $label $raw "PASS" "PASS" "Expected: 10 (OK)" }
            else { Pdf-Row $label $raw "WARN" "WARN" "Expected: 10 (current: $raw)" }
            continue
        }
        if($label -eq 'Set Directory Cache Schedule'){
            $raw=$Data['directory_cache.scheduled']
            if($raw -eq '1' -or $raw -eq 'true'){ Pdf-Row $label $raw "PASS" "PASS" "Schedule is configured" }
            else { Pdf-Row $label $raw "CRITICAL" "CRITICAL" "Schedule is NOT configured" }
            continue
        }
        if($label -eq 'Enable System Watchdog'){
            $ctrl=$Data['watchdog.control']
            if($ctrl -eq '1'){ Pdf-Row $label "Enabled" "PASS" "PASS" $note }
            else { Pdf-Row $label "Disabled" "CRITICAL" "CRITICAL" $note }
            continue
        }
        if($label -eq 'Watchdog - SMTP'){
            $val=$Data['watchdog.smtp']
            if($val -eq '1'){ Pdf-Row $label "Enabled" "PASS" "PASS" $note }
            else { Pdf-Row $label "Disabled" "CRITICAL" "CRITICAL" $note }
            continue
        }
        if($label -eq 'Watchdog - POP3/IMAP'){
            $val=$Data['watchdog.pop3']
            if($val -eq '1'){ Pdf-Row $label "Enabled" "PASS" "PASS" $note }
            else { Pdf-Row $label "Disabled" "CRITICAL" "CRITICAL" $note }
            continue
        }
        if($label -eq 'Watchdog - IM/VoIP'){
            $val=$Data['watchdog.im']
            if($val -eq '1'){ Pdf-Row $label "Enabled" "PASS" "PASS" $note }
            else { Pdf-Row $label "Disabled" "CRITICAL" "CRITICAL" $note }
            continue
        }
        if($label -eq 'Watchdog - GroupWare'){
            $val=$Data['watchdog.gw']
            if($val -eq '1'){ Pdf-Row $label "Enabled" "PASS" "PASS" $note }
            else { Pdf-Row $label "Disabled" "CRITICAL" "CRITICAL" $note }
            continue
        }
        if($label -eq 'Watchdog Interval'){
            $interval=$Data['watchdog.interval_minutes']
            if([string]::IsNullOrEmpty($interval)){$interval=0}
            if($interval -eq 0){ Pdf-Row $label "Every minute (0)" "PASS" "PASS" "Every minute (0) - optimal" }
            elseif($interval -ge 1 -and $interval -le 60){ Pdf-Row $label "${interval} minutes" "PASS" "PASS" "${interval} minutes (optimal)" }
            elseif($interval -gt 60 -and $interval -le 1440){ Pdf-Row $label "${interval} minutes" "WARN" "WARN" "Interval is long" }
            else { Pdf-Row $label "${interval} minutes" "CRITICAL" "CRITICAL" "Interval is too long" }
            continue
        }
        if($label -eq 'Integrate Archive with IMAP Folder'){
            $raw=$Data['archive.integrate_with_imap']
            if($raw -eq '1'){ Pdf-Row $label "Enabled" "PASS" "PASS" $note }
            else { Pdf-Row $label "Disabled" "CRITICAL" "CRITICAL" $note }
            continue
        }
        if($label -eq 'Number of Used Seats / License Max Users'){
            $raw=$Data['icewarp.license.used_seats_note']
            if([string]::IsNullOrEmpty($raw) -or $raw -like '*not available*'){
                Pdf-Row $label "unavailable" "WARN" "WARN" "Unable to retrieve license usage - check via Admin API"
            } else { Pdf-Row $label $raw "INFO" "INFO" $note }
            continue
        }
        if($label -eq 'Enable Daytime Clock Synchronization'){
            $raw=$Data['icewarp.daytime_clock_sync.enabled']
            if($raw -eq '1'){ Pdf-Row $label "Enabled" "PASS" "PASS" $note }
            elseif($raw -eq '0'){ Pdf-Row $label "Disabled" "CRITICAL" "CRITICAL" $note }
            else { Pdf-Row $label "Unknown" "WARN" "WARN" "Daytime sync setting not detected" }
            continue
        }
        if($kind -eq 'V' -and $label -eq 'Disk (Total GB / Used %)'){
            $usedPercent=$Data['storage.root_fs.used_percent']
            if([string]::IsNullOrEmpty($usedPercent)){$usedPercent=0}
            $status="INFO"
            if(Pdf-IsNum $usedPercent){
                if($usedPercent -ge 95){$status="CRITICAL"}
                elseif($usedPercent -ge 80){$status="WARN"}
                else {$status="PASS"}
            }
            Pdf-Row $label $Data['storage.root_fs.total_gb'] $status $status "Disk usage: ${usedPercent}%"
            continue
        }
        if($kind -eq 'V' -and $label -eq 'CPU Usage'){
            $load15=$Data['os.cpu.load15']; if([string]::IsNullOrEmpty($load15)){$load15=0}
            $cores=$Data['os.cpu.count']; if([string]::IsNullOrEmpty($cores)){$cores=1}
            $cpuPercent=0; $status="INFO"
            if(Pdf-IsNum $load15 -and Pdf-IsNum $cores -and $cores -gt 0){
                $cpuPercent=[math]::Round(($load15/$cores)*100,2)
                if($cpuPercent -gt 95){$status="CRITICAL"}
                elseif($cpuPercent -gt 50){$status="WARN"}
                else {$status="PASS"}
            }
            Pdf-Row $label $load15 $status $status "CPU load is ${cpuPercent}%"
            continue
        }
        if($kind -eq 'V' -and $label -eq 'RAM (Total KB / Available KB)'){
            $totalKb=$Data['os.memory.total_kb']; if([string]::IsNullOrEmpty($totalKb)){$totalKb=0}
            $availKb=$Data['os.memory.available_kb']; if([string]::IsNullOrEmpty($availKb)){$availKb=0}
            $value="Total(KB)=${totalKb} / Available KB=${availKb}"
            $bkind="PASS"; $btext="PASS"; $msg=""
            if(Pdf-IsNum $totalKb -and Pdf-IsNum $availKb -and $totalKb -gt 0){
                $usedPercent=[math]::Round((($totalKb-$availKb)/$totalKb)*100,2)
                if($usedPercent -gt 90){$bkind="CRITICAL";$btext="CRITICAL";$msg="RAM usage ${usedPercent}% (CRITICAL - above 90%)"}
                elseif($usedPercent -gt 40){$bkind="WARN";$btext="WARN";$msg="RAM usage ${usedPercent}% (WARN - above 40%)"}
                else {$msg="RAM usage ${usedPercent}% (OK)"}
            } else { $msg="Unable to calculate RAM usage" }
            Pdf-Row $label $value $bkind $btext $msg
            continue
        }
        if($kind -eq 'V' -and $label -eq 'APP OS Last Update'){
            $lastUpdate=$Data['os.last_update_date']
            $value=$lastUpdate; if([string]::IsNullOrEmpty($value)){$value='unknown'}
            $bkind="INFO"; $btext="INFO"; $msg=""
            if(-not [string]::IsNullOrEmpty($lastUpdate) -and $lastUpdate -ne 'N/A' -and $lastUpdate -ne 'null'){
                $days=Pdf-DaysAgo $lastUpdate
                if($days -le 7){$bkind="PASS";$btext="PASS";$msg="OS updated recently (${days} days ago)"}
                elseif($days -le 30){$bkind="WARN";$btext="WARN";$msg="OS update is ${days} days old (consider updating)"}
                else {$bkind="CRITICAL";$btext="CRITICAL";$msg="OS is outdated (${days} days since last update)"}
            } else { $msg="OS last update date not available" }
            Pdf-Row $label $value $bkind $btext $msg
            continue
        }
        if($kind -eq 'V' -and $label -eq 'Swap Usage (7 days)'){
            $status=$Data['system.swap.status']; if([string]::IsNullOrEmpty($status)){$status='INFO'}
            $msg=$Data['system.swap.message']
            $bkind="INFO"; $btext="INFO"
            switch($status){ 'PASS'{$bkind="PASS";$btext="PASS"} 'CRITICAL'{$bkind="CRITICAL";$btext="CRITICAL"} }
            $usedPercent=$Data['system.swap.used_percent']; if([string]::IsNullOrEmpty($usedPercent)){$usedPercent=0}
            Pdf-Row $label "${usedPercent}%" $bkind $btext $msg
            continue
        }
        if($kind -eq 'V' -and $label -eq 'Database Scope'){
            $scope=$Data['database.scope']; if([string]::IsNullOrEmpty($scope)){$scope='unknown'}
            Pdf-Row $label $scope "PASS" "PASS" "Database scope: ${scope}"
            continue
        }
        if($kind -eq 'V' -and ($keys -like 'security.intrusion.*.value*' -or $keys -eq 'security.intrusion.block_duration_minutes')){
            $raw=$Data[$keys]
            $r=Pdf-IntrusionValidate $keys $raw
            $bkind,$btext,$note2=$r.Split('|')
            Pdf-Row $label $raw $bkind $btext $note2
            continue
        }
        if($kind -eq 'V'){
            $val=Pdf-ClValue $keys
            Pdf-Row $label $val "INFO" "INFO" $note
            continue
        }
        $raw=$Data[$keys]
        if([string]::IsNullOrEmpty($raw)){$raw=""}
        if($kind -eq 'T'){
            $expected=$note
            if($raw -eq $expected){ Pdf-Row $label $raw "PASS" "PASS" "Expected: $expected" }
            else { Pdf-Row $label $raw "WARN" "WARN" "Expected: $expected (current: $raw)" }
            continue
        }
        switch($kind){
            'F'{
                if($raw -eq '1' -or $raw -eq 'true'){ Pdf-Row $label "Found" "PASS" "PASS" $note }
                elseif($raw -eq '0' -or $raw -eq 'false'){ Pdf-Row $label "Missing" "CRITICAL" "CRITICAL" $note }
                else { Pdf-Row $label "N/A" "INFO" "INFO" $note }
            }
            'B'{
                if($raw -eq '1' -or $raw -eq 'true'){ Pdf-Row $label "Enabled" "PASS" "PASS" $note }
                else { Pdf-Row $label "Disabled" "CRITICAL" "CRITICAL" $note }
            }
            'R'{
                if($raw -eq '0' -or $raw -eq 'false'){ Pdf-Row $label "No" "PASS" "PASS" $note }
                elseif($raw -eq '1' -or $raw -eq 'true'){ Pdf-Row $label "Yes" "CRITICAL" "CRITICAL" $note }
                else { Pdf-Row $label "N/A" "INFO" "INFO" $note }
            }
            'L'{
                if(-not [string]::IsNullOrEmpty($raw) -and $raw -ne '0'){ Pdf-Row $label "Enabled (level $raw)" "PASS" "PASS" $note }
                elseif($raw -eq '0'){ Pdf-Row $label "Disabled" "CRITICAL" "CRITICAL" $note }
                else { Pdf-Row $label "N/A" "INFO" "INFO" $note }
            }
            'Z'{
                if($raw -eq '0'){ Pdf-Row $label "Disabled" "WARN" "WARN" "Backup emails is disabled (WARN)" }
                elseif(-not [string]::IsNullOrEmpty($raw)){ Pdf-Row $label $raw "INFO" "INFO" $note }
                else { Pdf-Row $label "not collected" "INFO" "INFO" $note }
            }
            'M'{
                if($raw -eq '1' -or $raw -eq 'true'){ Pdf-Row $label "Yes" "WARN" "WARN" $note }
                else { Pdf-Row $label "No" "PASS" "PASS" $note }
            }
            'G'{
                if($raw -eq '1' -or $raw -eq 'true'){ Pdf-Row $label "Yes" "PASS" "PASS" $note }
                else { Pdf-Row $label "No" "CRITICAL" "CRITICAL" $note }
            }
            'P'{
                if($raw -eq '1' -or $raw -eq 'true'){ Pdf-Row $label "Active" "CRITICAL" "CRITICAL" $note }
                else { Pdf-Row $label "Off" "PASS" "PASS" $note }
            }
            'W'{ Pdf-Row $label $raw "INFO" "INFO" $note }
            'D'{
                if($raw -eq '0' -or $raw -eq 'false'){ Pdf-Row $label "Disabled" "PASS" "PASS" $note }
                elseif($raw -eq '1' -or $raw -eq 'true'){ Pdf-Row $label "Enabled" "WARN" "WARN" $note }
                else { Pdf-Row $label "N/A" "INFO" "INFO" $note }
            }
            'H'{
                $worst='pass'; $msgs=@()
                $hk=$keys.Split(',')
                foreach($k in $hk){
                    $result=$Data["health.$k.result"]
                    if(-not [string]::IsNullOrEmpty($result)){
                        if($result -eq 'fail'){ $worst='fail' }
                        elseif($result -eq 'warn' -and $worst -ne 'fail'){ $worst='warn' }
                    }
                    $m=$Data["health.$k.message"]
                    if(-not [string]::IsNullOrEmpty($m)){ $msgs+=$m }
                }
                $bkind='INFO'
                switch($worst){ 'pass'{$bkind='PASS'} 'warn'{$bkind='WARN'} 'fail'{$bkind='CRITICAL'} }
                $joinedMsg=($msgs -join '; ')
                if([string]::IsNullOrEmpty($joinedMsg)){ $joinedMsg=$note }
                Pdf-Row $label "" $bkind $bkind $joinedMsg
            }
            default{
                if(-not [string]::IsNullOrEmpty($raw)){ Pdf-Row $label $raw "INFO" "INFO" $note }
                else { Pdf-Row $label "N/A" "INFO" "INFO" $note }
            }
        }
    }
}

function Build-TechnicalAppendix([hashtable]$Data){
    Pdf-SectionHeader "Appendix: Collected Data"
    $script:_PDF_ROW_INDEX=0
    $keys=@($Data.Keys) | Sort-Object
    $categories=@{
        'agent.'='Agent'; 'general.'='General'; 'domain.'='Domain'
        'icewarp.'='IceWarp'; 'dns.'='DNS'; 'smtp.'='SMTP'
        'security.'='Security'; 'watchdog.'='Watchdog'; 'monitor.'='Monitor'
        'os.'='OS'; 'storage.'='Storage'; 'service.'='Service'
        'database.'='Database'; 'backup.'='Backup'; 'archive.'='Archive'
        'directory_cache.'='Directory Cache'; 'admin.'='Admin'
        'health.'='Health'; 'mysql.'='MySQL'; 'system.'='System'
        'fulltext.'='Full Text'; 'logging.'='Logging'; 'other.'='Other'
    }
    $groups=@{}
    foreach($k in $keys){
        $cat='other.'
        foreach($prefix in $categories.Keys){
            if($k -like "${prefix}*"){ $cat=$prefix; break }
        }
        if(-not $groups.ContainsKey($cat)){ $groups[$cat]=@() }
        $groups[$cat]+=$k
    }
    foreach($cat in $categories.Keys){
        if(-not $groups.ContainsKey($cat)){ continue }
        Pdf-AppendixCategory $categories[$cat]
        foreach($k in $groups[$cat]){
            $v=$Data[$k]
            if([string]::IsNullOrEmpty($v)){ $v='(empty)' }
            Pdf-Row $k $v "INFO" "INFO" ""
        }
    }
}

function Pdf-WriteFile([string]$OutPath){
    $P=$script:_PDF_PAGES.Count
    if($P -eq 0){ Write-Warning "build_pdf: nothing to render"; return $null }
    $F_REG=2+2*$P+1; $F_BOLD=2+2*$P+2; $F_OBL=2+2*$P+3
    $offsets=@{}
    $sb=[System.Text.StringBuilder]::new()
    [void]$sb.Append("%PDF-1.4`n")
    $sb.Append("1 0 obj`n<< /Type /Catalog /Pages 2 0 R >>`nendobj`n")|Out-Null
    $offsets[1]=0
    $kids=""
    for($i=1;$i -le $P;$i++){ $kids+="$((2+i)) 0 R " }
    $sb.Append("2 0 obj`n<< /Type /Pages /Kids [ ${kids}] /Count ${P} >>`nendobj`n")|Out-Null
    $offsets[2]=0
    for($i=1;$i -le $P;$i++){
        $pageNum=$i+2; $contentNum=$i+2+$P
        $sb.Append("${pageNum} 0 obj`n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $($script:PDF_PAGE_W) $($script:PDF_PAGE_H)] /Resources << /Font << /F1 ${F_REG} 0 R /F2 ${F_BOLD} 0 R /F3 ${F_OBL} 0 R >> >> /Contents ${contentNum} 0 R >>`nendobj`n")|Out-Null
        $stream=$script:_PDF_PAGES[$i-1]
        $sb.Append("${contentNum} 0 obj`n<< /Length $($stream.Length) >>`nstream`n${stream}endstream`nendobj`n")|Out-Null
    }
    $sb.Append("${F_REG} 0 obj`n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>`nendobj`n")|Out-Null
    $sb.Append("${F_BOLD} 0 obj`n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>`nendobj`n")|Out-Null
    $sb.Append("${F_OBL} 0 obj`n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique >>`nendobj`n")|Out-Null
    $total=$F_OBL+1
    $xrefStart=$sb.Length
    $sb.Append("xref`n0 ${total}`n")|Out-Null
    $sb.Append("0000000000 65535 f `n")|Out-Null
    for($n=1;$n -le $F_OBL;$n++){
        $sb.Append(sprintf "%010d 00000 n `n" $offsets[$n])|Out-Null
    }
    $sb.Append("trailer`n<< /Size ${total} /Root 1 0 R >>`nstartxref`n${xrefStart}`n%%EOF`n")|Out-Null
    [System.IO.File]::WriteAllText($OutPath, $sb.ToString())
    return $OutPath
}

function Build-TechnicalReportPdf([hashtable]$Data,[string]$OutPath){
    Build-TechnicalReport $Data $OutPath
    Render-Checklist $Data
    Build-TechnicalAppendix $Data
    Pdf-Finish
    return (Pdf-WriteFile $OutPath)
}