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
/// 资源（源码在 <c>assets/</c>，由 build.ps1 随构建复制到 exe 同级的 <c>config\</c> 并设为 Hidden——
/// 交付目录里不再额外留一个 <c>assets\</c>；隐藏后也不干扰用户查看 <c>config\config.ini</c>）：
/// <list type="bullet">
///   <item>fColors.icl 图标库 → exe 同级 <c>config\fColors.icl</c>（Hidden）</item>
///   <item>desktop.template0~11.ini 共 12 份模板 → exe 同级 <c>config\folder-icons\</c>（Hidden），
///         命名与 <c>F:\!config\templateN</c> 一一对应（template0 → desktop.template0.ini）</item>
/// </list>
/// 运行期：① 检查 <c>config\fColors.icl</c> 是否存在（缺失则文件夹变色不可用，但不影响启动）；
/// ② 按各标准目录的模板，把其中的占位符 <c>{{ICONLIB}}</c> 替换为指向 <c>config\fColors.icl</c> 的相对路径
/// （用 <see cref="Path.GetRelativePath"/> 动态计算，目录被用户改位置也能正确指向；同目录时补 <c>.\</c> 前缀，
/// 与 Windows 原生 desktop.ini 的写法一致），写出为该目录的 desktop.ini（UTF-16 LE+BOM + Hidden+System）。
/// </para>
/// <para>
/// 图标分配（按目录性质分三档，序号对应 fColors.icl 内图标序号）：
/// <list type="bullet">
///   <item>index 0（template0）—— <c>config</c>：程序自管的配置目录，图标库就放在这里</item>
///   <item>index 8（template8）—— <c>script</c>、<c>lib</c>：用户创建/维护脚本需要看护的目录</item>
///   <item>index 1（template1）—— <c>log</c>、<c>cache</c>、<c>runtime</c>：程序自动生成的系统目录</item>
/// </list>
/// 仅处理上述标准目录本身，<b>不递归子目录</b>（子目录不给图标）。
/// </para>
/// <para>任何异常均被吞掉并记调试日志，绝不影响主程序启动。</para>
/// </summary>
public static class FolderCustomizer
{
    // 图标序号：与 F:\!config 的 templateN 一一对应
    private const int IconIndexConfig = 0; // config（template0，图标库所在目录）
    private const int IconIndexUser = 8;   // script / lib（template8，用户维护的目录）
    private const int IconIndexSystem = 1; // log / cache / runtime（template1，系统自动生成目录）

    // 资源在 exe 同级 config\ 下的位置（由 build.ps1 从 assets/ 复制而来并设为 Hidden）
    private const string ResDir = "config";
    private const string FolderIconsRelDir = "config\\folder-icons";
    private const string IconLibName = "fColors.icl";
    private const string DesktopIniName = "desktop.ini";
    private const string IconLibPlaceholder = "{{ICONLIB}}";

    private static readonly string ExeDir =
        Path.GetDirectoryName(Environment.ProcessPath) ?? AppContext.BaseDirectory;
    private static readonly string IconLibPath = Path.Combine(ExeDir, ResDir, IconLibName);
    private static readonly string TemplatesDir = Path.Combine(ExeDir, FolderIconsRelDir);

    // 模板文件名统一为 desktop.template{N}.ini（N=0~11，与 F:\!config\templateN 对应）
    private static string TemplateFile(int iconIndex) => $"desktop.template{iconIndex}.ini";

