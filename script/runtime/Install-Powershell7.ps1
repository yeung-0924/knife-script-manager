# 更新时间: 2026-09-04 18:16:34
# Install-Powershell7.ps1 - 安装 PowerShell 7（含 pwsh.exe）
#   下载源（DOWNLOAD_SOURCE）：
#     Microsoft = 通过 WinGet（Microsoft.PowerShell）从微软官方渠道安装（默认，二进制来自微软 CDN，系统级目录）
#     GitHub    = 从 GitHub 下载官方「解压即用」zip 包到自定义 runtime 目录（与 Install-Node 同套约定）
# 说明（与 Install-Node.ps1 / Install-Go.ps1 同一套约定）：
#   1) 统一用 Write-Output 输出（走 success stream / stdout），避免重定向场景下日志丢失。
#   2) 下载用 HttpWebRequest 流式读取，在主线程每 5 秒打印一次进度。
#   3) zip 用系统 ZipFile 解压。
#   4) 版本解析：GitHub 源直接使用所选大版本的首个稳定版（如 7.5 → 7.5.0），不再依赖 api.github.com（受限网络常被墙）；
#      Microsoft 源通过 WinGet（Microsoft.PowerShell）安装，版本固定为所选大版本的 .0 正式版（如 7.5.0），二进制来自微软官方渠道。
#   5) 覆盖原文件=否（默认）：安装目录已有同大版本 PowerShell 目录时跳过下载解压直接复用；=是 则先删再装。
#   6) PATH 通过 SCRIPT_MANAGER_ENV 聚合变量统一管理：Path 写入实际路径（CMD 不展开自定义 %VAR% 引用），
#      SCRIPT_MANAGER_ENV 单独保留作为聚合记录。
#   7) PowerShell 7 是自包含解压包（不需要 POWERSHELL_HOME 之类环境变量），故只提供「设置 PATH」选项。

# 输出 UTF-8（脚本单独运行时也保证中文不乱码）
# 包 try/catch：输出被重定向、无控制台时该赋值可能抛异常，不能让它中断脚本
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8
} catch {
    # 忽略：执行器已在 -Command 中设置过 [Console]::OutputEncoding
}

$ErrorActionPreference = 'Stop'

# ---- 颜色（ANSI SGR）：入参/结果亮绿(92)、信息亮黄(93)、异常亮红(91) ----
$ESC = [char]27
$GREEN = "$ESC[92m"; $YELLOW = "$ESC[93m"; $RED = "$ESC[91m"; $RESET = "$ESC[0m"
function Say { param([string]$Text = '') Write-Output $Text }
function SayC { param([string]$Color, [string]$Tag, [string]$Text) Write-Output "$Color[$Tag]$RESET $Text" }

