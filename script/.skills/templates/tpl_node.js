#!/usr/bin/env node
// 更新时间: 2026-09-04 17:31:44
// Node 最小模板（ScriptManager）
// 参数用 _p{NAME} 占位符，运行前由程序替换
console.log("===== Hello, World =====");
// 从脚本自身首行注释解析「更新时间」并打印（不硬编码）
const fs = require('fs');
const _utLine = fs.readFileSync(__filename, 'utf-8').split('\n').find(l => l.includes('更新时间:'));
const _ut = _utLine ? _utLine.split('更新时间:')[1].trim() : '';
if (_ut) console.log('[信息] 更新时间: ' + _ut);
console.log("Hello, _p{NAME}!");
