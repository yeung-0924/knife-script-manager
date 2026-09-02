#!/usr/bin/env python3
# SVG 转多尺寸 ICO：一步完成，替代「SVG → 导出多个 PNG → 在线工具合成 ICO」的繁琐流程。
#
# 参数：
#   -SvgPath  源 SVG 文件路径（必填）
#   -OutPath  输出 ICO 路径或目录（可选，默认：与源文件同目录、同名 .ico）
#             若传入已存在的目录，则在该目录生成「源文件名.ico」
#   -Sizes    尺寸列表，逗号分隔（必填，如 16,32,48,64,256；单个最大 256）
#
# 关于正方形：
#   ICO 格式层面允许非正方形（ICONDIRENTRY 的 width/height 是各自独立的 1 字节字段），
#   但 Windows 的图标加载一律按正方形处理，非正方形会被拉伸变形，故一律输出正方形。
#   源 SVG 非正方形时，固定按【contain】适配：按长边补齐正方形画布，原图居中、四周透明，
#   内容完整不裁剪（代价是图标视觉上小一圈）。不再提供 crop，避免静默切掉内容。
#
# 依赖：
#   pillow                     必需（多尺寸 ICO 编码，原生支持，无需手工拼 ICO 二进制）
#   cairosvg  或  svglib       二选一（SVG 光栅化），脚本自动探测，优先 cairosvg
#
# 安装命令（Windows）：
#   pip install pillow svglib reportlab        # 推荐：纯 Python，无二进制依赖
#   pip install pillow cairosvg                # 可选：渲染质量更好，但 Windows 需 cairo 运行库
#
# 为什么用 Python 而不是 Java：
#   - Pillow 的 img.save(fmt="ICO", sizes=[...]) 一行即可输出多尺寸 ICO，
#     而 Java 需 Batik 光栅化 + 自行拼装 ICO 容器格式（或依赖已停更的 image4j），成本高得多。

import argparse
import io
import os
import platform
import sys

# 占位符未被替换时的特征（用户留空该参数）
PLACEHOLDER_MARK = "_p{"


def is_unset(value):
    """判断参数是否仍为未替换的占位符（用户留空）。"""
    return not value or PLACEHOLDER_MARK in value


# ===================== 依赖探测 =====================

def detect_engine():
    """探测可用的 SVG 光栅化引擎，返回 ("cairosvg"|"svglib", 模块或元组) 或 (None, 原因说明)。"""
    ensure_lib_on_path()  # 让 lib/python 中的可选引擎（cairosvg/svglib/reportlab）也可被发现
    try:
        import cairosvg  # noqa: F401
        return "cairosvg", cairosvg
    except Exception:
        pass

    try:
        from svglib.svglib import svg2rlg  # noqa: F401
        from reportlab.graphics import renderPM  # noqa: F401
        return "svglib", (svg2rlg, renderPM)
    except Exception as e:
        print(f"[调试] svglib/renderPM 加载失败：{e}")
        import traceback
        traceback.print_exc()

    return None, (
        "未找到任何 SVG 渲染引擎。请安装其一：\n"
        "  pip install svglib reportlab     （推荐，纯 Python 无二进制依赖）\n"
        "  pip install cairosvg             （质量更好，Windows 需 cairo 运行库）"
    )


def ensure_lib_on_path():
    """把容器约定的依赖目录加入 sys.path（若存在）。

    运行时容器会注入环境变量 SCRIPT_MANAGER_LIB 指向 lib/ 根目录，其下结构约定：
      lib/python/            放置「与架构无关」的纯 Python 包（如 svglib、reportlab）
      lib/python/<arch>/     放置「与架构相关」的编译扩展包（如 Pillow 的 PIL，含原生 .pyd）
                             arch 取值：arm64 / amd64（按 platform.machine() 判定）

    这样脚本无需用户在全局 pip install，依赖随 lib 走、可移植、跨架构通用。
    """
    lib_root = os.environ.get("SCRIPT_MANAGER_LIB", "")
    if not lib_root:
        return
    py_lib = os.path.join(lib_root, "python")
    # jar 不分架构，但 python 的编译扩展分架构；arm64 机器不能加载 amd64 的 .pyd
    machine = (os.environ.get("PROCESSOR_ARCHITECTURE", "")
               or platform.machine()).lower()
    arch = "arm64" if "arm" in machine else "amd64"

    # 1) 公共纯 Python 包目录（始终优先，含架构无关依赖）
    if os.path.isdir(py_lib) and py_lib not in sys.path:
        sys.path.insert(0, py_lib)
    # 2) 当前架构的原生扩展包目录（仅当存在时加入，缺失架构目录则跳过不影响其他依赖）
    arch_lib = os.path.join(py_lib, arch)
    if os.path.isdir(arch_lib) and arch_lib not in sys.path:
        sys.path.insert(0, arch_lib)