    // 各标准目录 -> (目录, 图标序号, 悬浮说明 InfoTip)。仅标准目录本身，不含子目录。
    // 说明文字刻意区分"用户维护"与"程序生成"，让用户一眼知道哪些能改、哪些能删。
    private static readonly (string Dir, int Index, string Tip)[] StandardDirs =
    {
        (AppConfig.ConfigDir,   IconIndexConfig, "程序配置目录：config.ini 在这里，可编辑修改"),
        (AppConfig.LogDir,      IconIndexSystem, "运行日志目录：程序自动生成，可安全删除"),
        (AppConfig.CacheDir,    IconIndexSystem, "缓存目录：程序自动生成，可安全删除"),
        (AppConfig.RuntimeDir,  IconIndexSystem, "脚本运行时目录：程序自动生成，勿手动改动"),
        (AppConfig.LibDir,      IconIndexUser,   "依赖库目录：脚本运行所需依赖，按语言分子目录"),
        (AppConfig.ScriptDir,   IconIndexUser,   "脚本目录：你的脚本都在这里，可自由增删改"),
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
            EnsureIconLibHidden();
            foreach (var (dir, idx, tip) in StandardDirs)
                Ensure(dir, idx, tip);
        }
        catch (Exception ex)
        {
            Debug.WriteLine("FolderCustomizer.ApplyToStandardDirs 失败(可忽略): " + ex.Message);
        }
    }

    private static void Ensure(string dir, int iconIndex, string infoTip)
    {
        if (string.IsNullOrWhiteSpace(dir)) return;
        try
        {
            Directory.CreateDirectory(dir);
            WriteDesktopIni(dir, iconIndex, infoTip);

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

    private static void WriteDesktopIni(string dir, int iconIndex, string infoTip)
    {
        var iconLib = Path.Combine(ExeDir, ResDir, IconLibName);
        // 从目标目录指向 exe 同级 config\fColors.icl 的相对路径：
        // log/cache/runtime/lib/script 得到 ..\config\fColors.icl；config 自身为同目录，补 .\ 前缀得 .\fColors.icl
        var rel = Path.GetRelativePath(dir, iconLib).Replace('/', '\\');
        if (!rel.StartsWith(".")) rel = ".\\" + rel;

        var tplPath = Path.Combine(TemplatesDir, TemplateFile(iconIndex));
        string template;
        if (File.Exists(tplPath))
            template = ReadTemplateText(tplPath);
        else
            // 模板缺失时退化：用当前目录序号生成最小可用模板（含占位符，供下方替换）
            template = $"[.ShellClassInfo]\r\nIconFile={IconLibPlaceholder}\r\nIconIndex={iconIndex}\r\n";

        var content = template.Replace(IconLibPlaceholder, rel);
        // 悬浮说明（InfoTip）：按目录性质给提示，让用户一眼知道哪些能改、哪些能删。
        // 不写进模板，由代码按目录追加，以保持 12 份模板与 F:\!config\templateN 一一对应的纯粹性。
        if (!string.IsNullOrWhiteSpace(infoTip))
            content += "InfoTip=" + infoTip + "\r\n";

        var iniPath = Path.Combine(dir, DesktopIniName);
        // 按字节写出 UTF-16 LE + BOM（与原始 desktop.ini 编码一致，资源管理器稳定识别）。
        // 不用 File.WriteAllText(encoding)：在部分运行时下该重载会写出空内容；显式带 BOM 的字节最稳妥。
        var enc = new UnicodeEncoding(false, true);
        var bytes = enc.GetPreamble().Concat(enc.GetBytes(content)).ToArray();
        File.WriteAllBytes(iniPath, bytes);
        // desktop.ini 需 Hidden+System 属性才会被资源管理器当作文件夹定制文件
        File.SetAttributes(iniPath, FileAttributes.Hidden | FileAttributes.System);
    }

    // 确保 exe 同级 config\fColors.icl 带 Hidden 属性（不显眼地躺在 config\ 里；不加 System，避免影响引用/删除）
    private static void EnsureIconLibHidden()
    {
        try
        {
            var attr = File.GetAttributes(IconLibPath);
            if ((attr & FileAttributes.Hidden) == 0)
                File.SetAttributes(IconLibPath, attr | FileAttributes.Hidden);
        }
        catch (Exception ex)
        {
            Debug.WriteLine("FolderCustomizer 隐藏 fColors.icl 失败(可忽略): " + ex.Message);
        }
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