# ---- 通用下载（流式 + 进度），供 GitHub 源使用；失败返回 $false 而非抛异常 ----
function Invoke-DownloadFile {
    param([string]$Url, [string]$Dest)
    try {
        $req = [System.Net.HttpWebRequest]::Create($Url)
        $req.Timeout = 60000
        $req.UserAgent = 'knife-script-manager'
        $resp = $req.GetResponse()
        $total = $resp.ContentLength
        $stream = $resp.GetResponseStream()
        $fs = New-Object System.IO.FileStream($Dest, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        $buffer = New-Object byte[] (1024 * 256)
        $read = 0
        $nextReport = [DateTime]::Now.AddSeconds(5)
        SayC $YELLOW '信息' "开始下载（共 $([math]::Round($total / 1MB, 1)) MB）"
        while (($n = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fs.Write($buffer, 0, $n); $read += $n
            if ([DateTime]::Now -ge $nextReport) {
                if ($total -gt 0) {
                    $pct = [int](($read * 100) / $total)
                    SayC $YELLOW '信息' "下载进度: $pct%（$([math]::Round($read / 1MB, 1)) / $([math]::Round($total / 1MB, 1)) MB）"
                } else {
                    SayC $YELLOW '信息' "下载进度: 已下载 $([math]::Round($read / 1MB, 1)) MB"
                }
                $nextReport = [DateTime]::Now.AddSeconds(5)
            }
        }
        $fs.Close(); $stream.Close(); $resp.Close()
        return $true
    } catch {
        SayC $RED '异常' "下载失败: $($_.Exception.Message)"
        return $false
    }
}

# ---- 定位 winget.exe：多层回退，提权/非交互环境下也能找到 ----
function Find-WingetExe {
    # 1) PATH 中的 winget（非提权常可用）
    try {
        $c = Get-Command winget.exe -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    } catch { }
    # 2) App Execution Alias（每用户 WindowsApps，非提权可用；提权下可能失效，仅作兜底）
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path $alias) { return $alias }
    # 3) 真实二进制：WindowsApps 下的 DesktopAppInstaller 包目录（提权下可被调用，最可靠）
    $waRoot = Join-Path $env:ProgramFiles 'WindowsApps'
    if (Test-Path $waRoot) {
        $pkgs = Get-ChildItem -Path $waRoot -Directory -Filter 'Microsoft.DesktopAppInstaller_*_x64*' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($pkgs) {
            $real = Join-Path $pkgs.FullName 'winget.exe'
            if (Test-Path $real) { return $real }
        }
    }
    return $null
}

# ---- 入参（工具在执行前把 _p{XXX} 占位符替换为用户的输入值）----
$InstallDir     = "_p{INSTALL_DIR}"
$Version        = "_p{VERSION}"
$DownloadSource = "_p{DOWNLOAD_SOURCE}"
$Overwrite      = "_p{OVERWRITE}"
$AddToPath      = "_p{SET_PATH}"

# 缺省兜底：用户未填时给一个合理默认，避免空值导致后续解析报错
if ([string]::IsNullOrWhiteSpace($Version))        { $Version = 'PowerShell 7.6 (LTS)' }
if ([string]::IsNullOrWhiteSpace($DownloadSource)) { $DownloadSource = 'Microsoft' }
if ([string]::IsNullOrWhiteSpace($Overwrite))      { $Overwrite = '否' }
if ([string]::IsNullOrWhiteSpace($AddToPath))      { $AddToPath = '是' }

Say '=========================================='
Say ' 安装 Powershell7 运行时环境'
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
SayC $GREEN '入参' "安装目录: $InstallDir"
SayC $GREEN '入参' "PowerShell 版本: $Version"
SayC $GREEN '入参' "下载源: $DownloadSource"
SayC $GREEN '入参' "覆盖原文件: $Overwrite"
SayC $GREEN '入参' "追加到 PATH: $AddToPath"

# ---- 参数校验 ----
# 安装目录留空时回退到默认：exe 同级 runtime 目录（由执行器注入 SCRIPT_MANAGER_RUNTIME）。
# 不依赖进程工作目录——提权执行时 ShellExecute 会把工作目录强制改为 System32。
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = $env:SCRIPT_MANAGER_RUNTIME
    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        SayC $RED '异常' '安装目录为空，且未获取到默认安装目录（SCRIPT_MANAGER_RUNTIME），请手动选择目标目录'
        exit 1
    }
    SayC $YELLOW '信息' "安装目录留空，使用默认目录: $InstallDir"
}
if ($Overwrite -ne '是' -and $Overwrite -ne '否') {
    SayC $RED '异常' "覆盖原文件取值无效「$Overwrite」，应为 是/否"
    exit 1
}
if ($DownloadSource -ne 'Microsoft' -and $DownloadSource -ne 'GitHub') {
    SayC $RED '异常' "下载源取值无效「$DownloadSource」，应为 Microsoft / GitHub"
    exit 1
}
# 从版本选项（如 "PowerShell 7.5"、"PowerShell 7.4 (LTS)"）中提取大版本号（如 7.5）
$majorMatch = [regex]::Match($Version, '(\d+\.\d+)')
if (-not $majorMatch.Success) {
    SayC $RED '异常' "无法从「$Version」中识别 PowerShell 大版本号"
    exit 1
}
$major = $majorMatch.Groups[1].Value

# ---- 架构检测（同 Install-Node.ps1：优先 .NET OSArchitecture，回退环境变量）----
# PowerShell 7 官方 win 包架构名：x64 / arm64（x86 自 7.4 起仍提供，但此处仅覆盖主流两架构）
$pwshArch = 'x64'
$archRaw = ''
try {
    $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ($osArch -eq [System.Runtime.InteropServices.Architecture]::Arm64 -or $osArch -eq [System.Runtime.InteropServices.Architecture]::Arm) {
        $pwshArch = 'arm64'
        $archRaw = 'ARM64'
    } else {
        $pwshArch = 'x64'
        $archRaw = 'x64 (AMD64)'
    }
} catch {
    $archRaw = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ($archRaw -eq 'ARM64') { $pwshArch = 'arm64' } else { $pwshArch = 'x64' }
}
SayC $YELLOW '信息' "系统架构: $archRaw -> 包架构 = $pwshArch"

