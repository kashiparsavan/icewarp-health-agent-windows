<#
.SYNOPSIS
Executive (management) PDF report writer (management_report.pdf).

.DESCRIPTION
Layout-for-layout port of the Linux management summary (agent 0.7.x):
  page 1  dark cover: identity, overall posture pill, control-score gauge and
          four KPI cards (controls / healthy / review / action);
  page 2  01 Executive overview: summary paragraph, control distribution bar,
          priority actions and key signals, management takeaway;
  page 3  02 Control areas: one card per checklist section with counts and a
          stacked bar, plus the status key;
  page 4  03 Recommended actions: ranked action cards, assessment scope and
          next step.

Control counts come from the technical checklist capture
($script:CHECKLIST_CAPTURED). Those row badges already follow health.* (see
ReportTechnical.ps1). The overall posture and the key signals come straight
from health.summary.overall and the nine health pillars. Nothing here is
recalculated against thresholds.

Geometry, colours and the text-width estimate (characters x size x 0.52)
mirror the Linux renderer so both platforms produce the same document.
#>
Set-StrictMode -Version 2.0

$script:MR_INV=[System.Globalization.CultureInfo]::InvariantCulture
$script:MR_C=@{
    CoverBg='0.043 0.063 0.102'; CoverGrid='0.105 0.145 0.205'; CoverDisc='0.060 0.085 0.125'
    CoverRing1='0.100 0.180 0.220'; CoverRing2='0.120 0.220 0.260'; CoverRule='0.120 0.170 0.230'
    CoverMuted='0.360 0.410 0.480'; Teal='0.160 0.700 0.640'; TealLight='0.550 0.900 0.850'
    GaugeTrack='0.075 0.102 0.153'; KpiBorder='0.120 0.160 0.230'; KpiFill='0.075 0.102 0.153'
    White='1 1 1'; Dark='0.043 0.063 0.102'
    PageBg='0.965 0.973 0.984'; TealDark='0.055 0.470 0.430'; Ink='0.090 0.120 0.170'; Muted='0.360 0.410 0.480'
    Rule='0.855 0.890 0.930'; CardBorder='0.855 0.890 0.930'; Track='0.890 0.910 0.940'; BarTrack='0.900 0.920 0.950'
    Healthy='0.160 0.700 0.640'; HealthyBar='0.100 0.550 0.440'; Review='0.900 0.630 0.200'
    Action='0.830 0.280 0.380'; ActionPill='0.690 0.180 0.280'; Info='0.480 0.420 0.850'; NA='0.400 0.460 0.550'
}

$script:MR_PAGES=[System.Collections.Generic.List[string]]::new()
$script:MR_CUR=''
$script:MR_DATA=$null

# --- Primitives -----------------------------------------------------------------

