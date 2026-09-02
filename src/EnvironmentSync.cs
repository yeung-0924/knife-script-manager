using System;
using System.Collections.Generic;
using Microsoft.Win32;

namespace ScriptManager;

/// <summary>
/// 环境变量同步：从注册表（Machine + User）重新加载环境变量到当前进程。
/// 进程启动时会从父进程继承一份环境变量快照且运行期不再更新——安装脚本（如 Install-Java.ps1）
/// 写入注册表的新值，工具必须重启才能看到。本类解决该问题：显式从注册表重读并覆盖进程环境，
/// 使「安装完 JDK 后无需重启工具，点刷新或直接运行即生效」。
/// 合并语义与 Windows 一致：
///   - Path = Machine + ";" + User（去重，Machine 在前，与系统拼接顺序一致）
///   - 其余变量：User 优先、Machine 补缺（同名时 User 覆盖 Machine）
/// </summary>
public static class EnvironmentSync
{
    private const string MachineKeyPath = @"SYSTEM\CurrentControlSet\Control\Session Manager\Environment";
    private const string UserKeyPath = @"Environment";

    /// <summary>从注册表重新加载全部环境变量到当前进程。任一步失败均静默忽略，保持进程原环境。</summary>
    public static void RefreshProcessEnvironment()
    {
        try
        {
            // 先 Machine 后 User：非 Path 变量按「User 覆盖 Machine」合并（与 Windows 行为一致）
            foreach (var name in ReadValueNames(EnvironmentVariableTarget.Machine))
                ApplyNonPath(name, EnvironmentVariableTarget.Machine);
            foreach (var name in ReadValueNames(EnvironmentVariableTarget.User))
                ApplyNonPath(name, EnvironmentVariableTarget.User);

            // Path 特殊处理：Machine + ";" + User 去重（Machine 在前）
            var machinePath = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.Machine) ?? "";
            var userPath = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? "";
            Environment.SetEnvironmentVariable("Path", MergePath(machinePath, userPath));
        }
        catch
        {
            // 刷新失败保持进程现状，不影响工具使用
        }
    }

    private static void ApplyNonPath(string name, EnvironmentVariableTarget target)
    {
        if (string.Equals(name, "Path", StringComparison.OrdinalIgnoreCase)) return;
        // GetEnvironmentVariable(name, target) 会展开 REG_EXPAND_SZ（如 %SCRIPT_MANAGER_ENV% → 实际路径）
        var value = Environment.GetEnvironmentVariable(name, target);
        if (value != null)
            Environment.SetEnvironmentVariable(name, value);
    }

    private static string MergePath(string machine, string user)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var parts = new List<string>();
        foreach (var p in (machine + ";" + user).Split(';'))
        {
            if (string.IsNullOrWhiteSpace(p)) continue;
            if (seen.Add(p)) parts.Add(p);
        }
        return string.Join(";", parts);
    }

    private static List<string> ReadValueNames(EnvironmentVariableTarget target)
    {
        var result = new List<string>();
        try
        {
            using var key = target == EnvironmentVariableTarget.Machine
                ? Registry.LocalMachine.OpenSubKey(MachineKeyPath)
                : Registry.CurrentUser.OpenSubKey(UserKeyPath);
            if (key != null) result.AddRange(key.GetValueNames());
        }
        catch
        {
            // 注册表不可读（权限等）时返回空集，上层已有整体保护
        }
        return result;
    }
}
