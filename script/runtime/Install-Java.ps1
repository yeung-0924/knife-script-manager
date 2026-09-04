# 更新时间: 2026-09-04 16:57:08
# Install-Java.ps1 - 按选择的发行版（Oracle OpenJDK / Microsoft OpenJDK / Alibaba Dragonwell）与版本下载并安装 JDK
# 说明（几个关键健壮性处理）：
#   1) 统一用 Write-Output 输出（走 success stream / stdout）。
#      执行器通过重定向 stdout 捕获日志；Write-Host 走 information stream（PS5+），
#      在部分重定向场景下捕获不到，会导致日志面板一片空白。
#   2) 下载用 HttpWebRequest 流式读取，在主线程每 5 秒打印一次进度。
#      不用 Register-ObjectEvent：事件回调在子线程，写 stdout 不稳定且容易丢日志。
#   3) 解压用 .NET ZipFile.ExtractToDirectory，比 Expand-Archive 快很多（JDK 包约 190MB）。
#   4) 环境变量写【用户级】（不需要管理员）；只有解压到 Program Files 等受保护目录才需要管理员。
#   5) java -version 的输出在 stderr，必须用 2>&1 合并才能拿到。
#   6) 下载链接按发行版构造：
#      - Oracle OpenJDK:   21+ 用 https://download.oracle.com/java/{major}/latest/jdk-{major}_windows-x64_bin.zip；
#                          17 无 latest 目录（404），用 archive 固定版本 jdk-17.0.12；仅 x64
#      - Microsoft OpenJDK: https://aka.ms/download-jdk/microsoft-jdk-{major}-windows-{arch}.zip（302 重定向到最新补丁包，从最终 URL 解析文件名）
#      - Alibaba Dragonwell: 通过 GitHub API 查 dragonwell-project/dragonwell{major} 的最新 release 资产（仅 x64）
#   7) 覆盖原文件=否（默认）：安装目录已有同主版本 JDK（含 bin\java.exe）时，跳过下载与解压，直接复用；
#      覆盖原文件=是：先删除已存在的同主版本目录，再重新下载解压。

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

# ---- 入参（工具在执行前把 _p{XXX} 占位符替换为用户的输入值）----
$Distro      = "_p{DISTRO}"
$InstallDir  = "_p{INSTALL_DIR}"
$Version     = "_p{VERSION}"
$Overwrite   = "_p{OVERWRITE}"
$SetJavaHome = "_p{SET_JAVA_HOME}"
$AddToPath   = "_p{SET_PATH}"

# 缺省兜底：用户未填时给一个合理默认，避免空值导致后续解析报错
if ([string]::IsNullOrWhiteSpace($Distro))     { $Distro = 'Oracle OpenJDK' }
if ([string]::IsNullOrWhiteSpace($Version))     { $Version = '25 (LTS)' }
if ([string]::IsNullOrWhiteSpace($Overwrite))   { $Overwrite = '否' }
if ([string]::IsNullOrWhiteSpace($SetJavaHome)) { $SetJavaHome = '是' }
if ([string]::IsNullOrWhiteSpace($AddToPath))   { $AddToPath = '是' }

Say '=========================================='
Say " 自动安装 JDK（$Distro）"
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
SayC $GREEN '入参' "发行版: $Distro"
SayC $GREEN '入参' "安装目录: $InstallDir"
SayC $GREEN '入参' "版本: $Version"
SayC $GREEN '入参' "覆盖原文件: $Overwrite"
SayC $GREEN '入参' "设置 JAVA_HOME: $SetJavaHome"
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
$validDistros = @('Oracle OpenJDK', 'Microsoft OpenJDK', 'Alibaba Dragonwell')
if ($validDistros -notcontains $Distro) {
    SayC $RED '异常' "发行版取值无效「$Distro」，应为 $($validDistros -join ' / ')"
    exit 1
}
# 从版本选项（如 "21 (LTS)"、"25"）中提取主版本号
$majorMatch = [regex]::Match($Version, '\d+')
if (-not $majorMatch.Success) {
    SayC $RED '异常' "无法从版本「$Version」中识别 JDK 主版本号"
    exit 1
}
$major = $majorMatch.Value
# 解压目录前缀：Dragonwell 解压为 dragonwell-<version>，其余发行版为 jdk-<version>
$jdkPrefix = if ($Distro -eq 'Alibaba Dragonwell') { 'dragonwell' } else { 'jdk' }

