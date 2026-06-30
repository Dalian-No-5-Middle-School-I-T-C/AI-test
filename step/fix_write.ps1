$ErrorActionPreference='SilentlyContinue'
$f = 'C:\Users\33554\Documents\learn\test\ark\step\entry\src\main\ets\pages\ChatPage.ets'
$lines = Get-Content $f
$fixed = $lines -join "`r`n"
[System.IO.File]::WriteAllText($f, $fixed, (New-Object System.Text.UTF8Encoding $true))
Write-Host "Done. Lines: $($lines.Length)"
