#!/usr/bin/env python3
# 更新时间: 2026-09-04
# Python 外部依赖测试：验证 lib/python 约定子目录能被脚本发现并加载。
# 约定：第三方依赖必须放到 lib/python/（放 lib/python1 等错误目录名不生效）。
# 运行时已注入环境变量 SCRIPT_MANAGER_LIB 指向 lib/ 根目录，脚本自行拼子目录。
import os
import sys
import argparse

parser = argparse.ArgumentParser(description="Python 外部依赖测试")
parser.add_argument("-Name", default="World", help="问候对象，默认 World")
args = parser.parse_args()

lib_root = os.environ.get("SCRIPT_MANAGER_LIB", "")
py_lib = os.path.join(lib_root, "python") if lib_root else ""

print(f"SCRIPT_MANAGER_LIB = {lib_root or '(未注入)'}")
print(f"约定依赖目录 lib/python = {py_lib}")

if py_lib and os.path.isdir(py_lib):
    # 把约定目录加入模块搜索路径，使其下的包/模块可被 import
    sys.path.insert(0, py_lib)
    entries = sorted(
        e for e in os.listdir(py_lib)
        if not e.startswith(".")
    )
    print(f"lib/python 下发现的依赖：{entries if entries else '(空)'}")

    # 真实用法示例：若 lib/python 下有可导入的包（如 requests/自建模块），此处 import
    # 例如：import mylib
    # 下面仅做可达性验证：
    try:
        import this_is_not_a_real_pkg  # noqa: F401  (仅用于演示 import 失败时的友好提示)
    except ImportError:
        print("（未放置真实 Python 包——把 .whl 解包后的包或自建模块放进 lib/python 即可 import）")
else:
    print("未找到 lib/python 目录，依赖加载跳过。")

print(f"Hello, {args.Name}! Python 依赖约定目录验证完成 ✔")