function Mr-N([double]$v){ return $v.ToString('0.##',$script:MR_INV) }
function Mr-Op([string]$s){ $script:MR_CUR += $s + "`n" }
function Mr-Escape([string]$s){
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
function Mr-Width([string]$t,[double]$size){ return $t.Length*$size*0.52 }
function Mr-Text([double]$x,[double]$y,[string]$txt,[string]$font,[double]$size,[string]$color){
    Mr-Op "$color rg"
    Mr-Op ("BT /{0} {1} Tf {2} {3} Td ({4}) Tj ET" -f $font, (Mr-N $size), (Mr-N $x), (Mr-N $y), (Mr-Escape $txt))
}
function Mr-TextRight([double]$right,[double]$y,[string]$txt,[string]$font,[double]$size,[string]$color){
    Mr-Text ($right - (Mr-Width $txt $size)) $y $txt $font $size $color
}
function Mr-TextCenter([double]$center,[double]$y,[string]$txt,[string]$font,[double]$size,[string]$color){
    Mr-Text ($center - (Mr-Width $txt $size)/2) $y $txt $font $size $color
}
# Shorten text to fit a width, ending with '.' when cut.
function Mr-Fit([string]$t,[double]$size,[double]$maxW){
    if((Mr-Width $t $size) -le $maxW){ return $t }
    $max=[int][Math]::Floor($maxW/($size*0.52))
    if($max -lt 2){ return '' }
    return $t.Substring(0,$max-1)+'.'
}
# Greedy word wrap using the same width estimate.
function Mr-Wrap([string]$t,[double]$size,[double]$maxW){
    $lines=[System.Collections.Generic.List[string]]::new()
    $cur=''
    foreach($word in ($t -split ' ')){
        if($word -eq ''){ continue }
        $test=if($cur){ "$cur $word" } else { $word }
        if($cur -and (Mr-Width $test $size) -gt $maxW){ $lines.Add($cur); $cur=$word } else { $cur=$test }
    }
    if($cur){ $lines.Add($cur) }
    return ,$lines.ToArray()
}
function Mr-Rect([double]$x,[double]$y,[double]$w,[double]$h,[string]$color){
    Mr-Op "$color rg"
    Mr-Op ("{0} {1} {2} {3} re f" -f (Mr-N $x),(Mr-N $y),(Mr-N $w),(Mr-N $h))
}
function Mr-Line([double]$x1,[double]$y1,[double]$x2,[double]$y2,[double]$w,[string]$color){
    Mr-Op "$color RG"
    Mr-Op ("{0} w" -f (Mr-N $w))
    Mr-Op ("{0} {1} m {2} {3} l S" -f (Mr-N $x1),(Mr-N $y1),(Mr-N $x2),(Mr-N $y2))
}
# Rounded rectangle; corner curves use half-radius handles like the Linux renderer.
function Mr-RoundRect([double]$x,[double]$y,[double]$w,[double]$h,[double]$r,[string]$color){
    $k=$r/2; $x2=$x+$w; $y2=$y+$h
    Mr-Op "$color rg"
    Mr-Op ("{0} {1} m" -f (Mr-N ($x+$r)),(Mr-N $y))
    Mr-Op ("{0} {1} l" -f (Mr-N ($x2-$r)),(Mr-N $y))
    Mr-Op ("{0} {1} {2} {3} {4} {5} c" -f (Mr-N ($x2-$r+$k)),(Mr-N $y),(Mr-N $x2),(Mr-N ($y+$r-$k)),(Mr-N $x2),(Mr-N ($y+$r)))
    Mr-Op ("{0} {1} l" -f (Mr-N $x2),(Mr-N ($y2-$r)))
    Mr-Op ("{0} {1} {2} {3} {4} {5} c" -f (Mr-N $x2),(Mr-N ($y2-$r+$k)),(Mr-N ($x2-$r+$k)),(Mr-N $y2),(Mr-N ($x2-$r)),(Mr-N $y2))
    Mr-Op ("{0} {1} l" -f (Mr-N ($x+$r)),(Mr-N $y2))
    Mr-Op ("{0} {1} {2} {3} {4} {5} c" -f (Mr-N ($x+$r-$k)),(Mr-N $y2),(Mr-N $x),(Mr-N ($y2-$r+$k)),(Mr-N $x),(Mr-N ($y2-$r)))
    Mr-Op ("{0} {1} l" -f (Mr-N $x),(Mr-N ($y+$r)))
    Mr-Op ("{0} {1} {2} {3} {4} {5} c" -f (Mr-N $x),(Mr-N ($y+$r-$k)),(Mr-N ($x+$r-$k)),(Mr-N $y),(Mr-N ($x+$r)),(Mr-N $y))
    Mr-Op 'f'
}
# White card with a 1pt border (outer border fill, inner white fill).
function Mr-Card([double]$x,[double]$y,[double]$w,[double]$h,[double]$r){
    Mr-RoundRect $x $y $w $h $r $script:MR_C.CardBorder
    Mr-RoundRect ($x+1) ($y+1) ($w-2) ($h-2) ($r-1) $script:MR_C.White
}
function Mr-CirclePath([double]$cx,[double]$cy,[double]$r){
    $k=0.5523*$r
    Mr-Op ("{0} {1} m" -f (Mr-N $cx),(Mr-N ($cy+$r)))
    Mr-Op ("{0} {1} {2} {3} {4} {5} c" -f (Mr-N ($cx+$k)),(Mr-N ($cy+$r)),(Mr-N ($cx+$r)),(Mr-N ($cy+$k)),(Mr-N ($cx+$r)),(Mr-N $cy))
    Mr-Op ("{0} {1} {2} {3} {4} {5} c" -f (Mr-N ($cx+$r)),(Mr-N ($cy-$k)),(Mr-N ($cx+$k)),(Mr-N ($cy-$r)),(Mr-N $cx),(Mr-N ($cy-$r)))
    Mr-Op ("{0} {1} {2} {3} {4} {5} c" -f (Mr-N ($cx-$k)),(Mr-N ($cy-$r)),(Mr-N ($cx-$r)),(Mr-N ($cy-$k)),(Mr-N ($cx-$r)),(Mr-N $cy))
    Mr-Op ("{0} {1} {2} {3} {4} {5} c" -f (Mr-N ($cx-$r)),(Mr-N ($cy+$k)),(Mr-N ($cx-$k)),(Mr-N ($cy+$r)),(Mr-N $cx),(Mr-N ($cy+$r)))
}
function Mr-Dot([double]$cx,[double]$cy,[double]$r,[string]$color){
    Mr-Op "$color rg"; Mr-CirclePath $cx $cy $r; Mr-Op 'f'
}
function Mr-Ring([double]$cx,[double]$cy,[double]$r,[double]$w,[string]$color){
    Mr-Op "$color RG"; Mr-Op ("{0} w" -f (Mr-N $w)); Mr-CirclePath $cx $cy $r; Mr-Op 'S'
}
# Gauge arc: clockwise from 12 o'clock, drawn as a polyline (Linux: round(pct*80) segments).
function Mr-Arc([double]$cx,[double]$cy,[double]$r,[double]$w,[string]$color,[double]$fraction){
    if($fraction -le 0){ return }
    if($fraction -gt 1){ $fraction=1 }
    $segments=[Math]::Max(1,[int][Math]::Round($fraction*80))
    Mr-Op "$color RG"; Mr-Op ("{0} w" -f (Mr-N $w))
    for($i=0;$i -le $segments;$i++){
        $angle=(2*[Math]::PI*$fraction*$i/$segments)
        $px=$cx+$r*[Math]::Sin($angle); $py=$cy+$r*[Math]::Cos($angle)
        $op=if($i -eq 0){'m'}else{'l'}
        Mr-Op ("{0} {1} {2}" -f $px.ToString('0.00',$script:MR_INV),$py.ToString('0.00',$script:MR_INV),$op)
    }
    Mr-Op 'S'
}
function Mr-NewPage(){
    if($script:MR_CUR){ $script:MR_PAGES.Add($script:MR_CUR) }
    $script:MR_CUR=''
}

# --- Status vocabulary ------------------------------------------------------------

function Mr-StatusWord([string]$s){
    switch($s){ 'pass'{'Healthy'} 'warn'{'Review'} 'fail'{'Action'} 'info'{'Info'} default{'N/A'} }
}
function Mr-StatusColor([string]$s){
    switch($s){ 'pass'{$script:MR_C.Healthy} 'warn'{$script:MR_C.Review} 'fail'{$script:MR_C.Action} 'info'{$script:MR_C.Info} default{$script:MR_C.NA} }
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
        'pass'{ return 'pass' } 'ok'{ return 'pass' } 'warn'{ return 'warn' }
        'fail'{ return 'fail' } 'critical'{ return 'fail' }
    }
    return 'na'
}

