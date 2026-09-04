#!/usr/bin/env python3
# 更新时间: 2026-09-04 17:31:44
# Python 最小模板（ScriptManager）
# 参数用 _p{NAME} 占位符，运行前由程序替换
print("===== Hello, World =====")
# 从脚本自身首行注释解析「更新时间」并打印（不硬编码）
with open(__file__, encoding="utf-8") as _f:
    _ut_line = next((l for l in _f if "更新时间:" in l), "")
_ut = _ut_line.split("更新时间:")[1].strip() if _ut_line else ""
if _ut:
    print(f"[信息] 更新时间: {_ut}")
print("Hello, _p{NAME}!")
