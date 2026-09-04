@echo off
rem 更新时间: 2026-09-04
rem ============================================================================
rem  ScriptManager 使用说明
rem ============================================================================

rem 生成 ESC 转义字符（Windows 10+ Conhost 支持 ANSI）
for /F "delims=" %%L in ('"prompt $E & echo on & for %%i in (1) do rem"') do set "RAW=%%L"
set "ESC=%RAW:~0,1%"

rem ---------- 标题：工具说明 ----------
echo %ESC%[91m# 工具说明：%ESC%[0m
echo %ESC%[90m本工具运行在 windows 操作系统，需 .net10 环境支持，也可选择内置环境的便携版进行使用，目前提供对 cmd ^| powershell ^| bash ^| java ^| python ^| nodejs ^| go ^| rust 语言的脚本支持（需安装对应的环境）。%ESC%[0m
echo.
rem ---------- 标题：目录说明 ----------
echo %ESC%[91m# 目录说明：%ESC%[0m
echo %ESC%[93mScriptManager 根目录%ESC%[0m
echo %ESC%[93m  - ScriptManager.exe 主程序%ESC%[0m
echo %ESC%[93m  - config 配置目录%ESC%[0m
echo %ESC%[93m    - config.ini 配置文件%ESC%[0m
echo %ESC%[93m  - script 脚本目录%ESC%[0m
echo %ESC%[93m    - README.md 脚本编写说明%ESC%[0m
echo %ESC%[93m  - lib 第三方依赖包%ESC%[0m
echo %ESC%[93m  - runtime 运行时环境%ESC%[0m
echo %ESC%[93m    - java%ESC%[0m
echo %ESC%[93m    - python%ESC%[0m
echo %ESC%[93m      - amd%ESC%[0m
echo %ESC%[93m      - arm%ESC%[0m
echo %ESC%[93m    - node%ESC%[0m
echo %ESC%[93m  - cache 缓存文件%ESC%[0m
echo %ESC%[93m  - log 日志文件%ESC%[0m
echo.
rem ---------- 标题：脚本编写说明 ----------
echo %ESC%[91m# 脚本编写说明：%ESC%[0m
echo %ESC%[90m详见 ScriptManager/README.md%ESC%[0m
echo.