def check_pillow():
    # 优先从容器约定的 lib/python 加载，其次回退全局 site-packages
    ensure_lib_on_path()
    try:
        from PIL import Image
        return Image
    except Exception as e:
        print(f"[调试] PIL 加载失败：{e}")
        print(f"[调试] SCRIPT_MANAGER_LIB = {os.environ.get('SCRIPT_MANAGER_LIB', '<未设置>')}")
        print(f"[调试] sys.path 前 5 项 = {sys.path[:5]}")
        return None


# ===================== SVG 光栅化 =====================

def rasterize(engine, engine_mod, svg_path, target_px):
    """把 SVG 光栅化为 RGBA 位图，短边约 target_px 像素。

    先按高分辨率渲染、后续再高质量缩小（超采样），
    避免直接按小尺寸渲染导致的边缘锯齿。
    """
    if engine == "cairosvg":
        import cairosvg
        png_bytes = cairosvg.svg2png(
            url=svg_path,
            output_width=target_px,
            output_height=target_px,
        )
        from PIL import Image
        return Image.open(io.BytesIO(png_bytes)).convert("RGBA")

    # svglib：按 dpi 控制输出尺寸。reportlab 内部 1px = dpi/72 像素，
    # 故 dpi = 72 * 目标像素 / SVG 原始尺寸。
    svg2rlg, renderPM = engine_mod
    drawing = svg2rlg(svg_path)
    if drawing is None:
        raise RuntimeError("SVG 解析失败，请确认文件内容有效")

    src = max(drawing.width, drawing.height) or target_px
    dpi = 72.0 * target_px / src
    # bg=0x00000000 保留透明背景；不设会渲染成不透明白底
    img = renderPM.drawToPIL(drawing, dpi=dpi, bg=0x00000000)
    return img.convert("RGBA")


# ===================== 主流程 =====================

