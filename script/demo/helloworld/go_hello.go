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
	for i := 0; i < len(args); i++ {
		if args[i] == "-Name" && i+1 < len(args) {
			name = args[i+1]
			i++
		}
	}

	// ===== Hello, World =====
	fmt.Println("===== Hello, World =====")

	// 入参
	fmt.Printf("%s[入参]%s name = %s\n", green, reset, name)

	// 信息
	fmt.Printf("%s[信息]%s Go 版本：%s\n", yellow, reset, runtime.Version())
	fmt.Printf("%s[信息]%s 执行目录：%s\n", yellow, reset, workingDir())

	// 脚本自身 stdout（原色，不加标识）
	fmt.Printf("Hello, %s! 来自 Go 示例脚本。\n", name)
	fmt.Println("1+1 =", 1+1)

	// 异常演示（仅当第二个参数为 "err" 时触发）
	if len(args) > 1 && args[1] == "err" {
		fmt.Printf("%s[异常]%s 故意抛出的演示错误\n", red, reset)
		os.Exit(1)
	}

	// ===== 多色日志 =====
	fmt.Println("===== 多色日志 =====")
	// 多彩日志：输出 16 种 ANSI 前景色（30-37 / 90-97），执行器解析 SGR 前景色并连同色名打印
	colors := []struct {
		code int
		name string
	}{
		{30, "黑"}, {31, "红"}, {32, "绿"}, {33, "黄"}, {34, "蓝"},
		{35, "品红"}, {36, "青"}, {37, "白"},
		{90, "灰"}, {91, "亮红"}, {92, "亮绿"}, {93, "亮黄"},
		{94, "亮蓝"}, {95, "亮品红"}, {96, "亮青"}, {97, "亮白"},
	}
	for _, c := range colors {
		fmt.Printf("%s[%d]%s这是一行\"%d\"日志（%s）%s\n", esc, c.code, "m", c.code, c.name, reset)
	}
}

func workingDir() string {
	wd, err := os.Getwd()
	if err != nil {
		return "<未知>"
	}
	return wd
}

