# 更新时间: 2026-09-04 18:16:34
# Get-RuntimeEnv.ps1 - 检测本机各语言运行时版本与可执行文件路径（未配置环境的语言输出为空）
# 说明（关键健壮性处理）：
#   1) 统一用 Write-Output 输出（走 success stream / stdout），与 Get-SystemInfo.ps1 同款处理。
#   2) 外部命令的版本输出可能走 stderr（java -version 等），一律 2>&1 合并后取首行。
#   3) 命令不存在、执行失败（如 Windows 商店版 python stub）一律视为"未配置"，版本输出为空。
#   4) 检测属于只读操作，任何单项失败都不应中断整体输出。
#   5) 逐语言「检测中 -> 结果」流式输出：先打印标题与更新时间，再每检测完一项立即输出一项，
#      避免先在内部攒齐所有结果、最后一次性打印（那样用户会看到约 10 秒空白、误以为卡住）。

# 输出 UTF-8（脚本单独运行时也保证中文不乱码）
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # 忽略：执行器已在 -Command 中设置过 [Console]::OutputEncoding
}

$ErrorActionPreference = 'Continue'

# 颜色（ANSI SGR）：信息亮黄(93) 带 [信息]，结果亮绿(92) 带 [结果]
$ESC = [char]27
$YELLOW = "$ESC[93m"; $GREEN = "$ESC[92m"; $RESET = "$ESC[0m"
function Say { param([string]$Text = '') Write-Output $Text }
function SayC { param([string]$Color, [string]$Tag, [string]$Text) Write-Output "$Color[$Tag]$RESET $Text" }

# 执行外部命令检测运行时：返回 @{ Path = '可执行文件路径'; Version = '版本号' }
# - 命令不存在 / 不是真实可执行文件 / 退出码非 0 / 无输出 -> 返回 @{ Path = 路径; Version = '' }
# - VersionRegex 从首行提取版本（捕获组 1）；VersionStrip 为提取后再去除的前缀
function Get-Runtime {
    param(
        [string]$Name,
        [string[]]$VersionArgs,
        [string]$VersionRegex = '',
        [string]$VersionStrip = ''
    )
    # 只取 Application 类型，避免被 PowerShell 别名 / 函数覆盖（如 java 被某个模块定义成 function）
    $cmd = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { return $null }
    $exePath = if ($cmd.Path) { $cmd.Path } else { $cmd.Source }
    if ([string]::IsNullOrWhiteSpace($exePath)) { return $null }
    # 仅允许真正的可执行扩展名，避免 Windows 把 .js / .vbs 等按文件关联交给 WSH 执行而弹出错误对话框
    $allowedExts = @('.exe', '.cmd', '.bat', '.com')
    $ext = [System.IO.Path]::GetExtension($exePath).ToLowerInvariant()
    if ($allowedExts -notcontains $ext) { return $null }
    $info = @{ Path = $exePath; Version = '' }
    try {
        # 先完整执行并捕获输出，再取首行。PowerShell 中外部命令进入管道后 $LASTEXITCODE 不再可靠，
        # 所以必须在重定向到变量后立即保存退出码，否则 java -version 这类命令会被误判为失败。
        $output = & $exePath @VersionArgs 2>&1
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0) { return $info }
        $line = $output | Select-Object -First 1
        if ($null -eq $line) { return $info }
        $version = ([string]$line).Trim()
        if ($VersionRegex) {
            $m = [regex]::Match($version, $VersionRegex)
            if ($m.Success) { $version = $m.Groups[1].Value }
        }
        if ($VersionStrip) { $version = $version -replace $VersionStrip, '' }
        $info.Version = $version
    } catch { }
    return $info
}

# ---- 标题与说明：先打印，让用户立即看到脚本已启动（而非攒到最后一次性刷出）----
Say '=========================================='
Say ' 运行时环境检测'
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
SayC $YELLOW '信息' '逐项检测本机各语言运行时（检测完成一项即输出一项，请稍候）'
Say ''

