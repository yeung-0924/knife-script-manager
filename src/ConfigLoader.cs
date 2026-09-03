using System.Diagnostics;
using System.IO;
using System.Text.Json;

namespace ScriptManager;

/// <summary>
/// 负责定位脚本目录、读取并校验脚本索引 json（顶层为数组）。
/// 默认脚本索引文件由 exe 同级的 config/config.ini 的 [script] default_script_file 配置（默认 script\index.json），
/// 用户可通过「打开」按钮加载其它位置的 index.json（持久化到 user_script_file）；找不到则不加载目录树。
/// 脚本来源为单一目录，随 exe 分发、用户可编辑，不再内置进 exe。
/// </summary>
public static class ConfigLoader
{
    /// <summary>脚本索引 json 的完整路径 = 脚本目录下的 index.json（来自配置，默认 exe 同级 script/index.json）。</summary>
    public static readonly string ScriptIndexJson = AppConfig.ScriptIndexJsonPath;

    /// <summary>脚本所在目录（由 default_script_file 推导，用于解析脚本相对路径与导出）。</summary>
    public static readonly string ScriptDir = AppConfig.ScriptDir;

    /// <summary>加载指定索引 json 路径的脚本列表，供 MVVM 构建树节点（文件不存在时返回空）。</summary>
    public static List<ScriptItem> LoadIndex(string indexPath)
    {
        var result = new List<ScriptItem>();
        var warnings = new List<string>();
        if (!File.Exists(indexPath))
            return result;
        LoadIndex(indexPath, result, warnings);
        return result;
    }

