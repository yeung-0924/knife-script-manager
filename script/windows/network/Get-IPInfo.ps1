# 更新时间: 2026-09-04 16:57:08
# Get-IPInfo.ps1 - 显示本机网络适配器与 IP 信息
# 说明（两个关键健壮性处理）：
#   1) 统一用 Write-Output 输出（写入 success stream / stdout）。
#      执行器通过重定向 stdout 捕获日志；而 Write-Host 走 information stream（PS5+），
#      在部分重定向场景下捕获不到，会导致日志面板一片空白。
#   2) 所有 NetTCPIP 相关 cmdlet 先检测可用性再调用。
#      命令不存在时抛的是 CommandNotFoundException（terminating error），
#      -ErrorAction SilentlyContinue 无法抑制它，脚本会直接终止、完全没有输出。
#      检测后不可用时回退到 ipconfig 解析，保证任何环境都能输出基础信息。

# 输出 UTF-8（脚本单独运行时也保证中文不乱码）
# 包 try/catch：输出被重定向、无控制台时该赋值可能抛异常，不能让它中断脚本
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # 忽略：执行器已在 -Command 中设置过 [Console]::OutputEncoding
}

function Say { param([string]$Text = '') Write-Output $Text }

# 颜色辅助（ANSI SGR）：信息亮黄(93) 带 [信息]，结果亮绿(92) 带 [结果]，异常亮红(91) 带 [异常]
# 说明类/章节标题走 SayC；网络明细等"脚本自身输出"保持原色（走 Say）。
$ESC = [char]27
$YELLOW = "$ESC[93m"; $GREEN = "$ESC[92m"; $RED = "$ESC[91m"; $RESET = "$ESC[0m"
function SayC { param([string]$Color, [string]$Tag, [string]$Text) Write-Output "$Color[$Tag]$RESET $Text" }

# 取接口显示名：优先别名，其次描述
function Get-IfName {
    param($Obj)
    if ($null -eq $Obj) { return '(未知接口)' }
    if (-not [string]::IsNullOrWhiteSpace($Obj.InterfaceAlias)) { return $Obj.InterfaceAlias }
    if (-not [string]::IsNullOrWhiteSpace($Obj.InterfaceDescription)) { return $Obj.InterfaceDescription }
    return '(未知接口)'
}

# 提前检测 cmdlet 可用性
$hasNetAddress = [bool](Get-Command -Name Get-NetIPAddress -ErrorAction SilentlyContinue)
$hasNetRoute   = [bool](Get-Command -Name Get-NetRoute -ErrorAction SilentlyContinue)
$hasDnsClient  = [bool](Get-Command -Name Get-DnsClientServerAddress -ErrorAction SilentlyContinue)

Say '=========================================='
Say ' 本机网络与 IP 信息'
Say '=========================================='
# ---- 控制台同步打印「更新时间」：从脚本头部注释读取，便于用户贴错误日志时直接看到脚本版本时间 ----
$updateTime = ''
try {
    $scriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($scriptPath)) { $scriptPath = $MyInvocation.MyCommand.Path }
    if (-not [string]::IsNullOrWhiteSpace($scriptPath)) {
        $hdrLine = Get-Content -LiteralPath $scriptPath -TotalCount 1 -ErrorAction SilentlyContinue
        if ($hdrLine -match '更新时间:\s*([\d\-: ]+)\s*$') { $updateTime = $Matches[1].Trim() }
    }
} catch { }
if (-not [string]::IsNullOrWhiteSpace($updateTime)) {
    SayC $YELLOW '信息' "更新时间: $updateTime"
}

# 1) 主要 IP：取「有默认路由」的接口 IPv4——这是对外通信实际使用的地址，最常被需要
Say ''
SayC $YELLOW '信息' '[1] 主要 IP 地址（对外通信）'
Say '------------------------------------------'
$primaryIp = $null
$primaryIfName = ''
if ($hasNetRoute -and $hasNetAddress) {
    $route = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object -Property RouteMetric | Select-Object -First 1
    if ($route) {
        $primaryIfName = Get-IfName $route
        $primaryIp = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $route.InterfaceIndex -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
            Select-Object -First 1
    }
}
if ($primaryIp) {
    Say ("  {0}" -f $primaryIp.IPAddress)
    Say ("  接口: {0}" -f $primaryIfName)
} else {
    Say '  (未能自动判定，请看下方的地址明细)'
}

# 2) 各适配器 IPv4 明细（过滤掉无意义的 APIPA 自动地址 169.254.*）
Say ''
SayC $YELLOW '信息' '[2] IPv4 地址明细'
Say '------------------------------------------'
if ($hasNetAddress) {
    $addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '169.254.*' } |
        Sort-Object -Property InterfaceIndex
    if ($addrs) {
        foreach ($a in $addrs) {
            Say ("  {0,-28} {1}/{2}" -f (Get-IfName $a), $a.IPAddress, $a.PrefixLength)
        }
    } else {
        Say '  (无)'
    }
} else {
    Say '  (Get-NetIPAddress 不可用，回退到 ipconfig)'
    ipconfig | Select-String -Pattern 'IPv4|IP Address' | ForEach-Object { Say ("  {0}" -f $_.Line.Trim()) }
}

# 3) 默认网关（按跃点排序，最优先的在前）
Say ''
SayC $YELLOW '信息' '[3] 默认网关'
Say '------------------------------------------'
if ($hasNetRoute) {
    $routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object -Property RouteMetric
    if ($routes) {
        foreach ($r in $routes) {
            Say ("  {0,-28} -> {1}  (跃点 {2})" -f (Get-IfName $r), $r.NextHop, $r.RouteMetric)
        }
    } else {
        Say '  (无)'
    }
} else {
    ipconfig | Select-String -Pattern '默认网关|Default Gateway' | ForEach-Object { Say ("  {0}" -f $_.Line.Trim()) }
}

# 4) DNS 服务器
Say ''
SayC $YELLOW '信息' '[4] DNS 服务器'
Say '------------------------------------------'
if ($hasDnsClient) {
    $dns = Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $null -ne $_.ServerAddresses -and $_.ServerAddresses.Count -gt 0 }
    if ($dns) {
        foreach ($d in $dns) {
            Say ("  {0,-28} {1}" -f (Get-IfName $d), ($d.ServerAddresses -join ', '))
        }
    } else {
        Say '  (无)'
    }
} else {
    Say '  (Get-DnsClientServerAddress 不可用，跳过)'
}

# 5) 连通性快速测试：只发 1 个包（原为多个目标各 2 包，耗时明显）
Say ''
SayC $YELLOW '信息' '[5] 连通性快速测试（每目标 1 包）'
Say '------------------------------------------'
if ($hasNetRoute) {
    $gw = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Sort-Object -Property RouteMetric | Select-Object -First 1).NextHop
    if (-not [string]::IsNullOrWhiteSpace($gw)) {
        $ok = Test-Connection -ComputerName $gw -Count 1 -Quiet -ErrorAction SilentlyContinue
        Say ("  网关 {0,-20} {1}" -f $gw, $(if ($ok) { '可达' } else { '不可达' }))
    } else {
        Say '  网关                     (无网关，跳过)'
    }
}
$okPub = Test-Connection -ComputerName '223.5.5.5' -Count 1 -Quiet -ErrorAction SilentlyContinue
Say ("  公网 223.5.5.5           {0}" -f $(if ($okPub) { '可达' } else { '不可达' }))

Say ''
Say '=========================================='
SayC $GREEN '结果' '完成'
Say '=========================================='

