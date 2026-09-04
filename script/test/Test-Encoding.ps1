# 更新时间: 2026-09-04 16:00:12
# 控制台同步打印更新时间（从首行注释解析，便于用户贴日志时直接看到脚本版本时间）
try {
    $sp = $PSCommandPath; if (-not $sp) { $sp = $MyInvocation.MyCommand.Path }
    if ($sp) {
        $hdr = Get-Content -LiteralPath $sp -TotalCount 1 -ErrorAction SilentlyContinue
        if ($hdr -match '更新时间:\s*([\d\-: ]+)\s*$') { Write-Output ("[脚本] 更新时间: " + $Matches[1].Trim()) }
    }
} catch { }
# Encoding test: output Hello World, no Chinese, saved as UTF-8 without BOM for testing.
Write-Output "Hello, World!"
Write-Output "你好, 世界!"
Write-Output "encoding-test script executed successfully"

