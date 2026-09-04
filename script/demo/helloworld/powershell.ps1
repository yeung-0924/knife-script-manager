# 更新时间: 2026-09-04 16:00:12
# PowerShell 示例脚本：输出 Hello World 并回显传入的参数
# 运行参数：-Name <值>，默认 World
param(
    [string]$Name = "World"
)

Write-Host "===== Hello, World ====="
# 控制台同步打印更新时间（从首行注释解析，便于用户贴日志时直接看到脚本版本时间）
try {
    $sp = $PSCommandPath; if (-not $sp) { $sp = $MyInvocation.MyCommand.Path }
    if ($sp) {
        $hdr = Get-Content -LiteralPath $sp -TotalCount 1 -ErrorAction SilentlyContinue
        if ($hdr -match '更新时间:\s*([\d\-: ]+)\s*$') { Write-Host ("[脚本] 更新时间: " + $Matches[1].Trim()) }
    }
} catch { }
Write-Host "Hello, $Name!"
Write-Host "接收参数 Name = $Name"

Write-Host "===== 多色日志 ====="
# 多彩日志：输出 16 种 ANSI 前景色（30-37 / 90-97），执行器解析 SGR 前景色并连同色名打印
$esc = [char]27
$codes = @(
    30, "黑", 31, "红", 32, "绿", 33, "黄", 34, "蓝", 35, "品红", 36, "青", 37, "白",
    90, "灰", 91, "亮红", 92, "亮绿", 93, "亮黄", 94, "亮蓝", 95, "亮品红", 96, "亮青", 97, "亮白"
)
for ($i = 0; $i -lt $codes.Count; $i += 2) {
    $code = $codes[$i]
    $name = $codes[$i + 1]
    Write-Host "$esc[${code}m这是一行“${code}”日志（$name）$esc[0m"
}