$script:MR_PILLARS=@(
    @('backup','Backup & Recovery'), @('mail_flow','Mail Flow & DNS'), @('tls','Transport Security'),
    @('access','Access & Authentication'), @('threat','Threat Protection'), @('resources','Server Resources'),
    @('os_update','OS & Patching'), @('monitoring','Monitoring & Watchdog'), @('database','Database Platform')
)
# Short operational-area names used in the narrative text.
$script:MR_AREA_NAMES=@{
    'DNS & Mail Flow Verification'='Mail Flow'; 'Logging'='Logging'
    'Backup, Watchdog and Monitoring'='Backup and Monitoring'; 'Migration Safety'='Migration Safety'
    'Storage, Certificates and Services'='Storage and Certificates'; 'SMTP Delivery Settings'='SMTP Delivery'
    'SMTP Protocol Hardening'='SMTP Hardening'; 'Intrusion Prevention - Block Rules'='Intrusion Prevention'
    'Rejection Rules and Access'='Access Controls'; 'Archive Settings'='Archiving'
    'Protocol and Access Hardening'='Protocol Hardening'; 'APP OS / Infrastructure'='Infrastructure'
    'Database'='Database'; 'MySQL Server (Remote DB)'='Remote Database'
}
# Recommended-action catalogue: title, remediation text and impact rank
# (lower = higher impact). Items not listed rank after these, in checklist order.
$script:MR_ACTIONS=@{
    'Change Admin Port'=@('Admin Port','Move the admin interface off the default port.',10)
    'Set customers-stat@parsavan.com'=@('Alert Mailbox','Set a monitored admin mailbox for alerts.',20)
    'Set Admin Email'=@('Admin Email','Set a monitored admin mailbox for alerts.',25)
    'Change Admin URL'=@('Admin URL','Move the admin interface off the default URL.',30)
    'Set Directory Cache Schedule'=@('Directory Cache Schedule','Schedule the Directory Cache rebuild during a low-traffic window.',40)
    'Swap Usage (7 days)'=@('Swap Usage','Investigate sustained swap use; add RAM or reduce memory pressure.',50)
    'Backup Emails'=@('Backup Emails','Restore this resilience control and verify it during the next maintenance window.',60)
}
function Mr-DefaultActionText([string]$section){
    switch -Wildcard ($section){
        'Backup*'                { return 'Restore this resilience control and verify it during the next maintenance window.' }
        'DNS*'                   { return 'Correct the DNS or mail-flow setting and re-test delivery.' }
        'Logging'                { return 'Enable this log so incidents can be investigated.' }
        'APP OS*'                { return 'Bring this infrastructure control back within the baseline.' }
        'Database'               { return 'Review the database platform setting with the service owner.' }
        'Storage*'               { return 'Review this service setting and remediate during the next maintenance window.' }
        default                  { return 'Apply the recommended hardening setting and confirm mail flow afterwards.' }
    }
}
function Mr-DefaultActionTitle([string]$label){
    $t=$label -replace '^(Change|Set|Enable|Check)\s+',''
    $t=$t -replace '\s*\([^)]*\)\s*$',''
    return $t
}

# --- Model ------------------------------------------------------------------------

function ConvertTo-ManagementChecklist(){
    $sections=[System.Collections.Generic.List[string]]::new()
    $items=@{}
    $rows=$script:CHECKLIST_CAPTURED
    if($null -eq $rows){ return @{sections=$sections; items=$items} }
    foreach($r in $rows){
        $sec=[string]$r.section
        if([string]::IsNullOrEmpty($sec)){ $sec='General' }
        if(-not $items.ContainsKey($sec)){
            $items[$sec]=[System.Collections.Generic.List[object]]::new()
            [void]$sections.Add($sec)
        }
        $value=[string]$r.value
        $status=switch([string]$r.bkind){
            'PASS'     { 'pass' }
            'WARN'     { 'warn' }
            'CRITICAL' { 'fail' }
            default {
                if([string]$r.btext -eq 'SKIP' -or $value -in @('','(empty)','N/A','n/a','not applicable','not collected')){ 'na' } else { 'info' }
            }
        }
        [void]$items[$sec].Add([pscustomobject]@{
            id=($items[$sec].Count + 1)
            label=[string]$r.label
            value=$value
            status=$status
        })
    }
    return @{sections=$sections; items=$items}
}

$script:MR_SECTION_PILLARS=@{
    'DNS & Mail Flow Verification'=@('mail_flow')
    'Logging'=@()
    'Backup, Watchdog and Monitoring'=@('backup','monitoring')
    'Migration Safety'=@()
    'Storage, Certificates and Services'=@('tls','threat')
    'SMTP Delivery Settings'=@()
    'SMTP Protocol Hardening'=@()
    'Intrusion Prevention - Block Rules'=@()
    'Rejection Rules and Access'=@('access')
    'Archive Settings'=@()
    'Protocol and Access Hardening'=@('access')
    'APP OS / Infrastructure'=@('resources','os_update')
    'Database'=@('database')
    'MySQL Server (Remote DB)'=@()
}

function Get-SectionHealthStatus([string]$sec){
    $st=@('na')
    if($script:MR_SECTION_PILLARS.ContainsKey($sec)){
        foreach($p in $script:MR_SECTION_PILLARS[$sec]){
            $st+=(Mr-HealthStatus $p)
        }
    }
    # worst: fail > warn > pass > info > na
    if($st -contains 'fail'){ return 'fail' }
    if($st -contains 'warn'){ return 'warn' }
    if($st -contains 'pass'){ return 'pass' }
    if($st -contains 'info'){ return 'info' }
    return 'na'
}

