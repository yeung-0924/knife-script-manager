using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace ScriptManager;

/// <summary>
/// 按 lang 解析出对应的 <see cref="ProcessStartInfo"/>：FileName = 用户配置的 runtime 路径，Arguments 按语言模板拼装。
/// </summary>
public static class RuntimeResolver
{
    /// <summary>取某个 lang 的进程启动参数；lang 未配置或文件不存在时返回 null（调用方应禁用执行按钮）。</summary>
    /// <param name="injectedVars">
    /// cmd 专用：由 <see cref="CmdScriptRewriter"/> 抽取出的中文片段（占位符 → 真值），注入进程环境块。
    /// 仅对 UseShellExecute=false 生效；提权路径请改用 <see cref="BuildSetLines"/> 写进临时 bat。
    /// </param>
    public static ProcessStartInfo? Build(string lang, string scriptPath, string args, string workingDir, IReadOnlyDictionary<string, string>? injectedVars = null)
    {
        var runtime = RuntimeConfig.Get(lang);
        if (string.IsNullOrWhiteSpace(runtime) || !File.Exists(runtime))
            return null;

        // cmd 模板需要 chcp 65001 防乱码，其他语言不串行包一层 shell
        var (fileName, arguments) = (lang ?? string.Empty).ToLowerInvariant() switch
        {
            ScriptLangs.PowerShell => (runtime, $"-NoProfile -ExecutionPolicy Bypass -Command \"$enc=[System.Text.UTF8Encoding]::new($false);[Console]::OutputEncoding=$enc;[Console]::InputEncoding=$enc;& \\\"{scriptPath}\\\"{args};exit $LASTEXITCODE\""),
            ScriptLangs.Cmd        => (runtime, $"/d /c \"chcp 65001 >nul && \"\"{scriptPath}\"\"{args}\""),
            ScriptLangs.Python     => (runtime, $"\"{scriptPath}\"{args}"),
            ScriptLangs.Java       => BuildJavaArgs(runtime, scriptPath, args),
            ScriptLangs.Bash       => (runtime, $"\"{scriptPath}\"{args}"),
            ScriptLangs.Node       => (runtime, $"\"{scriptPath}\"{args}"),
            ScriptLangs.Go         => (runtime, $"run \"{scriptPath}\"{args}"),
            // pwsh（PowerShell 7）与 powershell 参数模板完全一致：
            // 均需 -ExecutionPolicy Bypass 绕过默认 Restricted，并在 -Command 内先切 UTF-8 再 dot-source 脚本。
            ScriptLangs.Pwsh       => (runtime, $"-NoProfile -ExecutionPolicy Bypass -Command \"$enc=[System.Text.UTF8Encoding]::new($false);[Console]::OutputEncoding=$enc;[Console]::InputEncoding=$enc;& \\\"{scriptPath}\\\"{args};exit $LASTEXITCODE\""),
            // Rust 是编译型语言：脚本文件在调用前已由 MainViewModel 用 rustc 预编译为临时 exe，
            // 此处 scriptPath 即编译产物 exe，FileName 用 scriptPath 直接执行（runtime 仅作存在性校验用）。
            ScriptLangs.Rust       => BuildRustArgs(runtime, scriptPath, args),
            _                      => (runtime, $"\"{scriptPath}\"{args}")
        };

        var startInfo = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            WorkingDirectory = workingDir,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        SetEncodingEnvironment(startInfo, lang);
        SetInjectedVariables(startInfo, injectedVars);
        foreach (var kv in ScriptEnvironmentVariables())
            startInfo.EnvironmentVariables[kv.Key] = kv.Value;
        return startInfo;
    }

    /// <summary>
    /// 脚本可见的环境变量（脚本管理器提供的目录信息），是进程注入与提权 set 行的<b>唯一来源</b>：
    /// <list type="bullet">
    /// <item>SCRIPT_MANAGER_LIB：第三方依赖目录（配置项 lib_dir，默认 exe 同级 lib），
    /// 例如 Java 脚本：<c>java -cp "%SCRIPT_MANAGER_LIB%\xxx.jar" Script.java</c></item>
    /// <item>SCRIPT_MANAGER_RUNTIME：运行时安装目录（配置项 runtime_dir，默认 exe 同级 runtime），
    /// 安装类脚本（Install-*.ps1）在未指定安装目录时以此为默认目标</item>
    /// </list>
    /// 值为绝对路径，脚本无需也不应依赖进程工作目录（提权时工作目录会被 ShellExecute 强制改为 System32）。
    /// </summary>
    public static IEnumerable<KeyValuePair<string, string>> ScriptEnvironmentVariables()
    {
        yield return new KeyValuePair<string, string>("SCRIPT_MANAGER_LIB", AppConfig.LibDir);
        yield return new KeyValuePair<string, string>("SCRIPT_MANAGER_RUNTIME", AppConfig.RuntimeDir);
    }

    /// <summary>
    /// 生成脚本可见环境变量的 set 命令行，供提权路径（UseShellExecute=true）写进临时 .bat。
    /// 提权走 ShellExecute，.NET 无法传递进程环境块（ShellExecute 不支持 lpEnvironment），只能退回 bat 内 set；
    /// 若不做这一步，提权脚本将拿不到 SCRIPT_MANAGER_LIB / SCRIPT_MANAGER_RUNTIME。
    /// 调用方必须把这些行放在 chcp 65001 之后——此时代码页已切到 UTF-8，bat 里的中文字节才能被正确解码
    /// （路径通常不含中文，但与中文注入变量保持同一顺序可避免顺序依赖）。
    /// </summary>
    public static IEnumerable<string> BuildScriptEnvSetLines()
    {
        foreach (var kv in ScriptEnvironmentVariables())
            yield return $"set \"{kv.Key}={kv.Value}\"";
    }

