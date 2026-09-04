# 更新时间: 2026-09-04
# Kill-Process.ps1 - 结束进程（支持三种方式，任选其一或组合）
# 参数（由程序代入，占位符 _p{XXX}）：
#   PORT - 端口号（按端口杀）
#   PID  - 进程 ID（按 PID 杀）
#   NAME - 进程名关键字（按进程名模糊匹配杀）
# 三种方式均为选填；全部未填则跳过本次执行。
# 说明（健壮性处理）：
#   1) 统一用 Write-Output 输出（写入 success stream / stdout）。
#      执行器通过重定向 stdout 捕获日志；而 Write-Host 走 information stream（PS5+），
#      在部分重定向场景下捕获不到，会导致日志面板一片空白。
#   2) 优先用 Get-NetTCPConnection 查询（Windows 8 / 2012+），
#      命令不可用时回退 netstat -ano 解析，保证任何环境都能找到占用端口的进程。
#   3) 按进程名模糊匹配会排除当前脚本自身进程，避免误杀执行器。
#   4) 结束进程失败（如进程属于其他用户/系统）时逐条提示，不中断整体执行。

# 输出 UTF-8（脚本单独运行时也保证中文不乱码）
# 包 try/catch：输出被重定向、无控制台时该赋值可能抛异常，不能让它中断脚本
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # 忽略：执行器已在 -Command 中设置过 [Console]::OutputEncoding
}

function Say { param([string]$Text = '') Write-Output $Text }

# 颜色辅助（ANSI SGR）：入参/结果亮绿(92)，信息亮黄(93)，异常亮红(91)
$ESC = [char]27
$YELLOW = "$ESC[93m"; $GREEN = "$ESC[92m"; $RED = "$ESC[91m"; $RESET = "$ESC[0m"
function SayC { param([string]$Color, [string]$Tag, [string]$Text) Write-Output "$Color[$Tag]$RESET $Text" }

Say '=========================================='
Say ' 结束进程（端口 / PID / 进程名）'
Say '=========================================='

# 入参（工具在执行前把 _p{XXX} 占位符替换为用户的输入值）
$PID_INPUT = "_p{PID}"
$PORT = "_p{PORT}"
$NAME = "_p{NAME}"

# 占位符未被替换（直接运行脚本）时置空
if ($PID_INPUT -match '_p\{') { $PID_INPUT = '' }
if ($PORT -match '_p\{') { $PORT = '' }
if ($NAME -match '_p\{') { $NAME = '' }
$PID_INPUT = $PID_INPUT.Trim()
$PORT = $PORT.Trim()
$NAME = $NAME.Trim()

# 全部未填 → 跳过本次执行
if ([string]::IsNullOrWhiteSpace($PORT) -and [string]::IsNullOrWhiteSpace($PID_INPUT) -and [string]::IsNullOrWhiteSpace($NAME)) {
    SayC $YELLOW '信息' '未提供任何条件（端口号 / PID / 进程名），本次跳过。'
    Say ''
    Say '=========================================='
    SayC $GREEN '结果' '完成（跳过）'
    Say '=========================================='
    exit 0
}

# 逐项校验（填了就要求格式合法）
if ($PID_INPUT -and $PID_INPUT -notmatch '^\d+$') {
    SayC $RED '异常' 'PID 无效（必须为正整数）'
    exit 1
}
if ($PORT -and ($PORT -notmatch '^\d+$' -or [int]$PORT -lt 1 -or [int]$PORT -gt 65535)) {
    SayC $RED '异常' '端口号无效（有效范围 1-65535）'
    exit 1
}

SayC $GREEN '入参' (
    "端口: {0}; PID: {1}; 进程名: {2}" -f `
    $(if ($PID_INPUT) { $PID_INPUT } else { '-' }),
    $(if ($PORT) { $PORT } else { '-' }),
    $(if ($NAME) { $NAME } else { '-' })
)

# 1) 汇总目标 PID 集合（三种方式取并集，去重）
$targets = @()

if ($PID_INPUT) {
    $targets += [int]$PID_INPUT
}

if ($PORT) {
    $byPort = @()
    try {
        $byPort = @(Get-NetTCPConnection -LocalPort $PORT -ErrorAction Stop |
            Select-Object -ExpandProperty OwningProcess -Unique)
    } catch {
        # 回退：netstat -ano 解析 TCP 行，取行尾 PID
        $byPort = @(netstat -ano | Select-String -Pattern ('TCP.*:{0}\s' -f $PORT) |
            ForEach-Object {
                if ($_.Line -match '(\d+)\s*$') { [int]$Matches[1] }
            })
    }
    $targets += $byPort
}

if ($NAME) {
    # 模糊匹配进程名（不区分大小写）；排除当前脚本自身，避免误杀执行器
    $byName = @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -ne $PID -and $_.ProcessName -like "*$NAME*" })
    $targets += $byName | Select-Object -ExpandProperty Id
}

$targets = @($targets | Sort-Object -Unique | Where-Object { $_ -gt 0 })

if ($targets.Count -eq 0) {
    SayC $YELLOW '信息' '未找到匹配的进程，无需处理。'
    Say ''
    Say '=========================================='
    SayC $GREEN '结果' '完成'
    Say '=========================================='
    exit 0
}

# 2) 展示将被结束的进程
SayC $YELLOW '信息' ("共匹配到 {0} 个进程：" -f $targets.Count)
foreach ($id in $targets) {
    $procName = '(未知)'
    try {
        $procName = (Get-Process -Id $id -ErrorAction Stop).ProcessName
    } catch { }
    Say ("  PID {0,-7} {1}" -f $id, $procName)
}

# 3) 结束进程
SayC $YELLOW '信息' '正在结束上述进程...'
$killed = 0
foreach ($id in $targets) {
    try {
        Stop-Process -Id $id -Force -ErrorAction Stop
        SayC $GREEN '结果' ("已结束 PID {0}" -f $id)
        $killed++
    } catch {
        SayC $RED '异常' ("结束 PID {0} 失败：{1}" -f $id, $_.Exception.Message)
    }
}

# 4) 汇总
Say ''
Say '=========================================='
if ($killed -gt 0) {
    SayC $GREEN '结果' ("完成：已结束 {0} 个进程" -f $killed)
} else {
    SayC $RED '异常' '未结束任何进程（进程可能属于其他用户/系统，需要管理员权限）'
}
Say '=========================================='
