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
    let mut name = "World".to_string();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "-Name" && i + 1 < args.len() {
            name = args[i + 1].clone();
            i += 2;
        } else {
            i += 1;
        }
    }

    // ===== Hello, World =====
    println!("===== Hello, World =====");

    // 入参
    println!("{}[入参]{} name = {}", GREEN, RESET, name);

    // 信息
    println!("{}[信息]{} 执行目录：{}", YELLOW, RESET, working_dir());

    // 脚本自身 stdout（原色，不加标识）
    println!("Hello, {}! 来自 Rust 示例脚本。", name);
    println!("1 + 1 = {}", 1 + 1);

    // 异常演示（仅当第二个参数为 "err" 时触发）
    if args.len() > 1 && args[1] == "err" {
        println!("{}[异常]{} 故意抛出的演示错误", RED, RESET);
        std::process::exit(1);
    }

    // ===== 多色日志 =====
    println!("===== 多色日志 =====");
    // 多彩日志：输出 16 种 ANSI 前景色（30-37 / 90-97），执行器解析 SGR 前景色并连同色名打印
    let colors: [(u8, &str); 16] = [
        (30, "黑"), (31, "红"), (32, "绿"), (33, "黄"), (34, "蓝"),
        (35, "品红"), (36, "青"), (37, "白"),
        (90, "灰"), (91, "亮红"), (92, "亮绿"), (93, "亮黄"),
        (94, "亮蓝"), (95, "亮品红"), (96, "亮青"), (97, "亮白"),
    ];
    for (code, name) in colors.iter() {
        println!("{}{}m这是一行\"{}\"日志（{}）{}", ESC, code, code, name, RESET);
    }
}

fn working_dir() -> String {
    env::current_dir()
        .map(|p| p.display().to_string())
        .unwrap_or_else(|_| "<未知>".to_string())
}
