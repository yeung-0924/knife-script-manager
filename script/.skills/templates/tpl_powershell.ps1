# 更新时间: 2026-09-04 16:57:08
# PowerShell 最小模板（ScriptManager）
# 参数用 _p{NAME} 占位符，运行前由程序替换为用户输入
# 也可用 param 块接收 -Name（二选一即可）
param( [string]$Name = "World" )

Write-Host "===== Hello, World ====="
# 控制台同步打印更新时间（从首行注释解析，便于用户贴日志时直接看到脚本版本时间）
try {
    $sp = $PSCommandPath; if (-not $sp) { $sp = $MyInvocation.MyCommand.Path }
    if ($sp) {
        $hdr = Get-Content -LiteralPath $sp -TotalCount 1 -ErrorAction SilentlyContinue
        if ($hdr -match '更新时间:\s*([\d\-: ]+)\s*$') { Write-Host ("[信息] 更新时间: " + $Matches[1].Trim()) }
    }
} catch { }
Write-Host "Hello, _p{NAME}!"
# 若改用 param 方式收参，可写：Write-Host "Hello, $Name!"

