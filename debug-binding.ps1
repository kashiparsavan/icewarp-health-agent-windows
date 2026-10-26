$ErrorActionPreference = 'Stop'

function Test-StringParam {
    param([string]$Domain)
    Write-Output "got: type=$($Domain.GetType().FullName) value='$Domain'"
}

Write-Output "=== 1. plain string ==="
try { Test-StringParam -Domain 'mtitc.ir' } catch { Write-Output "FAIL: $($_.Exception.Message)" }

Write-Output "=== 2. null ==="
try { Test-StringParam -Domain $null } catch { Write-Output "FAIL: $($_.Exception.Message)" }

Write-Output "=== 3. empty string ==="
try { Test-StringParam -Domain '' } catch { Write-Output "FAIL: $($_.Exception.Message)" }

Write-Output "=== 4. single-element array ==="
try { Test-StringParam -Domain @('mtitc.ir') } catch { Write-Output "FAIL: $($_.Exception.Message)" }

Write-Output "=== 5. two-element array ==="
try { Test-StringParam -Domain @('mtitc.ir', 'other') } catch { Write-Output "FAIL: $($_.Exception.Message)" }

Write-Output "=== 6. array containing an array ==="
try { Test-StringParam -Domain @(@('mtitc.ir')) } catch { Write-Output "FAIL: $($_.Exception.Message)" }

Write-Output "=== 7. array containing a hashtable ==="
try { Test-StringParam -Domain @(@{x=1}) } catch { Write-Output "FAIL: $($_.Exception.Message)" }

Write-Output "=== 8. multi-line string ==="
try { Test-StringParam -Domain "##internalservicedomain.icewarp.com##`r`n`r`nmtitc.ir`r`n" } catch { Write-Output "FAIL: $($_.Exception.Message)" }