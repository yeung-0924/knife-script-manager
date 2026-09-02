using System.IO;
using System.Text;

namespace ScriptManager;

/// <summary>
/// 文件编码探测辅助。
/// 脚本文件统一约定为 UTF-8（无 BOM）；读取源文件时先探测 BOM，
/// 兼容历史遗留的带 BOM / GBK / UTF-16 文件，探测不到时按 UTF-8 读取。
/// </summary>
public static class EncodingHelper
{
    /// <summary>
    /// 读取文件实际字符编码（探测 BOM；无 BOM 时回退 UTF-8 无 BOM）。
    /// </summary>
    public static Encoding DetectFromFile(string path)
    {
        try
        {
            using var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            var bom = new byte[3];
            var read = fs.Read(bom, 0, 3);
            if (read >= 3 && bom[0] == 0xEF && bom[1] == 0xBB && bom[2] == 0xBF)
                return new UTF8Encoding(true);
            if (read >= 2 && bom[0] == 0xFF && bom[1] == 0xFE)
                return new UnicodeEncoding(false, true); // UTF-16 LE BOM
            if (read >= 2 && bom[0] == 0xFE && bom[1] == 0xFF)
                return new UnicodeEncoding(true, true);  // UTF-16 BE BOM
            if (read >= 3 && bom[0] == 0x2B && bom[1] == 0x2F && bom[2] == 0x76)
                return new UTF8Encoding(true); // UTF-7 起始，罕见，按 BOM UTF-8 处理
        }
        catch
        {
            // 读取失败时回退默认
        }
        return new UTF8Encoding(false);
    }
}
