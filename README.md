# 每日作业 · macOS 原生版（SwiftUI）

本分支 `features/Mac` **只包含 macOS 原生版**，方便单独浏览与克隆；
Windows 版（Tauri + Vue 3）在 `master` 分支。

```
macos/                     SwiftPM 工程：Sources / Tests / scripts / Resources
fixtures/data.sample.json  两版共用的数据编解码契约样本（Swift 测试读它）
LICENSE                    MIT
```

## 快速开始

```bash
cd macos
swift test                     # 42 个单元测试（课表调度 / 存储 / 节假日 / 编解码契约）
./scripts/build-app.sh         # 发布构建（universal：Intel + Apple Silicon）→ build/每日作业.app
./scripts/make-dmg.sh          # 一键出签名 DMG → build/每日作业-1.0-universal.dmg
open build/每日作业.app
```

详细说明见 [macos/README.md](macos/README.md)：结构、数据契约、节假日规则、快捷键、出图语义。
与 Windows 版的差异审计见 [macos/PARITY.md](macos/PARITY.md)。

## 系统要求

macOS 26 或更高（代码用到 macOS 26 的 SwiftUI API，`Package.swift` 的 deployment target 也是 26）。
