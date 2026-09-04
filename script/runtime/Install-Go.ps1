# 更新时间: 2026-09-04
# Install-Go.ps1 - 从 go.dev 下载并安装 Go（官方 zip 解压即用）
# 说明（与 Install-Java.ps1 / Install-Python.ps1 同一套约定）：
#   1) 统一用 Write-Output 输出（走 success stream / stdout），避免重定向场景下日志丢失。
#   2) 下载用 HttpWebRequest 流式读取，在主线程每 20% 打印一次进度。
#   3) zip 用系统 ZipFile 解压。
#   4) 版本通过 https://go.dev/dl/?mode=json 动态匹配所选主版本（major）的最新稳定版。
#      注意：Go 官方只维护最近两个 minor（如 1.27 / 1.26），更早的 major 在 API 中查不到。
#   5) Go 官方 zip 解压后目录名固定为 go，本脚本将其重命名为 go-{完整版本}（如 go-1.26.7），
#      支持多版本共存，也便于 PATH 特征识别。
#   6) 覆盖原文件=否（默认）：安装目录已有同主版本 go 目录时跳过下载解压直接复用；=是 则先删再装。
#   7) PATH 通过 SCRIPT_MANAGER_ENV 聚合变量统一管理：Path 写入实际路径（CMD 不展开自定义 %VAR% 引用），
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
$InstallDir = "_p{INSTALL_DIR}"
$Version    = "_p{VERSION}"
$Overwrite  = "_p{OVERWRITE}"
$AddToPath  = "_p{SET_PATH}"

# 缺省兜底
if ([string]::IsNullOrWhiteSpace($Version))   { $Version = 'Go 1.26' }
if ([string]::IsNullOrWhiteSpace($Overwrite)) { $Overwrite = '否' }
if ([string]::IsNullOrWhiteSpace($AddToPath)) { $AddToPath = '是' }

Say '=========================================='
Say ' 自动安装 Go（官方 zip 解压即用包）'
Say '=========================================='
SayC $GREEN '入参' "安装目录: $InstallDir"
SayC $GREEN '入参' "Go 版本: $Version"
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
# 从版本选项（如 "Go 1.26"）中提取 主.次 版本号（如 1.26）
$majorMatch = [regex]::Match($Version, '(\d+\.\d+)')
if (-not $majorMatch.Success) {
    SayC $RED '异常' "无法从「$Version」中识别 Go 版本号"
    exit 1
}
$major = $majorMatch.Groups[1].Value

# ---- 架构检测（同 Install-Java.ps1：优先 .NET OSArchitecture，回退环境变量）----
# Go 官方 win 包架构名：amd64 / arm64
$goArch = 'amd64'
$archRaw = ''
try {
    $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    if ($osArch -eq [System.Runtime.InteropServices.Architecture]::Arm64 -or $osArch -eq [System.Runtime.InteropServices.Architecture]::Arm) {
        $goArch = 'arm64'
        $archRaw = 'ARM64'
    } else {
        $goArch = 'amd64'
        $archRaw = 'x64 (AMD64)'
    }
} catch {
    $archRaw = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
    if ($archRaw -eq 'ARM64') { $goArch = 'arm64' } else { $goArch = 'amd64' }
}
SayC $YELLOW '信息' "系统架构: $archRaw -> 包架构 = $goArch"

# ---- 查找安装目录中已存在的同主版本 go 目录（命名 go-{完整版本}）----
function Find-MatchingGo {
    param([string]$Dir, [string]$Major)
    Get-ChildItem -Path $Dir -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            if ($_.Name -notmatch "^go-$([regex]::Escape($Major))(\.\d+)?$") { return $false }
            if (-not (Test-Path (Join-Path $_.FullName 'bin\go.exe'))) { return $false }
            return $true
        } |
        Select-Object -First 1
}

# 判断一个 PATH 分段是否是 Go 的 bin 目录（形如 ...\go-1.26.7\bin 或 ...\go\bin，且含 go.exe）
function Test-IsGoBinPath {
    param([string]$Segment)
    $s = $Segment.TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($s)) { return $false }
    $leaf = Split-Path -Path $s -Leaf
    if ($leaf -inotmatch '^bin$') { return $false }
    $parent = Split-Path -Path $s -Parent
    $parentLeaf = Split-Path -Path $parent -Leaf
    if ($parentLeaf -inotmatch '^go(-\d+\.\d+(\.\d+)?)?$') { return $false }
    if (-not (Test-Path (Join-Path $parent 'go.exe'))) { return $false }
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

# ---- 主流程：已有同主版本 go 目录且不覆盖 -> 直接复用；否则重新安装 ----
$existingGo = $null
if ($Overwrite -eq '否') {
    $existingGo = Find-MatchingGo -Dir $InstallDir -Major $major
}

