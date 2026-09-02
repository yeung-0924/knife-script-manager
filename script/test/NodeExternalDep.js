#!/usr/bin/env node
// Node.js 外部依赖测试：验证 lib/node 约定子目录能被脚本发现并加载。
// 约定：第三方依赖必须放到 lib/node/（放 lib/node1 等错误目录名不生效）。
// 运行时已注入环境变量 SCRIPT_MANAGER_LIB 指向 lib/ 根目录，脚本自行拼子目录。
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
const libRoot = process.env.SCRIPT_MANAGER_LIB || "";
const nodeLib = libRoot ? require("path").join(libRoot, "node") : "";

console.log(`SCRIPT_MANAGER_LIB = ${libRoot || "(未注入)"}`);
console.log(`约定依赖目录 lib/node = ${nodeLib}`);

if (nodeLib && require("fs").existsSync(nodeLib)) {
    // 把约定目录加入模块解析路径，使其下的包可被 require
    module.paths.unshift(nodeLib);
    const entries = require("fs")
        .readdirSync(nodeLib)
        .filter((e) => !e.startsWith("."));
    console.log(`lib/node 下发现的依赖：${entries.length ? entries : "(空)"}`);

    // 真实用法示例：若 lib/node 下有可 require 的包（如 lodash），此处 require
    // 例如：const _ = require("lodash");
    console.log("（未放置真实 Node 包——把 npm 包放进 lib/node 即可 require）");
} else {
    console.log("未找到 lib/node 目录，依赖加载跳过。");
}

console.log(`Hello, ${args.Name}! Node 依赖约定目录验证完成 ✔`);
