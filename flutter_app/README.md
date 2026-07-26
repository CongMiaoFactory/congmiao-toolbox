# Congmiao Toolbox — Flutter 版

这是 `congmiao-toolbox` 的 Flutter 分支实现，与主分支（Tauri 2 + Svelte 5 + Rust）功能对齐的跨平台移植。
架构分析与移植映射见 [../docs/flutter-port.md](../docs/flutter-port.md)。

## 环境准备

本目录只包含 Dart 源码与 `pubspec.yaml`，平台外壳（`windows/`、`android/` 等）不入库，
首次使用时生成：

```bash
cd flutter_app
flutter create . --project-name congmiao_toolbox_flutter --org com.congmiao --platforms windows,macos,linux,android
flutter pub get
```

## 运行

```bash
flutter run -d windows   # 或 macos / linux / android
```

## 验证

```bash
flutter analyze
flutter test
```

`test/` 下的用例逐条移植自主分支的 `launcher.test.ts` 与 `workspace.test.ts`，
确保启动器打分、安全计算器、计时器恢复、窗口几何钳制等行为与原版一致。

## 已移植功能

- 桌面隐喻主界面：壁纸（URL + 模糊）、顶栏、侧栏导航、底部 Dock
- 应用内浮动工具窗口：拖拽、缩放、最小化、最大化、层级管理，布局持久化恢复
- 快速启动器（Ctrl+K）：模糊搜索、收藏/最近加权、`> timer 10m`、`> todo …`、
  `> workspace`、`> peek`、无 eval 安全计算器、URL 识别与网页搜索
- 工具窗口：JSON 格式化、万能编码转换（Base64/URL/Unicode）、哈希校验中心
  （MD5/SHA-1/SHA-256/SHA-512）、深层取色器（HEX/RGB/HSL）、生产力时钟
  （秒表 + 计圈 + 倒计时）、幸运大转盘
- 剪贴板快捷动作：复制时间戳、格式化剪贴板 JSON、URL Encode、Base64、SHA-256
- 桌面小组件：时钟、待办、番茄钟、最近操作流
- 工作区持久化：schema 与主分支 `workspace.json` v1 相同，含计时器跨重启恢复
  （`reconcileTimers`）、工作区模板保存/应用、损坏存档自动备份

## 待移植（原版依赖 Rust 后端）

| 功能 | 原版实现 | Flutter 计划 |
| --- | --- | --- |
| Peek PC 局域网监视 | `src-tauri/src/peek_server` | `dart:io` HttpServer 复刻鉴权/限流/日志 |
| 屏幕使用时长 | `usage_tracker.rs` | 各平台 MethodChannel |
| 系统监控（CPU/内存） | `sysinfo` | MethodChannel 或 FFI |
| 心率 BLE + 悬浮窗 | `heartrate.rs` (btleplug) | `flutter_blue_plus` + 独立窗口 |
| 文件工具三件套 | `file_tools.rs` | `dart:io` + Isolate，保留预览/撤销流程 |
| 媒体控制 | `media_module.rs` (Windows SMTC) | MethodChannel |
| Python 排版 / 图片转换 / 翻译 | ruff-wasm / Canvas / 在线接口 | 本机进程 / `package:image` / 待定 |
| 系统托盘、全局快捷键、开机自启、更新器 | Tauri 插件 | `tray_manager`、`hotkey_manager`、`launch_at_startup` 等 |