# ---- 逐语言「检测中 -> 结果」流式输出，避免一次性憋到最后让用户以为卡住 ----
function Show-RuntimeRow {
    param([string]$Lang, [string]$Path, [string]$Version)
    Say "[$Lang]"
    if ($Path) {
        $ver = if ([string]::IsNullOrWhiteSpace($Version)) { '未知' } else { $Version }
        Say "版本号：$ver"
        Say "可执行文件路径：$Path"
    } else {
        Say '未检测到运行时环境'
    }
    Say ''
}

# PowerShell 5.1（系统自带 powershell.exe，即脚本当前运行环境）
SayC $YELLOW '信息' '检测中: PowerShell 5.1 ...'
$ps51Path = (Get-Process -Id $PID).Path
$ps51Ver = ''
try { $ps51Ver = [string]$PSVersionTable.PSVersion } catch { }
Show-RuntimeRow -Lang 'PowerShell 5.1' -Path $ps51Path -Version $ps51Ver

# PowerShell 7（pwsh，可选安装；版本取文件属性，避免额外启动 pwsh 进程）
SayC $YELLOW '信息' '检测中: PowerShell 7 ...'
$pwshPath = ''
$pwshVer = ''
$pwshCmd = Get-Command -Name 'pwsh' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($pwshCmd -and $pwshCmd.Path) {
    $pwshPath = $pwshCmd.Path
    try {
        $pwshVer = (Get-Item $pwshPath).VersionInfo.ProductVersion
        if ([string]::IsNullOrWhiteSpace($pwshVer)) { $pwshVer = (Get-Item $pwshPath).VersionInfo.FileVersion }
    } catch { }
}
Show-RuntimeRow -Lang 'PowerShell 7' -Path $pwshPath -Version $pwshVer

# cmd（cmd.exe 版本即 Windows 系统版本）
SayC $YELLOW '信息' '检测中: cmd ...'
$cmdPath = $env:ComSpec
$cmdVer = ''
try { $cmdVer = (Get-Item $cmdPath).VersionInfo.ProductVersion } catch { }
Show-RuntimeRow -Lang 'cmd' -Path $cmdPath -Version $cmdVer

# bash（Git Bash 等，未加入 PATH 则视为未配置）
SayC $YELLOW '信息' '检测中: bash ...'
$bashInfo = Get-Runtime 'bash' @('--version') 'version\s+([^\s,]+)'
Show-RuntimeRow -Lang 'bash' -Path $bashInfo.Path -Version $bashInfo.Version

# java（java -version 输出在 stderr，已 2>&1 合并）
SayC $YELLOW '信息' '检测中: java ...'
$javaInfo = Get-Runtime 'java' @('-version')
Show-RuntimeRow -Lang 'java' -Path $javaInfo.Path -Version $javaInfo.Version

# python（Windows 商店 stub 未安装真 Python 时执行失败，会被视为未配置；python3 兜底）
SayC $YELLOW '信息' '检测中: python ...'
$pyInfo = Get-Runtime 'python' @('--version') '' '^Python\s+'
if (-not $pyInfo -or -not $pyInfo.Version) { $pyInfo = Get-Runtime 'python3' @('--version') '' '^Python\s+' }
Show-RuntimeRow -Lang 'python' -Path $pyInfo.Path -Version $pyInfo.Version

# node
SayC $YELLOW '信息' '检测中: node ...'
$nodeInfo = Get-Runtime 'node' @('--version')
Show-RuntimeRow -Lang 'node' -Path $nodeInfo.Path -Version $nodeInfo.Version

# go
SayC $YELLOW '信息' '检测中: go ...'
$goInfo = Get-Runtime 'go' @('version') '' '^go version\s+'
Show-RuntimeRow -Lang 'go' -Path $goInfo.Path -Version $goInfo.Version

# rust
SayC $YELLOW '信息' '检测中: rust ...'
$rustInfo = Get-Runtime 'rustc' @('--version') '' '^rustc\s+'
Show-RuntimeRow -Lang 'rust' -Path $rustInfo.Path -Version $rustInfo.Version

Say '=========================================='
SayC $GREEN '结果' '完成'
Say '=========================================='
