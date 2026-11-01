<#
.SYNOPSIS
Executive (management) PDF report writer (management_report.pdf).
.DESCRIPTION
Port of Linux lib/management_report.sh manual PDF drawing engine.
#>
Set-StrictMode -Version 2.0

$script:MR_PAGE_W = 612; $script:MR_PAGE_H = 792
$script:MR_MARGIN = 44; $script:MR_TOP_Y = 744; $script:MR_BOTTOM_Y = 52
$script:MR_RIGHT = $script:MR_PAGE_W - $script:MR_MARGIN
$script:MR_CONTENT_W = $script:MR_RIGHT - $script:MR_MARGIN
$script:MR_CHECKLIST_VERSION = '1.14'
$script:MR_C_INK='0.060 0.075 0.105'; $script:MR_C_SURFACE='0.090 0.110 0.150'
$script:MR_C_CARD='0.120 0.160 0.230'; $script:MR_C_INK_2='0.150 0.200 0.280'
$script:MR_C_BORDER='0.220 0.260 0.330'; $script:MR_C_GRID='0.130 0.170 0.240'
$script:MR_C_TEAL='0.000 0.620 0.580'; $script:MR_C_TEAL_LIGHT='0.400 0.780 0.740'
$script:MR_C_TEAL_DARK='0.000 0.420 0.400'; $script:MR_C_WHITE='1 1 1'
$script:MR_C_TEXT='0.92 0.93 0.95'; $script:MR_C_MUTED='0.55 0.58 0.62'
$script:MR_C_GREEN='0.118 0.518 0.286'; $script:MR_C_GREEN_DARK='0.060 0.300 0.170'
$script:MR_C_AMBER='0.83 0.53 0.06'; $script:MR_C_ROSE='0.753 0.224 0.169'
$script:MR_C_ROSE_DARK='0.450 0.130 0.100'; $script:MR_C_VIOLET='0.45 0.35 0.60'
$script:MR_C_VIOLET_DARK='0.28 0.20 0.38'; $script:MR_C_SLATE='0.40 0.42 0.46'

$script:MR_PAGES=[System.Collections.Generic.List[string]]::new()
$script:MR_CUR=""; $script:MR_Y=$script:MR_TOP_Y
$script:MR_BG=$script:MR_C_SURFACE; $script:MR_FOOTER=1
$script:MR_PAGE_NO=0; $script:MR_LAST_Y=$script:MR_TOP_Y
$script:MR_TOTAL=0; $script:MR_PASS=0; $script:MR_WARN=0
$script:MR_CRIT=0; $script:MR_INFO=0; $script:MR_NA=0
$script:MR_SCORE=0; $script:MR_OVERALL='pass'
$script:MR_SECTION_ORDER=[System.Collections.Generic.List[string]]::new()
$script:MR_SEC_PASS=@{}; $script:MR_SEC_WARN=@{}
$script:MR_SEC_CRIT=@{}; $script:MR_SEC_INFO=@{}
$script:MR_ISSUES=[System.Collections.Generic.List[string]]::new()
$script:MR_SORTED_ISSUES=[System.Collections.Generic.List[string]]::new()
$script:MR_CUR_SECTION=""; $script:MR_SEC_SEEN=@{}

