using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace ScriptManager.ViewModels;

/// <summary>
/// MVVM 基类：实现 INotifyPropertyChanged，供所有 ViewModel 复用属性通知。
/// 替代原 WinForms 中依赖 InvokeRequired 的跨线程 UI 更新——WPF 绑定自动切回 UI 线程。
/// </summary>
public class ViewModelBase : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected bool SetProperty<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
            return false;
        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    protected void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
}