# ---- 查找安装目录中已存在的同大版本 PowerShell 目录（解压目录名自带完整版本，天然多版本共存）----
function Find-MatchingPwsh {
    param([string]$Dir, [string]$Major)
    Get-ChildItem -Path $Dir -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $m = [regex]::Match($_.Name, '^PowerShell-(\d+\.\d+)\.\d+-win-(x64|arm64)$')
            if (-not $m.Success) { return $false }
            if ($m.Groups[1].Value -ne $Major) { return $false }
            if (-not (Test-Path (Join-Path $_.FullName 'pwsh.exe'))) { return $false }
            return $true
        } |
        Select-Object -First 1
}

# 判断一个 PATH 分段是否是 PowerShell 7 安装目录（目录名 PowerShell-7.x.x-win-xxx 且含 pwsh.exe）
function Test-IsPwshHomePath {
    param([string]$Segment)
    $s = $Segment.TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    if ($s -notmatch '\\PowerShell-(\d+\.\d+)\.\d+-win-(x64|arm64)$') { return $false }
    if (-not (Test-Path (Join-Path $s 'pwsh.exe'))) { return $false }
    return $true
}

# ---- GitHub 源：下载官方「解压即用」zip 包到自定义目录，返回解压出的 PowerShell 目录绝对路径 ----
# 失败时返回 $null（不再 exit 1），由主流程统一收口报错，避免回退场景漏成含糊的 null 崩溃。
function Install-ViaGitHub {
    param([string]$Major, [string]$InstallDir, [string]$Overwrite)
    # 覆盖模式：先删除同大版本的旧 PowerShell 目录
    if ($Overwrite -eq '是') {
        $oldPwsh = Find-MatchingPwsh -Dir $InstallDir -Major $Major
        if ($oldPwsh) {
            SayC $YELLOW '信息' "覆盖模式：删除旧目录 $($oldPwsh.FullName)"
            try {
                Remove-Item -Path $oldPwsh.FullName -Recurse -Force -ErrorAction Stop
            } catch {
                SayC $RED '异常' "删除旧目录失败: $($_.Exception.Message)"
                SayC $RED '异常' '请先关闭占用该目录的程序（如正在运行的 pwsh 进程），或手动删除后重试'
                return $null
            }
        }
    }

    # ---- 版本推导：给定大版本（如 7.5）直接使用该系列首个稳定版（如 7.5.0）----
    # 不依赖 api.github.com（受限网络常被墙），避免「查询版本」这一步就失败
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $pwshVer = "$Major.0"
    SayC $YELLOW '信息' "PowerShell 版本: $pwshVer（大版本 $Major 的首个稳定版）"

    # ---- 下载（流式 + 进度；主源 GitHub + 镜像回退，提升受限网络下的成功率）----
    $tmpDir = Join-Path $env:TEMP 'script-manager-pwsh'
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
    $zipPath = Join-Path $tmpDir "PowerShell-$pwshVer-win-$pwshArch.zip"

    $primaryUrl = "https://github.com/PowerShell/PowerShell/releases/download/v$pwshVer/PowerShell-$pwshVer-win-$pwshArch.zip"
    $mirrorUrl  = "https://mirror.ghproxy.com/https://github.com/PowerShell/PowerShell/releases/download/v$pwshVer/PowerShell-$pwshVer-win-$pwshArch.zip"
    $mirrorUrl2 = "https://ghproxy.net/https://github.com/PowerShell/PowerShell/releases/download/v$pwshVer/PowerShell-$pwshVer-win-$pwshArch.zip"
    $urls = @($primaryUrl, $mirrorUrl, $mirrorUrl2)
    $ok = $false
    foreach ($u in $urls) {
        SayC $YELLOW '信息' "尝试下载源: $u"
        if (Invoke-DownloadFile -Url $u -Dest $zipPath) { $ok = $true; break }
    }
    if (-not $ok) {
        SayC $RED '异常' '所有下载源均失败：请检查网络（需可访问 GitHub 或其镜像），或手动下载便携 zip 后解压'
        return $null
    }
    SayC $GREEN '结果' "下载完成: $zipPath"

    # ---- 解压（ZipFile）----
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    SayC $YELLOW '信息' "解压到: $InstallDir（请稍候）"
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $InstallDir)
    } catch {
        SayC $RED '异常' "解压失败: $($_.Exception.Message)"
        SayC $RED '异常' '若目标位于 Program Files 等受保护目录，请换一个目录，或以管理员身份运行'
        return $null
    }
    SayC $GREEN '结果' '解压完成'

    # 清理临时压缩包（失败不影响结果）
    try { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue } catch { }

    # ---- 定位本次解压出的 PowerShell 目录 ----
    $found = Find-MatchingPwsh -Dir $InstallDir -Major $Major
    if (-not $found) {
        SayC $RED '异常' "解压后未找到 PowerShell 目录（含 pwsh.exe），请检查目录: $InstallDir"
        return $null
    }
    return $found.FullName
}

