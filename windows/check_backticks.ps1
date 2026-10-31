$b = [System.IO.File]::ReadAllBytes("C:\Projects\icewarp-health-agent-windows\windows\lib\ReportTechnical.ps1")
for($i=0; $i -lt $b.Length; $i++) {
    if($b[$i] -eq 96) {
        $prev = [char]$b[$i-1]
        $cur = [char]$b[$i]
        $next1 = [char]$b[$i+1]
        $next2 = [char]$b[$i+2]
        "Backtick at $i : [$prev][$cur][$next1][$next2]"
    }
}