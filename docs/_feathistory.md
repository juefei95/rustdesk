# 本次功能代码改动记录

本文按代码文件说明本次 Windows 托盘相关改动实现了什么功能，以及各文件之间的调用关系。

## 改动文件与功能对应

| 文件 | 代码改动 | 对应功能 |
| --- | --- | --- |
| `src/tray.rs` | 托盘菜单、菜单事件和左键点击事件 | 增加“设置”“检查更新”“退出”；“打开”和左键点击统一恢复主窗口；退出改为结束用户进程。 |
| `src/platform/windows.rs` | `find_main_window`、`restore_main_window`、`open_main_window_settings`、`quit_all_user_processes` | 定位已有主窗口并恢复；发送打开设置消息；清理当前用户启动的相关进程。 |
| `flutter/windows/runner/flutter_window.cpp` | `kTrayActionMessage` 和 `MessageHandler` | 接收 Rust 发送的 Windows 消息，并转发给 Flutter 的 MethodChannel。 |
| `flutter/lib/desktop/pages/simplelink_desktop_page.dart` | `org.rustdesk.rustdesk/tray` 的监听 | 接收 `openSettings` 后显示窗口、获得焦点并打开基本设置页面。 |
| `flutter/windows/runner/main.cpp` | `--settings` 参数白名单、已有窗口激活方式 | 允许“设置”兜底启动；重复启动时恢复最小化窗口并置前。 |
| `flutter/lib/main.dart` | 读取 `--settings` 启动参数 | 将启动参数传入桌面主页。 |
| `flutter/lib/desktop/pages/desktop_tab_page.dart` | `openSettingsOnStart` 和设置页 Tab 创建 | 当程序由 `--settings` 启动时，初始显示基本设置页面。 |
| `src/core_main.rs` | Windows 服务状态判断注释 | 保留并明确 Windows 服务进程无法可靠读取命令行参数的原因；运行逻辑未改变。 |

## `src/tray.rs`：托盘菜单和事件分发

### 菜单项

`make_tray()` 中原有“打开 / 停止服务”菜单改为：

```rust
Open -> open_func
Settings -> settings_func
Check for updates -> update_func
Exit -> quit_all_user_processes
```

- `Open`：Windows 下优先调用 `restore_main_window()`；仅在没有找到主窗口时才调用 `run_me([])` 启动新实例。
- `Settings`：优先调用 `open_main_window_settings()`；若主窗口不存在，则调用 `run_me(["--settings"])`。
- `Check for updates`：Windows 下调用已有的 `updater::manually_check_update()`。
- `Exit`：不再调用 `uninstall_service(false, false)`，改为调用 `quit_all_user_processes()`。因此不会触发服务卸载对应的 UAC 提权流程。

### 托盘左键行为

`TrayEvent::Click` 的 Windows 左键抬起事件直接调用 `open_func()`，因此左键打开和菜单“打开”使用同一套恢复逻辑。事件增加了一秒防抖，避免快速连续点击重复执行恢复。

## `src/platform/windows.rs`：主窗口恢复、设置消息和退出清理

### `find_main_window()`

通过下列条件查找已有主窗口：

```text
窗口类      FLUTTER_RUNNER_WIN32_WINDOW
窗口标题    crate::get_app_name()
用户会话    当前 Windows Session
```

完整标题匹配避免将标题为“应用名 - Install”或“应用名 - Connection Manager”的窗口当作主窗口；会话判断避免误操作其他用户会话的窗口。

### `restore_main_window()`

找到窗口后依次调用：

```text
ShowWindow(SW_RESTORE)
BringWindowToTop
SetForegroundWindow
```

这使托盘操作恢复已隐藏或最小化的主界面，而不是默认再创建一个 Flutter 主窗口。

### `open_main_window_settings()`

先执行与 `restore_main_window()` 相同的窗口恢复操作，再使用：

```text
PostMessageW(WM_APP + 0x51, 1, 0)
```

向 Flutter Runner 发送“打开设置”请求。消息常量由 Rust 和 C++ 两侧保持一致：`WM_APP + 0x51` 和动作值 `1`。

