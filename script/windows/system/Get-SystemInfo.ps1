# Get-SystemInfo.ps1 - 显示本机系统信息（操作系统 / CPU / 内存 / 显卡 / 磁盘）
# 说明（与 Get-IPInfo.ps1 相同的两个关键健壮性处理）：
#   1) 统一用 Write-Output 输出（写入 success stream / stdout）。
#      执行器通过重定向 stdout 捕获日志；而 Write-Host 走 information stream（PS5+），
#      在部分重定向场景下捕获不到，会导致日志面板一片空白。
#   2) 所有 CIM 查询前先检测 Get-CimInstance 可用性，查询失败时逐章节降级，
#      保证任何环境都能输出基础信息。

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
# 系统明细等"脚本自身输出"保持原色（走 Say）。
$ESC = [char]27
$YELLOW = "$ESC[93m"; $GREEN = "$ESC[92m"; $RED = "$ESC[91m"; $RESET = "$ESC[0m"
function SayC { param([string]$Color, [string]$Tag, [string]$Text) Write-Output "$Color[$Tag]$RESET $Text" }

# 数值格式化
function Format-Gb { param([double]$Bytes) if ($Bytes -le 0) { return '未知' } return ('{0:N1} GB' -f ($Bytes / 1GB)) }
function Format-Pct { param([double]$Used, [double]$Total) if ($Total -le 0) { return '--' } return ('{0:N1}%' -f ($Used / $Total * 100)) }

# 提前检测 CIM 可用性（CommandNotFoundException 是 terminating error，SilentlyContinue 压不住）
$hasCim = [bool](Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)
if (-not $hasCim) {
    SayC $RED '异常' '当前环境缺少 Get-CimInstance，无法获取系统信息。'
    exit 1
}

# CPU 使用率：优先性能计数器（约 1 秒采样），失败回退 CIM 性能类，再失败返回 $null
function Get-CpuUsage {
    try {
        $sample = Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 1 -ErrorAction Stop
        return [math]::Round($sample.CounterSamples[0].CookedValue, 1)
    } catch { }
    try {
        $perf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop
        return [math]::Round([double]$perf.PercentProcessorTime, 1)
    } catch { }
    return $null
}

# 显卡显存：优先注册表 qwMemorySize（AdapterRAM 是 uint32，超过 4GB 会回绕），否则回退 AdapterRAM
function Get-GpuMemory {
    param([string]$Desc, $AdapterRam)
    $base = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    try {
        $prop = Get-ChildItem $base -ErrorAction SilentlyContinue | ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if ($p -and $p.DriverDesc -eq $Desc) { $p }
        } | Select-Object -First 1
        $mem = $prop.'HardwareInformation.qwMemorySize'
        if ($mem) { return [uint64]$mem }
    } catch { }
    if ($AdapterRam) { return [uint64]$AdapterRam }
    return 0
}

Say '=========================================='
Say ' 本机系统信息'
Say '=========================================='

# 1) 操作系统
Say ''
SayC $YELLOW '信息' '[1] 操作系统'
Say '------------------------------------------'
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    Say ("  系统      {0}" -f $os.Caption)
    Say ("  版本      {0}（{1}）" -f $os.Version, $os.OSArchitecture)
    $up = (Get-Date) - [System.Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime)
    Say ("  运行时长  {0}" -f ("{0} 天 {1} 小时 {2} 分钟" -f $up.Days, $up.Hours, $up.Minutes))
} catch {
    SayC $RED '异常' '  获取操作系统信息失败（已跳过）'
}

# 2) CPU
Say ''
SayC $YELLOW '信息' '[2] CPU'
Say '------------------------------------------'
try {
    $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop | Select-Object -First 1
    Say ("  型号      {0}" -f $cpu.Name.Trim())
    Say ("  物理核心  {0} 个 / 逻辑处理器 {1} 个" -f $cpu.NumberOfCores, $cpu.NumberOfLogicalProcessors)
    Say ("  主频      {0:N1} GHz" -f ($cpu.MaxClockSpeed / 1000))
    $usage = Get-CpuUsage
    if ($null -ne $usage) {
        Say ("  使用率    {0}%" -f $usage)
    } else {
        Say '  使用率    （无法获取）'
    }
} catch {
    SayC $RED '异常' '  获取 CPU 信息失败（已跳过）'
}

# 3) 内存
Say ''
SayC $YELLOW '信息' '[3] 内存'
Say '------------------------------------------'
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $totalMem = [double]$os.TotalVisibleMemorySize * 1KB
    $freeMem = [double]$os.FreePhysicalMemory * 1KB
    $usedMem = $totalMem - $freeMem
    Say ("  总容量  {0}" -f (Format-Gb $totalMem))
    Say ("  已使用  {0}（{1}）" -f (Format-Gb $usedMem), (Format-Pct $usedMem $totalMem))
    Say ("  可用    {0}" -f (Format-Gb $freeMem))
} catch {
    SayC $RED '异常' '  获取内存信息失败（已跳过）'
}

# 4) 显卡
Say ''
SayC $YELLOW '信息' '[4] 显卡'
Say '------------------------------------------'
try {
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction Stop
    if (-not $gpus) {
        Say '  （未检测到显卡）'
    } else {
        foreach ($g in $gpus) {
            $gpuMem = Get-GpuMemory -Desc $g.Name -AdapterRam $g.AdapterRAM
            Say ("  {0}" -f $g.Name)
            Say ("    显存     {0}" -f (Format-Gb $gpuMem))
            if ($g.DriverVersion) { Say ("    驱动版本 {0}" -f $g.DriverVersion) }
        }
    }
} catch {
    SayC $RED '异常' '  获取显卡信息失败（已跳过）'
}

# 5) 磁盘
Say ''
SayC $YELLOW '信息' '[5] 磁盘'
Say '------------------------------------------'
try {
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
    if (-not $disks) {
        Say '  （未检测到本地磁盘）'
    } else {
        foreach ($d in $disks) {
            $totalDisk = [double]$d.Size
            $freeDisk = [double]$d.FreeSpace
            $usedDisk = $totalDisk - $freeDisk
            Say ("  {0,-4} 总容量 {1,-10} 已用 {2,-10}（{3,-6}）剩余 {4}" -f `
                $d.DeviceID, (Format-Gb $totalDisk), (Format-Gb $usedDisk), (Format-Pct $usedDisk $totalDisk), (Format-Gb $freeDisk))
        }
    }
} catch {
    SayC $RED '异常' '  获取磁盘信息失败（已跳过）'
}

Say ''
Say '=========================================='
SayC $GREEN '结果' '完成'
Say '=========================================='
