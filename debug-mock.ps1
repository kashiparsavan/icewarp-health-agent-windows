$ErrorActionPreference = 'Stop'
$root = "C:\Projects\icewarp-health-agent-windows"
. "$root\windows\lib\Config.ps1"
. "$root\windows\lib\Common.ps1"
. "$root\windows\lib\Logging.ps1"
. "$root\windows\lib\IceWarpTool.ps1"
. "$root\windows\lib\Json.ps1"

$config = Get-AgentConfig -Root "$root\windows"
$ctx = Initialize-AgentContext -Root "$root\windows" -Config $config -Version '0.1.0'

# Mock the raw tool.exe output for "list domain" exactly as returned live.
$mockDomainOutput = "`r`n##internalservicedomain.icewarp.com##`r`n`r`nmtitc.ir`r`n"

# Override Invoke-IceWarpToolList to return our mock.
function global:Invoke-IceWarpToolList {
    param([string]$ToolPath, [string]$ListType, [int]$TimeoutSeconds = 10)
    if ($ListType -eq 'domain') { return $mockDomainOutput }
    return ''
}

Write-Output "=== Get-IceWarpDomainList raw ==="
$r = Get-IceWarpDomainList -Context $ctx
Write-Output "type=$($r.GetType().FullName) count=$($r.Count)"
foreach ($e in $r) { Write-Output "  elem type=$($e.GetType().FullName) value='$e'" }

Write-Output "=== @(wrapped) ==="
$w = @($r)
Write-Output "type=$($w.GetType().FullName) count=$($w.Count)"
foreach ($e in $w) { Write-Output "  elem type=$($e.GetType().FullName) value='$e'" }

Write-Output "=== foreach domain, then call setting ==="
foreach ($d in @($w)) {
    Write-Output "about to call with domain type=$($d.GetType().FullName) value='$d'"
    try {
        $s = Get-IceWarpDomainSetting -Domain $d -Name 'D_NumberLimit' -Context $ctx
        Write-Output "  setting result='$s'"
    } catch {
        Write-Output "  FAILED: $($_.Exception.Message)"
    }
}