# Install-Python.ps1 - 自动安装 Python，支持两种下载源：
#   A) 华为云镜像（默认，国内直连快）：下载 python.org 官方安装器并静默安装（/quiet），
#      路径 https://mirrors.huaweicloud.com/python/<版本>/python-<版本>-<架构>.exe
#   B) GitHub 官方：astral-sh/python-build-standalone 的 install_only 包，解压即用，
#      版本通过 GitHub API 动态匹配资产；可选 MIRROR_PREFIX 代理前缀加速下载。
# 说明（几个关键健壮性处理，与 Install-Java.ps1 同一套约定）：
#   1) 统一用 Write-Output 输出（走 success stream / stdout），避免重定向场景下日志丢失。
#   2) 下载用 HttpWebRequest 流式读取，在主线程每 20% 打印一次进度。
#   3) 解压用系统自带 tar.exe（Windows 10 1803+ 内置），install_only 包是 tar.gz。
#   4) 管理员（工具已配 admin=true 提权）写系统级 Machine；拒绝提权时回退用户级 User。
#   5) 版本通过 Python 3.x 主版本动态获取最新补丁，不硬编码具体补丁号。
#   6) 覆盖原文件=否（默认）：GitHub 模式下安装目录已有 python 目录（含 python.exe）时跳过下载解压直接复用；
#      覆盖原文件=是：先删除已存在的 python 目录，再重新下载解压。（华为云安装器模式每次幂等重装，忽略此参数）
#   7) 已知限制：Windows ARM64 的 Python 自 3.11 起才有官方构建，3.10 及更早只有 x64（任何下载源都没有）。
#   8) PATH 通过 SCRIPT_MANAGER_ENV 聚合变量统一管理：Path 写入实际路径（CMD 不展开自定义 %VAR% 引用），
#      SCRIPT_MANAGER_ENV 单独保留作为聚合记录。

# 输出 UTF-8（脚本单独运行时也保证中文不乱码）
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

# ---- 入参（工具在执行前把 _p{XXX} 占位符替换为用户的输入值）----
$InstallDir     = "_p{INSTALL_DIR}"
$Version        = "_p{VERSION}"
$DownloadSource = "_p{DOWNLOAD_SOURCE}"
$MirrorPrefix   = "_p{MIRROR_PREFIX}"
$Overwrite      = "_p{OVERWRITE}"
$AddToPath      = "_p{SET_PATH}"

# 缺省兜底
if ([string]::IsNullOrWhiteSpace($Version))        { $Version = 'Python 3.12' }
if ([string]::IsNullOrWhiteSpace($DownloadSource)) { $DownloadSource = '华为云镜像' }
if ([string]::IsNullOrWhiteSpace($Overwrite))      { $Overwrite = '否' }
if ([string]::IsNullOrWhiteSpace($AddToPath))      { $AddToPath = '是' }

Say '=========================================='
Say ' 自动安装 Python（官方安装器 / 解压即用）'
Say '=========================================='
SayC $GREEN '入参' "安装目录: $InstallDir"
SayC $GREEN '入参' "Python 版本: $Version"
SayC $GREEN '入参' "下载源: $DownloadSource"
if (-not [string]::IsNullOrWhiteSpace($MirrorPrefix)) {
    SayC $GREEN '入参' "代理前缀: $MirrorPrefix"
}
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
if ($DownloadSource -ne '华为云镜像' -and $DownloadSource -ne 'GitHub 官方') {
    SayC $RED '异常' "下载源取值无效「$DownloadSource」，应为 华为云镜像 / GitHub 官方"
    exit 1
}
# 从版本选项（如 "Python 3.12"）中提取 主.次 版本号（如 3.12）
$verMatch = [regex]::Match($Version, '(\d+\.\d+)')
if (-not $verMatch.Success) {
    SayC $RED '异常' "无法从「$Version」中识别 Python 版本号"
    exit 1
}
$majorMinor = $verMatch.Groups[1].Value

