using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;
using System.Windows.Media;

namespace ScriptManager;

/// <summary>
/// null → Collapsed，否则 Visible。用于图标按需显示。
/// </summary>
public class NullToVisibilityConverter : IValueConverter
{
    public static readonly NullToVisibilityConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value == null ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotImplementedException();
}

/// <summary>
/// bool → Visibility。true=Visible（标准 BooleanToVisibilityConverter 语义）。
/// </summary>
public class BooleanToVisibilityConverter : IValueConverter
{
    public static readonly BooleanToVisibilityConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is true ? Visibility.Visible : Visibility.Collapsed;
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotImplementedException();
}

/// <summary>
/// bool → Visibility 取反。true=Collapsed（用于 TextBox/ComboBox 二选一）。
/// </summary>
public class InverseBoolToVisibilityConverter : IValueConverter
{
    public static readonly InverseBoolToVisibilityConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is true ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotImplementedException();
}

/// <summary>
/// 字符串为空或 null → Visible，否则 Collapsed。用于输入框灰字占位符（Value 为空时显示 placeholder）。
/// </summary>
public class StringEmptyToVisibilityConverter : IValueConverter
{
    public static readonly StringEmptyToVisibilityConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => string.IsNullOrEmpty(value as string) ? Visibility.Visible : Visibility.Collapsed;
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotImplementedException();
}

/// <summary>
/// 字符串非空 → Visible，否则 Collapsed。用于「清空」按钮（仅在输入框有值时才显示）。
/// 与 StringEmptyToVisibilityConverter 正好相反。
/// </summary>
public class StringNotEmptyToVisibilityConverter : IValueConverter
{
    public static readonly StringNotEmptyToVisibilityConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => string.IsNullOrEmpty(value as string) ? Visibility.Collapsed : Visibility.Visible;
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotImplementedException();
}

/// <summary>
/// bool → bool 取反。用于执行中禁用各类按钮/输入框（IsEnabled 绑定 IsRunning 的反向）。
/// </summary>
public class InverseBoolConverter : IValueConverter
{
    public static readonly InverseBoolConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is not true;
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is not true;
}

/// <summary>
/// bool → Grid.Column：有参数(true)时脚本预览放右列(1)，无参数(false)时占满起点(0)。
/// </summary>
public class BoolToGridColumnConverter : IValueConverter
{
    public static readonly BoolToGridColumnConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is true ? 1 : 0;
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotImplementedException();
}

/// <summary>
/// bool → Grid.ColumnSpan：有参数(true)时脚本预览仅占右列(1)，无参数(false)时跨满两列(2)。
/// </summary>
public class BoolToGridColumnSpanConverter : IValueConverter
{
    public static readonly BoolToGridColumnSpanConverter Instance = new();
    public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        => value is true ? 1 : 2;
    public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        => throw new NotImplementedException();
}
