using System.Collections.Generic;
using System.Linq;

namespace ScriptManager.Cache;

/// <summary>
/// 目录树展开状态缓存：记住哪些容器节点（来源根/分组）是展开的。
/// 数据持久化到 cache/tree-state.json，保存的是「展开节点的稳定 Path 集合」。
/// 叶子（脚本项）不参与。
/// </summary>
public static class TreeStateCache
{
    private const string FileName = "tree-state.json";

    /// <summary>保存当前展开的容器节点 Path 集合。</summary>
    public static void Save(IEnumerable<string> expandedPaths)
    {
        CacheStore.WriteJson(FileName, expandedPaths.ToList());
    }

    /// <summary>
    /// 读取展开的 Path 集合。返回 null 表示无缓存（调用方应默认全部收起）。
    /// </summary>
    public static HashSet<string>? LoadExpanded()
    {
        var list = CacheStore.ReadJson<List<string>>(FileName);
        if (list == null) return null;
        return new HashSet<string>(list);
    }
}
