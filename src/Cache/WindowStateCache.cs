using System;
using System.Windows;

namespace ScriptManager.Cache;

/// <summary>
/// 窗口状态缓存：记住窗口的尺寸与状态（普通/最大化/全屏）。
/// 位置（Left/Top）不缓存——每次启动由 WindowStartupLocation 决定。
/// 数据持久化到 cache/window-state.json。
/// </summary>
public static class WindowStateCache
{
    private const string FileName = "window-state.json";

    private sealed class State
    {
        public double Width { get; set; }
        public double Height { get; set; }
        public int WindowState { get; set; }   // (int)System.Windows.WindowState
        public bool FullScreen { get; set; }
    }

    /// <summary>从窗口读取当前状态并写入缓存（关闭时调用）。位置不保存。</summary>
    public static void Save(Window window)
    {
        var bounds = window.RestoreBounds;
        var normal = bounds.IsEmpty
            ? new Rect(window.Left, window.Top, window.Width, window.Height)
            : bounds;

        var state = new State
        {
            Width = normal.Width,
            Height = normal.Height,
            WindowState = (int)window.WindowState,
            // 全屏特征：最大化且隐藏了边框/标题栏
            FullScreen = window.WindowState == WindowState.Maximized
                         && window.WindowStyle == WindowStyle.None
        };
        CacheStore.WriteJson(FileName, state);
    }

    /// <summary>
    /// 在窗口显示（Show）之前调用：若缓存为全屏/最大化，立即就位，避免先以普通尺寸闪一帧再切换。
    /// 普通状态在此不处理（尺寸交由 ApplyNormalSize 在 Loaded 时设置）。
    /// </summary>
    public static void ApplyPreShow(Window window)
    {
        var state = CacheStore.ReadJson<State>(FileName);
        if (state == null) return;

        if (state.FullScreen)
        {
            window.WindowStyle = WindowStyle.None;
            window.WindowState = WindowState.Maximized;
        }
        else if (state.WindowState == (int)WindowState.Maximized)
        {
            window.WindowState = WindowState.Maximized;
        }
        // 普通状态：留到 ApplyNormalSize 处理尺寸
    }

    /// <summary>
    /// 在 Loaded 时调用：仅当缓存为普通窗口时恢复尺寸（此时改尺寸不可见，不会闪）。
    /// </summary>
    public static void ApplyNormalSize(Window window)
    {
        var state = CacheStore.ReadJson<State>(FileName);
        if (state == null) return;

        if (state.WindowState == (int)WindowState.Normal)
        {
            if (state.Width >= window.MinWidth && state.Height >= window.MinHeight)
            {
                window.Width = state.Width;
                window.Height = state.Height;
            }
        }
        // 最小化不恢复（避免启动即缩任务栏），保持当前（普通）状态
    }
}
