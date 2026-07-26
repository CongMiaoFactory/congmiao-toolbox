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

`test/` 下的用例移植自主分支的 `launcher.test.ts`、`workspace.test.ts` 与
`file_tools.rs` / `security.rs` 的 Rust 测试，另含 Peek 服务器的真实 HTTP
端到端测试，确保移植语义与原版一致。

## 功能状态（迁移已完成）

18 个注册工具全部可用：

- **桌面壳**：壁纸（URL + 模糊）、顶栏、侧栏、Dock、浮动工具窗口（拖拽/缩放/
  最大化，布局持久化恢复）、Ctrl+K 快速启动器（模糊搜索、`> timer` / `> todo` /
  `> workspace` / `> peek` 命令、无 eval 计算器、URL/网页搜索）
- **纯逻辑工具**：JSON 格式化、编码转换（Base64/URL/Unicode）、哈希校验
  （MD5/SHA-1/256/512）、取色器（HEX/RGB/HSL）、生产力时钟（秒表+计圈+倒计时）、
  幸运大转盘、5 个剪贴板快捷动作
- **文件工具三件套**（`dart:io`，与 Rust 版同一套安全不变量）：批量重命名、
  规则整理、重复扫描；先预览后执行 + 原子操作日志 + 撤销
- **Peek 远程监视**：`dart:io` HttpServer 复刻——64 位高熵 API 密钥（仅存哈希、
  恒定时间比较）、失败限流（60 秒 10 次）、防抖连接日志（500 条 / 30 天）、
  监听范围与端口配置、手机浏览器仪表盘（/api/status 提供 CPU/内存/前台窗口）
- **系统监控**：仪表盘 CPU/内存磁贴（Windows: PowerShell CIM；Linux: /proc；
  macOS: top）
- **屏幕使用时长**：win32 FFI 前台窗口每秒采样，持久化到 `app_usage.json`
  （与 Rust 版同名同构；打开页面或启动 Peek 服务后开始统计）
- **图片格式工厂**：package:image 离线解码 PNG/JPG/WebP/GIF/BMP，输出 PNG/JPG
- **Python 工具集**：字典 → JSON（内置 Python 字面量解析器）+ 本机 ruff 排版
- **多语互译机**：与原版相同的免费 Google 翻译端点（需联网）

## 已知平台限制（与原版差异）

| 能力 | 说明 |
| --- | --- |
| Peek 手机端截图 | 需要原生屏幕捕获，接口返回 501，仪表盘显示占位提示 |
| 屏幕时长 / 前台窗口 | 依赖 win32 FFI，仅 Windows；其余平台显示说明 |
| 媒体控制（SMTC） | 需要 WinRT 平台通道，未移植；状态接口 media 字段为 null |
| 心率 BLE 悬浮窗 | 需要 BLE 插件与多窗口支持，未移植 |
| 系统托盘 / 全局快捷键 / 开机自启 / 更新器 | 桌面集成插件（tray_manager 等）列为后续增强 |
| WebP 输出 | 纯 Dart 尚无 WebP 编码器，仅支持读取 |