def main():
    parser = argparse.ArgumentParser(description="SVG 转多尺寸 ICO")
    parser.add_argument("-SvgPath", default="_p{SVG_PATH}", help="源 SVG 文件路径")
    parser.add_argument("-OutPath", default="_p{OUT_PATH}", help="输出 ICO 路径（可选）")
    parser.add_argument("-Sizes", default="_p{SIZES}", help="尺寸列表，逗号分隔（必填，如 16,32,48,64,256）")
    args = parser.parse_args()

    print("[信息] SVG 转多尺寸 ICO")

    # ---- 校验源路径 ----
    if is_unset(args.SvgPath):
        print("[错误] 未提供源 SVG 路径（参数 -SvgPath）")
        return 1
    svg_path = args.SvgPath.strip().strip('"').strip("'")
    if not os.path.isfile(svg_path):
        print("[错误] 源文件不存在: " + svg_path)
        return 1

    # ---- 输出路径 ----
    if is_unset(args.OutPath):
        out_path = os.path.splitext(svg_path)[0] + ".ico"
    else:
        raw = args.OutPath.strip().strip('"').strip("'")
        # 若用户给的是目录（以 .ico 结尾视为文件，否则视为目录），则按源文件名生成 .ico
        if os.path.isdir(raw):
            out_path = os.path.join(raw, os.path.splitext(os.path.basename(svg_path))[0] + ".ico")
        else:
            out_path = raw
    out_dir = os.path.dirname(os.path.abspath(out_path))
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    # ---- 尺寸列表（必填）----
    # 一个 ICO 可内含多个尺寸，Windows 按显示场景自动选用：
    #   16=任务栏/小图标视图，48=桌面，64/256=大图标视图与高 DPI 屏幕。
    if is_unset(args.Sizes):
        print("[错误] 未提供尺寸列表（参数 _SIZES），请填写，如：16,32,48,64,256")
        return 1

    sizes = []
    for part in args.Sizes.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            sizes.append(int(part))
        except ValueError:
            print("[错误] 尺寸不是整数: " + part)
            return 1
    if not sizes:
        print("[错误] 尺寸列表为空，请填写，如：16,32,48,64,256")
        return 1

    # ICO 规范上限 256；0 表示 256，但这里直接限制更直观
    bad = [s for s in sizes if s < 1 or s > 256]
    if bad:
        print("[错误] 尺寸超出 1-256 范围: " + ", ".join(str(b) for b in bad))
        return 1
    sizes = sorted(set(sizes))

    # ---- 依赖检查 ----
    Image = check_pillow()
    if Image is None:
        print("[错误] 缺少 Pillow（PIL 包）。请将 Pillow 安装到容器约定的依赖目录：")
        print("        把 Pillow 的 PIL 包放到 lib/python/ 下（运行时容器会注入")
        print("        环境变量 SCRIPT_MANAGER_LIB 指向 lib/ 根目录），例如：")
        print("          pip install pillow --target <lib>/python")
        print("        或在脚本管理器中通过「依赖管理」下载 Pillow 到 lib/python。")
        return 1

    engine, engine_mod = detect_engine()
    if engine is None:
        print("[错误] " + engine_mod)
        return 1

    print("[信息] 源文件: " + os.path.basename(svg_path))
    print("[信息] 渲染引擎: " + engine)
    print("[信息] 目标尺寸: " + ", ".join(str(s) for s in sizes))

    # ---- 光栅化：按最大尺寸的 4 倍超采样，再缩小以保证小尺寸质量 ----
    max_size = max(sizes)
    # 上限保护：避免超大 SVG 与超高分辨率导致内存占用过高
    render_px = min(max_size * 4, 2048)
    print("[信息] 渲染分辨率: " + str(render_px) + "px（超采样后缩小）")

    try:
        img = rasterize(engine, engine_mod, svg_path, render_px)
    except Exception as ex:
        print("[错误] 渲染失败: " + str(ex))
        if engine == "cairosvg":
            print("[提示] cairosvg 在 Windows 上依赖 cairo 运行库；"
                  "若无该环境，可改用纯 Python 方案：pip install svglib reportlab")
        return 1

    # ---- 适配为正方形（固定 contain）----
    # ICO 的 ICONDIRENTRY 里 width/height 是两个独立字段，【格式层面允许非正方形】，
    # 但 Windows 的图标加载一律按正方形处理，非正方形会被拉伸变形，故一律输出正方形。
    # 固定采用 contain：按长边补齐为正方形画布，原图居中、四周透明。
    # 不提供 crop —— 裁剪会静默切掉横向/纵向 logo 的两侧内容，代价不透明。
    width, height = img.size
    if width != height:
        side = max(width, height)
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(img, ((side - width) // 2, (side - height) // 2))
        img = canvas
        print("[信息] 源图非正方形（" + str(width) + "x" + str(height) +
              "），已居中留白为 " + str(side) + "x" + str(side) +
              "（内容完整，四周透明）")

    # ---- 保存多尺寸 ICO（Pillow 原生支持，一行搞定）----
    try:
        img.save(out_path, format="ICO", sizes=[(s, s) for s in sizes])
    except Exception as ex:
        print("[错误] 写入 ICO 失败: " + str(ex))
        return 1

    print("[结果] 已生成: " + out_path)
    print("[结果] 包含尺寸: " + ", ".join(str(s) + "x" + str(s) for s in sizes))
    print("[结果] 文件大小: " + str(os.path.getsize(out_path)) + " 字节")
    return 0


if __name__ == "__main__":
    sys.exit(main())
