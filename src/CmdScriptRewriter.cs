using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace ScriptManager;

/// <summary>
/// cmd/bat 专用预处理：把脚本内容里的非 ASCII 片段抽成环境变量占位符，使脚本在字节层面降为 ASCII，
/// 从而彻底规避「cmd 按控制台活动代码页解码 bat 文件」造成的文件偏移漂移与中文乱码。
/// </summary>
/// <remarks>
/// <para>
/// <b>原理</b>：cmd.exe 没有"文件编码"概念——它按当前控制台活动代码页（中文 Windows 默认 936/GBK）把 bat
/// 的字节解码成字符。（补注：给 bat 加 UTF-8 BOM 也无效，`EF BB BF` 会被解成 `ï»¿` 拼到首行开头，
/// 反而让 <c>@echo off</c> 的 <c>@</c> 失效。）而进程环境块是 UTF-16，cmd 展开 <c>%VAR%</c> 取到的是
/// Unicode 原文，与代码页无关。把中文从"文件字节"搬到"环境块"，脚本即可降为纯 ASCII。
/// </para>
/// <para>
/// <b>为什么必须逐行全覆盖、不能跳过注释行</b>（2026-08-29 实机踩坑，务必牢记）：
/// cmd 计算"下一行的文件偏移"用的是<b>解码后的字符数</b>，而文件实际是<b>字节数</b>。一个 UTF-8 中文
/// 占 3 字节却只算 1 字符——即便 chcp 65001 把它正确解码，偏移也只前进 1 而非 3，每遇一个中文就前移 2 字节，
/// 逐行累积，最终整行错位。表现为：中文越多、越靠后，行首被"砍掉"的字符越多，被砍剩下的半截行
/// 被当成命令执行，刷出大量 <c>'xxx' is not recognized as an internal or external command</c>。
/// <b>只要文件里还剩任何一个多字节字符——哪怕在 REM 注释里——漂移就会发生并污染后续所有行。</b>
/// 因此 <c>REM</c> 注释行也必须改写（"注释乱码无害"只考虑了内容，没考虑偏移）。
/// </para>
/// <para>
/// <b>已知取舍</b>：改写后 REM 注释行会显示 <c>%SM_TXT_nnn%</c> 字面量（cmd 对 REM 后内容不做变量展开），
/// 在 <c>@echo off</c> 下不可见；未写 <c>@echo off</c> 的脚本回显时会看到占位符而非中文。
/// 同理，<c>:标签</c> 与 <c>goto</c> 行若含中文，改写后因标签匹配不展开变量会导致跳转失效——
/// 但"单个 goto 失效"远轻于"偏移漂移让整个脚本崩溃"，且中文标签名本就不合脚本编写规范。
/// </para>
/// </remarks>
public static class CmdScriptRewriter
{
    /// <summary>注入变量名前缀（后接三位序号），刻意生僻以避免与脚本自身变量冲突。</summary>
    public const string VarPrefix = "SM_TXT_";

    /// <summary>
    /// 可抽取内容总量的安全上限（字符数），超出则整份脚本放弃改写、退回原文执行。
    /// 原因：进程环境块总容量约 32K 字符，超限会让进程直接起不来——宁可不优化，也不能跑不起来。
    /// </summary>
    private const int MaxExtractedChars = 16000;

    /// <summary>改写结果：<see cref="Content"/> 为 ASCII 化后的脚本，<see cref="Variables"/> 为待注入环境的中文真值。</summary>
    public sealed class Result
    {
        public Result(string content, IReadOnlyDictionary<string, string> variables)
        {
            Content = content;
            Variables = variables;
        }

        /// <summary>ASCII 化后的脚本内容（非 ASCII 片段已替换为 <c>%SM_TXT_nnn%</c> 占位符）。</summary>
        public string Content { get; }

        /// <summary>占位符 → 中文真值，需由调用方注入进程环境块（UTF-16，无损）。</summary>
        public IReadOnlyDictionary<string, string> Variables { get; }
    }

    /// <summary>对 bat 内容做 ASCII 化改写；无需改写（无非 ASCII 内容或总量超限）时原样返回。</summary>
    public static Result Rewrite(string content)
    {
        var variables = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        if (string.IsNullOrEmpty(content))
            return new Result(content, variables);

        var lines = content.Split('\n');

        // 第一遍：只统计可抽取总量。超环境块余量则整体放弃，保证「改写后一定跑得起来」。
        var budget = 0;
        foreach (var line in lines)
        {
            foreach (var (_, length) in EnumerateNonAsciiSpans(line))
            {
                budget += length;
                if (budget > MaxExtractedChars)
                    return new Result(content, variables);
            }
        }
        if (budget == 0)
            return new Result(content, variables);

        // 第二遍：把非 ASCII 片段替换为 %SM_TXT_nnn%，真值存入 variables。
        // 逐行全覆盖、不跳过任何行（含 REM 注释与标签行），确保字节数 ≡ 字符数，偏移不漂移。
        var builder = new StringBuilder(content.Length + 4096);
        var index = 0;
        for (var i = 0; i < lines.Length; i++)
        {
            if (i > 0) builder.Append('\n');

            var line = lines[i];
            var copied = 0;
            foreach (var (start, length) in EnumerateNonAsciiSpans(line))
            {
                var name = VarPrefix + (index++).ToString("D3", CultureInfo.InvariantCulture);
                variables[name] = line.Substring(start, length);
                builder.Append(line, copied, start - copied).Append('%').Append(name).Append('%');
                copied = start + length;
            }
            builder.Append(line, copied, line.Length - copied);
        }

        return new Result(builder.ToString(), variables);
    }

    /// <summary>枚举行内所有"连续非 ASCII 片段"的起始下标与长度。</summary>
    private static IEnumerable<(int Start, int Length)> EnumerateNonAsciiSpans(string line)
    {
        var start = -1;
        for (var i = 0; i < line.Length; i++)
        {
            if (line[i] > 127)
            {
                if (start < 0) start = i;
            }
            else if (start >= 0)
            {
                yield return (start, i - start);
                start = -1;
            }
        }
        if (start >= 0)
            yield return (start, line.Length - start);
    }
}