    /// <summary>
    /// 把 <see cref="CmdScriptRewriter"/> 抽取出的中文片段注入进程环境块。
    /// 环境块是 UTF-16，不经过 cmd 的文件解码，因此中文无损且不受控制台代码页影响。
    /// </summary>
    private static void SetInjectedVariables(ProcessStartInfo startInfo, IReadOnlyDictionary<string, string>? injectedVars)
    {
        if (injectedVars == null) return;
        foreach (var pair in injectedVars)
            startInfo.EnvironmentVariables[pair.Key] = pair.Value;
    }

    /// <summary>
    /// 生成 set 命令行，供提权路径（UseShellExecute=true）写进临时 .bat。
    /// 提权走 ShellExecute，.NET 无法传递进程环境块（ShellExecute 不支持 lpEnvironment），只能退回 bat 内 set。
    /// 调用方必须把这些行放在 chcp 65001 之后——此时代码页已切到 UTF-8，bat 里的中文字节才能被正确解码。
    /// </summary>
    public static IEnumerable<string> BuildSetLines(IReadOnlyDictionary<string, string>? injectedVars)
    {
        if (injectedVars == null) yield break;
        foreach (var pair in injectedVars)
            yield return $"set \"{pair.Key}={pair.Value}\"";
    }

    /// <summary>
    /// 构造 Java 单文件源码执行参数：自动把 <c>lib/java/</c> 约定子目录下的全部 jar 拼成 classpath，
    /// 放在源文件之前（launcher 选项须先于源文件名），使 Java 依赖对脚本透明可用。
    /// 约定：lib 根目录按语言分子目录（java/python/node…），放错目录（如 lib/java1）不生效。
    /// 当 lib/java 目录为空/不存在时退化为纯单文件执行。
    /// </summary>
    private static (string FileName, string Arguments) BuildJavaArgs(string runtime, string scriptPath, string args)
    {
        var javaLib = Path.Combine(AppConfig.LibDir, "java");
        string? cp = null;
        try
        {
            if (Directory.Exists(javaLib))
            {
                var jars = Directory.GetFiles(javaLib, "*.jar", SearchOption.TopDirectoryOnly)
                                    .ToArray();
                if (jars.Length > 0)
                    cp = string.Join(Path.PathSeparator.ToString(), jars);
            }
        }
        catch { /* 忽略 classpath 探测异常，退化执行 */ }

        var arguments = cp == null
            ? $"\"{scriptPath}\"{args}"
            : $"--class-path \"{cp}\" \"{scriptPath}\"{args}";
        return (runtime, arguments);
    }

    /// <summary>
    /// 构造 Rust 执行参数：Rust 是编译型语言，脚本源文件（.rs）已在 <see cref="ViewModels.MainViewModel"/> 准备阶段
    /// 用 rustc 预编译为临时 .exe（仅当编译成功才进入执行阶段）。因此此处 scriptPath 已是编译产物，
    /// FileName 直接指向该 exe；runtime（rustc 路径）仅用于上层存在性校验，不参与进程启动。
    /// </summary>
    private static (string FileName, string Arguments) BuildRustArgs(string runtime, string scriptPath, string args)
    {
        return (scriptPath, $"\"{scriptPath}\"{args}");
    }

    /// <summary>
    /// 为子进程设置环境变量，强制其以 UTF-8 输出标准流，避免中文乱码。
    /// 若用户已配置同名环境变量则追加，避免覆盖其原有设置。
    /// 注：脚本文件统一 UTF-8 无 BOM，Java 临时文件亦无 BOM，故 Java 固定 -Dfile.encoding=UTF-8。
    /// </summary>
    private static void SetEncodingEnvironment(ProcessStartInfo startInfo, string? lang)
    {
        switch ((lang ?? string.Empty).ToLowerInvariant())
        {
            case ScriptLangs.Java:
                // 单文件源码执行（JEP 330）按 -Dfile.encoding 读取源文件，固定 UTF-8。
                // stdout/stderr 仍强制 UTF-8（sun.stdout/stderr.encoding），保证输出不乱码。
                // 注：javac 专用的 -encoding 参数对 `java Script.java` 单文件模式无效，故用等价方案 -Dfile.encoding。
                AppendEnv(startInfo, "JDK_JAVA_OPTIONS", "-Dfile.encoding=UTF-8 -Dsun.stdout.encoding=UTF-8 -Dsun.stderr.encoding=UTF-8");
                break;
            case ScriptLangs.Python:
                startInfo.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8";
                break;
            case ScriptLangs.Bash:
                // git-bash 默认按系统 GBK(CP936) 输出到管道，需强制 UTF-8 locale。
                // 用 C.UTF-8（Win10+ 自带、免安装中文 locale 即可生效），避免 zh_CN.UTF-8 未安装时 fallback 乱码。
                startInfo.EnvironmentVariables["LANG"] = "C.UTF-8";
                startInfo.EnvironmentVariables["LC_ALL"] = "C.UTF-8";
                break;
        }
    }

    private static void AppendEnv(ProcessStartInfo startInfo, string key, string value)
    {
        var existing = startInfo.EnvironmentVariables.ContainsKey(key) ? startInfo.EnvironmentVariables[key] : null;
        startInfo.EnvironmentVariables[key] = string.IsNullOrWhiteSpace(existing) ? value : $"{existing} {value}";
    }
}
