using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows;

namespace ScriptManager;

/// <summary>
/// WPF 应用入口（替代原 WinForms 的 Program.cs）。
/// 启动前的运行时自动检测保留在 MainViewModel 构造中完成。
/// </summary>
public partial class App : Application
{
    // 静态构造函数先于任何 XAML/实例初始化执行，确保最早期就能捕获启动崩溃
    static App()
    {
        var logDir = AppConfig.LogDir;
        Directory.CreateDirectory(logDir); // 配置的日志目录可能不存在（含 UNC），确保可写
        // 为各标准目录套用彩色文件夹样式（desktop.ini + System 属性）。放在最早期，不受后续 UI 初始化成败影响。
        FolderCustomizer.ApplyToStandardDirs();

        // 错误日志路径每次现算：log_dir 配置改动后无需重启，下一次异常即写入新目录。
        void Write(string kind, Exception? ex)
        {
            try
            {
                var logPath = Path.Combine(AppConfig.LogDir, "error.log");
                var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {kind}\n{ex}\n";
                File.AppendAllText(logPath, line, System.Text.Encoding.UTF8);
            }
            catch { }
        }

        // 非 UI 线程（包括其他线程、终结器）未处理异常
        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            Write($"UnhandledException ({(args.IsTerminating ? "Terminating" : "NonTerminating")})",
                args.ExceptionObject as Exception);

        // UI 线程（Dispatcher）未处理异常
        // 注意：在静态构造函数阶段 DispatcherUnhandledException 事件尚未可订阅，
        // 实际订阅放到 OnStartup 中；此处仅记录 AppDomain 级异常。
        TaskScheduler.UnobservedTaskException += (_, args) =>
            Write("UnobservedTaskException", args.Exception);
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // 错误日志目录确保存在（log_dir 可能指向 UNC）；路径每次现算，配置改动后无需重启即生效。
        Directory.CreateDirectory(AppConfig.LogDir);

        DispatcherUnhandledException += (_, args) =>
        {
            try
            {
                var logPath = Path.Combine(AppConfig.LogDir, "error.log");
                var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] DispatcherUnhandledException\n{args.Exception}\n";
                File.AppendAllText(logPath, line, System.Text.Encoding.UTF8);
            }
            catch { }
            // 不吞掉异常：保持原有崩溃行为，仅额外记录到 error.log
            args.Handled = false;
        };
    }
}
