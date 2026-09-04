// 更新时间: 2026-09-04
// Rust 最小模板（ScriptManager）
// 参数用 _p{NAME} 占位符，运行前由程序替换；文件命名须 snake_case（如 hello.rs）
// 运行前程序会用 rustc 编译为临时 exe 再执行
fn main() {
    println!("===== Hello, World =====");
    println!("Hello, _p{NAME}!");
}