$goHome = $null
if ($existingGo) {
    SayC $YELLOW '信息' "检测到已安装 Go: $($existingGo.FullName)，跳过下载与解压"
    $goHome = $existingGo.FullName
} else {
    # 覆盖模式：先删除同主版本的旧 go 目录
    if ($Overwrite -eq '是') {
        $oldGo = Find-MatchingGo -Dir $InstallDir -Major $major
        if ($oldGo) {
            SayC $YELLOW '信息' "覆盖模式：删除旧目录 $($oldGo.FullName)"
            try {
                Remove-Item -Path $oldGo.FullName -Recurse -Force -ErrorAction Stop
            } catch {
                SayC $RED '异常' "删除旧目录失败: $($_.Exception.Message)"
                SayC $RED '异常' '请先关闭占用该目录的程序（如正在运行的 Go 进程），或手动删除后重试'
                exit 1
            }
        }
    }

    # ---- 通过 go.dev/dl/?mode=json 动态获取该主版本的最新稳定版本 ----
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $goVer = $null
    SayC $YELLOW '信息' "从 go.dev 查询 Go $major 的最新稳定版本..."
    try {
        $dl = Invoke-RestMethod -Uri 'https://go.dev/dl/?mode=json' `
            -Headers @{ 'User-Agent' = 'knife-script-manager' } -ErrorAction Stop
        $hit = $dl | Where-Object {
            $_.stable -and $_.version -match "^go$([regex]::Escape($major))\."
        } | Select-Object -First 1
        if ($hit) { $goVer = $hit.version.TrimStart('go') }
    } catch {
        SayC $RED '异常' "查询 Go 版本信息失败: $($_.Exception.Message)"
        SayC $RED '异常' '请检查网络连接后重试'
        exit 1
    }
    if (-not $goVer) {
        SayC $RED '异常' "未找到 Go $major 的稳定版本。Go 官方仅维护最近两个 minor（如 1.27 / 1.26），请换一个版本"
        exit 1
    }
    $downloadUrl = "https://go.dev/dl/go$goVer.windows-$goArch.zip"
    SayC $YELLOW '信息' "下载链接: $downloadUrl"

    # ---- 下载（流式 + 进度）----
    $tmpDir = Join-Path $env:TEMP 'script-manager-go'
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }

    $fs = $null
    $zipPath = Join-Path $tmpDir "go$goVer.windows-$goArch.zip"
    try {
        $req = [System.Net.HttpWebRequest]::Create($downloadUrl)
        $req.Timeout = 60000
        $req.UserAgent = 'knife-script-manager'
        $resp = $req.GetResponse()
        $total = $resp.ContentLength
        $stream = $resp.GetResponseStream()
        $fs = New-Object System.IO.FileStream($zipPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        $buffer = New-Object byte[] (1024 * 256)
        $read = 0
        $nextReport = [DateTime]::Now.AddSeconds(5)
        SayC $YELLOW '信息' "开始下载: go$goVer.windows-$goArch.zip（约 $([math]::Round($total / 1MB, 1)) MB）"
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

    # ---- 解压（Go zip 顶层目录固定为 go，需重命名为 go-{完整版本} 以便多版本共存）----
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
    $extractTmp = Join-Path $tmpDir ("go-extract-" + [guid]::NewGuid().ToString('N'))
    if (-not (Test-Path $extractTmp)) { New-Item -ItemType Directory -Path $extractTmp -Force | Out-Null }
    SayC $YELLOW '信息' "解压到临时目录并重命名（请稍候）..."
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractTmp)
    } catch {
        SayC $RED '异常' "解压失败: $($_.Exception.Message)"
        exit 1
    }
    $goDir = Get-ChildItem -Path $extractTmp -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq 'go' } | Select-Object -First 1
    if (-not $goDir) {
        SayC $RED '异常' '解压后未找到 go 目录，安装包结构异常'
        try { Remove-Item $extractTmp -Recurse -Force -ErrorAction SilentlyContinue } catch { }
        exit 1
    }

    # 目标目录 go-{完整版本}
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    $targetHome = Join-Path $InstallDir "go-$goVer"
    if (Test-Path $targetHome) {
        # 同名目录已存在（覆盖模式的兜底）：直接删掉旧的再移动
        try {
            Remove-Item -Path $targetHome -Recurse -Force -ErrorAction Stop
        } catch {
            SayC $RED '异常' "删除旧目录失败: $($_.Exception.Message)"
            SayC $RED '异常' '请先关闭占用该目录的程序，或手动删除后重试'
            exit 1
        }
    }
    try {
        Move-Item -Path $goDir.FullName -Destination $targetHome -ErrorAction Stop
    } catch {
        SayC $RED '异常' "移动到安装目录失败: $($_.Exception.Message)"
        exit 1
    }
    # 清理临时目录与压缩包（失败不影响结果）
    try { Remove-Item $extractTmp -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    try { Remove-Item $zipPath -Force -ErrorAction SilentlyContinue } catch { }
    SayC $GREEN '结果' '解压并重命名完成'
    $goHome = $targetHome
}

$goExe = Join-Path $goHome 'bin\go.exe'
if (-not (Test-Path $goExe)) {
    SayC $RED '异常' "未找到 go.exe，请检查目录: $goHome"
    exit 1
}

# ---- 验证（go version 输出 2>&1 合并后原色输出）----
SayC $YELLOW '信息' '验证 go version:'
$oldEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
try {
    $verOut = (& $goExe version 2>&1 | Out-String)
} finally {
    $ErrorActionPreference = $oldEap
}
$verOut.TrimEnd()

# ---- 写环境变量 ----
# 管理员（工具已配 admin=true 提权）-> 写系统级 Machine；拒绝提权（非管理员）-> 回退用户级 User
$isAdmin = Test-IsAdministrator
$scope = if ($isAdmin) { 'Machine' } else { 'User' }
if (-not $isAdmin) {
    SayC $YELLOW '信息' '当前未以管理员运行，环境变量写入【用户级】。若系统 PATH 里还有其他 Go，可能仍优先于本版本。'
}

if ($AddToPath -eq '是') {
    try {
        # Go 的 bin 目录为 {goHome}\bin
        $binDir = Join-Path $goHome 'bin'
        $binDirNorm = $binDir.TrimEnd('\')

        # 顺序很重要（同 Install-Java.ps1）：先建好新条目（SCRIPT_MANAGER_ENV + PATH 前置），
        # 再清理旧 Go 绝对路径。避免「旧路径删了、新条目没建成」导致 go 彻底找不到。
        # 1) 把本次 bin 目录前置进 SCRIPT_MANAGER_ENV，同时移除聚合变量里旧的 go 条目
        #    （脚本块匹配 go bin 特征；java/python/node 等其他运行时条目保留不动）
        Add-ScriptManagerEnvEntry -BinDir $binDir -Scope $scope -IsOldEntry {
            param([string]$s)
            Test-IsGoBinPath $s
        }
        SayC $GREEN '结果' "已把 Go bin 目录写入 SCRIPT_MANAGER_ENV（$scope）: $binDir"

        # 2) 确保主作用域 PATH 前置 SCRIPT_MANAGER_ENV 中的实际路径（CMD 不会展开 %VAR% 引用）
        Ensure-PathHasScriptManagerEnv -Scope $scope
        SayC $GREEN '结果' "已把 SCRIPT_MANAGER_ENV 中的实际路径前置到 $scope PATH"

        # 3) 最后清理：从 Machine + User 两级 PATH 移除旧的 Go bin 绝对路径（\bin + go 特征 + 含 go.exe）
        #    此时新路径已就位，删旧路径不会造成 go 缺失。
        #    保护当前 SCRIPT_MANAGER_ENV 中的路径，避免把刚写进去的新 Go 误删。
        $protectedPaths = @((Get-ScriptManagerEnvForScope -Scope 'Machine') + (Get-ScriptManagerEnvForScope -Scope 'User') | Select-Object -Unique)
        foreach ($oldScope in @('Machine', 'User')) {
            $rawOld = [Environment]::GetEnvironmentVariable('Path', $oldScope)
            if ([string]::IsNullOrWhiteSpace($rawOld)) { continue }
            $removed = @()
            $segmentsOld = @($rawOld -split ';' | ForEach-Object {
                $s = $_.TrimEnd('\')
                if ([string]::IsNullOrWhiteSpace($s)) { return $null }
                if ((Test-IsGoBinPath $s) -and -not ($protectedPaths -contains $s)) {
                    $script:removed += $s
                    return $null
                }
                return $s
            } | Where-Object { $_ } | Select-Object -Unique)
            $newRaw = $segmentsOld -join ';'
            # 防御：过滤后为空（该作用域 PATH 只剩 go 项）时跳过写入，避免把 PATH 清空
            if (-not [string]::IsNullOrWhiteSpace($newRaw) -and $newRaw -ne $rawOld) {
                [Environment]::SetEnvironmentVariable('Path', $newRaw, $oldScope)
                foreach ($r in $removed) {
                    SayC $YELLOW '信息' "已从 $oldScope PATH 移除旧 Go 路径: $r"
                }
            }
        }
    } catch {
        SayC $RED '异常' "更新 PATH 失败: $($_.Exception.Message)"
    }
}

Say ''
Say '=========================================='
SayC $GREEN '结果' "Go $goVer 安装完成"
SayC $GREEN '结果' "Go 目录: $goHome"
if ($AddToPath -eq '是') {
    SayC $GREEN '结果' "已加入 SCRIPT_MANAGER_ENV: $(Join-Path $goHome 'bin')"
    SayC $YELLOW '信息' '工具管理的所有运行时 bin 统一记录在 SCRIPT_MANAGER_ENV，PATH 中写入实际路径'
    SayC $YELLOW '信息' "查看当前内容（新终端）: echo %SCRIPT_MANAGER_ENV%"
    SayC $YELLOW '信息' "切换 Go 版本: 更新 SCRIPT_MANAGER_ENV 后，重新运行安装脚本同步 PATH"
    SayC $YELLOW '信息' "环境变量已写入【$scope 级】，新打开的终端才会生效"
}
Say '=========================================='

