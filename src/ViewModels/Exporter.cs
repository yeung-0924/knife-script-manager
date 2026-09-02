using System.Diagnostics;
using System.IO;
using System.IO.Compression;

namespace ScriptManager.ViewModels;

/// <summary>
/// 导出辅助：将脚本目录（script）整体打包为 script_yyyyMMddHHmmss.zip。
/// zip 内根目录为 script/...（与发布目录结构一致），便于分发脚本。
/// </summary>
public static class Exporter
{
    /// <summary>
    /// 将脚本目录整体打包为 destRoot/script_yyyyMMddHHmmss.zip。
    /// 成功时 zipPath 为生成的压缩包完整路径；失败返回 false，error 说明具体原因。
    /// </summary>
    public static bool ExportToZip(string? scriptDir, string destRoot, out string? zipPath, out string? error)
    {
        zipPath = null;
        error = null;
        try
        {
            if (!Directory.Exists(scriptDir))
            {
                error = string.Format(Strings.StatusExportSourceMissingFormat, scriptDir);
                return false;
            }

            var srcFull = Path.GetFullPath(scriptDir);
            var destFull = Path.GetFullPath(destRoot);

            // 防止把 zip 写进源目录自身（zip 会混入源、下次导出被递归打包）：
            // OpenFolderDialog 默认停在 ExeDir，若选中 script/ 本身或其子目录则拒绝。
            if (string.Equals(destFull, srcFull, StringComparison.OrdinalIgnoreCase)
                || destFull.StartsWith(srcFull + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
            {
                error = Strings.StatusExportSameDir;
                return false;
            }

            Directory.CreateDirectory(destRoot);
            zipPath = Path.Combine(destRoot, $"script_{DateTime.Now:yyyyMMddHHmmss}.zip");

            var files = Directory.GetFiles(scriptDir, "*", SearchOption.AllDirectories);
            if (files.Length == 0)
            {
                error = Strings.StatusExportEmpty;
                return false;
            }

            using (var zip = ZipFile.Open(zipPath, ZipArchiveMode.Create))
            {
                foreach (var file in files)
                {
                    var rel = Path.GetRelativePath(scriptDir, file);
                    // zip 内统一用 / 分隔符，且带 script/ 根目录前缀
                    var entryName = Path.Combine("script", rel).Replace('\\', '/');
                    zip.CreateEntryFromFile(file, entryName);
                }
            }
            return true;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[Exporter] 导出失败：{ex.Message}");
            error = ex.Message;
            return false;
        }
    }
}