function Get-ManagementModel([hashtable]$checklist){
    $m=@{ Total=0; Pass=0; Warn=0; Fail=0; Info=0; Na=0 }
    $sectionModels=[System.Collections.Generic.List[object]]::new()
    $actions=[System.Collections.Generic.List[object]]::new()
    $secIndex=0
    foreach($sec in $checklist.sections){
        $s=@{ Name=$sec; Pass=0; Warn=0; Fail=0; Info=0; Na=0 }
        foreach($item in $checklist.items[$sec]){
            $m.Total++
            switch($item.status){
                'pass' { $s.Pass++; $m.Pass++ }
                'warn' { $s.Warn++; $m.Warn++ }
                'fail' { $s.Fail++; $m.Fail++ }
                'info' { $s.Info++; $m.Info++ }
                default { $s.Na++; $m.Na++ }
            }
            if($item.status -eq 'fail' -or $item.status -eq 'warn'){
                $entry=$null
                if($script:MR_ACTIONS.ContainsKey($item.label)){ $entry=$script:MR_ACTIONS[$item.label] }
                $title=if($entry){ $entry[0] } else { Mr-DefaultActionTitle $item.label }
                $text=if($entry){ $entry[1] } else { Mr-DefaultActionText $sec }
                $rank=if($entry){ [int]$entry[2] } else { 1000 + $secIndex*100 + [int]$item.id }
                [void]$actions.Add([pscustomobject]@{
                    Severity=$(if($item.status -eq 'fail'){0}else{1})
                    Rank=$rank
                    Status=$item.status
                    Title=$title
                    Section=$sec
                    Text=$text
                })
            }
        }
        # Combine checklist status with health pillar status - worst wins
        $checklistStatus=if($s.Fail -gt 0){'fail'}elseif($s.Warn -gt 0){'warn'}elseif($s.Pass -gt 0){'pass'}elseif($s.Info -gt 0){'info'}else{'na'}
        $healthStatus=Get-SectionHealthStatus $sec
        # Priority: fail > warn > pass > info > na
        $statusPriority=@{'fail'=4; 'warn'=3; 'pass'=2; 'info'=1; 'na'=0}
        $s.Status=if($statusPriority[$healthStatus] -gt $statusPriority[$checklistStatus]){ $healthStatus } else { $checklistStatus }
        [void]$sectionModels.Add([pscustomobject]$s)
        $secIndex++
    }
    $m.Sections=$sectionModels
    # Action before review, then impact rank (catalogue, else checklist order).
    $m.Actions=@($actions | Sort-Object -Property Severity, Rank)
    $scored=$m.Pass+$m.Warn+$m.Fail
    $m.Score=if($scored -gt 0){ [int][Math]::Round($m.Pass*100.0/$scored) } else { 0 }

    # Overall posture comes from the health engine summary.
    $overall=Mr-DataValue 'health.summary.overall'
    if($overall -notin @('pass','warn','fail')){
        $overall=if($m.Fail -gt 0){'fail'}elseif($m.Warn -gt 0){'warn'}else{'pass'}
    }
    $m.Overall=$overall
    $m.Posture=switch($overall){ 'fail'{'Action required'} 'warn'{'Review recommended'} default{'Healthy'} }

    # Key signals: health pillars that are not passing, failures first.
    $signals=[System.Collections.Generic.List[object]]::new()
    foreach($want in @('fail','warn')){
        foreach($p in $script:MR_PILLARS){
            if((Mr-HealthStatus $p[0]) -eq $want){
                [void]$signals.Add([pscustomobject]@{ Title=$p[1]; Status=$want; Message=(Mr-DataValue ("health.{0}.message" -f $p[0])) })
            }
        }
    }
    $m.Signals=$signals

    $areas=[System.Collections.Generic.List[string]]::new()
    foreach($a in $m.Actions){
        $name=$script:MR_AREA_NAMES[$a.Section]; if(-not $name){ $name=$a.Section }
        if(-not $areas.Contains($name)){ $areas.Add($name) }
        if($areas.Count -ge 2){ break }
    }
    $m.Areas=($areas -join ' and ')
    return $m
}

# --- Page furniture -----------------------------------------------------------------

function Mr-LightPage([string]$eyebrow,[string]$title,[string]$subtitle,[int]$pageNo){
    Mr-NewPage
    Mr-Rect 0 0 612 792 $script:MR_C.PageBg
    Mr-Text 44 766 'ICEWARP HEALTH ASSESSMENT' F2 6.8 $script:MR_C.TealDark
    Mr-TextRight 568 766 'MANAGEMENT SUMMARY' F1 6.8 $script:MR_C.Muted
    Mr-Line 44 754 568 754 0.6 $script:MR_C.Rule
    Mr-Text 44 732 $eyebrow F2 7.2 $script:MR_C.TealDark
    Mr-Text 44 710 $title F2 19 $script:MR_C.Ink
    Mr-Text 44 694 $subtitle F1 8.4 $script:MR_C.Muted
    Mr-Line 44 682 568 682 0.8 $script:MR_C.Rule
    Mr-Line 44 40 568 40 0.5 $script:MR_C.Rule
    Mr-Text 44 27 'PARSAVAN  |  ICEWARP HEALTH AGENT' F1 6.2 $script:MR_C.Muted
    Mr-Text 234 27 'CONFIDENTIAL' F1 6.2 $script:MR_C.Muted
    Mr-TextRight 568 27 ("Page {0}" -f $pageNo) F1 6.2 $script:MR_C.Muted
}
function Mr-Pill([double]$x,[double]$y,[string]$status){
    $label=switch($status){ 'fail'{'FAIL'} 'warn'{'WARN'} 'pass'{'HEALTHY'} 'info'{'INFO'} default{'N/A'} }
    $fill=if($status -eq 'fail'){ $script:MR_C.ActionPill } else { $script:MR_C.Review }
    $ink=if($status -eq 'fail'){ $script:MR_C.White } else { $script:MR_C.Dark }
    Mr-RoundRect $x $y 54 14 7 $fill
    Mr-TextCenter ($x+27) ($y+3) $label 'Helvetica-Bold' 8 $ink
}

