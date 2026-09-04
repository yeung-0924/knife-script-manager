#!/usr/bin/env node
# 更新时间: 2026-09-04
// Node.js 示例脚本：输出 Hello World 并回显传入的参数
// 运行参数：-Name <值>，默认 World

function parseArgs(argv) {
    const args = { Name: "World" };
    for (let i = 0; i < argv.length; i++) {
        if (argv[i] === "-Name" && i + 1 < argv.length) {
            args.Name = argv[i + 1];
            i++;
        }
    }
    return args;
}

const args = parseArgs(process.argv.slice(2));
console.log("===== Hello, World =====");
console.log(`Hello, ${args.Name}!`);
console.log(`接收参数 Name = ${args.Name}`);

console.log("===== 多色日志 =====");
// 多彩日志：输出 16 种 ANSI 前景色（30-37 / 90-97），执行器解析 SGR 前景色并连同色名打印
console.log("\x1b[30m这是一行\"30\"日志（黑）\x1b[0m");
console.log("\x1b[31m这是一行\"31\"日志（红）\x1b[0m");
console.log("\x1b[32m这是一行\"32\"日志（绿）\x1b[0m");
console.log("\x1b[33m这是一行\"33\"日志（黄）\x1b[0m");
console.log("\x1b[34m这是一行\"34\"日志（蓝）\x1b[0m");
console.log("\x1b[35m这是一行\"35\"日志（品红）\x1b[0m");
console.log("\x1b[36m这是一行\"36\"日志（青）\x1b[0m");
console.log("\x1b[37m这是一行\"37\"日志（白）\x1b[0m");
console.log("\x1b[90m这是一行\"90\"日志（灰）\x1b[0m");
console.log("\x1b[91m这是一行\"91\"日志（亮红）\x1b[0m");
console.log("\x1b[92m这是一行\"92\"日志（亮绿）\x1b[0m");
console.log("\x1b[93m这是一行\"93\"日志（亮黄）\x1b[0m");
console.log("\x1b[94m这是一行\"94\"日志（亮蓝）\x1b[0m");
console.log("\x1b[95m这是一行\"95\"日志（亮品红）\x1b[0m");
console.log("\x1b[96m这是一行\"96\"日志（亮青）\x1b[0m");
console.log("\x1b[97m这是一行\"97\"日志（亮白）\x1b[0m");

