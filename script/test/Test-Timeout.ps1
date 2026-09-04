# 更新时间: 2026-09-04 16:57:08
# 控制台同步打印更新时间（从首行注释解析，便于用户贴日志时直接看到脚本版本时间）
try {
    $sp = $PSCommandPath; if (-not $sp) { $sp = $MyInvocation.MyCommand.Path }
    if ($sp) {
        $hdr = Get-Content -LiteralPath $sp -TotalCount 1 -ErrorAction SilentlyContinue
        if ($hdr -match '更新时间:\s*([\d\-: ]+)\s*$') { Write-Output ("[信息] 更新时间: " + $Matches[1].Trim()) }
    }
} catch { }
# Test script: print one line per second for 10 seconds, then exit.
for ($i = 1; $i -le 10; $i++) {
    Write-Output "Second $i - $(Get-Date -Format 'HH:mm:ss')"
    Start-Sleep -Seconds 1
}
Write-Output "Test finished"

