#!/usr/bin/env bash
# 更新时间: 2026-09-04 17:31:44
# Bash 最小模板（ScriptManager）
# 参数用 _p{NAME} 占位符，运行前由程序替换
echo "===== Hello, World ====="
# 从脚本自身首行注释解析「更新时间」并打印（不硬编码）
UT=$(grep -m1 '更新时间:' "$0" | sed 's/.*更新时间:[[:space:]]*//')
echo "[信息] 更新时间: $UT"
echo "Hello, _p{NAME}!"