# ---- 架构检测 ----
# 优先用 .NET OSArchitecture（返回真实系统架构，不受进程位数、x64 模拟影响），
# 兜底再用 PROCESSOR_ARCHITEW6432/PROCESSOR_ARCHITECTURE 环境变量。
# 各发行版 Windows 包架构范围：
#   Oracle/Microsoft：x64 + aarch64（Oracle 的 aarch64 仅 21+；Microsoft 11+）
#   Alibaba Dragonwell：仅 x64
$arch = 'x64'
$archRaw = ''
try {
    $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ($osArch -eq [System.Runtime.InteropServices.Architecture]::Arm64 -or $osArch -eq [System.Runtime.InteropServices.Architecture]::Arm) {
        $arch = 'aarch64'
        $archRaw = 'ARM64'
    } else {
        $arch = 'x64'
        $archRaw = 'x64 (AMD64)'
    }
} catch {
    # .NET 版本过老不支持 RuntimeInformation 时回退环境变量
    $archRaw = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ($archRaw -eq 'ARM64') { $arch = 'aarch64' } else { $arch = 'x64' }
}
SayC $YELLOW '信息' "系统架构: $archRaw -> 包架构 = $arch"

# ---- 查找安装目录中已存在的同主版本 JDK（目录名形如 jdk-21.0.12.1+1 或 dragonwell-21.0.11.0.11，且含 bin\java.exe）----
# Prefix 按发行版区分：Dragonwell 解压目录为 dragonwell-<version>，其余发行版为 jdk-<version>
function Find-MatchingJdk {
    param([string]$Dir, [string]$Major, [string]$Prefix = 'jdk')
    Get-ChildItem -Path $Dir -Directory -Filter "$Prefix*" -ErrorAction SilentlyContinue |
        Where-Object {
            if (-not (Test-Path (Join-Path $_.FullName 'bin\java.exe'))) { return $false }
            $m = [regex]::Match($_.Name, "^$Prefix-(\d+)")
            return $m.Success -and $m.Groups[1].Value -eq $Major
        } |
        Select-Object -First 1
}

# 判断一个 PATH 分段是否指向某个 JDK 的 bin 目录（按路径特征识别，不访问文件系统）
function Test-IsJdkBinPath {
    param([string]$Segment)
    $s = $Segment.TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    # 形如 ...\jdk-xxxxx\bin 或 ...\dragonwell-xxxxx\bin
    if ($s -notmatch '\\bin$') { return $false }
    $parent = Split-Path -Path $s -Parent
    if ([string]::IsNullOrWhiteSpace($parent)) { return $false }
    return ($parent -imatch '\\jdk-?\d') -or (Split-Path -Path $parent -Leaf -imatch '^jdk-?\d') -or
           ($parent -imatch '\\dragonwell-?\d') -or (Split-Path -Path $parent -Leaf -imatch '^dragonwell-?\d')
}