# --- Page 1: cover ----------------------------------------------------------------------

function Mr-Cover($m,[string]$date,[string]$version){
    Mr-NewPage
    $C=$script:MR_C
    Mr-Rect 0 0 612 792 $C.CoverBg
    for($x=0;$x -le 612;$x+=36){ Mr-Line $x 0 $x 792 0.3 $C.CoverGrid }
    for($y=0;$y -le 792;$y+=36){ Mr-Line 0 $y 612 $y 0.3 $C.CoverGrid }
    Mr-Dot 512 604 192 $C.CoverDisc
    Mr-Ring 512 604 176 0.8 $C.CoverRing1
    Mr-Ring 512 604 132 0.6 $C.CoverRing2

    Mr-Rect 44 716 8 8 $C.Teal
    Mr-Text 58 716 'PARSAVAN' F2 8 $C.White
    Mr-Text 126 716 'ICEWARP HEALTH AGENT' F1 7 $C.CoverMuted
    Mr-TextRight 568 716 ("CHECKLIST v{0}" -f $script:PDF_CHECKLIST_VERSION) F1 7 $C.TealLight

    Mr-Text 44 640 'MANAGEMENT SUMMARY' F2 8.5 $C.TealLight
    Mr-Text 44 600 'Health Check Report' F2 30 $C.White
    Mr-Text 44 570 'Mail security, resilience and service health at a glance.' F1 10.5 $C.CoverMuted
    Mr-Line 44 548 156 548 2 $C.Teal

    $company=Mr-DataValue 'general.company'; if(-not $company){ $company=Mr-DataValue 'domain.primary.name' }; if(-not $company){ $company='IceWarp server' }
    $domain=Mr-DataValue 'domain.primary.name'
    $hostName=Mr-DataValue 'agent.hostname'; if(-not $hostName){ $hostName='unknown' }
    Mr-Text 44 518 'PREPARED FOR' F2 6.8 $C.TealLight
    Mr-Text 44 492 (Mr-Fit $company 19 380) F2 19 $C.White
    if($domain){ Mr-Text 44 472 $domain F1 10 $C.CoverMuted }
    Mr-Text 44 452 (Mr-Fit ("Server: {0}   |   Generated: {1}" -f $hostName, $date) 8 380) F1 8 $C.CoverMuted
    Mr-Text 44 430 'OVERALL POSTURE' F1 6.8 $C.CoverMuted

    $pillFill=switch($m.Overall){ 'fail'{$C.ActionPill} 'warn'{$C.Review} default{$C.HealthyBar} }
    $pillInk=if($m.Overall -eq 'warn'){ $C.Dark } else { $C.White }
    $ringColor=switch($m.Overall){ 'fail'{$C.Action} 'warn'{$C.Review} default{$C.Teal} }
    $overallWord=switch($m.Overall){ 'fail'{'FAIL'} 'warn'{'WARNING'} default{'HEALTHY'} }
    $overallColor=switch($m.Overall){ 'fail'{$C.Action} 'warn'{$C.Review} default{$C.Healthy} }
    Mr-RoundRect 44 398 196 30 8 $pillFill
    Mr-Text 56 408 ("{0}  |  {1}% pass rate" -f $m.Posture, $m.Score) F2 8.6 $pillInk
    Mr-Text 44 366 ("{0} controls assessed across {1} operational areas" -f $m.Total, $m.Sections.Count) F1 8.2 $C.CoverMuted
    # Overall status word (CRITICAL/WARNING/HEALTHY) like Linux PDF
    Mr-Rect 44 442 540 44 $overallColor
    Mr-Text 50 466 ("OVERALL: {0}" -f $overallWord) F2 15 $C.White

    Mr-Ring 500 420 48 8 $C.GaugeTrack
    Mr-Arc 500 420 48 5 $ringColor ($m.Score/100.0)
    Mr-Dot 500 420 36 $C.CoverBg
    Mr-TextCenter 500 424 ("{0}%" -f $m.Score) F2 18 $C.White
    Mr-TextCenter 500 406 'CONTROL SCORE' F1 5.8 $C.CoverMuted

    $kpis=@(
        @($m.Total,'CONTROLS',$C.Teal), @($m.Pass,'HEALTHY',$C.HealthyBar),
        @($m.Warn,'REVIEW',$C.Review), @($m.Fail,'ACTION',$C.Action)
    )
    for($i=0;$i -lt 4;$i++){
        $x=44+$i*134
        Mr-RoundRect $x 246 122 76 9 $C.KpiBorder
        Mr-RoundRect ($x+1) 247 120 74 8 $C.KpiFill
        Mr-Line $x 319 ($x+122) 319 2 $kpis[$i][2]
        Mr-Text ($x+12) 290 ([string]$kpis[$i][0]) F2 22 $C.White
        Mr-Text ($x+12) 264 $kpis[$i][1] F1 6.8 $C.CoverMuted
    }

    $technician=Mr-DataValue 'general.technician'
    Mr-Line 44 96 568 96 0.5 $C.CoverRule
    Mr-Text 44 76 (Mr-Fit ("Technician: {0}" -f $technician) 7 200) F1 7 $C.CoverMuted
    Mr-Text 264 76 ("Based on IceWarp CheckList v{0}" -f $script:PDF_CHECKLIST_VERSION) F1 7 $C.CoverMuted
    Mr-TextRight 568 76 'CONFIDENTIAL' F2 7 $C.TealLight
    Mr-Text 44 58 'This report is a management summary. The technical report contains item-level evidence and raw data.' F1 6.4 $C.CoverMuted
}