# ---- 架构检测（同 Install-Java.ps1：优先 .NET OSArchitecture，回退环境变量）----
# python-build-standalone 的 Windows 包架构名：x86_64 / aarch64
$pbsArch = 'x86_64'
$archRaw = ''
try {
    $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ($osArch -eq [System.Runtime.InteropServices.Architecture]::Arm64 -or $osArch -eq [System.Runtime.InteropServices.Architecture]::Arm) {
        $pbsArch = 'aarch64'
        $archRaw = 'ARM64'
    } else {
        $pbsArch = 'x86_64'
        $archRaw = 'x64 (AMD64)'
    }
} catch {
    $archRaw = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ($archRaw -eq 'ARM64') { $pbsArch = 'aarch64' } else { $pbsArch = 'x86_64' }
}
SayC $YELLOW '信息' "系统架构: $archRaw -> 包架构 = $pbsArch"

# ---- 查找安装目录中已存在的 python 目录（install_only 包解压后目录名固定为 python）----
function Find-MatchingPython {
    param([string]$Dir)
    Get-ChildItem -Path $Dir -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            if ($_.Name -inotmatch '^python3?\d*(\.\d+)?$') { return $false }
            if (-not (Test-Path (Join-Path $_.FullName 'python.exe'))) { return $false }
            return $true
        } |
        Select-Object -First 1
}

