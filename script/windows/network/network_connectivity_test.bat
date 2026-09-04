@echo off
rem 更新时间: 2026-09-04 14:59:35
REM 网络连通性测试（ICMP 或 TCP 端口）。
REM 占位符：_p{HOST} - 目标主机（IPv4 或域名，必填）
REM         _p{PORT} - 目标端口（选填；填写后改为 TCP 测试，否则做 ICMP 测试）
REM
REM 模式：
REM   仅填主机      → ICMP（优先 ping.exe，缺失则用 PowerShell Test-Connection）
REM   主机 + 端口    → TCP（PowerShell TcpClient；再降级 curl）
REM 域名会先做 DNS 解析并展示“域名 → IP”。
REM
REM ============ 实现约束（踩过坑，勿改回旧写法）============
REM 1. 禁止用 for /f 捕获外部命令输出。原因：for /f 启动子进程会破坏 cmd 的批处理文件读取指针，
REM    导致后续 goto 找不到标签，报 "The system cannot find the batch label specified - summary"
REM    （本脚本曾在 TCP 分支 100% 触发，而 ICMP 分支正常——区别就是块内有无 for /f）。
REM    替代方案：只需判断成败 → 让 powershell 直接 exit 码；需要文本内容 → 临时文件 + set /p。
REM 2. 本脚本已彻底去掉 goto，改为 if/else 嵌套，避免任何对文件指针跳转的依赖。
REM 3. 需要文本时用 Out-File -Encoding ASCII 写临时文件：PowerShell 默认输出 UTF-16LE，
REM    cmd 侧读出来会是乱码；显式 ASCII 可保证 set /p 读到正确内容（捕获的仅为 IP 等 ASCII 文本）。
REM 4. 判断成败统一用 if errorlevel 1 —— 该语法直接读当前 errorlevel，不受变量展开时机影响。

setlocal EnableDelayedExpansion

REM 生成 ESC 字符（与 test_cmd_colors.bat 同款可靠写法，避免 for /f 在重定向环境下抓不到）
for /F "delims=" %%L in ('"prompt $E & echo on & for %%i in (1) do rem"') do set "RAW=%%L"
set "ESC=%RAW:~0,1%"

set "TARGET=_p{HOST}"
set "PORT=_p{PORT}"
set "TMPF=%TEMP%\se_nettest_%RANDOM%.tmp"
set "TEST_OK="

REM ---------- 1. 校验主机 ----------
if "%TARGET%"=="" (
    echo %RED%[异常] 未提供目标主机%RESET%
    exit /b 1
)

REM ---------- 2. 判断 IP / 域名并解析 ----------
set "RESOLVED_IP=%TARGET%"
set "IS_IP4=0"
REM 颜色辅助变量：入参/结果 92 亮绿，信息 93 亮黄，异常 91 亮红
set "GREEN=%ESC%[92m"
set "YELLOW=%ESC%[93m"
set "RED=%ESC%[91m"
set "RESET=%ESC%[0m"