# --- Page 2: executive overview ---------------------------------------------------------

function Mr-Plural([int]$n,[string]$one,[string]$many){ if($n -eq 1){ return "$n $one" }; return "$n $many" }

function Mr-ExecutiveOverview($m){
    $C=$script:MR_C
    Mr-LightPage '01  /  EXECUTIVE OVERVIEW' 'Executive overview' 'What the assessment found and where to focus first.' 2

    $lead="The assessment covered {0} controls across {1} operational areas." -f $m.Total, $m.Sections.Count
    if($m.Fail -gt 0){
        $para="{0} {1} and {2}; the highest-impact gaps are in {3}." -f $lead, (Mr-Plural $m.Fail 'control requires action' 'controls require action'), (Mr-Plural $m.Warn 'needs review' 'need review'), $m.Areas
    } elseif($m.Warn -gt 0){
        $para="{0} No controls require action and {1}; the main review items are in {2}." -f $lead, (Mr-Plural $m.Warn 'needs review' 'need review'), $m.Areas
    } else {
        $para="{0} All scored controls meet the baseline." -f $lead
    }
    $y=664
    foreach($line in (Mr-Wrap $para 9.4 415)){ Mr-Text 44 $y $line F1 9.4 $C.Ink; $y-=13 }
    $label=$y+13-23

    # Control distribution: stacked bar over every control, last segment takes the remainder.
    Mr-Text 44 $label 'CONTROL DISTRIBUTION' F2 6.6 $C.Muted
    Mr-RoundRect 44 ($label-22) 524 8 4 $C.Track
    $parts=@(@($m.Pass,$C.HealthyBar,'Healthy'),@($m.Warn,$C.Review,'Review'),@($m.Fail,$C.Action,'Action'),@($m.Info,$C.Info,'Info'),@($m.Na,$C.NA,'N/A'))
    $lastNonZero=-1; for($i=0;$i -lt $parts.Count;$i++){ if($parts[$i][0] -gt 0){ $lastNonZero=$i } }
    $x=44
    for($i=0;$i -lt $parts.Count;$i++){
        $n=[int]$parts[$i][0]
        if($n -le 0 -or $m.Total -le 0){ continue }
        $w=if($i -eq $lastNonZero){ 568-$x } else { [Math]::Floor($n*524.0/$m.Total) }
        Mr-Rect $x ($label-22) $w 8 $parts[$i][1]
        $x+=$w
    }
    for($i=0;$i -lt $parts.Count;$i++){
        $lx=44+$i*104
        Mr-Dot ($lx+4) ($label-35) 4 $(if($i -eq 0){$C.Healthy}else{$parts[$i][1]})
        Mr-Text ($lx+13) ($label-38) ("{0}  {1}" -f $parts[$i][2], $parts[$i][0]) F1 7.4 $C.Muted
    }

    $head=$label-68
    Mr-Text 44 $head 'PRIORITY ACTIONS' F2 6.6 $C.Muted
    Mr-Text 378 $head 'KEY SIGNALS' F2 6.6 $C.Muted

    $top=$head-12
    $priority=@($m.Actions | Select-Object -First 4)
    if($priority.Count -eq 0){
        Mr-Card 44 ($top-64) 316 64 6
        Mr-Rect 44 ($top-64) 3 64 $C.Healthy
        Mr-Dot 62 ($top-16) 4 $C.Healthy
        Mr-Text 72 ($top-20) 'No priority actions' F2 8.8 $C.Ink
        Mr-Text 56 ($top-36) 'All operational areas' F1 6.3 $C.Muted
        Mr-Text 56 ($top-51) 'No control requires action or review.' F1 7.1 $C.Ink
    }
    foreach($a in $priority){
        $color=Mr-StatusColor $a.Status
        Mr-Card 44 ($top-64) 316 64 6
        Mr-Rect 44 ($top-64) 3 64 $color
        Mr-Dot 62 ($top-16) 4 $color
        Mr-Text 72 ($top-20) (Mr-Fit $a.Title 8.8 218) F2 8.8 $C.Ink
        Mr-Pill 296 ($top-22) $a.Status
        Mr-Text 56 ($top-36) (Mr-Fit $a.Section 6.3 290) F1 6.3 $C.Muted
        Mr-Text 56 ($top-51) (Mr-Fit $a.Text 7.1 295) F1 7.1 $C.Ink
        $top-=72
    }

    $top=$head-16
    $signals=@($m.Signals | Select-Object -First 4)
    if($signals.Count -eq 0){
        $signals=@([pscustomobject]@{ Title='All pillars'; Status='pass'; Message='All nine health pillars pass.' })
    }
    foreach($s in $signals){
        Mr-Card 378 ($top-58) 190 58 6
        Mr-Dot 390 ($top-12) 4 (Mr-StatusColor $s.Status)
        Mr-Text 400 ($top-19) (Mr-Fit ($s.Title.ToUpperInvariant()) 5.9 160) F1 5.9 $C.Muted
        Mr-Text 390 ($top-32) (Mr-StatusWord $s.Status) F2 8.6 $C.Ink
        [string[]]$lines=Mr-Wrap $s.Message 5.8 120
        for($i=0;$i -lt [Math]::Min(2,$lines.Count);$i++){ Mr-Text 390 ($top-43-7*$i) $lines[$i] F1 5.8 $C.Muted }
        $top-=66
    }

    if($m.Fail -gt 0){
        $lead2=if($m.Score -ge 80){ 'The platform is largely healthy, but the material risk sits in' } else { 'The platform needs remediation; the material risk sits in' }
        $takeaway="{0} {1}. Resolve those actions first, then re-run the assessment to confirm closure." -f $lead2, $m.Areas
    } elseif($m.Warn -gt 0){
        $takeaway="No controls require immediate action. Review the flagged items in {0} during the next maintenance window, then re-run the assessment." -f $m.Areas
    } else {
        $takeaway='All assessed controls meet the baseline. Keep the current configuration and re-run the assessment on schedule.'
    }
    Mr-Card 44 150 524 72 7
    Mr-Rect 44 150 3 72 $C.Teal
    Mr-Text 60 208 'MANAGEMENT TAKEAWAY' F2 6.6 $C.TealDark
    $y=194
    [string[]]$takeawayLines=Mr-Wrap $takeaway 8.2 415
    for($i=0;$i -lt [Math]::Min(4,$takeawayLines.Count);$i++){ Mr-Text 60 $y $takeawayLines[$i] F1 8.2 $C.Ink; $y-=10 }
}

