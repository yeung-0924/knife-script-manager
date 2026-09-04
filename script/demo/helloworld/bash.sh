#!/usr/bin/env bash
# 更新时间: 2026-09-04 14:59:35
# Bash 示例脚本：输出 Hello World 并回显传入的参数
# 运行参数：-Name <值>，默认 World

NAME="World"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -Name)
            NAME="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo "===== Hello, World ====="
echo "Hello, $NAME!"
echo "接收参数 Name = $NAME"

echo "===== 多色日志 ====="
# 多彩日志：输出 16 种 ANSI 前景色（30-37 / 90-97），执行器解析 SGR 前景色并连同色名打印
echo $'\e[30m这是一行"30"日志（黑）\e[0m'
echo $'\e[31m这是一行"31"日志（红）\e[0m'
echo $'\e[32m这是一行"32"日志（绿）\e[0m'
echo $'\e[33m这是一行"33"日志（黄）\e[0m'
echo $'\e[34m这是一行"34"日志（蓝）\e[0m'
echo $'\e[35m这是一行"35"日志（品红）\e[0m'
echo $'\e[36m这是一行"36"日志（青）\e[0m'
echo $'\e[37m这是一行"37"日志（白）\e[0m'
echo $'\e[90m这是一行"90"日志（灰）\e[0m'
echo $'\e[91m这是一行"91"日志（亮红）\e[0m'
echo $'\e[92m这是一行"92"日志（亮绿）\e[0m'
echo $'\e[93m这是一行"93"日志（亮黄）\e[0m'
echo $'\e[94m这是一行"94"日志（亮蓝）\e[0m'
echo $'\e[95m这是一行"95"日志（亮品红）\e[0m'
echo $'\e[96m这是一行"96"日志（亮青）\e[0m'
echo $'\e[97m这是一行"97"日志（亮白）\e[0m'

