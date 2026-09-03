using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;

namespace ScriptManager;

/// <summary>
/// 文件夹变色（desktop.ini + fColors.icl）。
/// <para>
/// 机制：Windows 资源管理器在文件夹含 <c>desktop.ini</c>（且文件夹带 System 属性、desktop.ini 带 Hidden+System）时，
/// 会按 desktop.ini 的 <c>IconFile</c>/<c>IconIndex</c> 显示该文件夹图标。这里在每个标准目录
/// （config/log/cache/lib/runtime/script）写入对应的 desktop.ini，通过相对路径引用 exe 同级
/// <c>config\fColors.icl</c> 图标库里的某个图标序号，从而让这些文件夹显示成彩色样式。
/// </para>
/// <para>
/// 资源来源：<c>fColors.icl</c> 由 build.ps1 在打包时复制到 <c>config\</c>；desktop.ini 由各目录相对
/// <c>config\fColors.icl</c> 的路径在运行时生成（相对路径用 <see cref="Path.GetRelativePath"/> 动态计算，
/// 故 config 自身为 <c>.\fColors.icl</c>、其余兄弟目录为 <c>..\config\fColors.icl</c>，即使目录被用户改到
/// 其它位置也能正确指向）。
/// 图标序号对齐 F:\!config：template6=6（通用系统目录）、template8=8（script 目录）、顶层=0（config 目录自身）。
/// </para>
/// <para>
/// 规范模板（含固定相对路径）保留在 <c>assets/folder-icons/desktop.template*.ini</c> 作为来源参考，运行时生成的
/// 内容与之一致。任何异常均被吞掉并记调试日志，绝不影响主程序启动。
/// </para>
/// </summary>
public static class FolderCustomizer
{
    // 图标序号：与 F:\!config 的 template6(6) / template8(8) / 顶层 config(0) 对应
    private const int IconIndexGeneric = 6; // log / cache / lib / runtime
    private const int IconIndexScript = 8;  // script
    private const int IconIndexConfig = 0;  // config（图标库所在目录）

    private static readonly string ExeDir =
        Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;

    /// <summary>为全部标准目录套用对应颜色样式。失败仅记调试日志，绝不抛异常影响启动。</summary>
    public static void ApplyToStandardDirs()
    {
        try
        {
            Ensure(AppConfig.ConfigDir, IconIndexConfig);
            Ensure(AppConfig.LogDir, IconIndexGeneric);
            Ensure(AppConfig.CacheDir, IconIndexGeneric);
            Ensure(AppConfig.LibDir, IconIndexGeneric);
            Ensure(AppConfig.RuntimeDir, IconIndexGeneric);
            Ensure(AppConfig.ScriptDir, IconIndexScript);
        }
        catch (Exception ex)
        {
            Debug.WriteLine("FolderCustomizer.ApplyToStandardDirs 失败(可忽略): " + ex.Message);
        }
    }

    private static void Ensure(string dir, int iconIndex)
    {
        if (string.IsNullOrWhiteSpace(dir)) return;
        try
        {
            Directory.CreateDirectory(dir);
            WriteDesktopIni(dir, iconIndex);

            // 文件夹加 System 属性，使内部 desktop.ini 生效（仅置 System；不改 ReadOnly，避免影响子文件写入）。
            var dirAttr = File.GetAttributes(dir);
            if ((dirAttr & FileAttributes.System) == 0)
                File.SetAttributes(dir, dirAttr | FileAttributes.System);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"FolderCustomizer.Ensure({dir}) 失败(可忽略): " + ex.Message);
        }
    }

    private static void WriteDesktopIni(string dir, int iconIndex)
    {
        var iconLib = Path.Combine(ExeDir, "config", "fColors.icl");
        // 从目标目录指向 config\fColors.icl 的相对路径（config 自身得到 .\fColors.icl，兄弟目录得到 ..\config\fColors.icl）
        var rel = Path.GetRelativePath(dir, iconLib).Replace('/', '\\');

        var content = $"[.ShellClassInfo]\r\nIconFile={rel}\r\nIconIndex={iconIndex}\r\n";
        var iniPath = Path.Combine(dir, "desktop.ini");
        // 按字节写出 UTF-16 LE + BOM（与原始 desktop.ini 编码一致，资源管理器稳定识别）。
        // 不用 File.WriteAllText(encoding)：在部分运行时下该重载会写出空内容；显式带 BOM 的字节最稳妥。
        var enc = new UnicodeEncoding(false, true);
        var bytes = enc.GetPreamble().Concat(enc.GetBytes(content)).ToArray();
        File.WriteAllBytes(iniPath, bytes);
        // desktop.ini 需 Hidden+System 属性才会被资源管理器当作文件夹定制文件
        File.SetAttributes(iniPath, FileAttributes.Hidden | FileAttributes.System);
    }
}