# 判断一个 PATH 分段是否是 Python 安装目录（目录名形如 python / python3 / Python312 / python3.12，
# 且目录内含 python.exe；双保险避免误删用户自建的同名目录）
function Test-IsPythonHomePath {
    param([string]$Segment)
    $s = $Segment.TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    $leaf = Split-Path -Path $s -Leaf
    if ($leaf -inotmatch '^python3?\d*(\.\d+)?(-[a-z0-9]+)?$') { return $false }
    if (-not (Test-Path (Join-Path $s 'python.exe'))) { return $false }
    return $true
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

# ---- SCRIPT_MANAGER_ENV 聚合变量（与 Install-Java.ps1 同一套机制）----
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

# 把新 bin 目录前置进 SCRIPT_MANAGER_ENV；$IsOldEntry 脚本块用于判定应移除的旧条目（按运行时特征）
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

# ---- 已知限制：Windows ARM64 的 Python 自 3.11 起才有官方构建（python.org 与
#      python-build-standalone 均如此），3.10 及更早只有 x64，任何下载源都没有。提前拦截 ----
if ($pbsArch -eq 'aarch64' -and $majorMinor -in @('3.9', '3.10')) {
    SayC $RED '异常' "Python $majorMinor 没有 Windows ARM64 构建（ARM64 自 Python 3.11 起才提供），请选择 Python 3.11 及以上版本"
    exit 1
}

$pythonHome = $null
if ($DownloadSource -ieq '华为云镜像') {
    # ==================== 华为云镜像：python.org 官方安装器，静默安装 ====================
    # 1) 解析 https://mirrors.huaweicloud.com/python/ 目录，取该主版本最新的补丁版本
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $pyVer = $null
    SayC $YELLOW '信息' "从华为云镜像查询 Python $majorMinor 的最新版本..."
    try {
        $html = (Invoke-WebRequest -Uri 'https://mirrors.huaweicloud.com/python/' `
            -UseBasicParsing -Headers @{ 'User-Agent' = 'knife-script-manager' } -TimeoutSec 60 -ErrorAction Stop).Content
        $verPat = "^$([regex]::Escape($majorMinor))\.\d+$"
        $versions = @([regex]::Matches($html, 'href="([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value.TrimEnd('/') } |
            Where-Object { $_ -match $verPat } |
            ForEach-Object { [version]$_ })
        if ($versions.Count -gt 0) {
            $pyVer = ($versions | Sort-Object -Descending | Select-Object -First 1).ToString()
        }
    } catch {
        SayC $RED '异常' "查询华为云镜像失败: $($_.Exception.Message)"
        SayC $RED '异常' '请检查网络连接后重试'
        exit 1
    }
    if (-not $pyVer) {
        SayC $RED '异常' "华为云镜像未找到 Python $majorMinor 的发布版本，请换一个版本"
        exit 1
    }

    # 2) 下载官方安装器（arm64 / amd64）
    $pyArch = if ($pbsArch -eq 'aarch64') { 'arm64' } else { 'amd64' }
    $downloadUrl = "https://mirrors.huaweicloud.com/python/$pyVer/python-$pyVer-$pyArch.exe"
    SayC $YELLOW '信息' "下载链接: $downloadUrl"
    $tmpDir = Join-Path $env:TEMP 'script-manager-python'
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
    $exePath = Join-Path $tmpDir "python-$pyVer-$pyArch.exe"
    $fs = $null
    try {
        $req = [System.Net.HttpWebRequest]::Create($downloadUrl)
        $req.Timeout = 60000
        $req.UserAgent = 'knife-script-manager'
        $resp = $req.GetResponse()
        $total = $resp.ContentLength
        $stream = $resp.GetResponseStream()
        $fs = New-Object System.IO.FileStream($exePath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        $buffer = New-Object byte[] (1024 * 256)
        $read = 0
        $nextReport = [DateTime]::Now.AddSeconds(5)
        SayC $YELLOW '信息' "开始下载: python-$pyVer-$pyArch.exe（约 $([math]::Round($total / 1MB, 1)) MB）"
        while (($n = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fs.Write($buffer, 0, $n)
            $read += $n
            # 按时间节流（每 5 秒一次）：小文件不会刷屏，大文件也不会半天不报
            # 用 [DateTime]::Now 而非 Get-Date —— 循环每 256KB 调用一次，cmdlet 开销明显
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
        $fs.Close(); $fs = $null
        $stream.Close()
        $resp.Close()
    } catch {
        if ($fs) { $fs.Close() }
        SayC $RED '异常' "下载失败: $($_.Exception.Message)"
        SayC $RED '异常' '请检查网络，或稍后重试'
        exit 1
    }
    SayC $GREEN '结果' "下载完成: $exePath"

    # 3) 静默安装到指定目录（InstallAllUsers=1 需要管理员，工具已提权；/quiet 无界面）。
    #    注意：官方安装器每次都是全新安装（幂等），OVERWRITE 参数在此模式下不适用
    SayC $YELLOW '信息' "静默安装到: $InstallDir（请稍候，安装器无界面属正常）"
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }

    # 3.1) 提前诊断（1603 的两大常见根因，先提示并在失败时给针对性建议）：
    #      a) 官方安装器底层是 MSI，TargetDir 含中文等非 ASCII 字符时静默安装极易报 1603；
    #      b) 目标盘可用空间不足。
    $hasNonAscii = $false
    foreach ($ch in $InstallDir.ToCharArray()) {
        if ([int]$ch -gt 127) { $hasNonAscii = $true; break }
    }
    if ($hasNonAscii) {
        SayC $YELLOW '信息' "提示: 安装目录含中文等非 ASCII 字符，官方安装器基于 MSI，静默安装到此类路径可能报错 1603"
        SayC $YELLOW '信息' '如本次失败，请优先改用纯英文路径（如 C:\Python314）后重试'
    }
    try {
        $drv = [System.IO.Path]::GetPathRoot($InstallDir)
        $dInfo = New-Object System.IO.DriveInfo($drv)
        if ($dInfo.IsReady -and $dInfo.AvailableFreeSpace -lt 500MB) {
            SayC $YELLOW '信息' "警告: 目标盘 $drv 可用空间不足 500MB，安装可能因空间不足失败"
        }
    } catch { }

    # 3.2) 执行静默安装。加 log 参数让安装器写 bundle 日志，失败时读取日志定位真实原因；
    #      TargetDir/log 路径手动加引号，防止含空格时被拆成多个参数
    $msiLog = Join-Path $env:TEMP "python-$pyVer-$pyArch-install.log"
    try { Remove-Item $msiLog -Force -ErrorAction SilentlyContinue } catch { }
    $proc = Start-Process -FilePath $exePath `
        -ArgumentList '/quiet', 'InstallAllUsers=1', "TargetDir=`"$InstallDir`"", 'Include_pip=1', 'PrependPath=0', 'Include_test=0', 'Shortcuts=0', "log=`"$msiLog`"" `
        -Wait -PassThru
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        SayC $RED '异常' "静默安装失败（退出码 $($proc.ExitCode)）"
        if (Test-Path $msiLog) {
            $errLines = @(Get-Content $msiLog -ErrorAction SilentlyContinue |
                Select-String -Pattern 'Error 0x|error 1603|failed|Failure|return value 3' -CaseSensitive:$false |
                Select-Object -Last 5)
            if ($errLines.Count -gt 0) {
                SayC $RED '异常' '安装日志中的关键错误信息:'
                foreach ($el in $errLines) { Say "  $($el.Line.Trim())" }
            }
        }
        SayC $RED '异常' '常见原因与处理:'
        if ($hasNonAscii) {
            SayC $RED '异常' "  1) 安装目录含中文等非 ASCII 字符（当前: $InstallDir），官方安装器对此支持不佳，请换成纯英文路径重试（最可能的原因）"
        }
        SayC $RED '异常' '  2) 目标盘空间不足，请清理磁盘后重试'
        SayC $RED '异常' '  3) 被杀毒软件/安全策略拦截，请临时关闭实时防护后重试'
        SayC $RED '异常' '  4) 也可改用「GitHub 官方」下载源（解压即用，不经过 MSI，可规避此类问题）'
        SayC $YELLOW '信息' "安装包保留在: $exePath，可双击手动安装排查"
        SayC $YELLOW '信息' "安装日志: $msiLog"
        exit 1
    }
    # 清理安装包（失败不影响结果）
    try { Remove-Item $exePath -Force -ErrorAction SilentlyContinue } catch { }
    SayC $GREEN '结果' '安装完成'
    $pythonHome = $InstallDir
} else {
    # ==================== GitHub 官方：python-build-standalone，解压即用 ====================
    # 已有 python 目录且不覆盖 -> 直接复用；否则重新安装
    $existingPy = $null
    if ($Overwrite -eq '否') {
        $existingPy = Find-MatchingPython -Dir $InstallDir
    }
    if ($existingPy) {
        SayC $YELLOW '信息' "检测到已安装 Python: $($existingPy.FullName)，跳过下载与解压"
        $pythonHome = $existingPy.FullName
    } else {
        # 覆盖模式：先删除已存在的 python 目录
        if ($Overwrite -eq '是') {
            $oldPy = Find-MatchingPython -Dir $InstallDir
            if ($oldPy) {
                SayC $YELLOW '信息' "覆盖模式：删除旧目录 $($oldPy.FullName)"
                try {
                    Remove-Item -Path $oldPy.FullName -Recurse -Force -ErrorAction Stop
                } catch {
                    SayC $RED '异常' "删除旧目录失败: $($_.Exception.Message)"
                    SayC $RED '异常' '请先关闭占用该目录的程序（如正在运行的 Python 进程），或手动删除后重试'
                    exit 1
                }
            }
        }

        # ---- 通过 GitHub API 动态匹配该主版本的最新 Windows 资产 ----
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $assetRegex = "^cpython-$([regex]::Escape($majorMinor))\.[0-9]+\+[0-9]+-$pbsArch-pc-windows-msvc-install_only\.tar\.gz$"
        SayC $YELLOW '信息' "从 GitHub 查询 $majorMinor 的最新构建资产..."
        $relTag = $null
        $asset = $null
        try {
            # 查最近 5 个 release（python-build-standalone 每个 release 通常包含当时所有活跃版本）
            $releases = Invoke-RestMethod -Uri 'https://api.github.com/repos/astral-sh/python-build-standalone/releases?per_page=5' `
                -Headers @{ 'User-Agent' = 'knife-script-manager' } -ErrorAction Stop
            foreach ($rel in $releases) {
                $asset = $rel.assets | Where-Object { $_.name -match $assetRegex } | Select-Object -First 1
                if ($asset) { $relTag = $rel.tag_name; break }
            }
        } catch {
            SayC $RED '异常' "查询 GitHub 发布信息失败: $($_.Exception.Message)"
            SayC $RED '异常' '请检查网络连接后重试'
            exit 1
        }
        if (-not $asset) {
            SayC $RED '异常' "未找到 Python $majorMinor 的 Windows ($pbsArch) 安装包，请尝试其他版本（如 3.12 / 3.13）"
            exit 1
        }
        # 支持自定义代理前缀（如 https://gh-proxy.com/），将 github.com 直链前置代理
        $githubBase = "https://github.com/astral-sh/python-build-standalone/releases/download/$relTag/$($asset.name)"
        if (-not [string]::IsNullOrWhiteSpace($MirrorPrefix)) {
            $prefix = $MirrorPrefix.TrimEnd('/') + '/'
            $downloadUrl = $prefix + $githubBase
            SayC $YELLOW '信息' "使用代理前缀: $prefix"
        } else {
            $downloadUrl = $githubBase
        }
        SayC $YELLOW '信息' "下载链接: $downloadUrl"

        # ---- 下载（流式 + 进度）----
        $tmpDir = Join-Path $env:TEMP 'script-manager-python'
        if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }

        $fs = $null
        try {
            $req = [System.Net.HttpWebRequest]::Create($downloadUrl)
            $req.Timeout = 60000
            $req.UserAgent = 'knife-script-manager'
            $resp = $req.GetResponse()
            $zipPath = Join-Path $tmpDir $asset.name
            $total = $resp.ContentLength
            $stream = $resp.GetResponseStream()
            $fs = New-Object System.IO.FileStream($zipPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
            $buffer = New-Object byte[] (1024 * 256)
            $read = 0
            $nextReport = [DateTime]::Now.AddSeconds(5)
            SayC $YELLOW '信息' "开始下载: $($asset.name)（约 $([math]::Round($total / 1MB, 1)) MB）"
            while (($n = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fs.Write($buffer, 0, $n)
                $read += $n
                # 按时间节流（每 5 秒一次）：小文件不会刷屏，大文件也不会半天不报
                # 用 [DateTime]::Now 而非 Get-Date —— 循环每 256KB 调用一次，cmdlet 开销明显
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
            $fs.Close(); $fs = $null
            $stream.Close()
            $resp.Close()
        } catch {
            if ($fs) { $fs.Close() }
            SayC $RED '异常' "下载失败: $($_.Exception.Message)"
            SayC $RED '异常' '请检查网络，或稍后重试'
            exit 1
        }
        SayC $GREEN '结果' "下载完成: $zipPath"

        # ---- 解压（系统自带 tar.exe，Windows 10 1803+）----
        $tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
        if (-not (Test-Path $tarExe)) {
            SayC $RED '异常' '系统缺少 tar.exe（需要 Windows 10 1803+），无法解压安装包'
            exit 1
        }
        SayC $YELLOW '信息' "解压到: $InstallDir（请稍候）"
        if (-not (Test-Path $InstallDir)) {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        }
        # $ErrorActionPreference='Stop' 时 native stderr 会抛 NativeCommandError，临时降级
        $oldEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            & $tarExe -xf $zipPath -C $InstallDir 2>&1 | Out-Null
            $tarExit = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $oldEap
        }
        if ($tarExit -ne 0) {
            SayC $RED '异常' "解压失败（tar 退出码 $tarExit）"
            SayC $RED '异常' '若目标位于 Program Files 等受保护目录，请换一个目录，或以管理员身份运行'
            exit 1
        }
        SayC $GREEN '结果' '解压完成'

        # 清理临时压缩包（失败不影响结果）
        try { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue } catch { }

        # ---- 定位本次解压出的 python 目录 ----
        $found = Find-MatchingPython -Dir $InstallDir
        if (-not $found) {
            SayC $RED '异常' "解压后未找到 python 目录（含 python.exe），请检查目录: $InstallDir"
            exit 1
        }
        $pythonHome = $found.FullName
    }
}

$pythonExe = Join-Path $pythonHome 'python.exe'
if (-not (Test-Path $pythonExe)) {
    SayC $RED '异常' "未找到 python.exe，请检查目录: $pythonHome"
    exit 1
}

# ---- 验证（python --version 输出 2>&1 合并后原色输出）----
SayC $YELLOW '信息' '验证 python --version:'
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $verOut = (& $pythonExe --version 2>&1 | Out-String)
} finally {
    $ErrorActionPreference = $oldEap
}
$verOut.TrimEnd()

# ---- 写环境变量 ----
# 管理员（工具已配 admin=true 提权）-> 写系统级 Machine；拒绝提权（非管理员）-> 回退用户级 User
$isAdmin = Test-IsAdministrator
$scope = if ($isAdmin) { 'Machine' } else { 'User' }
if (-not $isAdmin) {
    SayC $YELLOW '信息' '当前未以管理员运行，环境变量写入【用户级】。若系统 PATH 里还有其他 Python，可能仍优先于本版本。'
}

if ($AddToPath -eq '是') {
    try {
        # Python 的 bin 目录就是 python.exe 所在目录（install_only 解压根目录）
        $binDir = $pythonHome
        $binDirNorm = $binDir.TrimEnd('\')

        # 顺序很重要（同 Install-Java.ps1）：先建好新条目（SCRIPT_MANAGER_ENV + PATH 前置），
        # 再清理旧 Python 绝对路径。避免「旧路径删了、新条目没建成」导致 python 彻底找不到。
        # 1) 把本次 python 目录前置进 SCRIPT_MANAGER_ENV，同时移除聚合变量里旧的 python 条目
        #    （脚本块匹配 python 特征；java/go 等其他运行时条目保留不动）
        Add-ScriptManagerEnvEntry -BinDir $binDir -Scope $scope -IsOldEntry {
            param([string]$s)
            Test-IsPythonHomePath $s
        }
        SayC $GREEN '结果' "已把 Python 目录写入 SCRIPT_MANAGER_ENV（$scope）: $binDir"

        # 2) 确保主作用域 PATH 前置 SCRIPT_MANAGER_ENV 中的实际路径（CMD 不会展开 %VAR% 引用）
        Ensure-PathHasScriptManagerEnv -Scope $scope
        SayC $GREEN '结果' "已把 SCRIPT_MANAGER_ENV 中的实际路径前置到 $scope PATH"

        # 3) 最后清理：从 Machine + User 两级 PATH 移除旧的 Python 绝对路径（目录名特征 + 含 python.exe）
        #    此时新路径已就位，删旧路径不会造成 python 缺失。
        #    保护当前 SCRIPT_MANAGER_ENV 中的路径，避免把刚写进去的新 Python 误删。
        $protectedPaths = @((Get-ScriptManagerEnvForScope -Scope 'Machine') + (Get-ScriptManagerEnvForScope -Scope 'User') | Select-Object -Unique)
        foreach ($oldScope in @('Machine', 'User')) {
            $rawOld = [Environment]::GetEnvironmentVariable('Path', $oldScope)
            if ([string]::IsNullOrWhiteSpace($rawOld)) { continue }
            $removed = @()
            $segmentsOld = @($rawOld -split ';' | ForEach-Object {
                $s = $_.TrimEnd('\')
                if ([string]::IsNullOrWhiteSpace($s)) { return $null }
                if ((Test-IsPythonHomePath $s) -and -not ($protectedPaths -contains $s)) {
                    $script:removed += $s
                    return $null
                }
                return $s
            } | Where-Object { $_ } | Select-Object -Unique)
            $newRaw = $segmentsOld -join ';'
            # 防御：过滤后为空（该作用域 PATH 只剩 python 项）时跳过写入，避免把 PATH 清空
            if (-not [string]::IsNullOrWhiteSpace($newRaw) -and $newRaw -ne $rawOld) {
                [Environment]::SetEnvironmentVariable('Path', $newRaw, $oldScope)
                foreach ($r in $removed) {
                    SayC $YELLOW '信息' "已从 $oldScope PATH 移除旧 Python 路径: $r"
                }
            }
        }
    } catch {
        SayC $RED '异常' "更新 PATH 失败: $($_.Exception.Message)"
    }
}

Say ''
Say '=========================================='
SayC $GREEN '结果' "Python $majorMinor 安装完成"
SayC $GREEN '结果' "Python 目录: $pythonHome"
if ($AddToPath -eq '是') {
    SayC $GREEN '结果' "已加入 SCRIPT_MANAGER_ENV: $pythonHome"
    SayC $YELLOW '信息' '工具管理的所有运行时 bin 统一记录在 SCRIPT_MANAGER_ENV，PATH 中写入实际路径'
    SayC $YELLOW '信息' "查看当前内容（新终端）: echo %SCRIPT_MANAGER_ENV%"
    SayC $YELLOW '信息' "切换 Python 版本: 更新 SCRIPT_MANAGER_ENV 后，重新运行安装脚本同步 PATH"
}
if ($AddToPath -eq '是') {
    SayC $YELLOW '信息' "环境变量已写入【$scope 级】，新打开的终端才会生效"
}
Say '=========================================='
