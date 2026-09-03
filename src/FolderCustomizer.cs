using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Text.RegularExpressions;

namespace ScriptManager;

/// <summary>
/// 文件夹变色（desktop.ini + fColors.icl）。
/// <para>
/// 机制：Windows 资源管理器在文件夹含 <c>desktop.ini</c>（且文件夹带 System 属性、desktop.ini 带 Hidden+System）时，
/// 会按 desktop.ini 的 <c>IconFile</c>/<c>IconIndex</c> 显示该文件夹图标。
/// </para>
/// <para>
/// 资源（全部内嵌进 exe，<b>不落盘到用户可编辑的 config\ 目录</b>——fColors.icl 不是给用户改的文件，内嵌最干净）：
/// <list type="bullet">
///   <item>fColors.icl 图标库 → 内嵌资源 <c>assets.fColors.icl</c></item>
///   <item>三份 desktop.ini 模板（config/index0、generic/index6、script/index8）→ 内嵌资源 <c>assets.folder-icons.desktop.*.ini</c></item>
/// </list>
/// 运行期：① 先把 fColors.icl 从程序集解压到 exe 同级 <c>ExeDir\fColors.icl</c>（shell 的 IconFile 必须指向真实磁盘文件，
/// 故无法纯内嵌、必须落一个真实文件，但放 exe 同级而非 config\，对用户不可见、不可编辑）；
/// ② 按各标准目录的桌面.ini 模板，正则替换其中的 <c>IconFile=...</c> 为指向 <c>ExeDir\fColors.icl</c> 的相对路径
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

    // 内嵌资源名（与 src/ScriptManager.csproj 的 LogicalName 对应）
    private const string ResIconLib    = "assets.fColors.icl";
    private const string ResTplConfig  = "assets.folder-icons.desktop.config.ini";
    private const string ResTplGeneric = "assets.folder-icons.desktop.template6.ini";
    private const string ResTplScript  = "assets.folder-icons.desktop.template8.ini";

    private const string IconLibFileName = "fColors.icl"; // 解压到 exe 同级的文件名
    private const string DesktopIniName  = "desktop.ini";

    private static readonly string ExeDir =
        Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;

    // 替换模板里 IconFile= 后的路径（保留前缀，仅替换路径部分）
    private static readonly Regex IconFileRegex = new Regex(@"IconFile=[^\r\n]*", RegexOptions.Compiled);

    /// <summary>为全部标准目录套用对应颜色样式。失败仅记调试日志，绝不抛异常影响启动。</summary>
    public static void ApplyToStandardDirs()
    {
        try
        {
            EnsureIconLibExtracted();

            Ensure(AppConfig.ConfigDir, ResTplConfig, IconIndexConfig);
            Ensure(AppConfig.LogDir, ResTplGeneric, IconIndexGeneric);
            Ensure(AppConfig.CacheDir, ResTplGeneric, IconIndexGeneric);
            Ensure(AppConfig.LibDir, ResTplGeneric, IconIndexGeneric);
            Ensure(AppConfig.RuntimeDir, ResTplGeneric, IconIndexGeneric);
            Ensure(AppConfig.ScriptDir, ResTplScript, IconIndexScript);
        }
        catch (Exception ex)
        {
            Debug.WriteLine("FolderCustomizer.ApplyToStandardDirs 失败(可忽略): " + ex.Message);
        }
    }

    // 把内嵌的 fColors.icl 解压到 exe 同级；已存在且大小一致则跳过，避免每次启动重写
    private static void EnsureIconLibExtracted()
    {
        var dest = Path.Combine(ExeDir, IconLibFileName);
        try
        {
            using var src = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResIconLib);
            if (src == null) return; // 资源缺失：文件夹变色不可用，但不影响启动
            if (File.Exists(dest) && new FileInfo(dest).Length == src.Length) return;
            using var outStream = File.Create(dest);
            src.CopyTo(outStream);
        }
        catch (Exception ex)
        {
            Debug.WriteLine("FolderCustomizer 解压 fColors.icl 失败(可忽略): " + ex.Message);
        }
    }

    private static void Ensure(string dir, string tplResName, int iconIndex)
    {
        if (string.IsNullOrWhiteSpace(dir)) return;
        try
        {
            Directory.CreateDirectory(dir);
            WriteDesktopIni(dir, tplResName, iconIndex);

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

    private static void WriteDesktopIni(string dir, string tplResName, int iconIndex)
    {
        var iconLib = Path.Combine(ExeDir, IconLibFileName);
        // 从目标目录指向 exe 同级 fColors.icl 的相对路径（标准目录均为 exe 的下一级，故得到 ..\fColors.icl）
        var rel = Path.GetRelativePath(dir, iconLib).Replace('/', '\\');

        var template = ReadEmbeddedText(tplResName);
        // 模板缺失时退化：用当前目录序号生成最小可用模板（含 IconFile= 供正则替换）
        if (string.IsNullOrEmpty(template))
            template = $"[.ShellClassInfo]\r\nIconFile=__ICONLIB__\r\nIconIndex={iconIndex}\r\n";

        var content = IconFileRegex.Replace(template, $"IconFile={rel}");

        var iniPath = Path.Combine(dir, DesktopIniName);
        // 按字节写出 UTF-16 LE + BOM（与原始 desktop.ini 编码一致，资源管理器稳定识别）。
        // 不用 File.WriteAllText(encoding)：在部分运行时下该重载会写出空内容；显式带 BOM 的字节最稳妥。
        var enc = new UnicodeEncoding(false, true);
        var bytes = enc.GetPreamble().Concat(enc.GetBytes(content)).ToArray();
        File.WriteAllBytes(iniPath, bytes);
        // desktop.ini 需 Hidden+System 属性才会被资源管理器当作文件夹定制文件
        File.SetAttributes(iniPath, FileAttributes.Hidden | FileAttributes.System);
    }

    // 读取内嵌文本资源（模板为 UTF-16 LE + BOM，用 Unicode 解码会自动吃掉 BOM）
    private static string ReadEmbeddedText(string resName)
    {
        try
        {
            using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(resName);
            if (stream == null) return string.Empty;
            using var reader = new StreamReader(stream, Encoding.Unicode);
            return reader.ReadToEnd();
        }
        catch
        {
            return string.Empty;
        }
    }
}
