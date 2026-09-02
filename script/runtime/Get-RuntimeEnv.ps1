# Get-RuntimeEnv.ps1 - 检测本机各语言运行时版本与可执行文件路径（未配置环境的语言输出为空）
# 说明（关键健壮性处理）：
#   1) 统一用 Write-Output 输出（走 success stream / stdout），与 Get-SystemInfo.ps1 同款处理。
#   2) 外部命令的版本输出可能走 stderr（java -version 等），一律 2>&1 合并后取首行。
#   3) 命令不存在、执行失败（如 Windows 商店版 python stub）一律视为"未配置"，版本输出为空。
#   4) 检测属于只读操作，任何单项失败都不应中断整体输出。

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

# ---- 逐语言检测 ----
# PowerShell 5.1（系统自带 powershell.exe，即脚本当前运行环境）
$ps51Path = (Get-Process -Id $PID).Path
$ps51Ver = ''
try { $ps51Ver = [string]$PSVersionTable.PSVersion } catch { }

# PowerShell 7（pwsh，可选安装；版本取文件属性，避免额外启动 pwsh 进程）
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

# cmd（cmd.exe 版本即 Windows 系统版本）
$cmdPath = $env:ComSpec
$cmdVer = ''
try { $cmdVer = (Get-Item $cmdPath).VersionInfo.ProductVersion } catch { }

# bash（Git Bash 等，未加入 PATH 则视为未配置）
$bashInfo = Get-Runtime 'bash' @('--version') 'version\s+([^\s,]+)'
$bashVer = if ($bashInfo) { $bashInfo.Version } else { '' }
$bashPath = if ($bashInfo) { $bashInfo.Path } else { '' }

# java（java -version 输出在 stderr，已 2>&1 合并）
$javaInfo = Get-Runtime 'java' @('-version')
$javaVer = if ($javaInfo) { $javaInfo.Version } else { '' }
$javaPath = if ($javaInfo) { $javaInfo.Path } else { '' }

# python（Windows 商店 stub 未安装真 Python 时执行失败，会被视为未配置）
$pyInfo = Get-Runtime 'python' @('--version') '' '^Python\s+'
if (-not $pyInfo -or -not $pyInfo.Version) { $pyInfo = Get-Runtime 'python3' @('--version') '' '^Python\s+' }
$pythonVer = if ($pyInfo) { $pyInfo.Version } else { '' }
$pythonPath = if ($pyInfo) { $pyInfo.Path } else { '' }

# node
$nodeInfo = Get-Runtime 'node' @('--version')
$nodeVer = if ($nodeInfo) { $nodeInfo.Version } else { '' }
$nodePath = if ($nodeInfo) { $nodeInfo.Path } else { '' }

# go
$goInfo = Get-Runtime 'go' @('version') '' '^go version\s+'
$goVer = if ($goInfo) { $goInfo.Version } else { '' }
$goPath = if ($goInfo) { $goInfo.Path } else { '' }

# rust
$rustInfo = Get-Runtime 'rustc' @('--version') '' '^rustc\s+'
$rustVer = if ($rustInfo) { $rustInfo.Version } else { '' }
$rustPath = if ($rustInfo) { $rustInfo.Path } else { '' }

# ---- 输出 ----
Say '=========================================='
Say ' 运行环境检测'
Say '=========================================='
SayC $YELLOW '信息' '各语言运行时版本与可执行文件路径'
Say ''
$rows = @(
    @{ Lang = 'PowerShell 5.1'; Version = $ps51Ver;   Path = $ps51Path },
    @{ Lang = 'PowerShell 7';   Version = $pwshVer;   Path = $pwshPath },
    @{ Lang = 'cmd';            Version = $cmdVer;    Path = $cmdPath },
    @{ Lang = 'bash';           Version = $bashVer;   Path = $bashPath },
    @{ Lang = 'java';           Version = $javaVer;   Path = $javaPath },
    @{ Lang = 'python';         Version = $pythonVer; Path = $pythonPath },
    @{ Lang = 'node';           Version = $nodeVer;   Path = $nodePath },
    @{ Lang = 'go';             Version = $goVer;     Path = $goPath },
    @{ Lang = 'rust';           Version = $rustVer;   Path = $rustPath }
)
foreach ($r in $rows) {
    Say "[$($r.Lang)]"
    if ($r.Path) {
        $ver = $r.Version
        if ([string]::IsNullOrWhiteSpace($ver)) { $ver = '未知' }
        Say "版本号：$ver"
        Say "可执行文件路径：$($r.Path)"
    } else {
        Say '未检测到运行时环境'
    }
    Say ''
}
Say '=========================================='
SayC $GREEN '结果' '完成'
Say '=========================================='