function Mr-Escape([string]$s){
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
function Mr-Text([float]$x,[float]$y,[string]$txt,[string]$font,[float]$size,[string]$color){
    $esc=Mr-Escape $txt
    $script:MR_CUR += "${color} rg`nBT /${font} ${size} Tf ${x} ${y} Td (${esc}) Tj ET`n"
}
function Mr-TextTrunc([float]$x,[float]$y,[string]$txt,[string]$font,[float]$size,[string]$color,[int]$max){
    Mr-Text $x $y (Pdf-Trunc $txt $max) $font $size $color
}
function Mr-TextCenter([float]$cx,[float]$y,[string]$txt,[string]$font,[float]$size,[string]$color){
    $w=[math]::Round($txt.Length*$size*0.52,1)
    Mr-Text ($cx-$w/2) $y $txt $font $size $color
}
function Mr-TextRight([float]$rx,[float]$y,[string]$txt,[string]$font,[float]$size,[string]$color){
    $w=[math]::Round($txt.Length*$size*0.52,1)
    Mr-Text ($rx-$w) $y $txt $font $size $color
}
function Mr-Line([float]$x1,[float]$y1,[float]$x2,[float]$y2,[float]$w,[string]$color){
    if(-not $color){$color=$script:MR_C_BORDER}
    $script:MR_CUR += "${color} RG`n${w} w`n${x1} ${y1} m ${x2} ${y2} l S`n"
}
function Mr-Rect([float]$x,[float]$y,[float]$w,[float]$h,[string]$color){
    $script:MR_CUR += "${color} rg`n${x} ${y} ${w} ${h} re f`n"
}
# Word-wrap a paragraph and return the baseline Y of the next free line so
# callers can stack paragraphs without overlapping them.
function Mr-Paragraph([float]$x,[float]$y,[float]$w,[string]$txt,[string]$font,[float]$size,[string]$color,[float]$lh){
    $cur=""
    foreach($word in $txt.Split(' ')){
        $test=if($cur){$cur+" "+$word}else{$word}
        $tw=$test.Length*$size*0.52
        if($tw -gt $w -and $cur){
            Mr-Text $x $y $cur $font $size $color
            $y-=$lh; $cur=$word
            if($y -lt $script:MR_BOTTOM_Y){ return $y }
        } else { $cur=$test }
    }
    if($cur -and $y -ge $script:MR_BOTTOM_Y){ Mr-Text $x $y $cur $font $size $color; $y-=$lh }
    return $y
}
function Mr-StatusColor([string]$s){
    switch($s){'pass'{$script:MR_C_GREEN} 'warn'{$script:MR_C_AMBER} 'fail'{$script:MR_C_ROSE} 'info'{$script:MR_C_TEAL} 'na'{$script:MR_C_SLATE} default{$script:MR_C_SLATE}}
}
function Mr-StatusFill([string]$s){ Mr-StatusColor $s }
function Mr-StatusTextColor([string]$s){
    switch($s){'pass'{$script:MR_C_GREEN_DARK} 'warn'{$script:MR_C_ROSE_DARK} 'fail'{$script:MR_C_ROSE_DARK} 'info'{$script:MR_C_TEAL_DARK} 'na'{$script:MR_C_SLATE} default{$script:MR_C_SLATE}}
}
function Mr-StatusWord([string]$s){
    switch($s){'pass'{'PASS'} 'warn'{'WARN'} 'fail'{'FAIL'} 'info'{'INFO'} 'na'{'N/A'} default{$s.ToUpper()}}
}
function Mr-OverallWord([string]$s){
    switch($s){'pass'{'HEALTHY'} 'warn'{'WARNING'} 'fail'{'CRITICAL'} default{$s.ToUpper()}}
}
function Mr-Background(){
    $script:MR_CUR += "${script:MR_BG} rg`n0 0 ${script:MR_PAGE_W} ${script:MR_PAGE_H} re f`n"
}
function Mr-PageHeader([string]$title){
    Mr-Rect $script:MR_MARGIN ($script:MR_TOP_Y+12) ($script:MR_CONTENT_W) 22 $script:MR_C_INK
    Mr-TextTrunc ($script:MR_MARGIN+10) ($script:MR_TOP_Y+17) $title 'Helvetica-Bold' 11 $script:MR_C_WHITE 62
}
function Mr-PageFooter(){
    if($script:MR_FOOTER){
        Mr-Line $script:MR_MARGIN $script:MR_BOTTOM_Y $script:MR_RIGHT $script:MR_BOTTOM_Y 0.5 $script:MR_C_BORDER
        Mr-Text ($script:MR_PAGE_W/2-20) ($script:MR_BOTTOM_Y-14) "Page $($script:MR_PAGE_NO)" 'Helvetica' 8 $script:MR_C_MUTED
    }
}
function Mr-NewPage(){
    if($script:MR_CUR){ $script:MR_PAGES.Add($script:MR_CUR)|Out-Null }
    $script:MR_PAGE_NO++; $script:MR_CUR=""; $script:MR_Y=$script:MR_TOP_Y
    Mr-Background
}
function Mr-Ensure([float]$need){
    if(($script:MR_Y-$need) -lt $script:MR_BOTTOM_Y){ Mr-NewPage }
}
function Mr-Finish(){
    if($script:MR_CUR){ $script:MR_PAGES.Add($script:MR_CUR)|Out-Null }
}
function Mr-SectionHeader([string]$title,[string]$sec){
    Mr-Ensure 44
    Mr-Rect $script:MR_MARGIN $script:MR_Y ($script:MR_CONTENT_W) 26 $script:MR_C_INK
    Mr-Text ($script:MR_MARGIN+12) ($script:MR_Y+8) $title 'Helvetica-Bold' 11 $script:MR_C_WHITE
    Mr-Text ($script:MR_RIGHT-140) ($script:MR_Y+8) "Section $($script:MR_SECTION_ORDER.Count)" 'Helvetica' 9 $script:MR_C_TEAL_LIGHT
    $script:MR_Y-=34
}
function Mr-SectionTitle([string]$title,[string]$sec){
    Mr-Ensure 24
    Mr-Text $script:MR_MARGIN $script:MR_Y $title 'Helvetica-Bold' 13 $script:MR_C_TEAL
    $script:MR_Y-=20
}
# --- Health-engine integration ---------------------------------------------
# Section status and the overall verdict come from health.* (lib/Health.ps1).
# Checklist row badges can only make a section worse, never better, so a
# section is never shown as PASS while the health engine reports a problem.
$script:MR_DATA=$null
$script:MR_PILLARS=@(
    @{Pillar='backup';Title='Backup & Recovery'},
    @{Pillar='mail_flow';Title='Mail Flow & DNS'},
    @{Pillar='tls';Title='Transport Security'},
    @{Pillar='access';Title='Access & Authentication'},
    @{Pillar='threat';Title='Threat Protection'},
    @{Pillar='resources';Title='Server Resources'},
    @{Pillar='os_update';Title='OS & Patching'},
    @{Pillar='monitoring';Title='Monitoring & Watchdog'},
    @{Pillar='database';Title='Database Platform'}
)
$script:MR_SECTION_PILLARS=@{
    'DNS & Mail Flow Verification'=@('mail_flow')
    'Backup, Watchdog and Monitoring'=@('backup','monitoring')
    'Storage, Certificates and Services'=@('tls','threat')
    'Rejection Rules and Access'=@('access')
    'Protocol and Access Hardening'=@('access')
    'APP OS / Infrastructure'=@('resources','os_update')
    'Database'=@('database')
}
function Mr-DataValue([string]$key){
    if($null -eq $script:MR_DATA -or -not $script:MR_DATA.Contains($key)){ return '' }
    $v=$script:MR_DATA[$key]
    if($null -eq $v){ return '' }
    if($v -is [bool]){ if($v){ return 'true' } else { return 'false' } }
    return [string]$v
}
function Mr-HealthStatus([string]$name){
    switch(Mr-DataValue "health.$name.result"){
        'pass'     { return 'pass' }
        'ok'       { return 'pass' }
        'warn'     { return 'warn' }
        'fail'     { return 'fail' }
        'critical' { return 'fail' }
    }
    return 'na'
}
function Mr-Worst([string[]]$statuses){
    if($statuses -contains 'fail'){ return 'fail' }
    if($statuses -contains 'warn'){ return 'warn' }
    if($statuses -contains 'pass'){ return 'pass' }
    if($statuses -contains 'info'){ return 'info' }
    return 'na'
}
function Mr-SectionStatusValue([string]$sec){
    $st=@('na')
    if($script:MR_SEC_CRIT[$sec]){ $st+='fail' }
    if($script:MR_SEC_WARN[$sec]){ $st+='warn' }
    if($script:MR_SEC_PASS[$sec]){ $st+='pass' }
    if($script:MR_SEC_INFO[$sec]){ $st+='info' }
    if($script:MR_SECTION_PILLARS.ContainsKey($sec)){
        foreach($p in $script:MR_SECTION_PILLARS[$sec]){ $st+=(Mr-HealthStatus $p) }
    }
    return (Mr-Worst $st)
}
function Mr-PillarTitle([string]$key){
    foreach($p in $script:MR_PILLARS){ if($p.Pillar -eq $key){ return $p.Title } }
    return $key
}
# Status badge: a filled box whose label is centred inside it. $y is the
# text baseline; the box spans $y-4 .. $y+10.
function Mr-Badge([float]$x,[float]$y,[float]$w,[string]$status){
    Mr-Rect $x ($y-4) $w 14 (Mr-StatusColor $status)
    Mr-TextCenter ($x+$w/2) $y (Mr-StatusWord $status) 'Helvetica-Bold' 8 $script:MR_C_WHITE
}
function Mr-SectionStatus([string]$sec){
    Mr-Badge ($script:MR_RIGHT-60) ($script:MR_Y+6) 56 (Mr-SectionStatusValue $sec)
}
function Mr-CoverLetter([string]$date,[string]$version){
    Mr-NewPage
    Mr-Text ($script:MR_MARGIN+80) 700 "IceWarp Health Agent" 'Helvetica-Bold' 22 $script:MR_C_TEAL
    Mr-Text ($script:MR_MARGIN+80) 678 "Executive Management Report" 'Helvetica' 14 $script:MR_C_TEXT
    Mr-Line $script:MR_MARGIN 660 $script:MR_RIGHT 660 1 $script:MR_C_TEAL
    $agentHost=Mr-DataValue 'agent.hostname'; if(-not $agentHost){ $agentHost='unknown' }
    $company=Mr-DataValue 'general.company'; if(-not $company){ $company='-' }
    Mr-Text $script:MR_MARGIN 640 ("Host: {0}    Company: {1}    Date: {2}" -f $agentHost, $company, $date) 'Helvetica' 9 $script:MR_C_MUTED
    $w=$script:MR_CONTENT_W
    $y=Mr-Paragraph $script:MR_MARGIN 612 $w "This report presents the results of the automated IceWarp health check performed on $($date). It summarizes the status of all control areas, highlights issues requiring attention, and lists recommended actions." 'Helvetica' 10 $script:MR_C_TEXT 14
    $y=Mr-Paragraph $script:MR_MARGIN ($y-8) $w "The assessment covers $($script:MR_TOTAL) checklist items across all major subsystems. Each item is classified as PASS, WARN, FAIL, INFO, or N/A. The overall health status is taken from the health engine (nine executive pillars)." 'Helvetica' 10 $script:MR_C_TEXT 14
    $failed=Mr-DataValue 'health.summary.failed'; $warnings=Mr-DataValue 'health.summary.warnings'; $total=Mr-DataValue 'health.summary.total_checks'
    $y=Mr-Paragraph $script:MR_MARGIN ($y-12) $w ("Health status: {0}  ({1} failed, {2} warnings of {3} pillars)" -f (Mr-OverallWord $script:MR_OVERALL), $failed, $warnings, $total) 'Helvetica-Bold' 11 (Mr-StatusColor $script:MR_OVERALL) 16
    $y=Mr-Paragraph $script:MR_MARGIN $y $w "Checklist compliance: $($script:MR_SCORE)% of scored items pass" 'Helvetica-Bold' 11 $script:MR_C_TEAL 16
    Mr-Text $script:MR_MARGIN ($y-10) "Report version: $($version)  |  Checklist: $($script:MR_CHECKLIST_VERSION)" 'Helvetica' 9 $script:MR_C_MUTED
}
function Mr-ExecutiveOverview(){
    Mr-NewPage
    Mr-SectionTitle "Executive Overview" ""
    Mr-Text $script:MR_MARGIN $script:MR_Y "Health status (health engine)" 'Helvetica' 9 $script:MR_C_MUTED
    Mr-Text ($script:MR_MARGIN+240) $script:MR_Y "Checklist compliance" 'Helvetica' 9 $script:MR_C_MUTED
    $script:MR_Y-=26
    Mr-Text $script:MR_MARGIN $script:MR_Y (Mr-OverallWord $script:MR_OVERALL) 'Helvetica-Bold' 22 (Mr-StatusColor $script:MR_OVERALL)
    Mr-Text ($script:MR_MARGIN+240) $script:MR_Y "$($script:MR_SCORE)%" 'Helvetica-Bold' 22 $script:MR_C_TEAL
    $script:MR_Y-=36
    # KPI tiles on one row: each label and its value share a fixed column,
    # so nothing overlaps and all six tiles stay inside the page width.
    $tiles=@(
        @('Total Checks',$script:MR_TOTAL,$script:MR_C_TEXT),
        @('Passed',$script:MR_PASS,$script:MR_C_GREEN),
        @('Warnings',$script:MR_WARN,$script:MR_C_AMBER),
        @('Failures',$script:MR_CRIT,$script:MR_C_ROSE),
        @('Info',$script:MR_INFO,$script:MR_C_TEAL),
        @('N/A',$script:MR_NA,$script:MR_C_SLATE)
    )
    $colW=$script:MR_CONTENT_W/6
    for($i=0;$i -lt $tiles.Count;$i++){
        $x=$script:MR_MARGIN+($i*$colW)
        Mr-Text $x $script:MR_Y $tiles[$i][0] 'Helvetica' 9 $script:MR_C_MUTED
        Mr-Text $x ($script:MR_Y-22) ([string]$tiles[$i][1]) 'Helvetica-Bold' 18 $tiles[$i][2]
    }
    $script:MR_Y-=46
    Mr-Line $script:MR_MARGIN $script:MR_Y $script:MR_RIGHT $script:MR_Y 0.5 $script:MR_C_BORDER
    $script:MR_Y-=24
    Mr-Text $script:MR_MARGIN $script:MR_Y "Health Engine - Nine Executive Pillars" 'Helvetica-Bold' 12 $script:MR_C_TEAL
    $script:MR_Y-=24
    foreach($p in $script:MR_PILLARS){
        Mr-Ensure 32
        $hs=Mr-HealthStatus $p.Pillar
        Mr-Badge $script:MR_MARGIN $script:MR_Y 56 $hs
        Mr-Text ($script:MR_MARGIN+66) $script:MR_Y $p.Title 'Helvetica-Bold' 10 $script:MR_C_TEXT
        $msg=Mr-DataValue "health.$($p.Pillar).message"
        if($msg){ Mr-TextTrunc ($script:MR_MARGIN+66) ($script:MR_Y-12) $msg 'Helvetica' 8 $script:MR_C_MUTED 105 }
        $script:MR_Y-=30
    }
}
function Mr-RenderControlAreas([hashtable]$checklist){
    foreach($sec in $checklist.sections){
        $items=$checklist.items[$sec]
        if(-not $items){ continue }
        $st=Mr-SectionStatusValue $sec
        Mr-NewPage
        $script:MR_Y=$script:MR_TOP_Y-16
        Mr-PageHeader $sec
        Mr-SectionStatus $sec
        $script:MR_Y-=30
        Mr-Text $script:MR_MARGIN $script:MR_Y "Status: $(Mr-StatusWord $st)" 'Helvetica-Bold' 11 (Mr-StatusColor $st)
        $script:MR_Y-=16
        if($script:MR_SECTION_PILLARS.ContainsKey($sec)){
            foreach($p in $script:MR_SECTION_PILLARS[$sec]){
                $hs=Mr-HealthStatus $p
                if($hs -eq 'na'){ continue }
                $line="Health engine - {0}: {1}. {2}" -f (Mr-PillarTitle $p), (Mr-StatusWord $hs), (Mr-DataValue "health.$p.message")
                Mr-TextTrunc $script:MR_MARGIN $script:MR_Y $line 'Helvetica' 8 (Mr-StatusColor $hs) 115
                $script:MR_Y-=12
            }
        }
        $script:MR_Y-=4
        Mr-Line $script:MR_MARGIN $script:MR_Y $script:MR_RIGHT $script:MR_Y 0.5 $script:MR_C_BORDER
        $script:MR_Y-=14
        foreach($item in $items){
            $status=$item.status
            if(-not $status){ $status='na' }
            $val=$item.value
            if(-not $val){ $val='N/A' }
            Mr-Ensure 18
            Mr-Rect $script:MR_MARGIN $script:MR_Y 10 10 (Mr-StatusColor $status)
            Mr-TextTrunc ($script:MR_MARGIN+16) ($script:MR_Y+1) $item.label 'Helvetica-Bold' 9 $script:MR_C_TEXT 58
            Mr-TextTrunc ($script:MR_RIGHT-170) ($script:MR_Y+1) $val 'Helvetica' 8 $script:MR_C_MUTED 40
            $script:MR_Y-=18
        }
    }
}
function Mr-RenderActions(){
    if($script:MR_ISSUES.Count -eq 0){ return }
    Mr-NewPage
    $script:MR_Y=$script:MR_TOP_Y-16
    Mr-PageHeader "Recommended Actions"
    $script:MR_Y-=24
    Mr-Text $script:MR_MARGIN $script:MR_Y "Issues Requiring Attention" 'Helvetica-Bold' 12 $script:MR_C_ROSE
    $script:MR_Y-=14
    Mr-Text $script:MR_MARGIN $script:MR_Y "Ordered by severity (FAIL before WARN), then health-engine pillars, then checklist order." 'Helvetica' 8 $script:MR_C_MUTED
    $script:MR_Y-=26
    $i=0
    foreach($issue in $script:MR_ISSUES){
        Mr-Ensure 22
        $i++
        Mr-Badge $script:MR_MARGIN $script:MR_Y 40 $issue.Status
        Mr-TextRight ($script:MR_MARGIN+70) $script:MR_Y "$i." 'Helvetica-Bold' 9 $script:MR_C_TEXT
        Mr-TextTrunc ($script:MR_MARGIN+76) $script:MR_Y ("{0} - {1}" -f $issue.Section, $issue.Label) 'Helvetica' 9 $script:MR_C_TEXT 86
        $script:MR_Y-=20
    }
}
function Mr-DisplayLabel([string]$s){ return $s }
function Mr-ShortSection([string]$s){
    $m=@{'MySQL scope'='MySQL';'Backup'='Backup';'Watchdog'='Watchdog';'Threads'='Threads';'Directory cache'='DirCache';'Intrusion validation'='Intrusion';'APP OS disk'='Disk';'APP OS CPU'='CPU';'APP OS RAM'='RAM';'APP OS swap'='Swap';'APP OS last update'='Update'}
    if($m[$s]){ return $m[$s] } else { return $s }
}
function Mr-JoinSections([string[]]$a){ return ($a -join ', ') }
function Mr-ActionText([string]$s){ return $s }
function Mr-LegendItem([string]$label,[string]$color){
    Mr-Rect $script:MR_MARGIN $script:MR_Y 8 8 $color
    Mr-Text ($script:MR_MARGIN+12) ($script:MR_Y+1) $label 'Helvetica' 8 $script:MR_C_TEXT
    $script:MR_Y-=12
}
function Mr-WriteFile([string]$OutPath){
    $n=$script:MR_PAGES.Count
    if($n -eq 0){ Write-Warning "management_report: nothing to render"; return $null }
    $nl="`n"
    $pageBase=3
    $contentBase=$pageBase+$n
    $fontBase=$contentBase+$n
    $fontHelv=$fontBase
    $fontBold=$fontBase+1
    $fontObl=$fontBase+2
    $fontBoldObl=$fontBase+3
    $total=$fontBase+4
    $offsets=@{}
    $body=[System.Text.StringBuilder]::new()
    [void]$body.Append("%PDF-1.4$nl")
    $offsets[1]=$body.Length
    [void]$body.Append("1 0 obj$($nl)<< /Type /Catalog /Pages 2 0 R >>$($nl)endobj$($nl)")
    $offsets[2]=$body.Length
    $kids=""
    for($i=0;$i -lt $n;$i++){ $kids+="$($pageBase+$i) 0 R " }
    [void]$body.Append("2 0 obj$($nl)<< /Type /Pages /Kids [ ${kids}] /Count $n >>$($nl)endobj$($nl)")
    $fontRes="/Helvetica $fontHelv 0 R /Helvetica-Bold $fontBold 0 R /Helvetica-Oblique $fontObl 0 R /Helvetica-BoldOblique $fontBoldObl 0 R"
    for($i=0;$i -lt $n;$i++){
        $pageNum=$pageBase+$i
        $contentNum=$contentBase+$i
        $offsets[$pageNum]=$body.Length
        [void]$body.Append("$pageNum 0 obj$($nl)<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $($script:MR_PAGE_W) $($script:MR_PAGE_H)] /Resources << /Font << $fontRes >> >> /Contents $contentNum 0 R >>$($nl)endobj$($nl)")
        $stream=$script:MR_PAGES[$i]
        $offsets[$contentNum]=$body.Length
        [void]$body.Append("$contentNum 0 obj$($nl)<< /Length $($stream.Length) >>$($nl)stream$($nl)$stream$($nl)endstream$($nl)endobj$($nl)")
    }
    $offsets[$fontHelv]=$body.Length
    [void]$body.Append("$fontHelv 0 obj$($nl)<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>$($nl)endobj$($nl)")
    $offsets[$fontBold]=$body.Length
    [void]$body.Append("$fontBold 0 obj$($nl)<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>$($nl)endobj$($nl)")
    $offsets[$fontObl]=$body.Length
    [void]$body.Append("$fontObl 0 obj$($nl)<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Oblique >>$($nl)endobj$($nl)")
    $offsets[$fontBoldObl]=$body.Length
    [void]$body.Append("$fontBoldObl 0 obj$($nl)<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-BoldOblique >>$($nl)endobj$($nl)")
    $xrefPos=$body.Length
    [void]$body.Append("xref$($nl)0 $total$($nl)")
    [void]$body.Append("0000000000 65535 f $($nl)")
    for($obj=1;$obj -lt $total;$obj++){
        $off=[int]$offsets[$obj]
        [void]$body.Append(("{0:D10} 00000 n $($nl)" -f $off))
    }
    [void]$body.Append("trailer$($nl)<< /Size $total /Root 1 0 R >>$($nl)startxref$($nl)$xrefPos$($nl)%%EOF$($nl)")
    [System.IO.File]::WriteAllText($OutPath,$body.ToString())
    return $OutPath
}
function ConvertTo-ManagementChecklist(){
    $sections=[System.Collections.Generic.List[string]]::new()
    $items=@{}
    $rows=$script:CHECKLIST_CAPTURED
    if($null -eq $rows){ return @{sections=$sections; items=$items} }
    foreach($r in $rows){
        $sec=$r.section
        if([string]::IsNullOrEmpty($sec)){ $sec='General' }
        if(-not $items.ContainsKey($sec)){
            $items[$sec]=[System.Collections.Generic.List[object]]::new()
            [void]$sections.Add($sec)
        }
        $status='info'
        switch([string]$r.bkind){
            'PASS' { $status='pass' }
            'WARN' { $status='warn' }
            'CRITICAL' { $status='fail' }
            default {
                if(([string]$r.value) -eq 'N/A' -or ([string]$r.btext) -eq 'N/A'){ $status='na' }
                else { $status='info' }
            }
        }
        [void]$items[$sec].Add([pscustomobject]@{
            id=($items[$sec].Count + 1)
            label=[string]$r.label
            value=[string]$r.value
            status=$status
        })
    }
    return @{sections=$sections; items=$items}
}

function Initialize-ManagementCounts([hashtable]$checklist){
    $script:MR_TOTAL=0; $script:MR_PASS=0; $script:MR_WARN=0
    $script:MR_CRIT=0; $script:MR_INFO=0; $script:MR_NA=0
    $script:MR_SEC_PASS=@{}; $script:MR_SEC_WARN=@{}
    $script:MR_SEC_CRIT=@{}; $script:MR_SEC_INFO=@{}
    $issues=[System.Collections.Generic.List[object]]::new()
    $secIndex=0
    foreach($sec in $checklist.sections){
        $script:MR_SEC_PASS[$sec]=0; $script:MR_SEC_WARN[$sec]=0
        $script:MR_SEC_CRIT[$sec]=0; $script:MR_SEC_INFO[$sec]=0
        $secItems=$checklist.items[$sec]
        if($secItems){
            foreach($item in $secItems){
                $status=[string]$item.status
                if([string]::IsNullOrEmpty($status)){ $status='na' }
                $script:MR_TOTAL++
                switch($status){
                    'pass' { $script:MR_PASS++; $script:MR_SEC_PASS[$sec]++ }
                    'warn' { $script:MR_WARN++; $script:MR_SEC_WARN[$sec]++ }
                    'fail' { $script:MR_CRIT++; $script:MR_SEC_CRIT[$sec]++ }
                    'info' { $script:MR_INFO++; $script:MR_SEC_INFO[$sec]++ }
                    default { $script:MR_NA++ }
                }
                if($status -eq 'fail' -or $status -eq 'warn'){
                    [void]$issues.Add([pscustomobject]@{
                        Rank=$(if($status -eq 'fail'){0}else{1})
                        SectionIndex=$secIndex
                        Id=[int]$item.id
                        Section=$sec
                        Label=[string]$item.label
                        Status=$status
                    })
                }
            }
        }
        $secIndex++
    }
    # Health-engine pillars that are not passing are actions in their own
    # right; within a severity they are listed before checklist items.
    $pIndex=0
    foreach($p in $script:MR_PILLARS){
        $hs=Mr-HealthStatus $p.Pillar
        if($hs -eq 'fail' -or $hs -eq 'warn'){
            [void]$issues.Add([pscustomobject]@{
                Rank=$(if($hs -eq 'fail'){0}else{1})
                SectionIndex=-1
                Id=$pIndex
                Section='Health engine'
                Label=('{0}: {1}' -f $p.Title, (Mr-DataValue "health.$($p.Pillar).message"))
                Status=$hs
            })
        }
        $pIndex++
    }
    # Numeric sort on severity, then checklist section order, then item order.
    $script:MR_ISSUES=[System.Collections.Generic.List[object]]::new()
    foreach($issue in @($issues | Sort-Object -Property Rank, SectionIndex, Id)){ [void]$script:MR_ISSUES.Add($issue) }

    $scored=$script:MR_PASS + $script:MR_WARN + $script:MR_CRIT
    if($scored -gt 0){ $script:MR_SCORE=[int](($script:MR_PASS * 100) / $scored) } else { $script:MR_SCORE=0 }
    # The overall verdict is the health engine's summary, not the checklist.
    $healthOverall=Mr-DataValue 'health.summary.overall'
    if($healthOverall -eq 'pass' -or $healthOverall -eq 'warn' -or $healthOverall -eq 'fail'){
        $script:MR_OVERALL=$healthOverall
    } elseif($script:MR_CRIT -gt 0){ $script:MR_OVERALL='fail' }
    elseif($script:MR_WARN -gt 0){ $script:MR_OVERALL='warn' }
    else { $script:MR_OVERALL='pass' }
}

function Build-ManagementReportPdf([hashtable]$Data,[string]$OutPath,[string]$Version,[string]$Date){
    $script:MR_DATA=$Data
    $script:MR_PAGES=[System.Collections.Generic.List[string]]::new()
    $script:MR_CUR=""; $script:MR_Y=$script:MR_TOP_Y
    $script:MR_PAGE_NO=0; $script:MR_FOOTER=1
    $script:MR_SECTION_ORDER=[System.Collections.Generic.List[string]]::new()
    $script:MR_SEC_SEEN=@{}
    if($null -eq $script:CHECKLIST_CAPTURED -or $script:CHECKLIST_CAPTURED.Count -eq 0){
        $script:_PDF_PAGES=[System.Collections.Generic.List[string]]::new()
        $script:_PDF_CUR=""; $script:_PDF_Y=$script:PDF_TOP_Y; $script:_PDF_ROW_INDEX=0
        Render-Checklist $Data
    }
    $checklist=ConvertTo-ManagementChecklist
    Initialize-ManagementCounts $checklist
    Mr-CoverLetter $Date $Version
    Mr-ExecutiveOverview
    Mr-RenderControlAreas $checklist
    Mr-RenderActions
    Mr-Finish
    return (Mr-WriteFile $OutPath)
}
