using System;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace ScriptManager;

/// <summary>
/// 文件夹变色（desktop.ini + fColors.icl）。
/// <para>
/// 机制：Windows 资源管理器在文件夹含 <c>desktop.ini</c>（且文件夹带 System 属性、desktop.ini 带 Hidden+System）时，
/// 会按 desktop.ini 的 <c>IconFile</c>/<c>IconIndex</c> 显示该文件夹图标。
/// </para>
/// <para>
/// 资源（保留在源码 <c>assets/</c> 目录，由 build.ps1 随构建复制到 exe 同级的 <c>assets\</c>，
/// <b>不进 config\ 用户可编辑区</b>——fColors.icl 不是给用户改的文件，放程序侧的 assets\ 最干净）：
/// <list type="bullet">
///   <item>fColors.icl 图标库 → exe 同级 <c>assets\fColors.icl</c></item>
///   <item>三份 desktop.ini 模板（config/index0、generic/index6、script/index8）→ exe 同级 <c>assets\folder-icons\</c></item>
/// </list>
/// 运行期：① 检查 <c>assets\fColors.icl</c> 是否存在（缺失则文件夹变色不可用，但不影响启动）；
/// ② 按各标准目录的模板，把其中的占位符 <c>{{ICONLIB}}</c> 替换为指向 <c>assets\fColors.icl</c> 的相对路径
/// （用 <see cref="Path.GetRelativePath"/> 动态计算，目录被用户改位置也能正确指向），写出为该目录的 desktop.ini
/// （UTF-16 LE+BOM + Hidden+System）。
/// 图标序号对齐 F:\!config：template6=6（通用系统目录）、template8=8（script 目录）、顶层=0（config 目录自身）。
/// </para>
/// <para>任何异常均被吞掉并记调试日志，绝不影响主程序启动。</para>
/// </summary>
public static class FolderCustomizer
{
    // 图标序号：与 F:\!config 的 template6(6) / template8(8) / 顶层 config(0) 对应
    private const int IconIndexGeneric = 6; // log / cache / lib / runtime
    private const int IconIndexScript = 8;  // script
    private const int IconIndexConfig = 0;  // config（图标库所在目录）

    // 资源在 exe 同级的位置（由 build.ps1 从 assets/ 复制而来，非用户可编辑区）
    private const string AssetsRelDir = "assets";
    private const string FolderIconsRelDir = "assets\\folder-icons";
    private const string IconLibName = "fColors.icl";
    private const string DesktopIniName = "desktop.ini";
    private const string IconLibPlaceholder = "{{ICONLIB}}";

    private static readonly string ExeDir =
        Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;
    private static readonly string IconLibPath = Path.Combine(ExeDir, AssetsRelDir, IconLibName);
    private static readonly string TemplatesDir = Path.Combine(ExeDir, FolderIconsRelDir);

    // 各标准目录 -> (目录, 模板文件名, 图标序号)
    private static readonly (string Dir, string TplFile, int Index)[] StandardDirs =
    {
        (AppConfig.ConfigDir,  "desktop.config.ini",   IconIndexConfig),
        (AppConfig.LogDir,     "desktop.template6.ini", IconIndexGeneric),
        (AppConfig.CacheDir,   "desktop.template6.ini", IconIndexGeneric),
        (AppConfig.LibDir,     "desktop.template6.ini", IconIndexGeneric),
        (AppConfig.RuntimeDir, "desktop.template6.ini", IconIndexGeneric),
        (AppConfig.ScriptDir,  "desktop.template8.ini", IconIndexScript),
    };

    /// <summary>为全部标准目录套用对应颜色样式。失败仅记调试日志，绝不抛异常影响启动。</summary>
    public static void ApplyToStandardDirs()
    {
        try
        {
            if (!File.Exists(IconLibPath))
            {
                Debug.WriteLine("FolderCustomizer: 未找到 " + IconLibPath + "，文件夹变色功能不可用（可忽略）");
                return;
            }
            foreach (var (dir, tpl, idx) in StandardDirs)
                Ensure(dir, tpl, idx);
        }
        catch (Exception ex)
        {
            Debug.WriteLine("FolderCustomizer.ApplyToStandardDirs 失败(可忽略): " + ex.Message);
        }
    }

    private static void Ensure(string dir, string tplFile, int iconIndex)
    {
        if (string.IsNullOrWhiteSpace(dir)) return;
        try
        {
            Directory.CreateDirectory(dir);
            WriteDesktopIni(dir, tplFile, iconIndex);

            // 文件夹加 System 属性，使内部 desktop.ini 生效（仅置 System；不改 ReadOnly，避免影响子文件写入）
            var dirAttr = File.GetAttributes(dir);
            if ((dirAttr & FileAttributes.System) == 0)
                File.SetAttributes(dir, dirAttr | FileAttributes.System);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"FolderCustomizer.Ensure({dir}) 失败(可忽略): " + ex.Message);
        }
    }

    private static void WriteDesktopIni(string dir, string tplFile, int iconIndex)
    {
        var iconLib = Path.Combine(ExeDir, AssetsRelDir, IconLibName);
        // 从目标目录指向 exe 同级 assets\fColors.icl 的相对路径（标准目录均为 exe 的下一级，故得到 ..\assets\fColors.icl）
        var rel = Path.GetRelativePath(dir, iconLib).Replace('/', '\\');

        var tplPath = Path.Combine(TemplatesDir, tplFile);
        string template;
        if (File.Exists(tplPath))
            template = ReadTemplateText(tplPath);
        else
            // 模板缺失时退化：用当前目录序号生成最小可用模板（含占位符，供下方替换）
            template = $"[.ShellClassInfo]\r\nIconFile={IconLibPlaceholder}\r\nIconIndex={iconIndex}\r\n";

        var content = template.Replace(IconLibPlaceholder, rel);

        var iniPath = Path.Combine(dir, DesktopIniName);
        // 按字节写出 UTF-16 LE + BOM（与原始 desktop.ini 编码一致，资源管理器稳定识别）。
        // 不用 File.WriteAllText(encoding)：在部分运行时下该重载会写出空内容；显式带 BOM 的字节最稳妥。
        var enc = new UnicodeEncoding(false, true);
        var bytes = enc.GetPreamble().Concat(enc.GetBytes(content)).ToArray();
        File.WriteAllBytes(iniPath, bytes);
        // desktop.ini 需 Hidden+System 属性才会被资源管理器当作文件夹定制文件
        File.SetAttributes(iniPath, FileAttributes.Hidden | FileAttributes.System);
    }

    // 容错读取模板：优先按 UTF-8（模板统一为 UTF-8 无 BOM）；若带 UTF-16 BOM 则按对应编码解码，
    // 避免“UTF-16 文件被当 UTF-8 读出乱码、占位符替换失败”的坑。
    private static string ReadTemplateText(string path)
    {
        var bytes = File.ReadAllBytes(path);
        if (bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE)
            return Encoding.Unicode.GetString(bytes, 2, bytes.Length - 2);
        if (bytes.Length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF)
            return Encoding.BigEndianUnicode.GetString(bytes, 2, bytes.Length - 2);
        return Encoding.UTF8.GetString(bytes);
    }
}