# --- Page 3: control areas -----------------------------------------------------------------

function Mr-ControlAreas($m){
    $C=$script:MR_C
    $sections=@($m.Sections)
    $pageNo=3
    Mr-LightPage '02  /  CONTROL AREAS' 'Control areas' 'How each operational area performed across the full checklist.' $pageNo
    $bottom=664
    for($i=0;$i -lt $sections.Count;$i++){
        $slot=$i % 14
        if($i -gt 0 -and $slot -eq 0){
            $pageNo++
            Mr-LightPage '02  /  CONTROL AREAS' 'Control areas (continued)' 'How each operational area performed across the full checklist.' $pageNo
        }
        $s=$sections[$i]
        $x=44+($slot % 2)*270
        $top=664-[Math]::Floor($slot/2)*68
        Mr-Card $x ($top-60) 254 60 6
        $color=Mr-StatusColor $s.Status
        Mr-Dot ($x+14) ($top-16) 4 $color
        Mr-Text ($x+25) ($top-19) (Mr-Fit $s.Name 8.2 190) F2 8.2 $C.Ink
        Mr-TextRight ($x+244) ($top-19) (Mr-StatusWord $s.Status) F2 6.4 $color
        $statusText=switch($s.Status){ 'fail'{'FAIL'} 'warn'{'REVIEW'} 'pass'{'HEALTHY'} 'info'{'INFO'} default{'N/A'} }
        Mr-Text ($x+14) ($top-44) ("Status: " + $statusText) F2 6.4 $color
        $scored=$s.Pass+$s.Warn+$s.Fail+$s.Info
        if($scored -eq 0){
            Mr-Text ($x+14) ($top-35) 'No applicable controls' F1 6.1 $C.Muted
        } else {
            $counts="{0} healthy  |  {1} review  |  {2} action" -f $s.Pass, $s.Warn, $s.Fail
            if($s.Info -gt 0){ $counts+=("  |  {0} info" -f $s.Info) }
            Mr-Text ($x+14) ($top-35) $counts F1 6 $C.Muted
            Mr-Rect ($x+14) ($top-50) 226 4 $C.BarTrack
            $segs=@(@($s.Pass,$C.HealthyBar),@($s.Warn,$C.Review),@($s.Fail,$C.Action),@($s.Info,$C.Info))
            $last=-1; for($k=0;$k -lt 4;$k++){ if($segs[$k][0] -gt 0){ $last=$k } }
            $bx=$x+14
            for($k=0;$k -lt 4;$k++){
                $n=[int]$segs[$k][0]
                if($n -le 0){ continue }
                $w=if($k -eq $last){ ($x+240)-$bx } else { [Math]::Floor($n*226.0/$scored) }
                Mr-Rect $bx ($top-50) $w 4 $segs[$k][1]
                $bx+=$w
            }
        }
        $bottom=$top-60
    }
    $label=$bottom-8
    Mr-Text 44 $label 'STATUS KEY' F2 6.6 $C.Muted
    $cardTop=$label-12
    Mr-Card 44 ($cardTop-58) 524 58 6
    $keyItems=@(@('Healthy','Meets the baseline',$C.Healthy),@('Review','Worth reviewing',$C.Review),@('Action','Needs remediation',$C.Action),@('Info / N/A','Context only',$C.Info))
    for($i=0;$i -lt 4;$i++){
        $kx=64+$i*126
        Mr-Dot $kx ($cardTop-22) 4 $keyItems[$i][2]
        Mr-Text ($kx+10) ($cardTop-25) $keyItems[$i][0] F2 7.6 $C.Ink
        Mr-Text ($kx+10) ($cardTop-38) $keyItems[$i][1] F1 6.4 $C.Muted
    }
    return $pageNo
}

# --- Page 4: recommended actions ------------------------------------------------------------

