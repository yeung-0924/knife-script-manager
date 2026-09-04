# 更新时间: 2026-09-04 14:59:35
# Test script: print one line per second for 10 seconds, then exit.
for ($i = 1; $i -le 10; $i++) {
    Write-Output "Second $i - $(Get-Date -Format 'HH:mm:ss')"
    Start-Sleep -Seconds 1
}
Write-Output "Test finished"