# ---- Microsoft 源辅助：在系统 PowerShell 目录中查找已安装的 pwsh.exe（按大版本匹配）----
function Find-WinGetPwsh {
    param([string]$Major)
    # 同时覆盖系统目录（--scope machine）与每用户安装位置，避免提权/非提权差异导致漏检
    $roots = @(
        'C:\Program Files\PowerShell',
        'C:\Program Files (x86)\PowerShell',
        (Join-Path $env:LOCALAPPDATA 'Microsoft\PowerShell')
    )
    foreach ($r in $roots) {
        if (-not (Test-Path $r)) { continue }
        $exe = Get-ChildItem -Path $r -Recurse -Filter pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($exe) {
            try {
                $v = (& $exe.FullName --version 2>&1 | Out-String)
                if ($v -match '(\d+\.\d+)' -and $Matches[1] -eq $Major) { return $exe.DirectoryName }
            } catch { }
        }
    }
    return $null
}

# ---- Microsoft 源：通过 WinGet 安装 Microsoft.PowerShell（二进制来自微软官方渠道）----
# 返回解压/安装出的 PowerShell 目录绝对路径；失败（winget 缺失/安装异常/未找到）返回 $null，由调用方如实报错（不再回退到其他下载源）
function Install-ViaWinGet {
    param([string]$Major)
    # 定位 winget.exe：多层回退（PATH → App Execution Alias → WindowsApps 内真实二进制），提权下也能找到
    $wingetExe = Find-WingetExe
    if (-not $wingetExe) {
        SayC $RED '异常' '未找到 winget.exe（Microsoft 源依赖 WinGet 安装 PowerShell），请先安装「应用安装程序(App Installer)」'
        SayC $YELLOW '信息' '可改用「下载源=GitHub」；或手动安装 App Installer 后重试'
        return $null
    }
    $wingetVer = "$Major.0"
    SayC $YELLOW '信息' "Microsoft 源：通过 WinGet 安装 Microsoft.PowerShell 版本 $wingetVer ..."
    SayC $YELLOW '信息' '注：WinGet 安装至系统 PowerShell 目录（默认 C:\Program Files\PowerShell\7），将忽略自定义安装目录'
    try {
        $p = Start-Process -FilePath $wingetExe -ArgumentList @(
            'install', '--id', 'Microsoft.PowerShell', '--source', 'winget', '--version', $wingetVer,
            '--scope', 'machine',
            '--accept-package-agreements', '--accept-source-agreements', '--silent'
        ) -Wait -PassThru -WindowStyle Hidden
        SayC $YELLOW '信息' "WinGet 退出码: $($p.ExitCode)"
    } catch {
        SayC $RED '异常' "WinGet 安装异常: $($_.Exception.Message)"
    }
    # 无论退出码都尝试定位 pwsh.exe（已安装时 WinGet 返回特定码而非 0）
    $pwshHome = Find-WinGetPwsh -Major $Major
    if ($pwshHome) { return $pwshHome }
    SayC $RED '异常' "WinGet 安装后未找到 pwsh.exe，可能安装失败、被安全策略拦截，或装到了非系统目录"
    return $null
}

