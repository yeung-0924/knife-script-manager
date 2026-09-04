# 更新时间: 2026-09-04 16:00:57
# 控制台同步打印更新时间（从首行注释解析，便于用户贴日志时直接看到脚本版本时间）
try {
    $sp = $PSCommandPath; if (-not $sp) { $sp = $MyInvocation.MyCommand.Path }
    if ($sp) {
        $hdr = Get-Content -LiteralPath $sp -TotalCount 1 -ErrorAction SilentlyContinue
        if ($hdr -match '更新时间:\s*([\d\-: ]+)\s*$') { Write-Host ("[脚本] 更新时间: " + $Matches[1].Trim()) }
    }
} catch { }
# --- 颜色辅助（ANSI SGR）---
# 入参/结果用 92 亮绿，信息用 93 亮黄，异常用 91 亮红
$ESC = [char]27
$GREEN = "$ESC[92m"
$YELLOW = "$ESC[93m"
$RED = "$ESC[91m"
$RESET = "$ESC[0m"
function C($color, $tag, $msg) { "$color[$tag]$RESET $msg" }

# --- 参数定义 ---
param(
    # 虚拟交换机名称
    [string]$SwitchName = "_p{SWITCH_NAME}",
    # 宿主机网关 IP
    [string]$GatewayIP = "_p{GATEWAY_IP}",
    # 子网掩码位数，24 代表 255.255.255.0
    [int]$SubnetPrefix = _p{SUBNET_PREFIX},
    # NAT 子网范围
    [string]$NatNetwork = "_p{NAT_NETWORK}"
)

# --- 入参 ---
Write-Host (C $GREEN '入参' "虚拟交换机名称(SwitchName) = $SwitchName")
Write-Host (C $GREEN '入参' "网关 IP(GatewayIP)           = $GatewayIP")
Write-Host (C $GREEN '入参' "子网掩码位数(SubnetPrefix) = $SubnetPrefix")
Write-Host (C $GREEN '入参' "NAT 子网(NatNetwork)         = $NatNetwork")

try {
    # --- 1. 在宿主机创建内部虚拟交换机 ---
    Write-Host (C $YELLOW '信息' "创建内部虚拟交换机: $SwitchName")
    New-VMSwitch -SwitchName $SwitchName -SwitchType Internal

    # --- 2. 为这个新交换机设置宿主机 IP（作为网关） ---
    Write-Host (C $YELLOW '信息' "获取虚拟网卡接口: *$SwitchName*")
    $switchAdapter = Get-NetAdapter | Where-Object { $_.Name -like "*$SwitchName*" }
    if (-not $switchAdapter) { throw "未找到名称匹配 '$SwitchName' 的网络适配器" }
    Write-Host (C $YELLOW '信息' "为虚拟网卡设置固定 IP: $GatewayIP/$SubnetPrefix")
    New-NetIPAddress -IPAddress $GatewayIP -PrefixLength $SubnetPrefix -InterfaceIndex $switchAdapter.ifIndex

    # --- 3. 在宿主机启用 NAT 功能 ---
    Write-Host (C $YELLOW '信息' "启用 NAT: $SwitchName -> $NatNetwork")
    New-NetNat -Name $SwitchName -InternalIPInterfaceAddressPrefix $NatNetwork

    # --- 执行结果 ---
    Write-Host (C $GREEN '结果' "创建完成！")
    Write-Host (C $GREEN '结果' "虚拟交换机名称: $SwitchName")
    Write-Host (C $GREEN '结果' "网关 IP: $GatewayIP")
    Write-Host (C $GREEN '结果' "NAT 子网: $NatNetwork")
    Write-Host (C $GREEN '结果' "请进入虚拟机，将其 IP 设置为该子网下的固定 IP（如 192.168.128.100），子网掩码为 255.255.255.0，网关为$GatewayIP")
}
catch {
    Write-Host (C $RED '异常' "$($_.Exception.Message)")
    exit 1
}

