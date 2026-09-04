# 更新时间: 2026-09-04 16:00:12
# PowerShell 7 (pwsh) 最小模板（ScriptManager）
# 语法与 Windows PowerShell 一致，index.json 中 lang 用 "pwsh"
# 参数用 _p{NAME} 占位符，运行前由程序替换为用户输入
param( [string]$Name = "World" )

Write-Host "===== Hello, World ====="
# 控制台同步打印更新时间（从首行注释解析，便于用户贴日志时直接看到脚本版本时间）
try {
    $sp = $PSCommandPath; if (-not $sp) { $sp = $MyInvocation.MyCommand.Path }
    if ($sp) {
        $hdr = Get-Content -LiteralPath $sp -TotalCount 1 -ErrorAction SilentlyContinue
        if ($hdr -match '更新时间:\s*([\d\-: ]+)\s*$') { Write-Host ("[脚本] 更新时间: " + $Matches[1].Trim()) }
    }
} catch { }
Write-Host "Hello, _p{NAME}!"

