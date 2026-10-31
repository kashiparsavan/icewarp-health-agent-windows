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
}function Mr-RoundRect([float]$x,[float]$y,[float]$w,[float]$h,[float]$r,[string]$color){
    if($r -gt 0){
        $script:MR_CUR += "${color} RG`n${r} w`n"
        $script:MR_CUR += "${x} ${y} ${r} ${r} 0 0 1 re f`n"
        $script:MR_CUR += "${x} ${y} ${r} ${r} 0 0 -1 re f`n"
    } else {
        $script:MR_CUR += "${color} rg`n${x} ${y} ${w} ${h} re f`n"
    }
}
function Mr-Circle([float]$cx,[float]$cy,[float]$r,[string]$color){
    $script:MR_CUR += "${color} rg`n${cx} ${cy} ${r} 0 360 re f`n"
}
function Mr-Ring([float]$cx,[float]$cy,[float]$r,[float]$rw,[string]$color){
    $script:MR_CUR += "${color} RG`n${rw} w`n${cx} ${cy} ${r} 0 360 re S`n"
}
function Mr-Arc([float]$cx,[float]$cy,[float]$r,[float]$rw,[float]$a1,[float]$a2,[string]$color){
    $script:MR_CUR += "${color} RG`n${rw} w`n${cx} ${cy} ${r} ${a1} ${a2} re S`n"
}
function Mr-Paragraph([float]$x,[float]$y,[float]$w,[float]$h,[string]$txt,[string]$font,[float]$size,[string]$color,[float]$lh){
    $lines=0; $cur=""
    foreach($word in $txt.Split(' ')){
        $test=if($cur){$cur+" "+$word}else{$word}
        $tw=$test.Length*$size*0.52
        if($tw -gt $w -and $cur){
            Mr-Text $x $y $cur $font $size $color
            $y-=$lh; $cur=$word; $lines++
            if($y -lt $script:MR_BOTTOM_Y){break}
        } else { $cur=$test }
    }
    if($cur -and $y -ge $script:MR_BOTTOM_Y){ Mr-Text $x $y $cur $font $size $color }
}
function Mr-Card([float]$x,[float]$y,[float]$w,[float]$h,[string]$color){
    Mr-RoundRect $x $y $w $h 4 $color
}
function Mr-DarkCard([float]$x,[float]$y,[float]$w,[float]$h,[string]$color){
    Mr-RoundRect $x $y $w $h 4 $color
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
    Mr-Text ($script:MR_MARGIN+10) ($script:MR_TOP_Y+17) $title 'Helvetica-Bold' 11 $script:MR_C_WHITE
}
function Mr-PageFooter(){
    if($script:MR_FOOTER){
        Mr-Line $script:MR_MARGIN $script:MR_BOTTOM_Y $script:MR_RIGHT $script:MR_BOTTOM_Y 0.5 $script:MR_C_BORDER
        Mr-Text ($script:MR_PAGE_W/2-20) ($script:MR_BOTTOM_Y-14) "Page $($script:MR_PAGE_NO)" 'Helvetica' 8 $script:MR_C_MUTED
    }
}
function Mr-NewPage(){
    $script:MR_PAGES.Add($script:MR_CUR)|Out-Null
    $script:MR_PAGE_NO++; $script:MR_CUR=""; $script:MR_Y=$script:MR_TOP_Y
    Mr-Background
}
function Mr-Ensure([float]$need){
    if(($script:MR_Y-$need) -lt $script:MR_BOTTOM_Y){ Mr-NewPage }
}
function Mr-Finish(){
    $script:MR_PAGES.Add($script:MR_CUR)|Out-Null
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
function Mr-Priority([string]$p){
    $c=switch($p){'high'{$script:MR_C_ROSE} 'med'{$script:MR_C_AMBER} 'low'{$script:MR_C_GREEN} default{$script:MR_C_SLATE}}
    Mr-Rect ($script:MR_RIGHT-50) ($script:MR_Y+2) 44 14 $c
    Mr-TextRight ($script:MR_RIGHT-3) ($script:MR_Y+6) $p.ToUpper() 'Helvetica-Bold' 8 $script:MR_C_WHITE
}
function Mr-SectionStatus([string]$sec){
    $st=if($script:MR_SEC_CRIT[$sec]){'fail'}elseif($script:MR_SEC_WARN[$sec]){'warn'}elseif($script:MR_SEC_PASS[$sec]){'pass'}elseif($script:MR_SEC_INFO[$sec]){'info'}else{'na'}
    $c=Mr-StatusColor $st
    Mr-Rect ($script:MR_RIGHT-70) ($script:MR_Y+2) 56 14 $c
    Mr-TextRight ($script:MR_RIGHT-3) ($script:MR_Y+6) (Mr-StatusWord $st) 'Helvetica-Bold' 8 $script:MR_C_WHITE
}
function Mr-GridEndRow(){
    $script:MR_Y-=18
}
function Mr-GridItem([string]$label,[string]$value,[string]$status,[int]$col){
    $x=$script:MR_MARGIN+($col*($script:MR_CONTENT_W/3))
    Mr-Text $x $script:MR_Y $label 'Helvetica' 8 $script:MR_C_MUTED
    $script:MR_Y-=11
    $c=Mr-StatusColor $status
    Mr-Rect $x $script:MR_Y 80 14 $c
    Mr-Text ($x+2) ($script:MR_Y+3) (Mr-StatusWord $status) 'Helvetica-Bold' 7 $script:MR_C_WHITE
    $script:MR_Y-=18
}
function Mr-RenderChecklist([hashtable]$checklist){
    $items=$checklist.items
    foreach($sec in $checklist.sections){
        $script:MR_SECTION_ORDER.Add($sec)|Out-Null
        $script:MR_CUR_SECTION=$sec
        $script:MR_SEC_SEEN[$sec]=$true
        Mr-SectionHeader $sec $sec
        $secItems=$items[$sec]
        if(-not $secItems){ continue }
        $row=0
        foreach($item in $secItems){
            $id=$item.id; $label=$item.label; $status=$item.status
            if(-not $status){ $status='na' }
            $script:MR_TOTAL++
            switch($status){'pass'{$script:MR_PASS++} 'warn'{$script:MR_WARN++} 'fail'{$script:MR_CRIT++} 'info'{$script:MR_INFO++} 'na'{$script:MR_NA++}}
            if($status -eq 'fail'){ $script:MR_ISSUES.Add("$sec|$id|$label")|Out-Null }
            if($status -eq 'warn'){ $script:MR_ISSUES.Add("$sec|$id|$label")|Out-Null }
            switch($sec){
                'MySQL scope' {
                    $val=$item.value
                    if($val -and $val -ne 'n/a'){ Mr-GridItem $label $val $status ($row%3) }
                    else { Mr-GridItem $label 'N/A' 'na' ($row%3) }
                }
                'Backup' {
                    $val=$item.value
                    if($val -and $val -ne 'n/a'){ Mr-GridItem $label $val $status ($row%3) }
                    else { Mr-GridItem $label 'N/A' 'na' ($row%3) }
                }
                'Watchdog' {
                    $val=$item.value
                    if($val -and $val -ne 'n/a'){ Mr-GridItem $label $val $status ($row%3) }
                    else { Mr-GridItem $label 'N/A' 'na' ($row%3) }
                }
                'Threads' {
                    $val=$item.value
                    if($val -and $val -ne 'n/a'){ Mr-GridItem $label $val $status ($row%3) }
                    else { Mr-GridItem $label 'N/A' 'na' ($row%3) }
                }
                'Directory cache' {
                    $val=$item.value
                    if($val -and $val -ne 'n/a'){ Mr-GridItem $label $val $status ($row%3) }
                    else { Mr-GridItem $label 'N/A' 'na' ($row%3) }
                }
                'Intrusion validation' {
                    $val=Pdf-IntrusionValidate $item
                    Mr-GridItem $label $val $status ($row%3)
                }
                'APP OS disk' {
                    $val=$item.value
                    if($val -and $val -ne 'n/a'){ Mr-GridItem $label $val $status ($row%3) }
                    else { Mr-GridItem $label 'N/A' 'na' ($row%3) }
                }
                'APP OS CPU' {
                    $val=$item.value
                    if($val -and $val -ne 'n/a'){ Mr-GridItem $label $val $status ($row%3) }
                    else { Mr-GridItem $label 'N/A' 'na' ($row%3) }
                }
                'APP OS RAM' {
                    $val=$item.value
                    if($val -and $val -ne 'n/a'){ Mr-GridItem $label $val $status ($row%3) }
                    else { Mr-GridItem $label 'N/A' 'na' ($row%3) }
                }
                'APP OS swap' {
                    $val=$item.value
                    if($val -and $val -ne 'n/a'){ Mr-GridItem $label $val $status ($row%3) }
                    else { Mr-GridItem $label 'N/A' 'na' ($row%3) }
                }
                'APP OS last update' {
                    $val=$item.value
                    if($val -and $val -ne 'n/a'){ Mr-GridItem $label $val $status ($row%3) }
                    else { Mr-GridItem $label 'N/A' 'na' ($row%3) }
                }
                default {
                    $val=$item.value
                    if($val -and $val -ne 'n/a'){ Mr-GridItem $label $val $status ($row%3) }
                    else { Mr-GridItem $label 'N/A' 'na' ($row%3) }
                }
            }
            $row++
            if(($row%3) -eq 0){ Mr-GridEndRow }
        }
        if(($row%3) -ne 0){ Mr-GridEndRow }
    }
}
function Mr-CoverLetter([string]$date,[string]$version){
    Mr-NewPage
    Mr-Text ($script:MR_MARGIN+80) 700 "IceWarp Health Agent" 'Helvetica-Bold' 22 $script:MR_C_TEAL
    Mr-Text ($script:MR_MARGIN+80) 678 "Executive Management Report" 'Helvetica' 14 $script:MR_C_TEXT
    Mr-Line $script:MR_MARGIN 660 $script:MR_RIGHT 660 1 $script:MR_C_TEAL
    Mr-Paragraph $script:MR_MARGIN 630 ($script:MR_CONTENT_W) "This report presents the results of the automated IceWarp health check performed on $($date). It summarizes the status of all control areas, highlights issues requiring attention, and lists recommended actions." 'Helvetica' 10 $script:MR_C_TEXT 14
    Mr-Paragraph $script:MR_MARGIN 590 ($script:MR_CONTENT_W) "The assessment covers $($script:MR_TOTAL) checks across all major subsystems. Each check is classified as PASS, WARN, FAIL, INFO, or N/A." 'Helvetica' 10 $script:MR_C_TEXT 14
    Mr-Paragraph $script:MR_MARGIN 550 ($script:MR_CONTENT_W) "Overall score: $($script:MR_SCORE)%  |  Status: $(Mr-OverallWord $script:MR_OVERALL)" 'Helvetica-Bold' 11 $script:MR_C_TEAL 16
    Mr-Text $script:MR_MARGIN 520 "Report version: $($version)  |  Checklist: $($script:MR_CHECKLIST_VERSION)" 'Helvetica' 9 $script:MR_C_MUTED
}
function Mr-ExecutiveOverview(){
    Mr-NewPage
    Mr-SectionTitle "Executive Overview" ""
    Mr-Ensure 20
    Mr-Text $script:MR_MARGIN $script:MR_Y "Overall Health Score" 'Helvetica-Bold' 12 $script:MR_C_TEAL
    $script:MR_Y-=16
    Mr-Text $script:MR_MARGIN $script:MR_Y "$($script:MR_SCORE)%" 'Helvetica-Bold' 28 $script:MR_C_TEAL
    $script:MR_Y-=30
    Mr-Ensure 20
    $row=0
    Mr-Text ($script:MR_MARGIN+($row*150)) $script:MR_Y "Total Checks" 'Helvetica' 9 $script:MR_C_MUTED
    $script:MR_Y-=12
    Mr-Text ($script:MR_MARGIN+($row*150)) $script:MR_Y "$($script:MR_TOTAL)" 'Helvetica-Bold' 18 $script:MR_C_TEXT
    $row++
    Mr-Text ($script:MR_MARGIN+($row*150)) $script:MR_Y "Passed" 'Helvetica' 9 $script:MR_C_MUTED
    $script:MR_Y-=12
    Mr-Text ($script:MR_MARGIN+($row*150)) $script:MR_Y "$($script:MR_PASS)" 'Helvetica-Bold' 18 $script:MR_C_GREEN
    $row++
    Mr-Text ($script:MR_MARGIN+($row*150)) $script:MR_Y "Warnings" 'Helvetica' 9 $script:MR_C_MUTED
    $script:MR_Y-=12
    Mr-Text ($script:MR_MARGIN+($row*150)) $script:MR_Y "$($script:MR_WARN)" 'Helvetica-Bold' 18 $script:MR_C_AMBER
    $row++
    Mr-Text ($script:MR_MARGIN+($row*150)) $script:MR_Y "Failures" 'Helvetica' 9 $script:MR_C_MUTED
    $script:MR_Y-=12
    Mr-Text ($script:MR_MARGIN+($row*150)) $script:MR_Y "$($script:MR_CRIT)" 'Helvetica-Bold' 18 $script:MR_C_ROSE
    $row++
    Mr-Text ($script:MR_MARGIN+($row*150)) $script:MR_Y "Info" 'Helvetica' 9 $script:MR_C_MUTED
    $script:MR_Y-=12
    Mr-Text ($script:MR_MARGIN+($row*150)) $script:MR_Y "$($script:MR_INFO)" 'Helvetica-Bold' 18 $script:MR_C_TEAL
    $row++
    Mr-Text ($script:MR_MARGIN+($row*150)) $script:MR_Y "N/A" 'Helvetica' 9 $script:MR_C_MUTED
    $script:MR_Y-=12
    Mr-Text ($script:MR_MARGIN+($row*150)) $script:MR_Y "$($script:MR_NA)" 'Helvetica-Bold' 18 $script:MR_C_SLATE
    $script:MR_Y-=24
}
function Mr-RenderControlAreas([hashtable]$checklist){
    foreach($sec in $checklist.sections){
        $items=$checklist.items[$sec]
        if(-not $items){ continue }
        $st=if($script:MR_SEC_CRIT[$sec]){'fail'}elseif($script:MR_SEC_WARN[$sec]){'warn'}elseif($script:MR_SEC_PASS[$sec]){'pass'}elseif($script:MR_SEC_INFO[$sec]){'info'}else{'na'}
        Mr-NewPage
        Mr-PageHeader $sec
        Mr-SectionStatus $sec
        $script:MR_Y-=30
        Mr-Ensure 20
        Mr-Text $script:MR_MARGIN $script:MR_Y "Status: $(Mr-StatusWord $st)" 'Helvetica-Bold' 11 (Mr-StatusColor $st)
        $script:MR_Y-=16
        Mr-Ensure 20
        Mr-Line $script:MR_MARGIN $script:MR_Y $script:MR_RIGHT $script:MR_Y 0.5 $script:MR_C_BORDER
        $script:MR_Y-=14
        foreach($item in $items){
            $id=$item.id; $label=$item.label; $status=$item.status
            if(-not $status){ $status='na' }
            $val=$item.value
            if(-not $val){ $val='N/A' }
            Mr-Ensure 18
            $c=Mr-StatusColor $status
            Mr-Rect $script:MR_MARGIN $script:MR_Y 10 10 $c
            Mr-Text ($script:MR_MARGIN+16) ($script:MR_Y+1) $label 'Helvetica-Bold' 9 $script:MR_C_TEXT
            Mr-Text ($script:MR_RIGHT-80) ($script:MR_Y+1) $val 'Helvetica' 8 $script:MR_C_MUTED
            $script:MR_Y-=18
        }
    }
}
function Mr-RenderActions(){
    if($script:MR_ISSUES.Count -eq 0){ return }
    Mr-NewPage
    Mr-PageHeader "Recommended Actions"
    $script:MR_Y-=30
    Mr-Ensure 20
    Mr-Text $script:MR_MARGIN $script:MR_Y "Issues Requiring Attention" 'Helvetica-Bold' 12 $script:MR_C_ROSE
    $script:MR_Y-=18
    $i=0
    foreach($issue in $script:MR_ISSUES){
        $parts=$issue.Split('|')
        $sec=$parts[0]; $id=$parts[1]; $label=$parts[2]
        Mr-Ensure 20
        $i++
        Mr-Rect $script:MR_MARGIN $script:MR_Y 18 18 4 $script:MR_C_ROSE
        Mr-Text ($script:MR_MARGIN+22) ($script:MR_Y+4) "$i" 'Helvetica-Bold' 9 $script:MR_C_WHITE
        Mr-Text ($script:MR_MARGIN+44) ($script:MR_Y+4) "$sec - $label" 'Helvetica' 9 $script:MR_C_TEXT
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
    $body=[System.Text.StringBuilder]::new()
    $body.Append("%PDF-1.4`n")|Out-Null
    $body.Append("1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj`n")|Out-Null
    $body.Append("2 0 obj<</Type/Pages/Kids[" )|Out-Null
    $n=$script:MR_PAGES.Count
    for($i=0;$i -lt $n;$i++){ $body.Append("$($i+3) 0 R ")|Out-Null }
    $body.Append("]/Count $n>>endobj`n")|Out-Null
    $fontObj=3+$n
    $body.Append("$fontObj 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica>>endobj`n")|Out-Null
    $body.Append("$($fontObj+1) 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica-Bold>>endobj`n")|Out-Null
    $body.Append("$($fontObj+2) 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica-Oblique>>endobj`n")|Out-Null
    $body.Append("$($fontObj+3) 0 obj<</Type/Font/Subtype/Type1/BaseFont/Helvetica-BoldOblique>>endobj`n")|Out-Null
    $contentStart=$fontObj+4
    for($i=0;$i -lt $n;$i++){
        $body.Append("$($contentStart+$i) 0 obj<</Length $($script:MR_PAGES[$i].Length)>>stream`n")|Out-Null
        $body.Append($script:MR_PAGES[$i])|Out-Null
        $body.Append("`nendstream>>endobj`n")|Out-Null
    }
    $xrefPos=$body.Length
    $body.Append("xref`n0 $($contentStart+$n+1)`n")|Out-Null
    $body.Append("0000000000 65535 f `n")|Out-Null
    $offset=15
    $body.Append("$($offset.ToString().PadLeft(10,'0')) 00000 n `n")|Out-Null
    $body.Append("$($body.Length.ToString().PadLeft(10,'0')) 00000 n `n")|Out-Null
    for($i=0;$i -lt $n;$i++){
        $body.Append("$($body.Length.ToString().PadLeft(10,'0')) 00000 n `n")|Out-Null
    }
    for($i=0;$i -lt 4;$i++){
        $body.Append("$($body.Length.ToString().PadLeft(10,'0')) 00000 n `n")|Out-Null
    }
    $body.Append("trailer<</Size $($contentStart+$n+1)/Root 1 0 R>>`n")|Out-Null
    $body.Append("startxref`n$xrefPos`n%%EOF`n")|Out-Null
    [System.IO.File]::WriteAllText($OutPath,$body.ToString())
}
function Build-ManagementReportPdf([hashtable]$checklist,[string]$OutPath,[string]$Version,[string]$Date){
    Mr-NewPage
    Mr-CoverLetter $Date $Version
    Mr-ExecutiveOverview
    Mr-RenderChecklist $checklist
    Mr-RenderActions
    Mr-Finish
    Mr-WriteFile $OutPath
}
