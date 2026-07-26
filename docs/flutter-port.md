# Flutter 分支：项目分析与移植说明

本文档记录 `flutter` 分支的由来：对主分支（Tauri 2 + Svelte 5 + Rust）的架构分析，
以及 Flutter 版（`flutter_app/`）的移植映射与后续路线。

## 1. 主分支架构分析

### 1.1 技术栈与形态

- **前端**：Svelte 5（runes 状态模型）+ TypeScript + Vite + Bun
- **后端**：Rust（Tauri 2），负责系统能力与本地服务
- **形态**：单窗口"桌面隐喻" —— 壁纸、顶栏、侧栏、桌面小组件、
  应用内浮动工具窗口（拖拽/缩放/最小化/最大化/层级）、底部 Dock、Ctrl+K 快速启动器

### 1.2 前端核心模块（`src/`）

| 模块 | 职责 |
| --- | --- |
| `toolRegistry.ts` | 18 个工具的注册表（窗口类 13 + 剪贴板动作类 5），含图标、快捷键、默认窗口尺寸、旧 ID 迁移 |
| `state.svelte.ts` | 全局状态：主题/壁纸/侧栏、窗口列表与 z 序、待办、计时器快照、工作区模板、收藏/最近、活动流；250ms 防抖持久化 |
| `workspace.ts` | 持久化 schema v1、`clampGeometry` 窗口钳制、`reconcileTimers` 计时器跨重启恢复（秒表 startedAt / 倒计时 targetAt / 番茄钟模式推进） |
| `launcher.ts` | 启动器：子序列模糊打分、收藏 +200 / 最近使用加权、`> timer / todo / peek / workspace` 命令、递归下降安全计算器（无 eval）、URL 归一化 |
| `persistence.ts` | 经 tauri-plugin-store 读写 `workspace.json`，损坏时由 Rust `recover_workspace_store` 备份重建 |
| `tools.ts` | 剪贴板快捷动作（时间戳/JSON/URL/Base64/SHA-256）与 `runTool` 分发 |

### 1.3 Rust 后端（`src-tauri/src/`）

| 模块 | 职责 |
| --- | --- |
| `peek_server/` | 局域网 HTTP 监视服务：高熵 API Key、失败限流、连接日志、隐私模式/全局模糊/敏感应用规则、移动端仪表盘（内嵌 HTML） |
| `usage_tracker.rs` | 前台应用轮询，屏幕使用时长统计 |
| `heartrate.rs` | BLE 心率（扫描/连接/设备过滤），配合 HR 悬浮窗 |
| `file_tools.rs` | 批量重命名 / 规则整理 / 重复扫描：先预览后执行、操作历史撤销、分阶段哈希 |
| `media_module.rs` | Windows SMTC 媒体信息与控制 |
| `lib.rs` | 系统托盘、全局快捷键、系统状态（sysinfo）、窗口关闭改隐藏、更新器/自启插件 |

### 1.4 值得保留的设计不变量

1. **先预览、可撤销**的文件操作流程（安全文件工具）
2. **计时器以绝对时间戳存档**（startedAt/targetAt），重启后用 `reconcileTimers` 对账，而非信任残留的 remaining
3. **工作区 schema 版本化 + 结构校验**，损坏存档备份而非丢弃
4. 启动器计算器**手写解析器、绝不 eval**
5. 工具注册表**单一事实来源**（窗口尺寸、快捷键、启动台/Dock 可见性都由它派生）

## 2. Flutter 版映射

### 2.1 对应关系

| 原模块 | Flutter 文件 | 说明 |
| --- | --- | --- |
| `toolRegistry.ts` | `lib/core/tool_registry.dart` | 同一批工具 ID 与元数据；`ported` 标记未完成项 |
| `workspace.ts` | `lib/core/workspace.dart` | schema v1 JSON 兼容；`reconcileTimers`/`clampGeometry`/`timerPreset`/`isWorkspaceV1` 逐行对齐 |
| `launcher.ts` | `lib/core/launcher.dart` | 打分、命令、计算器（含 JS 风格 remainder）、URL 归一化 |
| `state.svelte.ts` | `lib/core/app_state.dart` | Svelte runes → `ChangeNotifier`；同样的 250ms 防抖持久化与持久化队列 |
| `persistence.ts` + store 插件 | `lib/core/persistence.dart` | `shared_preferences` 存单键 JSON；损坏时备份到 `congmiao.workspace.corrupt.<ts>` |
| `tools.ts` | `lib/tools/actions.dart` | 剪贴板动作与 `runTool` 分发 |
| `file_tools.rs` | `lib/core/file_tools.dart` | 纯 `dart:io` 复刻：预览计划缓存（10 分钟 TTL）、执行前源文件校验、两阶段重命名（支持 a↔b 互换）、跨磁盘 safe move、原子撤销日志（tmp/bak 轮换，上限 10 条）、大小 → 抽样哈希 → 全量哈希的重复扫描（可取消，带进度回调；BLAKE3 换为 SHA-256，哈希仅内部使用不落盘） |
| `FloatingWindow.svelte` | `lib/ui/floating_window.dart` | Stack + Positioned + Pan 手势实现拖拽/缩放 |
| `CommandPalette.svelte` | `lib/ui/command_palette.dart` | Dialog + CallbackShortcuts 上下键导航 |
| `App.svelte` 桌面模式 | `lib/ui/home_shell.dart` | 壁纸/顶栏/NavigationRail/桌面层/Dock/全局快捷键 |
| 各工具 Svelte 组件 | `lib/tools/*.dart` | JSON/编码/哈希/取色/时钟/转盘已实现；其余为说明性占位窗口 |
| `launcher.test.ts` / `workspace.test.ts` | `test/*.dart` | 用例逐条移植，行为等价的回归护栏 |

### 2.2 有意的差异

- 持久化后端从 tauri-plugin-store 换成 `shared_preferences`（JSON 结构不变，
  迁移时可直接拷贝原 `workspace.json` 内容）
- URL 归一化基于 `Uri`，纯域名结果不带 JS `new URL()` 的尾部斜杠
- 幸运大转盘先实现单层转盘 + 历史记录；原版多级决策树列入后续
- 番茄钟/倒计时结束暂以活动流提示，系统通知待接 `flutter_local_notifications`

### 2.3 后续路线（按优先级）

1. ~~文件工具三件套~~ ✅ 已完成（`lib/core/file_tools.dart` + 三个工具窗口 + 测试）
2. **Peek PC**：`dart:io` HttpServer 复刻 `peek_server` 的鉴权、限流、日志与移动端
   仪表盘（纯 Dart 可行，无需平台通道；截图与前台应用检测需要通道或 FFI）
3. **平台通道**：系统监控（sysinfo 等价）、屏幕使用时长、媒体控制
4. **桌面集成**：托盘（tray_manager）、全局快捷键（hotkey_manager）、
   开机自启（launch_at_startup）、多窗口 HR 悬浮窗（desktop_multi_window）
5. **心率 BLE**：`flutter_blue_plus`（同时打开移动端使用场景）
6. 图片转换（`package:image`）、Python 排版（本机 ruff 进程）、翻译（接口待定）

## 3. 分支使用方式

- `main`：Tauri + Svelte 主线，正常发版
- `flutter`：本分支。原代码保持不动，Flutter 版位于 `flutter_app/`，
  便于移植时对照参考实现；两版共享同一套持久化 schema 语义
- 开发引导见 [flutter_app/README.md](../flutter_app/README.md)
