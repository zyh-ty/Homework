# 每日作业 · 原生 macOS 版（SwiftUI）

原 Windows 客户端（Tauri + Vue）的 macOS 原生重写：SwiftUI + AppKit + EventKit，
一眼 macOS，放映画面按 1920×1080 设计稿等比缩放绘制，屏幕所见即导出的 PNG。

## 构建 / 运行

```bash
cd macos
swift test                     # 40 个单元测试（课表调度 / 存储 / 节假日 / 编解码契约）
./scripts/build-app.sh         # 发布构建（universal：Intel + Apple Silicon）→ build/每日作业.app
open build/每日作业.app
./scripts/build-app.sh debug   # 调试构建
```

打包 DMG（带背景图、图标位置、拖拽安装；自动挑钥匙串里的 Apple Development 证书签名）：

```bash
./scripts/make-dmg.sh                          # → build/每日作业-1.0-universal.dmg
SKIP_BUILD=1 ./scripts/make-dmg.sh             # 复用已有 .app，只重做 DMG（调版式时用）
ARCHS=native ./scripts/build-app.sh            # 只出本机架构（开发用）
```

图标 / 安装窗口背景（改了素材才需要）：

```bash
swift scripts/make-icon.swift Sources/HomeworkMac/Resources/badge.png Resources
swift scripts/make-dmg-background.swift build/dmg-background.png 660 420
```

与 Windows 版（Tauri）的差异审计见 [PARITY.md](PARITY.md)。

## 数据契约

`fixtures/data.sample.json` 是两版共用的编解码契约样本（含旧版遗留字段），
Rust 侧 `store::tests::decodes_shared_fixture` 与 Swift 侧 `decodesCanonicalFixture` 各读一遍，
并断言双方**写出**的结构一致——数据互读不再只靠口头约定。

解码严格度对齐 Rust serde：

- 字段**缺失** → 用默认值（对齐容器级 `#[serde(default)]`）
- 显式 **null** 或**类型不符** → 整体加载失败，交给备份恢复（`loadOrRecover`）并提示，
  而不是静默退化成空数据；只有 Rust 声明为 `Option` 的字段（`copied_from_weekday`、`data_dir`）接受 null
- 旧字段（`created_date` 等）加载时忽略、写出时丢弃

> 早先的实现把上述情况一律回退默认值，`days` 一旦被写成 `null` 就会「加载成功但所有天都没了」，
> 且不触发备份恢复——现在这类结构损坏必定走恢复路径。

无界面出图（验证放映版式用）：

```bash
.build/release/HomeworkMac --export /tmp/slide.png --date 2026-09-30 --mode all --debug
#   --mode all|submit   --data <数据目录>   --debug 打印版式度量
```

## 结构

```
Sources/HomeworkKit/          纯逻辑（无 UI，可单测）
  Model.swift                 AppData / Day / 公告 / 设置（snake_case，与原版数据文件互通）
  Schedule.swift              课表合成、上学日推算、建议学科、ViewModel、周总览
  Store.swift                 数据目录、原子保存、滚动备份、损坏恢复、目录迁移、出图
  Holiday.swift               节假日规则：日历标题解析、问候语、休息日判定、调休提醒
Sources/HomeworkMac/          应用与界面
  HomeworkMacApp.swift        App/Scene/命令菜单/全局按键/外观
  AppState.swift              单一状态源：自动保存、自动出图、启动定位、焦点导航
  MainWindow.swift            侧边栏 + 工具栏 + 提示条
  EditPage.swift              公告 / 作业 / 演讲提醒 / 课表 四张卡片
  WeekPage.swift              本周总览 + 周课表模版编辑
  SettingsPage.swift          设置（常规 / 天数管理 / 节假日与调休 / 快捷键 / 关于）
  PresentWindow.swift         放映窗口（全屏、右键菜单、隐藏指针）
  Slide.swift                 放映画面与 PNG 导出（同一份视图，严格所见即所得）
  HolidayService.swift        EventKit 读取「中国大陆节假日」，缓存到磁盘
  Theme.swift / Badge.swift   配色、卡片样式、班徽墨迹裁剪
```

## 与原版的关系

- 数据文件格式完全一致（`data.json`，UTF-8、snake_case、`null` 照写），两个版本可互读；
  默认数据目录 `~/Documents/每日作业数据`，配置指针在 `~/Library/Application Support/每日作业/每日作业配置.ini`。
- 行为规则（页面日 / 显示日、「仅要交」、英语A/B、公告全局、启动定位、自动出图）与原版一致，
  视觉与交互按 macOS 习惯重做：侧边栏、统一工具栏、连续圆角卡片、SF Symbols、玻璃按钮、
  原生分段控件/日期选择/菜单，浅色为默认外观（可在设置里切换深色/跟随系统）。
- 新增：系统日历节假日识别（放假当天放映显示「国庆快乐 / 周末休息」并跳过作业，
  日历标注的调休上课日提前提醒新增这一天并确认是否调课）。

## 快捷键

| 按键 | 作用 |
| --- | --- |
| `F5` / `⌘↩` | 进入放映；放映中 `F5` / `Esc` / `⌘.` 退出 |
| `⌥1`~`⌥4` | 跳到 公告 / 作业 / 演讲 / 课表 |
| `⌥↑` `⌥↓` | 在条目之间上下切换 |
| `↩` | 新建下一条；`⌃↩` 标记当前条目 |
| `←` `→` | 切换上一天 / 下一天 |
| `⌘T` `⌘D` `⌘S` `⌘K` `⌘,` | 今天 / 出图 / 保存 / 课表总览 / 设置 |