function Mr-RecommendedActions($m,[int]$pageNo){
    $C=$script:MR_C
    Mr-LightPage '03  /  RECOMMENDED ACTIONS' 'Recommended actions' 'Ordered by operational impact. The technical report lists every finding.' $pageNo
    $top=664
    $list=@($m.Actions | Select-Object -First 6)
    if($list.Count -eq 0){
        Mr-Card 44 ($top-56) 524 56 6
        Mr-Rect 44 ($top-56) 3 56 $C.Healthy
        Mr-Text 82 ($top-20) 'No remediation actions required' F2 8.8 $C.Ink
        Mr-Text 82 ($top-33) 'All operational areas' F1 6.3 $C.Muted
        Mr-Text 82 ($top-47) 'Every scored control meets the baseline.' F1 7.1 $C.Ink
        $top-=64
    }
    $n=0
    foreach($a in $list){
        $n++
        Mr-Card 44 ($top-56) 524 56 6
        Mr-Rect 44 ($top-56) 3 56 (Mr-StatusColor $a.Status)
        Mr-Text 56 ($top-18) ("{0}." -f $n) F2 8 $C.TealDark
        Mr-Text 82 ($top-20) (Mr-Fit $a.Title 8.8 400) F2 8.8 $C.Ink
        Mr-Pill 504 ($top-22) $a.Status
        Mr-Text 82 ($top-33) (Mr-Fit $a.Section 6.3 410) F1 6.3 $C.Muted
        Mr-Text 82 ($top-47) (Mr-Fit $a.Text 7.1 470) F1 7.1 $C.Ink
        $top-=64
    }
    $label=$top+8-22
    Mr-Text 44 $label 'ASSESSMENT SCOPE' F2 6.6 $C.Muted
    $cardTop=$label-12
    Mr-Card 44 ($cardTop-58) 524 58 6
    $scope=@(@('STANDARD',("IceWarp CheckList v{0}" -f $script:PDF_CHECKLIST_VERSION)),@('EVIDENCE','Live collector data'),@('NEXT REVIEW','Next scheduled assessment'))
    for($i=0;$i -lt 3;$i++){
        $sx=58+$i*168
        Mr-Text $sx ($cardTop-22) $scope[$i][0] F1 5.8 $C.Muted
        Mr-Text $sx ($cardTop-38) $scope[$i][1] F2 7.8 $C.Ink
    }
    $y=$cardTop-58-18
    Mr-Text 44 $y 'NEXT STEP' F2 6.4 $C.TealDark
    $y-=14
    foreach($line in (Mr-Wrap 'Review the action list with the service owner, schedule the remediation window, then re-run the assessment to confirm closure.' 7.8 415)){
        Mr-Text 44 $y $line F1 7.8 $C.Ink; $y-=10
    }
}

# --- Writer ---------------------------------------------------------------------------------

function Mr-WriteFile([string]$OutPath){
    $n=$script:MR_PAGES.Count
    if($n -eq 0){ Write-Warning "management_report: nothing to render"; return $null }
    $nl="`n"
    $pageBase=3; $contentBase=$pageBase+$n; $fontBase=$contentBase+$n
    $total=$fontBase+3
    $offsets=@{}
    $body=[System.Text.StringBuilder]::new()
    [void]$body.Append("%PDF-1.4$nl")
    $offsets[1]=$body.Length
    [void]$body.Append("1 0 obj$($nl)<< /Type /Catalog /Pages 2 0 R >>$($nl)endobj$($nl)")
    $kids=""
    for($i=0;$i -lt $n;$i++){ $kids+="$($pageBase+$i) 0 R " }
    $offsets[2]=$body.Length
    [void]$body.Append("2 0 obj$($nl)<< /Type /Pages /Kids [ ${kids}] /Count $n >>$($nl)endobj$($nl)")
    $fontRes="/F1 $fontBase 0 R /F2 $($fontBase+1) 0 R /F3 $($fontBase+2) 0 R"
    for($i=0;$i -lt $n;$i++){
        $pageNum=$pageBase+$i; $contentNum=$contentBase+$i
        $offsets[$pageNum]=$body.Length
        [void]$body.Append("$pageNum 0 obj$($nl)<< /Type /Page /Parent 2 0 R /Resources << /Font << $fontRes >> >> /MediaBox [0 0 612 792] /Contents $contentNum 0 R >>$($nl)endobj$($nl)")
        $stream=$script:MR_PAGES[$i]
        $offsets[$contentNum]=$body.Length
        [void]$body.Append("$contentNum 0 obj$($nl)<< /Length $($stream.Length) >>$($nl)stream$($nl)$($stream)endstream$($nl)endobj$($nl)")
    }
    $names=@('Helvetica','Helvetica-Bold','Helvetica-Oblique')
    for($f=0;$f -lt 3;$f++){
        $offsets[$fontBase+$f]=$body.Length
        [void]$body.Append("$($fontBase+$f) 0 obj$($nl)<< /Type /Font /Subtype /Type1 /BaseFont /$($names[$f]) >>$($nl)endobj$($nl)")
    }
    $xrefPos=$body.Length
    [void]$body.Append("xref$($nl)0 $total$($nl)")
    [void]$body.Append("0000000000 65535 f $($nl)")
    for($obj=1;$obj -lt $total;$obj++){
        [void]$body.Append(("{0:D10} 00000 n $($nl)" -f [int]$offsets[$obj]))
    }
    [void]$body.Append("trailer$($nl)<< /Size $total /Root 1 0 R >>$($nl)startxref$($nl)$xrefPos$($nl)%%EOF$($nl)")
    [System.IO.File]::WriteAllText($OutPath,$body.ToString())
    return $OutPath
}

function Build-ManagementReportPdf([hashtable]$Data,[string]$OutPath,[string]$Version,[string]$Date){
    $script:MR_DATA=$Data
    $script:MR_PAGES=[System.Collections.Generic.List[string]]::new()
    $script:MR_CUR=''
    if($null -eq $script:CHECKLIST_CAPTURED -or $script:CHECKLIST_CAPTURED.Count -eq 0){
        # Capture the checklist without keeping the technical pages.
        $script:_PDF_PAGES=[System.Collections.Generic.List[string]]::new()
        $script:_PDF_CUR=""; $script:_PDF_Y=$script:PDF_TOP_Y; $script:_PDF_ROW_INDEX=0
        Render-Checklist $Data
    }
    $displayDate=$Date
    $parsed=[datetime]::MinValue
    if([datetime]::TryParseExact($Date,'yyyy-MM-dd',$script:MR_INV,[System.Globalization.DateTimeStyles]::None,[ref]$parsed)){
        $displayDate=$parsed.ToString('dd MMMM yyyy',$script:MR_INV)
    }
    $model=Get-ManagementModel (ConvertTo-ManagementChecklist)
    Mr-Cover $model $displayDate $Version
    Mr-ExecutiveOverview $model
    $lastPage=Mr-ControlAreas $model
    Mr-RecommendedActions $model ($lastPage+1)
    Mr-NewPage
    return (Mr-WriteFile $OutPath)
}
