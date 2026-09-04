// 更新时间: 2026-09-04 17:31:44
// Rust 最小模板（ScriptManager）
// 参数用 _p{NAME} 占位符，运行前由程序替换；文件命名须 snake_case（如 hello.rs）
// 运行前程序会用 rustc 把本文件编译为临时 exe 再执行
// 注：ScriptManager 运行时会把本文件写成随机临时文件（se_script_*.rs）再 rustc 编译，
// 故无法用固定文件名 include_str!；改为用 std::env::current_exe() 定位「同目录同名 .rs 源码」并解析「更新时间」（不硬编码，改名/随机名都照常工作）
use std::fs;

fn main() {
    println!("===== Hello, World =====");
    // 从编译所用源码（与 exe 同目录、同名 .rs）解析「更新时间」并打印（不硬编码）
    if let Ok(exe) = std::env::current_exe() {
        let mut candidates: Vec<std::path::PathBuf> = Vec::new();
        // 首选：exe 同名 .rs（rustc 默认把 .rs 编译到同目录 .exe）
        if let Some(p) = exe.with_extension("rs").canonicalize().ok() {
            candidates.push(p);
        }
        // 兜底：扫描 exe 所在目录里所有 .rs 源文件
        if let Some(dir) = exe.parent() {
            if let Ok(entries) = fs::read_dir(dir) {
                for e in entries.flatten() {
                    let p = e.path();
                    if p.extension().and_then(|s| s.to_str()) == Some("rs") {
                        candidates.push(p);
                    }
                }
            }
        }
        for p in candidates {
            if let Ok(content) = fs::read_to_string(&p) {
                if let Some(line) = content.lines().find(|l| l.contains("更新时间:")) {
                    if let Some(rest) = line.split_once("更新时间:") {
                        println!("[信息] 更新时间: {}", rest.trim());
                        break;
                    }
                }
            }
        }
    }
    println!("Hello, _p{NAME}!");
}
