# 更新时间: 2026-09-04 14:59:35
# Update-Firewall.ps1 - 按用户选择更新 Windows 防火墙（域网络 / 专用网络 / 公用网络）配置
#
# 三个参数均为下拉框（启用 / 禁用），由程序代入后执行：
#   域网络   -> _p{DOMAIN}
#   专用网络 -> _p{PRIVATE}
#   公用网络 -> _p{PUBLIC}
# 值为空表示该网络类型「不改动」（配合输入框的清空按钮，留空即跳过）。
#
# 两个健壮性处理：
#   1) 统一用 Write-Output（写 stdout）。执行器通过重定向 stdout 捕获日志；
#      Write-Host 走 information stream（PS5+），部分重定向场景下捕获不到，会导致日志面板空白。
#   2) Set-NetFirewallProfile 依赖 NetSecurity 模块，命令不存在时抛 CommandNotFoundException
#      （terminating error），-ErrorAction SilentlyContinue 压不住它，脚本会直接终止且无输出；
#      故先用 Get-Command 检测，不可用时回退到 netsh。

# 输出 UTF-8（包 try/catch：输出被重定向、无控制台时该赋值可能抛异常，不能让它中断脚本）
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # 忽略：执行器已在 -Command 中设置过
}

function Say { param([string]$Text = '') Write-Output $Text }

# 颜色辅助（ANSI SGR）：入参/结果亮绿(92) 带 [入参]/[结果]，信息亮黄(93) 带 [信息]，异常亮红(91) 带 [异常]
# 防火墙状态等"脚本自身输出"保持原色（走 Say）。
$ESC = [char]27
$GREEN = "$ESC[92m"; $YELLOW = "$ESC[93m"; $RED = "$ESC[91m"; $RESET = "$ESC[0m"
function SayC { param([string]$Color, [string]$Tag, [string]$Text) Write-Output "$Color[$Tag]$RESET $Text" }

# 把参数的中文选项转成布尔；无法识别返回 $null（调用方据此跳过）
function Convert-State {
    param([string]$Value)
    switch -Wildcard ($Value.Trim()) {
        '启用' { return $true }
        '禁用' { return $false }
        'True' { return $true }
        'False' { return $false }
        '1' { return $true }
        '0' { return $false }
        default { return $null }
    }
}

# 三个网络配置：参数值 -> PowerShell 的 Profile 名 / netsh 的 profile 名
$profiles = @(
    @{ Key = '_DOMAIN'; Label = '域网络'; PSName = 'Domain'; NetshName = 'domainprofile' },
    @{ Key = '_PRIVATE'; Label = '专用网络'; PSName = 'Private'; NetshName = 'privateprofile' },
    @{ Key = '_PUBLIC'; Label = '公用网络'; PSName = 'Public'; NetshName = 'publicprofile' }
)

# 各参数的值（由程序代入；此处为占位符，直接在 PowerShell 中运行时保持原样）
$values = @{
    'DOMAIN'   = '_p{DOMAIN}'
    'PRIVATE'  = '_p{PRIVATE}'
    'PUBLIC'   = '_p{PUBLIC}'
}

Say '=========================================='
Say ' Windows 防火墙配置更新'
Say '=========================================='
Say ''

# 入参（三个网络类型的目标状态）
SayC $GREEN '入参' ("域网络   (_DOMAIN ) = {0}" -f $values['_DOMAIN'])
SayC $GREEN '入参' ("专用网络 (_PRIVATE) = {0}" -f $values['_PRIVATE'])
SayC $GREEN '入参' ("公用网络 (_PUBLIC ) = {0}" -f $values['_PUBLIC'])
Say ''

# 1) 解析用户选择
$plan = @()
foreach ($p in $profiles) {
    $raw = $values[$p.Key]
    # 占位符未被替换（用户未填）或填了空白 -> 跳过
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw -match '^\$\{.*\}$') {
        Say ("  {0,-10} (未选择，跳过)" -f $p.Label)
        continue
    }

    $enabled = Convert-State -Value $raw
    if ($null -eq $enabled) {
        Say ("  {0,-10} 无法识别的选项「{1}」，已跳过（仅支持：启用 / 禁用）" -f $p.Label, $raw)
        continue
    }

    $plan += @{ Item = $p; Enabled = $enabled }
}

Say ''
if ($plan.Count -eq 0) {
    Say '没有需要更新的配置项（三个参数均为空或未识别）。'
    Say '请在左侧参数面板选择「启用」或「禁用」后重新执行。'
    exit 0
}

# 2) 选择可用的实现方式
$useNetsh = -not [bool](Get-Command -Name Set-NetFirewallProfile -ErrorAction SilentlyContinue)
if ($useNetsh) {
    SayC $YELLOW '信息' 'Set-NetFirewallProfile 不可用，改用 netsh 方式。'
    Say ''
}

# 3) 逐项应用
$failed = 0
foreach ($task in $plan) {
    $p = $task.Item
    $want = if ($task.Enabled) { '启用' } else { '禁用' }
    SayC $YELLOW '信息' ("正在{0}「{1}」防火墙..." -f $want, $p.Label)

    try {
        if ($useNetsh) {
            $state = if ($task.Enabled) { 'on' } else { 'off' }
            $out = & netsh advfirewall set $($p.NetshName) state $state 2>&1
            $code = $LASTEXITCODE
            if ($code -ne 0) {
                throw ("netsh 返回退出码 {0}：{1}" -f $code, ($out -join ' '))
            }
        } else {
            # -Enabled 需要 GpoBoolean 枚举，不能直接传 [bool]（$true/$false），
            # 否则报 "Invalid cast from 'System.Boolean' to ...GpoBoolean"
            $stateEnum = if ($task.Enabled) {
                [Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.GpoBoolean]::True
            } else {
                [Microsoft.PowerShell.Cmdletization.GeneratedTypes.NetSecurity.GpoBoolean]::False
            }
            Set-NetFirewallProfile -Profile $p.PSName -Enabled $stateEnum -ErrorAction Stop
        }
        SayC $GREEN '结果' ("    -> {0}成功" -f $want)
    }
    catch {
        $failed++
        SayC $RED '异常' ("    -> {0}失败：{1}" -f $want, $_.Exception.Message)
        SayC $RED '异常' '       若为权限/访问被拒，请确认已以管理员身份运行；若为参数类型错误，请联系脚本维护者。'
    }
}

# 4) 回显最终状态，便于确认改动已生效
Say ''
SayC $YELLOW '信息' '[当前防火墙状态]'
Say '------------------------------------------'
try {
    if (-not $useNetsh) {
        $current = Get-NetFirewallProfile -ErrorAction Stop
        foreach ($p in $profiles) {
            $hit = $current | Where-Object { $_.Name -eq $p.PSName }
            if ($hit) {
                Say ("  {0,-10} {1}" -f $p.Label, $(if ($hit.Enabled) { '已启用' } else { '已禁用' }))
            }
        }
    } else {
        $out = & netsh advfirewall show allprofiles state 2>&1
        $out | Select-String -Pattern '状态|State' | ForEach-Object { Say ("  {0}" -f $_.Line.Trim()) }
    }
}
catch {
    Say ("  读取当前状态失败：{0}" -f $_.Exception.Message)
}

Say ''
Say '=========================================='
if ($failed -eq 0) {
    SayC $GREEN '结果' ' 全部完成'
} else {
    SayC $GREEN '结果' (" 完成，但有 {0} 项失败（详见上方）" -f $failed)
}
Say '=========================================='

# 有失败项时返回非 0，让执行器显示「已退出（代码 1）」
if ($failed -gt 0) { exit 1 }