@echo off
rem 更新时间: 2026-09-04 17:31:44
rem CMD 最小模板（ScriptManager）
rem 参数用 _p{NAME} 占位符，运行前由程序替换（中文由程序自动处理，照常写即可）
echo ===== Hello, World =====
rem 从脚本自身注释解析「更新时间」并打印（不硬编码，按 ASCII 时间戳匹配以避开中文编码问题）
for /f "usebackq delims=" %%L in (`findstr /r "20[0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]" "%~f0"`) do (
    for /f "tokens=1* delims=:" %%A in ("%%L") do (
        echo [信息]%%B
        goto :ut_done
    )
)
:ut_done
echo Hello, _p{NAME}!
