# 时间線 · Windows 版

## 在 Windows 上自己编

装好 Flutter 3.47.6 和 Visual Studio 2022（勾选「使用 C++ 的桌面开发」）后：

```powershell
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
```

产物在 `build/windows/x64/runner/Release/`，整个目录一起发，
`data` 文件夹和几个 dll 都得跟着 exe 走。

## 用 GitHub Actions

推上去就自动编，产物在 Actions 页面里，名字是 `shijianxian-windows`。
