package main
// 更新时间: 2026-09-04

import "fmt"

// Go 最小模板（ScriptManager）
// 参数用 _p{NAME} 占位符，运行前由程序替换；文件命名须 snake_case（如 hello.go）
func main() {
	fmt.Println("===== Hello, World =====")
	fmt.Println("Hello, _p{NAME}!")
}
