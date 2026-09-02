using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
using System.Text;

namespace ScriptManager.Utils
{
    /// <summary>
    /// 零依赖的目录选择对话框（WPF 没有原生 FolderBrowserDialog）。
    /// 通过现代 IFileDialog + FOS_PICKFOLDERS 实现，弹出的就是系统标准的"选择文件夹"窗口，
    /// 与文件浏览（OpenFileDialog 同样基于 IFileDialog）风格一致。
    /// 仅在 Windows 下可用（项目已是 -windows 目标）。
    /// </summary>
    public static class FolderPicker
    {
        private static readonly Guid CLSID_FileOpenDialog = new("DC1C5A9C-E88A-4DDE-A5A1-60F82A20AEF7");
        private static readonly Guid IID_IFileDialog = new("42F85136-DB7E-439C-85F1-E4075D135FC8");

        [DllImport("ole32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern int CoCreateInstance(
            [MarshalAs(UnmanagedType.LPStruct)] Guid rclsid,
            IntPtr pUnkOuter,
            uint dwClsContext,
            [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
            out IFileDialog ppv);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();

        [ComImport]
        [Guid("42F85136-DB7E-439C-85F1-E4075D135FC8")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IFileDialog
        {
            // IModalWindow
            int Show(IntPtr hwndOwner);
            // IFileDialog
            void SetFileTypes(uint cFileTypes, IntPtr rgFileTypes);
            void SetFileTypeIndex(uint iFileType);
            void GetFileTypeIndex(out uint piFileType);
            void Advise(IntPtr pfde, out uint pdwCookie);
            void Unadvise(uint dwCookie);
            void SetOptions(FOS fos);
            void GetOptions(out FOS pfos);
            void SetDefaultFolder(IShellItem psi);
            void SetFolder(IShellItem psi);
            void GetFolder(out IShellItem ppsi);
            void GetCurrentSelection(out IShellItem ppsi);
            void SetFileName([MarshalAs(UnmanagedType.LPWStr)] string pszName);
            void GetFileName([MarshalAs(UnmanagedType.LPWStr)] out string pszName);
            void SetTitle([MarshalAs(UnmanagedType.LPWStr)] string pszTitle);
            void SetOkButtonLabel([MarshalAs(UnmanagedType.LPWStr)] string pszText);
            void SetFileNameLabel([MarshalAs(UnmanagedType.LPWStr)] string pszLabel);
            void GetResult(out IShellItem ppsi);
            void AddPlace(IShellItem psi, int fdap);
            void SetDefaultExtension([MarshalAs(UnmanagedType.LPWStr)] string pszDefaultExtension);
            void Close(int hr);
            void SetClientGuid([MarshalAs(UnmanagedType.LPStruct)] Guid guid);
            void ClearClientData();
            void SetFilter(IntPtr pFilter);
        }

        [ComImport]
        [Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellItem
        {
            void BindToHandler(IntPtr pbc, [MarshalAs(UnmanagedType.LPStruct)] Guid bhid, [MarshalAs(UnmanagedType.LPStruct)] Guid riid, out IntPtr ppv);
            void GetParent(out IShellItem ppsi);
            void GetDisplayName(SIGDN sigdnName, [MarshalAs(UnmanagedType.LPWStr)] out string ppszName);
            void GetAttributes(uint sfgaoMask, out uint psfgaoAttributes);
            void Compare(IShellItem psi, uint hint, out int piOrder);
        }

        [ComImport]
        [Guid("BCC18B79-BA16-442F-80C4-8A59C30C463B")]
        [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellItemImageFactory { }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern int SHCreateItemFromParsingName(
            [MarshalAs(UnmanagedType.LPWStr)] string pszPath,
            IntPtr pbc,
            [MarshalAs(UnmanagedType.LPStruct)] Guid riid,
            out IShellItem ppv);

        [Flags]
        private enum FOS : uint
        {
            FOS_PICKFOLDERS = 0x20,
            FOS_FORCEFILESYSTEM = 0x40,
            FOS_PATHMUSTEXIST = 0x800,
            FOS_NOVALIDATE = 0x100,
            FOS_NOTESTFILECREATE = 0x10000
        }

        private enum SIGDN : uint
        {
            SIGDN_FILESYSPATH = 0x80058000
        }

        /// <summary>
        /// 弹出现代风格的"选择文件夹"对话框。
        /// </summary>
        /// <param name="title">对话框标题。</param>
        /// <param name="selectedPath">初始选中的目录（可为空）。</param>
        /// <returns>选中目录的完整路径；用户取消则返回 null。</returns>
        public static string? PickFolder(string title, string? selectedPath = null)
        {
            int hr = CoCreateInstance(CLSID_FileOpenDialog, IntPtr.Zero, 1 /*CLSCTX_INPROC_SERVER*/, IID_IFileDialog, out var dlg);
            if (hr != 0 || dlg == null)
                return null;

            try
            {
                dlg.SetOptions(FOS.FOS_PICKFOLDERS | FOS.FOS_FORCEFILESYSTEM | FOS.FOS_PATHMUSTEXIST);
                if (!string.IsNullOrWhiteSpace(title))
                    dlg.SetTitle(title);

                IShellItem? initial = TryCreateItem(selectedPath);
                if (initial != null)
                {
                    // SetFolder 让对话框直接定位到该目录
                    dlg.SetFolder(initial);
                }

                hr = dlg.Show(GetForegroundWindow());
                if (hr != 0) // 用户取消或关闭
                    return null;

                dlg.GetResult(out var item);
                item.GetDisplayName(SIGDN.SIGDN_FILESYSPATH, out var path);
                return string.IsNullOrEmpty(path) ? null : path;
            }
            finally
            {
                Marshal.ReleaseComObject(dlg);
            }
        }

        private static IShellItem? TryCreateItem(string? path)
        {
            if (string.IsNullOrWhiteSpace(path) || !System.IO.Directory.Exists(path))
                return null;
            int hr = SHCreateItemFromParsingName(path!, IntPtr.Zero, new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), out var item);
            return hr == 0 ? item : null;
        }
    }
}
