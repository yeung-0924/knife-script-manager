// 更新时间: 2026-09-04
use std::env;

// 颜色（ANSI 转义，Windows 10+ 终端原生支持）
const ESC: &str = "\x1b";
const GREEN: &str = "\x1b[92m"; // 入参
const YELLOW: &str = "\x1b[93m"; // 信息
const RED: &str = "\x1b[91m"; // 异常
const RESET: &str = "\x1b[0m";

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let name = if !args.is_empty() {
        args[0].clone()
    } else {
        "World".to_string()
    };

    // 入参
    println!("{}[入参]{} name = {}", GREEN, RESET, name);

    // 信息
    println!("{}[信息]{} 执行目录：{}", YELLOW, RESET, working_dir());

    // 脚本自身 stdout（原色，不加标识）
    println!("Hello, {}! 来自 Rust 测试脚本。", name);
    println!("1 + 1 = {}", 1 + 1);

    // 异常演示（仅当第二个参数为 "err" 时触发）
    if args.len() > 1 && args[1] == "err" {
        println!("{}[异常]{} 故意抛出的演示错误", RED, RESET);
        std::process::exit(1);
    }
}

fn working_dir() -> String {
    env::current_dir()
        .map(|p| p.display().to_string())
        .unwrap_or_else(|_| "<未知>".to_string())
}
