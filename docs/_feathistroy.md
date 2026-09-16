# 名称拆分与 Windows 系统对象说明

本文记录定制版中几个容易混淆的名称，以及它们在代码和系统命令中的作用。核心原则是：用户看到的品牌名、Windows 服务名、防火墙规则名、EXE 文件名分别固定，不再互相推导。

## 名称列表

| 名称类型 | 当前值示例 | 代码位置 | 主要作用 |
| --- | --- | --- | --- |
| 用户可见品牌 | 点连远程助手 | Flutter 标题、页面文字、版本资源 | 给用户看的名字，出现在窗口标题、任务管理器描述、界面文案等位置。 |
| 产品稳定 ID | DianLianRemoteAssistant | `libs/hbb_common/src/config.rs` 的 `APP_NAME` | 程序内部长期使用的身份标识，配置、注册表、升级兼容逻辑可能会引用。 |
| 主程序 EXE | `dianlian.exe` | `src/platform/windows.rs` 的 `WINDOWS_EXE_NAME`，以及 Flutter Windows `BINARY_NAME` | 磁盘上的可执行文件名，`taskkill /IM`、安装目录、升级覆盖时使用。 |
| Windows 服务名 | `DianLianService` | `src/platform/windows.rs` 的 `WINDOWS_SERVICE_NAME` | `sc create`、`sc start`、`sc stop`、`sc delete` 使用的真实服务名，必须稳定且前后一致。 |
| Windows 服务显示名 | 点连远程助手服务 | `src/platform/windows.rs` 的 `WINDOWS_SERVICE_DISPLAY_NAME` | 服务管理器里给用户看的服务名称，不参与 `sc stop` 这类命令匹配。 |
| 防火墙规则名 | `DianLianService` | `src/platform/windows.rs` 的 `WINDOWS_FIREWALL_RULE_NAME` | `netsh advfirewall firewall add/delete rule name=...` 使用，安装和卸载必须一致。 |

## 为什么不全部使用 app_name

原始 RustDesk 代码里，很多地方可以直接用 `app_name` 推导：

```text
服务名 = app_name
EXE 名 = app_name.exe
防火墙规则名 = app_name Service
```

定制版商业化后，这几个名字的职责已经不同。如果继续全部使用 `app_name`，后续改品牌文案、改 EXE 名或改服务名时，容易出现服务停不掉、防火墙规则删不掉、升级覆盖错文件等问题。

因此现在按用途拆开：

```text
sc stop / sc delete        -> DianLianService
DisplayName=              -> 点连远程助手服务
taskkill /F /IM           -> dianlian.exe
netsh firewall rule name  -> DianLianService
窗口标题和界面文案          -> 点连远程助手
```

## 典型执行示例

### 创建服务

```bat
sc create DianLianService binpath= "\"C:\Program Files\...\dianlian.exe\" --service" start= auto DisplayName= "点连远程助手服务"
sc start DianLianService
```

### 停止并删除服务

```bat
sc stop DianLianService
sc delete DianLianService
```

这里必须使用 Windows 服务名 `DianLianService`，不能使用用户可见品牌名。

### 清理进程

```bat
taskkill /F /IM dianlian.exe
```

这里使用的是 EXE 文件名，不是服务名，也不是产品显示名。

### 添加和删除防火墙规则

```bat
netsh advfirewall firewall add rule name="DianLianService" dir=in action=allow program="C:\Program Files\...\dianlian.exe" enable=yes
netsh advfirewall firewall delete rule name="DianLianService"
```

防火墙规则名可以和服务名保持一致，便于排查和卸载清理，但它本质上仍然是防火墙规则名。

## 本次代码调整点

| 文件 | 调整内容 | 作用 |
| --- | --- | --- |
| `src/platform/windows.rs` | 新增 `WINDOWS_SERVICE_DISPLAY_NAME` | 服务管理器中显示中文服务名。 |
| `src/platform/windows.rs` | 新增 `WINDOWS_FIREWALL_RULE_NAME` | 防火墙规则创建和删除使用同一个固定名。 |
| `src/platform/windows.rs` | `sc create/start/stop/delete` 统一使用 `WINDOWS_SERVICE_NAME` | 避免服务名和应用显示名混用。 |
| `src/platform/windows.rs` | `taskkill /IM` 统一使用 `WINDOWS_EXE_NAME` | 避免进程名和服务名混用。 |
| `src/platform/windows.rs` | `DisplayName=` 使用 `WINDOWS_SERVICE_DISPLAY_NAME` | 服务显示名对用户友好，同时不影响服务命令。 |

## 后续维护规则

以后如果只改品牌展示，例如从“点连远程助手”改成另一个中文名，优先改用户可见文案和版本资源，不要顺手改 `WINDOWS_SERVICE_NAME`。

如果必须改 `WINDOWS_SERVICE_NAME`，需要同步考虑旧服务迁移：先停止并删除旧服务名，再创建新服务名，否则用户机器上可能残留旧服务。
