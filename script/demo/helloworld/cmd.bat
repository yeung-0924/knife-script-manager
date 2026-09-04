@echo off
rem 更新时间: 2026-09-04
rem CMD 示例脚本：输出 Hello World 并回显传入的参数
rem 运行参数：-Name <值>，默认 World
set "NAME=World"
set "_shifted=0"

:parse
if "%~1"=="" goto done
if /i "%~1"=="-Name" (
    set "NAME=%~2"
    shift
    shift
    goto parse
)
shift
goto parse

:done
echo ===== Hello, World =====
echo Hello, %NAME%!
echo 接收参数 Name = %NAME%

echo ===== 多色日志 =====
rem 多彩日志：输出 16 种 ANSI 前景色（30-37 / 90-97），执行器解析 SGR 前景色并连同色名打印
for /F "delims=" %%L in ('"prompt $E & echo on & for %%i in (1) do rem"') do set "RAW=%%L"
set "ESC=%RAW:~0,1%"

echo %ESC%[30m这是一行"30"日志（黑）%ESC%[0m
echo %ESC%[31m这是一行"31"日志（红）%ESC%[0m
echo %ESC%[32m这是一行"32"日志（绿）%ESC%[0m
echo %ESC%[33m这是一行"33"日志（黄）%ESC%[0m
echo %ESC%[34m这是一行"34"日志（蓝）%ESC%[0m
echo %ESC%[35m这是一行"35"日志（品红）%ESC%[0m
echo %ESC%[36m这是一行"36"日志（青）%ESC%[0m
echo %ESC%[37m这是一行"37"日志（白）%ESC%[0m
echo %ESC%[90m这是一行"90"日志（灰）%ESC%[0m
echo %ESC%[91m这是一行"91"日志（亮红）%ESC%[0m
echo %ESC%[92m这是一行"92"日志（亮绿）%ESC%[0m
echo %ESC%[93m这是一行"93"日志（亮黄）%ESC%[0m
echo %ESC%[94m这是一行"94"日志（亮蓝）%ESC%[0m
echo %ESC%[95m这是一行"95"日志（亮品红）%ESC%[0m
echo %ESC%[96m这是一行"96"日志（亮青）%ESC%[0m
echo %ESC%[97m这是一行"97"日志（亮白）%ESC%[0m
