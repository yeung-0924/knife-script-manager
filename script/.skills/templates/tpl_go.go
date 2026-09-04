package main

// 更新时间: 2026-09-04 17:31:44

import (
	"fmt"
	"os"
	"runtime"
	"strings"
)

// Go 最小模板（ScriptManager）
// 参数用 _p{NAME} 占位符，运行前由程序替换；文件命名须 snake_case（如 hello.go）
// 注：ScriptManager 运行时会把本文件写成随机临时文件（se_script_*.go）再 `go run`，
// 故无法用固定文件名 embed；改为用 runtime.Caller(0) 取「自身源码路径」并解析「更新时间」（不硬编码，改名/随机名都照常工作）
func main() {
	fmt.Println("===== Hello, World =====")
	// 从自身源码注释解析「更新时间」并打印（不硬编码）
	if _, file, _, ok := runtime.Caller(0); ok {
		if data, err := os.ReadFile(file); err == nil {
			for _, line := range strings.Split(string(data), "\n") {
				if strings.Contains(line, "更新时间:") {
					fmt.Printf("[信息] 更新时间: %s\n", strings.TrimSpace(strings.SplitN(line, "更新时间:", 2)[1]))
					break
				}
			}
		}
	}
	fmt.Println("Hello, _p{NAME}!")
}