### `quit_all_user_processes()`

该函数先向 RustDesk 服务发送关闭通知，随后按当前可执行文件名清理当前用户会话中的以下进程类型：

```text
无参数主程序
--cm
--server
--tray
```

当前托盘进程会从清理列表中排除，最后由自身 `std::process::exit(0)` 退出。这里的清理是进程级处理，不是 Windows 服务卸载。

## C++ 与 Flutter：设置页跨进程链路

### `flutter/windows/runner/flutter_window.cpp`

`FlutterWindow::MessageHandler()` 在 Flutter 和插件消息处理之前识别 `WM_APP + 0x51`。当动作值为 `1` 时，它创建 `org.rustdesk.rustdesk/tray` MethodChannel，并调用：

```text
openSettings
```

同一文件还调整了 `WM_SHOWWINDOW` 的重绘保护：每次窗口变为可见时都会重置计数并重新启动重绘计时器，处理隐藏到托盘后恢复时的白屏风险。

### `flutter/lib/desktop/pages/simplelink_desktop_page.dart`

`_SimpleLinkDesktopPageState.initState()` 注册 `org.rustdesk.rustdesk/tray` 的 MethodChannel 处理器。收到 `openSettings` 时依次执行：

```text
windowManager.show()
windowManager.focus()
_selectPage(3)
```

其中 `_selectPage(3)` 选择简连桌面页中的基本设置页面。`dispose()` 中会注销该处理器，避免页面销毁后仍接收消息。

## 无主窗口时的设置兜底启动

当托盘进程找不到主窗口时，设置功能不会失效，而是启动：

```text
rustdesk.exe --settings
```

这条启动路径涉及三个文件：

| 文件 | 作用 |
| --- | --- |
| `flutter/windows/runner/main.cpp` | 将 `--settings` 加入单实例参数白名单，使该参数可启动新实例。重复启动普通实例时使用 `SW_RESTORE`、`BringWindowToTop` 和 `SetForegroundWindow` 恢复已有窗口。 |
| `flutter/lib/main.dart` | 从 `kBootArgs` 判断是否带有 `--settings`，并传给 `App`。 |
| `flutter/lib/desktop/pages/desktop_tab_page.dart` | 接到 `openSettingsOnStart` 后创建并选中基本设置 Tab。 |

## 代码调用顺序

### 关闭主窗口后从托盘打开主界面

```text
src/tray.rs
  open_func()
    -> src/platform/windows.rs
         restore_main_window()
           -> FindWindowW(...)
           -> ShowWindow(SW_RESTORE)
           -> BringWindowToTop()
           -> SetForegroundWindow()
```

`restore_main_window()` 返回 `false` 时，`open_func()` 才会调用 `run_me([])` 创建主程序。

### 从托盘打开基本设置

```text
src/tray.rs
  settings_func()
    -> src/platform/windows.rs
         open_main_window_settings()
           -> 恢复主窗口
           -> PostMessageW(WM_APP + 0x51, 1, 0)
             -> flutter/windows/runner/flutter_window.cpp
                  MessageHandler()
                    -> MethodChannel("org.rustdesk.rustdesk/tray")
                         InvokeMethod("openSettings")
                           -> flutter/lib/desktop/pages/simplelink_desktop_page.dart
                                _selectPage(3)
```

若第一步未找到主窗口：

```text
settings_func()
  -> run_me(["--settings"])
    -> flutter/windows/runner/main.cpp
    -> flutter/lib/main.dart
    -> flutter/lib/desktop/pages/desktop_tab_page.dart
```

### 从托盘退出

```text
src/tray.rs
  Exit 菜单事件
    -> 隐藏托盘图标
    -> src/platform/windows.rs
         quit_all_user_processes()
           -> send_close(POSTFIX_SERVICE)
           -> 清理主程序、--cm、--server、--tray 进程
           -> 当前托盘进程退出
```

## 构建验证

本次实现已使用以下命令完成 Windows Release 构建：

```powershell
$env:RUST_LOG = 'info'
.\flutter\run-release.ps1
```

产物路径：`flutter\build\windows\x64\runner\Release\rustdesk.exe`。