REM 入参
echo %GREEN%[入参] 目标主机(TARGET) = %TARGET%%RESET%
echo %GREEN%[入参] 目标端口(PORT)   = %PORT%%RESET%
REM 用 PowerShell 精确判断 IPv4（findstr 正则在某些域名上会被误判为 IP）
powershell -NoProfile -Command "$ip=[IPAddress]::None; exit [int]([IPAddress]::TryParse('%TARGET%', [ref]$ip) -and ($ip.AddressFamily -eq 'InterNetwork'))" >nul 2>&1
if %errorlevel% equ 1 set "IS_IP4=1"
if "%IS_IP4%"=="1" (
    echo %YELLOW%[信息] 输入为 IPv4 地址，跳过 DNS 解析%RESET%
    echo %YELLOW%[信息] 目标 = %TARGET%%RESET%
) else (
    echo %YELLOW%[信息] 输入为域名，正在 DNS 解析: %TARGET%%RESET%
    set "RESOLVED_IP="

    REM 优先用 PowerShell Resolve-DnsName（Win8+）；-Encoding ASCII 保证 cmd 侧可读
    powershell -NoProfile -Command "(Resolve-DnsName -Name '%TARGET%' -ErrorAction SilentlyContinue | Where-Object {$_.Type -eq 'A'} | Select-Object -First 1).IPAddress | Out-File -Encoding ASCII -FilePath '%TMPF%'" >nul 2>&1
    if exist "%TMPF%" (
        set /p RESOLVED_IP=< "%TMPF%"
        del "%TMPF%" 2>nul
    )

    REM nslookup 兜底
    if "!RESOLVED_IP!"=="" (
        set "NS_LINE="
        nslookup -timeout=3 %TARGET% 2>nul | findstr /R /C:"^Address:" > "%TMPF%"
        if exist "%TMPF%" (
            set /p NS_LINE=< "%TMPF%"
            del "%TMPF%" 2>nul
        )
        if defined NS_LINE (
            REM 处理字符串（非读进程输出），安全：Address:  1.2.3.4 → 取 IP
            for /f "tokens=2 delims=: " %%i in ("!NS_LINE!") do set "RESOLVED_IP=%%i"
        )
    )

    if "!RESOLVED_IP!"=="" (
        echo %RED%[异常] DNS 解析失败: %TARGET%%RESET%
        exit /b 1
    )
    echo %YELLOW%[信息] 解析结果: %TARGET% → !RESOLVED_IP!%RESET%
)

REM ---------- 3. 测试：按端口分流（TCP / ICMP）----------
if "%PORT%"=="" (
    where ping >nul 2>&1
    if not errorlevel 1 (
        echo %YELLOW%[信息] 正在 ping %TARGET% ...%RESET%
        ping -n 4 %TARGET%
        if errorlevel 1 (set "TEST_OK=0") else (set "TEST_OK=1")
    ) else (
        where powershell >nul 2>&1
        if not errorlevel 1 (
            echo %YELLOW%[信息] 未找到 ping，改用 PowerShell Test-Connection 测试 %TARGET% ...%RESET%
            powershell -NoProfile -Command "if (Test-Connection -ComputerName '%TARGET%' -Count 4 -Quiet) { exit 0 } else { exit 1 }" >nul 2>&1
            if errorlevel 1 (set "TEST_OK=0") else (set "TEST_OK=1")
        ) else (
            echo %RED%[异常] 环境既无 ping 也无 PowerShell Test-Connection，无法测试。%RESET%
            exit /b 1
        )
    )
) else (
    where powershell >nul 2>&1
    if not errorlevel 1 (
        echo %YELLOW%[信息] 使用 PowerShell TcpClient 测试 TCP %TARGET%:%PORT% ...%RESET%
        powershell -NoProfile -Command "try { $c=New-Object System.Net.Sockets.TcpClient; $c.Connect('%TARGET%',%PORT%); $c.Close(); exit 0 } catch { exit 1 }" >nul 2>&1
        if errorlevel 1 (set "TEST_OK=0") else (set "TEST_OK=1")
    ) else (
        where curl >nul 2>&1
        if not errorlevel 1 (
            echo %YELLOW%[信息] 使用 curl 测试 TCP %TARGET%:%PORT% ...%RESET%
            curl -s -o nul --connect-timeout 4 telnet://%TARGET%:%PORT% >nul 2>&1
            if errorlevel 1 (set "TEST_OK=0") else (set "TEST_OK=1")
        ) else (
            echo %RED%[异常] 无任何可用工具进行 TCP 测试（需要 PowerShell 或 curl）。%RESET%
            exit /b 1
        )
    )
)

REM ---------- 4. 汇总 ----------
echo.
if "%PORT%"=="" (
    if "%TEST_OK%"=="1" (
        echo %GREEN%[结果] %TARGET% 连通正常（解析 IP: !RESOLVED_IP!）%RESET%
        exit /b 0
    )
    echo %GREEN%[结果] %TARGET% 不可达（解析 IP: !RESOLVED_IP!）%RESET%
    exit /b 1
)

if "%TEST_OK%"=="1" (
    echo %GREEN%[结果] %TARGET%:%PORT% TCP 端口开放（解析 IP: !RESOLVED_IP!）%RESET%
    exit /b 0
)
echo %GREEN%[结果] %TARGET%:%PORT% TCP 端口不通（解析 IP: !RESOLVED_IP!）%RESET%
exit /b 1