# 当前进程是否具备管理员权限（决定环境变量写系统级 Machine 还是用户级 User）
function Test-IsAdministrator {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

# ---- SCRIPT_MANAGER_ENV 聚合变量（与 Install-Node.ps1 同一套机制）----
# 读取聚合变量（Machine + User 两个作用域合并去重，保证切换过作用域后不丢条目）
function Get-ScriptManagerEnv {
    $items = @()
    foreach ($s in @('Machine', 'User')) {
        $raw = [Environment]::GetEnvironmentVariable('SCRIPT_MANAGER_ENV', $s)
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $items += $raw -split ';'
        }
    }
    $items = $items | ForEach-Object { $_.TrimEnd('\') } |
        Where-Object { $_ } |
        Select-Object -Unique
    return ($items -join ';')
}

# 读取指定作用域的 SCRIPT_MANAGER_ENV 条目（返回数组，用于写 Path 时避免跨作用域污染）
function Get-ScriptManagerEnvForScope {
    param([string]$Scope)
    $raw = [Environment]::GetEnvironmentVariable('SCRIPT_MANAGER_ENV', $Scope)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    return @($raw -split ';' | ForEach-Object { $_.TrimEnd('\') } | Where-Object { $_ } | Select-Object -Unique)
}

# 把新目录前置进 SCRIPT_MANAGER_ENV；$IsOldEntry 脚本块用于判定应移除的旧条目（按运行时特征）
function Add-ScriptManagerEnvEntry {
    param([string]$BinDir, [string]$Scope, [scriptblock]$IsOldEntry)
    $binNorm = $BinDir.TrimEnd('\')
    $current = Get-ScriptManagerEnv
    if ([string]::IsNullOrWhiteSpace($current)) {
        $newVal = $binNorm
    } else {
        # 注意：ForEach-Object 中 return $null 会在数组里留下 null 元素，必须用 Where-Object 过滤后再 join
        $items = @($current -split ';' | ForEach-Object {
            $s = $_.TrimEnd('\')
            if ([string]::IsNullOrWhiteSpace($s)) { return $null }
            if ($s -ieq $binNorm) { return $null }
            if (& $IsOldEntry $s) { return $null }
            return $s
        } | Where-Object { $_ } | Select-Object -Unique)
        $newVal = ($binNorm + ';' + ($items -join ';')).Trim(';')
    }
    [Environment]::SetEnvironmentVariable('SCRIPT_MANAGER_ENV', $newVal, $Scope)
}

# 确保指定作用域 PATH 前置 SCRIPT_MANAGER_ENV 中的实际路径（去重后写回）
function Ensure-PathHasScriptManagerEnv {
    param([string]$Scope)
    $raw = [Environment]::GetEnvironmentVariable('Path', $Scope)
    $envPaths = Get-ScriptManagerEnvForScope -Scope $Scope
    if ($envPaths.Count -eq 0) { return }
    $envValue = $envPaths -join ';'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $newPath = $envValue
    } else {
        $segments = @($raw -split ';' | ForEach-Object {
            $s = $_.TrimEnd('\')
            if ([string]::IsNullOrWhiteSpace($s)) { return $null }
            # 移除旧版遗留的 %SCRIPT_MANAGER_ENV% 字面量（兼容旧数据）
            if ($s -ieq '%SCRIPT_MANAGER_ENV%') { return $null }
            # 移除已经存在于 SCRIPT_MANAGER_ENV 中的路径，避免重复
            if ($envPaths -contains $s) { return $null }
            return $s
        } | Where-Object { $_ } | Select-Object -Unique)
        $newPath = $envValue + ';' + ($segments -join ';')
    }
    [Environment]::SetEnvironmentVariable('Path', $newPath, $Scope)
}

# ---- 主流程：按下载源分支（Microsoft=WinGet / GitHub=便携 zip）；已存在则按需复用或重装 ----
# 安装函数统一「成功返回目录路径 / 失败返回 $null」（不再 exit 1），由本段统一收口报错，
# 避免失败被赋成 $null 后漏到下游、抛出含糊的「参数绑定为 null」错误。
$pwshHome = $null
if ($DownloadSource -ieq 'Microsoft') {
    # ==================== Microsoft 源：WinGet 安装（微软官方渠道）====================
    # 用户选了什么就用什么：不再回退到 GitHub，失败如实提示原因与建议。
    $existingWinGet = $null
    if ($Overwrite -eq '否') { $existingWinGet = Find-WinGetPwsh -Major $major }
    if ($existingWinGet) {
        SayC $YELLOW '信息' "检测到已通过 WinGet 安装 PowerShell $major : $existingWinGet，跳过安装"
        $pwshHome = $existingWinGet
    } else {
        # Install-ViaWinGet 内部用 SayC(Write-Output) 打印诊断，调用方若直接 `$x = Func` 会把诊断行也收进 $x（变成数组），
        # 导致路径变量变成诊断文本而非目录。return 值是 pipeline 最后一个元素，用 [-1] 只取它。
        $pwshHome = @(Install-ViaWinGet -Major $major)[-1]
    }
} else {
    # ==================== GitHub 源：便携 zip（用户显式选择）====================
    $existingPwsh = $null
    if ($Overwrite -eq '否') {
        $existingPwsh = Find-MatchingPwsh -Dir $InstallDir -Major $major
    }
    if ($existingPwsh) {
        SayC $YELLOW '信息' "检测到已安装 PowerShell $major : $($existingPwsh.FullName)，跳过下载与解压"
        $pwshHome = $existingPwsh.FullName
    } else {
        # 同上：用 [-1] 取 return 值，避免 SayC 诊断行污染路径变量
        $pwshHome = @(Install-ViaGitHub -Major $major -InstallDir $InstallDir -Overwrite $Overwrite)[-1]
    }
}

# ---- 兜底收口：所选下载源未能产出可用 pwsh 目录时，如实提示原因与建议后退出（不回退、不堆异常） ----
if ([string]::IsNullOrWhiteSpace($pwshHome)) {
    if ($DownloadSource -ieq 'Microsoft') {
        SayC $RED '失败' "PowerShell $major 安装失败（下载源=Microsoft / WinGet）：未得到可用的 pwsh.exe"
        SayC $YELLOW '原因' "常见原因：① 本机未安装「应用安装程序(App Installer)」，找不到 winget.exe；② 安全策略/组策略拦截了 WinGet 安装；③ WinGet 装到了非系统目录导致未能定位"
        SayC $YELLOW '建议' "请确认已安装 App Installer 且可联网后重试；或切换其他下载源"
    } else {
        SayC $RED '失败' "PowerShell $major 安装失败（下载源=GitHub）：下载或解压未能产出可用的 pwsh.exe"
        SayC $YELLOW '原因' "常见原因：① 网络不可达 GitHub（受限网络常被墙）；② 临时目录/安装目录无写入权限；③ 磁盘空间不足"
        SayC $YELLOW '建议' "请确认可访问 github.com（或改用「下载源=Microsoft」）；亦可手动到 https://github.com/PowerShell/PowerShell/releases 下载便携 zip 解压到安装目录"
    }
    exit 1
}
try {
    # 双重保险：即便任何路径下 $pwshHome 仍为空，也在这里捕获并输出明确错误，绝不让含糊的 Join-Path 崩溃冒泡到用户日志
    $pwshExe = Join-Path $pwshHome 'pwsh.exe'
} catch {
    SayC $RED '异常' "拼接 pwsh.exe 路径失败（pwshHome=$pwshHome）：$($_.Exception.Message)"
    exit 1
}
if (-not (Test-Path $pwshExe)) {
    SayC $RED '异常' "安装目录存在但缺少 pwsh.exe: $pwshHome"
    exit 1
}

# ---- 验证（pwsh --version 输出 2>&1 合并后原色输出）----
SayC $YELLOW '信息' '验证 pwsh --version:'
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $verOut = (& $pwshExe --version 2>&1 | Out-String)
} finally {
    $ErrorActionPreference = $oldEap
}
$verOut.TrimEnd()

# ---- 写环境变量 ----
# 管理员（工具已配 admin=true 提权）-> 写系统级 Machine；拒绝提权（非管理员）-> 回退用户级 User
$isAdmin = Test-IsAdministrator
$scope = if ($isAdmin) { 'Machine' } else { 'User' }
if (-not $isAdmin) {
    SayC $YELLOW '信息' '当前未以管理员运行，环境变量写入【用户级】。若系统 PATH 里还有其他 PowerShell，可能仍优先于本版本。'
}

if ($AddToPath -eq '是') {
    try {
        # PowerShell 7 是自包含解压包，pwsh.exe 在解压根目录（同 Node 的 node.exe 所在目录）
        $binDir = $pwshHome
        $binDirNorm = $binDir.TrimEnd('\')

        # 顺序很重要（同 Install-Node.ps1）：先建好新条目（SCRIPT_MANAGER_ENV + PATH 前置），
        # 再清理旧 PowerShell 绝对路径。避免「旧路径删了、新条目没建成」导致 pwsh 彻底找不到。
        # 1) 把本次 PowerShell 目录前置进 SCRIPT_MANAGER_ENV，同时移除聚合变量里旧的 PowerShell 条目
        #    （脚本块匹配 PowerShell 特征；java/node/python/go 等其他运行时条目保留不动）
        Add-ScriptManagerEnvEntry -BinDir $binDir -Scope $scope -IsOldEntry {
            param([string]$s)
            Test-IsPwshHomePath $s
        }
        SayC $GREEN '结果' "已把 PowerShell 目录写入 SCRIPT_MANAGER_ENV（$scope）: $binDir"

        # 2) 确保主作用域 PATH 前置 SCRIPT_MANAGER_ENV 中的实际路径（CMD 不会展开 %VAR% 引用）
        Ensure-PathHasScriptManagerEnv -Scope $scope
        SayC $GREEN '结果' "已把 SCRIPT_MANAGER_ENV 中的实际路径前置到 $scope PATH"

        # 3) 最后清理：从 Machine + User 两级 PATH 移除旧的 PowerShell 绝对路径（目录名特征 + 含 pwsh.exe）
        #    此时新路径已就位，删旧路径不会造成 pwsh 缺失。
        #    保护当前 SCRIPT_MANAGER_ENV 中的路径，避免把刚写进去的新 PowerShell 误删。
        $protectedPaths = @((Get-ScriptManagerEnvForScope -Scope 'Machine') + (Get-ScriptManagerEnvForScope -Scope 'User') | Select-Object -Unique)
        foreach ($oldScope in @('Machine', 'User')) {
            $rawOld = [Environment]::GetEnvironmentVariable('Path', $oldScope)
            if ([string]::IsNullOrWhiteSpace($rawOld)) { continue }
            $removed = @()
            $segmentsOld = @($rawOld -split ';' | ForEach-Object {
                $s = $_.TrimEnd('\')
                if ([string]::IsNullOrWhiteSpace($s)) { return $null }
                if ((Test-IsPwshHomePath $s) -and -not ($protectedPaths -contains $s)) {
                    $script:removed += $s
                    return $null
                }
                return $s
            } | Where-Object { $_ } | Select-Object -Unique)
            $newRaw = $segmentsOld -join ';'
            # 防御：过滤后为空（该作用域 PATH 只剩 PowerShell 项）时跳过写入，避免把 PATH 清空
            if (-not [string]::IsNullOrWhiteSpace($newRaw) -and $newRaw -ne $rawOld) {
                [Environment]::SetEnvironmentVariable('Path', $newRaw, $oldScope)
                foreach ($r in $removed) {
                    SayC $YELLOW '信息' "已从 $oldScope PATH 移除旧 PowerShell 路径: $r"
                }
            }
        }
    } catch {
        SayC $RED '异常' "更新 PATH 失败: $($_.Exception.Message)"
    }
}

Say ''
Say '=========================================='
SayC $GREEN '结果' "PowerShell $major 安装完成"
SayC $GREEN '结果' "PowerShell 目录: $pwshHome"
if ($AddToPath -eq '是') {
    SayC $GREEN '结果' "已加入 SCRIPT_MANAGER_ENV: $pwshHome"
    SayC $YELLOW '信息' '工具管理的所有运行时 bin 统一记录在 SCRIPT_MANAGER_ENV，PATH 中写入实际路径'
    SayC $YELLOW '信息' "查看当前内容（新终端）: echo %SCRIPT_MANAGER_ENV%"
    SayC $YELLOW '信息' "切换 PowerShell 版本: 更新 SCRIPT_MANAGER_ENV 后，重新运行安装脚本同步 PATH"
    SayC $YELLOW '信息' "环境变量已写入【$scope 级】，新打开的终端才会生效"
}
Say '=========================================='