    /// <summary>
    /// 加载单个脚本索引 json，递归处理嵌套结构，过滤后写入 result，问题记入 warnings。
    /// 目录节点（有 children）递归处理；脚本节点解析路径并校验文件存在。
    /// 处理后若目录内已无有效节点，该目录整体剔除，避免出现空分组。
    /// </summary>
    private static void LoadIndex(string indexPath, List<ScriptItem> result, List<string> warnings)
    {
        if (!File.Exists(indexPath))
        {
            warnings.Add($"未找到配置文件：{indexPath}\n请检查 config/config.ini 的 [script] json 设置。");
            return;
        }

        try
        {
            var dir = Path.GetDirectoryName(indexPath) ?? AppContext.BaseDirectory;
            var json = File.ReadAllText(indexPath);
            var raw = JsonSerializer.Deserialize<List<ScriptItem>>(json, new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true
            }) ?? new List<ScriptItem>();

            var visiting = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            visiting.Add(Path.GetFullPath(indexPath));

            foreach (var node in raw)
            {
                var processed = ProcessNode(node, dir, visiting, warnings);
                if (processed != null)
                    result.Add(processed);
            }
        }
        catch (Exception ex)
        {
            warnings.Add($"解析 {indexPath} 失败：{ex.Message}");
        }
    }

    /// <summary>
    /// 处理单个索引节点：返回处理后的节点，无效则返回 null（调用方据此剔除）。
    /// 目录节点先展开 include 并递归处理子节点；脚本节点解析并校验脚本文件。
    /// </summary>
    private static ScriptItem? ProcessNode(ScriptItem node, string dir, HashSet<string> visiting, List<string> warnings)
    {
        // 先展开 include（被引文件内容原地追加为当前节点的子节点）。
        // include 可出现在任意层级（顶层或子孙），被引文件内的 path / 嵌套 include
        // 一律相对【被引文件自身所在目录】，使其自洽。
        var hasInclude = !string.IsNullOrWhiteSpace(node.Include) || node.Includes != null;
        if (hasInclude)
        {
            var included = ResolveIncludes(node, dir, visiting, warnings);
            warnings.Add($"[include 诊断] 节点「{node.Name}」共解析到 {included.Count} 个子节点。");
            if (included.Count > 0)
            {
                node.Children ??= new List<ScriptItem>();
                node.Children.AddRange(included);
            }

            // 已展开过 include，清空标记防止递归处理子节点时再次展开同一文件
            node.Include = null;
            node.Includes = null;
        }

        // 目录节点：递归处理子节点，剔除无效的；子节点全空则整个目录不显示
        if (node.IsGroup)
        {
            var kept = new List<ScriptItem>();
            foreach (var child in node.Children!)
            {
                // 被 include 进来的子节点用其自身所在目录基准，否则用父级 dir
                var childDir = child.BaseDir ?? dir;
                var processed = ProcessNode(child, childDir, visiting, warnings);
                if (processed != null)
                    kept.Add(processed);
            }

            if (kept.Count == 0)
            {
                warnings.Add($"目录内无有效脚本，已跳过：{node.Name}");
                return null;
            }

            node.Children = kept;
            return node;
        }

        // 脚本节点：校验路径并解析
        if (string.IsNullOrWhiteSpace(node.Path))
        {
            warnings.Add($"节点缺少 path，已跳过：{node.Name}");
            return null;
        }

        // 解析路径（去 ./ 前缀）
        var rel = node.Path.Replace("/", "\\").TrimStart('.', '\\', '/');
        node.ResolvedPath = Path.Combine(dir, rel);

        if (!File.Exists(node.ResolvedPath))
        {
            warnings.Add($"脚本文件不存在，已跳过：{node.Name} -> {node.Path}");
            return null;
        }

        return node;
    }

    /// <summary>
    /// 解析节点的 include 字段：可接受单个字符串或字符串数组（JsonElement 形态）。
    /// 对每个被引文件，读取并解析为 ScriptItem 列表，递归展平其嵌套 include，
    /// 且所有被引内容以【被引文件所在目录】为基准（path / 嵌套 include 相对该目录）。
    /// 防循环：同一绝对路径已在处理栈中则跳过并产生告警，避免 A↔B 互相引用死循环。
    /// 被引文件支持三种形态：① 顶层数组；② 单个目录节点对象；③ { "children": [...] } 聚合。
    /// </summary>
    private static List<ScriptItem> ResolveIncludes(ScriptItem node, string baseDir,
        HashSet<string> visiting, List<string> warnings)
    {
        var files = new List<string>();
        if (!string.IsNullOrWhiteSpace(node.Include)) files.Add(node.Include!);
        if (node.Includes != null) files.AddRange(node.Includes.Where(f => !string.IsNullOrWhiteSpace(f)));

        var result = new List<ScriptItem>();
        foreach (var rel in files)
        {
            var abs = Path.GetFullPath(Path.Combine(baseDir, rel.Replace("/", "\\").TrimStart('.', '\\', '/')));
            if (!File.Exists(abs))
            {
                warnings.Add($"include 引用的文件不存在，已跳过：{rel}");
                continue;
            }
            if (!visiting.Add(abs))
            {
                warnings.Add($"检测到循环 include（已跳过）：{abs}");
                continue;
            }

            try
            {
                var incDir = Path.GetDirectoryName(abs) ?? AppContext.BaseDirectory;
                var incJson = File.ReadAllText(abs);
                var doc = JsonSerializer.Deserialize<JsonElement>(incJson);

                List<ScriptItem> parsed;
                if (doc.ValueKind == System.Text.Json.JsonValueKind.Array)
                {
                    parsed = JsonSerializer.Deserialize<List<ScriptItem>>(incJson,
                        new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
                        ?? new List<ScriptItem>();
                }
                else if (doc.ValueKind == System.Text.Json.JsonValueKind.Object)
                {
                    // 形态 ②：单个目录节点对象，直接用
                    var single = JsonSerializer.Deserialize<ScriptItem>(incJson,
                        new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                    parsed = single != null ? new List<ScriptItem> { single } : new List<ScriptItem>();
                }
                else
                {
                    parsed = new List<ScriptItem>();
                }

                foreach (var incNode in parsed)
                {
                    // 设 BaseDir 为该被引文件目录，使其内 path / 嵌套 include 相对自身；
                    // 不在此处 ProcessNode，改由外层 group 递归统一处理（避免双重处理与 dir 错乱）。
                    // 先递归展开其内部的 include（用 incDir 基准），再交回外层。
                    incNode.BaseDir = incDir;
                    if (!string.IsNullOrWhiteSpace(incNode.Include) || incNode.Includes != null)
                    {
                        var nested = ResolveIncludes(incNode, incDir, visiting, warnings);
                        if (nested.Count > 0)
                        {
                            incNode.Children ??= new List<ScriptItem>();
                            incNode.Children.AddRange(nested);
                        }
                        // 已在此展开 include，清空标记防止外层 group 递归时再次展开同一文件而重复
                        incNode.Include = null;
                        incNode.Includes = null;
                    }
                    result.Add(incNode);
                }
            }
            catch (Exception ex)
            {
                warnings.Add($"解析 include 文件失败，已跳过：{abs} -> {ex.Message}");
            }
            finally
            {
                visiting.Remove(abs); // 允许其它分支再次引用同一文件
            }
        }

        return result;
    }
}
