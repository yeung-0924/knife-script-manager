# Get-PortUsage.ps1 - 查看当前运行的进程占用的 TCP 端口
# 参数（由程序代入，占位符 _p{NAME}）：NAME - 进程名关键字（可选，留空显示全部）
# 说明（健壮性处理）：
#   1) 统一用 Write-Output 输出（写入 success stream / stdout）。
#      执行器通过重定向 stdout 捕获日志；而 Write-Host 走 information stream（PS5+），
#      在部分重定向场景下捕获不到，会导致日志面板一片空白。
#   2) 优先用 Get-NetTCPConnection 查询（Windows 8 / 2012+），
#      命令不可用时回退 netstat -ano 解析，保证任何环境都能列出端口占用。
#   3) 进程名一次批量缓存，避免逐条 Get-Process 的重复开销。

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
Say ' 进程端口占用查询'
Say '=========================================='

# 入参（工具在执行前把 _p{XXX} 占位符替换为用户的输入值）
$keyword = "_p{NAME}"
# 占位符未被替换（直接运行脚本）或留空 → 视为不过滤
if ($keyword -match '_p\{' -or [string]::IsNullOrWhiteSpace($keyword)) { $keyword = '' }
$keyword = $keyword.Trim()
SayC $GREEN '入参' ("关键字: {0}" -f $(if ($keyword) { $keyword } else { '(空，显示全部)' }))

# 1) 采集 TCP 连接 → 端口/PID/状态
$entries = @()
try {
    $conns = Get-NetTCPConnection -ErrorAction Stop
    foreach ($c in $conns) {
        if ($null -eq $c.OwningProcess -or [int]$c.OwningProcess -le 0) { continue }
        $entries += [pscustomobject]@{
            Port  = $c.LocalPort
            Pid   = [int]$c.OwningProcess
            State = [string]$c.State
            Addr  = [string]$c.LocalAddress
        }
    }
} catch {
    # 回退：netstat -ano 解析 TCP 行
    foreach ($line in (netstat -ano)) {
        if ($line -match '^\s*TCP\s+(\S+):(\d+)\s+\S+\s+(\S+)\s+(\d+)\s*$') {
            $pidN = [int]$Matches[4]
            if ($pidN -le 0) { continue }
            $entries += [pscustomobject]@{
                Port  = [int]$Matches[2]
                Pid   = $pidN
                State = $Matches[3]
                Addr  = $Matches[1]
            }
        }
    }
}

if ($entries.Count -eq 0) {
    SayC $YELLOW '信息' '未检测到任何 TCP 连接。'
    Say ''
    Say '=========================================='
    SayC $GREEN '结果' '完成'
    Say '=========================================='
    exit 0
}

# 2) 进程名映射（一次批量缓存）
$names = @{}
foreach ($p in ($entries | Select-Object -ExpandProperty Pid -Unique)) {
    $names[$p] = (Get-Process -Id $p -ErrorAction SilentlyContinue).ProcessName
}

# 3) 按关键字过滤（匹配进程名，不区分大小写）
if ($keyword) {
    $entries = @($entries | Where-Object {
        $n = $names[[int]$_.Pid]
        $n -and $n -like "*$keyword*"
    })
    if ($entries.Count -eq 0) {
        SayC $YELLOW '信息' ("没有进程名包含 '{0}' 的连接。" -f $keyword)
        Say ''
        Say '=========================================='
        SayC $GREEN '结果' '完成'
        Say '=========================================='
        exit 0
    }
}

# 4) 输出一：进程 → 监听端口（LISTEN 分组，最常关心）
Say ''
SayC $YELLOW '信息' '[1] 进程 → 监听端口（LISTEN）'
Say '------------------------------------------'
$listenGroups = $entries | Where-Object { $_.State -match 'Listen' } |
    Group-Object Pid | Sort-Object Name
if (-not $listenGroups) {
    Say '  （无监听中的端口）'
} else {
    foreach ($g in $listenGroups) {
        $n = $names[[int]$g.Name]
        if (-not $n) { $n = '(未知进程)' }
        $ports = ($g.Group | Select-Object -ExpandProperty Port | Sort-Object -Unique | ForEach-Object { $_.ToString() }) -join ', '
        Say ("  {0} (PID {1})  监听: {2}" -f $n, $g.Name, $ports)
    }
}

# 5) 输出二：端口占用明细（按状态排序，LISTEN 在前）
Say ''
SayC $YELLOW '信息' '[2] 端口占用明细'
Say '------------------------------------------'
$order = @{ 'Listen' = 0; 'Established' = 1 }
$sorted = $entries | Sort-Object @{ Expression = { if ($order.ContainsKey([string]$_.State)) { $order[[string]$_.State] } else { 2 } } },
    @{ Expression = { [string]$_.State } },
    @{ Expression = { $_.Port } }
foreach ($e in $sorted) {
    $n = $names[[int]$e.Pid]
    if (-not $n) { $n = '(未知进程)' }
    Say ("  {0,-22} {1,-13} {2,-7} {3}" -f ("{0}:{1}" -f $e.Addr, $e.Port), $e.State, $e.Pid, $n)
}

Say ''
Say '=========================================='
SayC $GREEN '结果' ("完成：共 {0} 条连接" -f $entries.Count)
Say '=========================================='