# 从指定作用域的 PATH 中找出所有 JDK bin 路径
function Find-JdkPathsInPath {
    param([string]$Scope)
    $raw = [Environment]::GetEnvironmentVariable('Path', $Scope)
    if ([string]::IsNullOrWhiteSpace($raw)) { return @() }
    return $raw -split ';' | Where-Object { Test-IsJdkBinPath $_ }
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

# ---- SCRIPT_MANAGER_ENV 聚合变量：所有工具管理的运行时 bin 目录统一放这里，便于识别与集中管理。
# 注意：CMD 搜索外部命令时不会展开 Path 中的自定义 %VAR% 引用，因此 Path 里必须写实际路径，
#       SCRIPT_MANAGER_ENV 单独保留作为元数据记录。
# 读取聚合变量（Machine 优先，回退 User；两个作用域合并去重，保证切换过作用域后不丢条目）
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

# 把新 bin 目录前置进 SCRIPT_MANAGER_ENV；$IsOldEntry 脚本块用于判定应移除的旧条目（按运行时特征，如 java 的 \jdk...\bin）
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

# ---- 主流程：已有同版本且不覆盖 -> 直接复用；否则重新安装 ----
$existingJdk = $null
if ($Overwrite -eq '否') {
    $existingJdk = Find-MatchingJdk -Dir $InstallDir -Major $major -Prefix $jdkPrefix
}

if ($existingJdk) {
    # 跳过下载与解压，直接复用现有安装
    SayC $YELLOW '信息' "检测到已安装同版本 JDK: $($existingJdk.Name)，跳过下载与解压"
    $javaHome = $existingJdk.FullName
} else {
    # 覆盖模式：先删除已存在的同版本目录
    if ($Overwrite -eq '是') {
        $oldJdks = Find-MatchingJdk -Dir $InstallDir -Major $major -Prefix $jdkPrefix
        if ($oldJdks) {
            SayC $YELLOW '信息' "覆盖模式：删除旧版本目录 $($oldJdks.Name)"
            try {
                Remove-Item -Path $oldJdks.FullName -Recurse -Force -ErrorAction Stop
            } catch {
                SayC $RED '异常' "删除旧目录失败: $($_.Exception.Message)"
                SayC $RED '异常' '请先关闭占用该目录的程序（如正在运行的 Java 进程），或手动删除后重试'
                exit 1
            }
        }
    }

    # ---- 按发行版构造下载链接 ----
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $downloadUrl = $null
    switch ($Distro) {
        'Oracle OpenJDK' {
            # Oracle 官方源：download.oracle.com
            #   - 21+：大版本 latest 链接（自动指向最新补丁）
            #   - 17：latest 目录不存在（实测 404），改用 archive 固定版本 17.0.12
            # 实测官方源 Windows 仅有 x64 包（无 ARM64 自动链接）
            if ($arch -ne 'x64') {
                SayC $RED '异常' "Oracle 官方源目前仅提供 Windows x64 自动下载链接（当前架构 $archRaw），请改用 Microsoft OpenJDK"
                exit 1
            }
            if ($major -eq '17') {
                $downloadUrl = 'https://download.oracle.com/java/17/archive/jdk-17.0.12_windows-x64_bin.zip'
                SayC $YELLOW '信息' 'Oracle 17 官方源无 latest 自动链接，使用 archive 固定版本 17.0.12'
            } else {
                $downloadUrl = "https://download.oracle.com/java/$major/latest/jdk-${major}_windows-${arch}_bin.zip"
            }
        }
        'Microsoft OpenJDK' {
            # aka.ms 大版本链接，自动重定向到该大版本的最新补丁包
            $downloadUrl = "https://aka.ms/download-jdk/microsoft-jdk-$major-windows-$arch.zip"
        }
        'Alibaba Dragonwell' {
            if ($arch -ne 'x64') {
                SayC $RED '异常' "Alibaba Dragonwell 目前仅提供 Windows x64 安装包（当前架构 $archRaw），请改用 Oracle / Microsoft 发行版"
                exit 1
            }
            # Dragonwell 无大版本 latest 链接，通过 GitHub API 查 dragonwell{major} 仓库最新 release 的资产
            $repo = "dragonwell-project/dragonwell$major"
            SayC $YELLOW '信息' "查询 $repo 最新 release..."
            try {
                $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers @{ 'User-Agent' = 'knife-script-manager' } -TimeoutSec 30
                # 仅匹配主安装包（..._x64_windows.zip），排除 -fix 修复包、.sha256 等附加资产
                $asset = $release.assets | Where-Object { $_.name -match '_x64_windows\.zip$' } | Select-Object -First 1
                if (-not $asset) {
                    SayC $RED '异常' "在 $repo 最新 release 中未找到 Windows x64 安装包"
                    exit 1
                }
                $downloadUrl = $asset.browser_download_url
                SayC $YELLOW '信息' "Dragonwell 版本: $($release.tag_name)，安装包: $($asset.name)"
            } catch {
                SayC $RED '异常' "查询 $repo 最新 release 失败: $($_.Exception.Message)"
                SayC $RED '异常' '请检查网络（需可访问 GitHub API），或改用 Oracle / Microsoft 发行版'
                exit 1
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($downloadUrl)) {
        SayC $RED '异常' "无法为发行版「$Distro」构造下载链接"
        exit 1
    }
    SayC $YELLOW '信息' "下载链接: $downloadUrl"

    # ---- 下载（流式 + 进度）----
    $tmpDir = Join-Path $env:TEMP 'script-manager-jdk'
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }

    $fs = $null
    try {
        $req = [System.Net.HttpWebRequest]::Create($downloadUrl)
        $req.Timeout = 60000
        $req.UserAgent = 'knife-script-manager'
        $resp = $req.GetResponse()
        # 部分源（如 aka.ms）会 302 重定向到 CDN，最终 URL 才是真实包名（如 microsoft-jdk-21.0.12.1-windows-x64.zip）
        $packageName = [System.IO.Path]::GetFileName($resp.ResponseUri.AbsoluteUri)
        if ([string]::IsNullOrWhiteSpace($packageName)) {
            $packageName = "jdk-$major-windows-$arch.zip"
        }
        $zipPath = Join-Path $tmpDir $packageName
        $total = $resp.ContentLength
        $stream = $resp.GetResponseStream()
        $fs = New-Object System.IO.FileStream($zipPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        $buffer = New-Object byte[] (1024 * 256)
        $read = 0
        $nextReport = [DateTime]::Now.AddSeconds(5)
        SayC $YELLOW '信息' "开始下载: $packageName（约 $([math]::Round($total / 1MB, 1)) MB）"
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
        SayC $RED '异常' '请检查网络，或确认该版本镜像可用'
        exit 1
    }
    SayC $GREEN '结果' "下载完成: $zipPath"

    # ---- 解压 ----
    SayC $YELLOW '信息' "解压到: $InstallDir（约需 1-3 分钟，请稍候）"
    try {
        if (-not (Test-Path $InstallDir)) {
            New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
        }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $InstallDir)
    } catch {
        SayC $RED '异常' "解压失败: $($_.Exception.Message)"
        SayC $RED '异常' '若目标位于 Program Files 等受保护目录，请换一个目录，或以管理员身份运行'
        exit 1
    }
    SayC $GREEN '结果' '解压完成'

    # 清理临时压缩包（失败不影响结果）
    try { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue } catch { }

    # ---- 定位本次解压出的同主版本 jdk 目录（避免取到目录里遗留的其他版本）----
    $found = Find-MatchingJdk -Dir $InstallDir -Major $major -Prefix $jdkPrefix
    if (-not $found) {
        SayC $RED '异常' "解压后未找到 $jdkPrefix-$major 目录（含 bin\java.exe），请检查目录: $InstallDir"
        exit 1
    }
    $javaHome = $found.FullName
}

$javaExe = Join-Path $javaHome 'bin\java.exe'
if (-not (Test-Path $javaExe)) {
    SayC $RED '异常' "未找到 java.exe，请检查目录: $javaHome"
    exit 1
}

# ---- 验证（java -version 输出在 stderr，2>&1 合并后原色输出）----
# 关键：$ErrorActionPreference='Stop' 时，外部命令向 stderr 写内容会抛 NativeCommandError 直接终止脚本，
# 因此这里临时降级为 Continue，拿到输出后再恢复。
SayC $YELLOW '信息' '验证 java -version:'
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $verOut = (& $javaExe -version 2>&1 | Out-String)
} finally {
    $ErrorActionPreference = $oldEap
}
$verOut.TrimEnd()

# ---- 写环境变量 ----
# 管理员（工具已配 admin=true 提权）-> 写系统级 Machine，从根源上保证新 JDK 优先于系统 PATH 里的旧 JDK；
# 若用户拒绝了 UAC 提权（非管理员）-> 回退写用户级 User，并提示系统 PATH 残留旧 JDK 的风险。
$isAdmin = Test-IsAdministrator
$scope = if ($isAdmin) { 'Machine' } else { 'User' }
if (-not $isAdmin) {
    SayC $YELLOW '信息' '当前未以管理员运行，环境变量写入【用户级】。若系统 PATH 里还有其他 JDK，可能仍优先于本版本。'
}

if ($SetJavaHome -eq '是') {
    try {
        [Environment]::SetEnvironmentVariable('JAVA_HOME', $javaHome, $scope)
        SayC $GREEN '结果' "已设置环境变量 JAVA_HOME（$scope）= $javaHome"
    } catch {
        SayC $RED '异常' "设置 JAVA_HOME 失败: $($_.Exception.Message)"
    }
}

if ($AddToPath -eq '是') {
    try {
        $binDir = Join-Path $javaHome 'bin'
        $binDirNorm = $binDir.TrimEnd('\')

        # 顺序很重要：先建好新引用（SCRIPT_MANAGER_ENV + PATH 里的 %SCRIPT_MANAGER_ENV%），
        # 再清理旧 JDK 绝对路径。避免「旧路径删了、新引用没建成」导致 java 彻底找不到。
        # 1) 把本次 JDK 的 bin 前置进 SCRIPT_MANAGER_ENV，同时移除聚合变量里旧的 JDK 条目
        #    （脚本块匹配 java 特征：路径形如 ...\jdk...\bin；python/go 等其他运行时条目保留不动）
        Add-ScriptManagerEnvEntry -BinDir $binDir -Scope $scope -IsOldEntry {
            param([string]$s)
            Test-IsJdkBinPath $s
        }
        SayC $GREEN '结果' "已把 JDK bin 写入 SCRIPT_MANAGER_ENV（$scope）: $binDir"

        # 2) 确保主作用域 PATH 前置 SCRIPT_MANAGER_ENV 中的实际路径（CMD 不会展开 %VAR% 引用）
        Ensure-PathHasScriptManagerEnv -Scope $scope
        SayC $GREEN '结果' "已把 SCRIPT_MANAGER_ENV 中的实际路径前置到 $scope PATH"

        # 3) 最后清理：从 Machine + User 两级 PATH 移除旧的 JDK 绝对路径（特征 \jdk...\bin）
        #    与旧版 %JDK_BIN% 字面量。此时新路径已就位，删旧路径不会造成 java 缺失。
        #    保护当前 SCRIPT_MANAGER_ENV 中的路径，避免把刚写进去的新 JDK 误删。
        $protectedPaths = @((Get-ScriptManagerEnvForScope -Scope 'Machine') + (Get-ScriptManagerEnvForScope -Scope 'User') | Select-Object -Unique)
        foreach ($oldScope in @('Machine', 'User')) {
            $rawOld = [Environment]::GetEnvironmentVariable('Path', $oldScope)
            if ([string]::IsNullOrWhiteSpace($rawOld)) { continue }
            $removed = @()
            $segmentsOld = @($rawOld -split ';' | ForEach-Object {
                $s = $_.TrimEnd('\')
                if ([string]::IsNullOrWhiteSpace($s)) { return $null }
                if ($s -ieq '%JDK_BIN%') {
                    $script:removed += $s
                    return $null
                }
                if ((Test-IsJdkBinPath $s) -and -not ($protectedPaths -contains $s)) {
                    $script:removed += $s
                    return $null
                }
                return $s
            } | Where-Object { $_ } | Select-Object -Unique)
            $newRaw = $segmentsOld -join ';'
            # 防御：过滤后为空（该作用域 PATH 只剩 JDK 项）时跳过写入，避免把 PATH 清空
            if (-not [string]::IsNullOrWhiteSpace($newRaw) -and $newRaw -ne $rawOld) {
                [Environment]::SetEnvironmentVariable('Path', $newRaw, $oldScope)
                foreach ($r in $removed) {
                    SayC $YELLOW '信息' "已从 $oldScope PATH 移除旧 JDK 路径: $r"
                }
            }
        }

        # 4) 清理旧版 JDK_BIN 变量（历史遗留，避免与新方案混淆）
        try {
            [Environment]::SetEnvironmentVariable('JDK_BIN', $null, 'Machine')
            [Environment]::SetEnvironmentVariable('JDK_BIN', $null, 'User')
            SayC $YELLOW '信息' '已删除旧版变量 JDK_BIN（统一改用 SCRIPT_MANAGER_ENV）'
        } catch { }
    } catch {
        SayC $RED '异常' "更新 PATH 失败: $($_.Exception.Message)"
    }
}

Say ''
Say '=========================================='
SayC $GREEN '结果' "JDK $major 安装完成"
SayC $GREEN '结果' "JAVA_HOME: $javaHome"
if ($AddToPath -eq '是') {
    SayC $GREEN '结果' "已加入 SCRIPT_MANAGER_ENV: $((Join-Path $javaHome 'bin'))"
    SayC $YELLOW '信息' '工具管理的所有运行时 bin 统一记录在 SCRIPT_MANAGER_ENV，PATH 中写入实际路径'
    SayC $YELLOW '信息' "查看当前内容（新终端）: echo %SCRIPT_MANAGER_ENV%"
    SayC $YELLOW '信息' "切换 JDK 版本: 更新 SCRIPT_MANAGER_ENV 后，重新运行安装脚本同步 PATH"
}
if ($SetJavaHome -eq '是' -or $AddToPath -eq '是') {
    SayC $YELLOW '信息' "环境变量已写入【$scope 级】，新打开的终端才会生效"
}
Say '=========================================='

