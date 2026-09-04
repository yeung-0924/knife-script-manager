package main
// 更新时间: 2026-09-04

import (
	"fmt"
	"os"
	"runtime"
)

// 颜色（ANSI 转义，Windows 10+ 终端原生支持）
const (
	esc    = "\x1b"
	green  = esc + "[92m" // 入参
	yellow = esc + "[93m" // 信息
	red    = esc + "[91m" // 异常
	reset  = esc + "[0m"
)

func main() {
	args := os.Args[1:]
	name := "World"
	if len(args) > 0 {
		name = args[0]
	}

	// 入参
	fmt.Printf("%s[入参]%s name = %s\n", green, reset, name)

	// 信息
	fmt.Printf("%s[信息]%s Go 版本：%s\n", yellow, reset, runtime.Version())
	fmt.Printf("%s[信息]%s 执行目录：%s\n", yellow, reset, workingDir())

	// 脚本自身 stdout（原色，不加标识）
	fmt.Printf("Hello, %s! 来自 Go 测试脚本。\n", name)
	fmt.Println("1+1 =", 1+1)

	// 异常演示（仅当第二个参数为 "err" 时触发）
	if len(args) > 1 && args[1] == "err" {
		fmt.Printf("%s[异常]%s 故意抛出的演示错误\n", red, reset)
		os.Exit(1)
	}
}

func workingDir() string {
	wd, err := os.Getwd()
	if err != nil {
		return "<未知>"
	}
	return wd
}
