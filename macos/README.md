# 每日作业 · 原生 macOS 版（SwiftUI）

原 Windows 客户端（Tauri + Vue）的 macOS 原生重写：SwiftUI + AppKit + EventKit，
一眼 macOS，放映画面按 1920×1080 设计稿等比缩放绘制，屏幕所见即导出的 PNG。

## 构建 / 运行

```bash
cd macos
swift test                     # 66 个单元测试（课表调度 / 存储 / 节假日 / 编解码契约 / 撤销栈 / 文件监听）
./scripts/build-app.sh         # 发布构建（universal：Intel + Apple Silicon）→ build/每日作业.app
open build/每日作业.app
./scripts/build-app.sh debug   # 调试构建
```

### Xcode 工程

`project.yml` 是工程定义的唯一来源，用 xcodegen 生成 `HomeworkMac.xcodeproj`
（app target `HomeworkApp` + 本地 SwiftPM 包 `HomeworkKit`）：

```bash
brew install xcodegen          # 已装可跳过
cd macos && xcodegen generate  # 改了 project.yml 或**新增/删除源文件**后都要跑一次
open HomeworkMac.xcodeproj     # ⌘R 运行；测测试用 HomeworkKit scheme（⌘U）
```

- `Support/Info.plist` 与 `Support/HomeworkMac.entitlements` 也由 xcodegen 生成，别手改。
- 两条构建路径共用 `Sources/`：Xcode 工程给能力/权限/公证用，`swift test` 与
  `build-app.sh` 给命令行与打包用；改完两边都过一遍。
- Xcode 工程里 app target 名为 `HomeworkApp`（产物仍是 `每日作业.app`）：
  叫 `HomeworkMac` 会和 SwiftPM 的可执行 target 撞名，Xcode 会把 scheme 解析到包那边去。

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
  Schedule.swift              课表合成、上学日推算、建议学科、ViewModel、周总览、早晨分界线时刻
  Store.swift                 数据目录、原子保存、滚动备份、损坏恢复、目录迁移、出图
  Holiday.swift               节假日规则：日历标题解析、问候语、休息日判定、调休提醒
  History.swift               快照式撤销栈（同一输入框内的连续编辑合并成一步）
  SlideText.swift             画面内容 → 文字版作业（发群用，样式与放映版式一致）
  DataFileWatcher.swift       监听数据目录，发现 data.json 被外部改动
Sources/HomeworkMac/          应用与界面
  HomeworkMacApp.swift        App/Scene/命令菜单（含撤销/重做）/全局按键/外观
  AppState.swift              单一状态源：撤销栈、自动保存、自动出图、启动定位、外部改动重载
  Presenter.swift             放映系统状态：禁止休眠、锁定切换、指定屏幕
  Clipboard.swift             剪贴板（PNG+TIFF / 文本+RTF）、分享面板、文字版富文本
  MainWindow.swift            侧边栏（含可拖出的缩略图）+ 工具栏 + 提示条
  EditPage.swift              公告 / 作业 / 演讲提醒 / 课表 四张卡片
  WeekPage.swift              本周总览 + 周课表模版编辑
  SettingsPage.swift          设置（常规 / 放映 / 天数管理 / 节假日与调休 / 快捷键 / 关于）
  PresentWindow.swift         放映窗口（全屏、指定屏幕与热插拔、右键菜单、隐藏指针）
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
- 出图语义与原版一致：**自动**出图固定「今天 · 全部」，文件名 `家庭作业_<今天>.png`；
  **手动**出图（`⌘D` / 工具栏 / 放映右键）导出当前屏幕所见，文件名用**页面日**（你选中的那一天）。
  图片写在数据目录（原版写在 exe 同级——macOS 上 `.app` 包内不可写，且会破坏签名）。
- 新增：系统日历节假日识别。**日历只做提示，不改动你的数据**：
  放假当天放映显示「国庆快乐 / 周末休息」问候（当天没有作业时），日历标注的调休上课日会提前提醒你
  新增这一天并确认上哪天的课。
  - 你**自己建过的那一天永远算上学日**——日历不会把有作业的那天当休息日跳过。
  - 日历只能「扣掉」假期，不能凭空添加课：调休上课日要你建天（一键加入会默认按最近一个上学日的
    课表填入，之后可在课表卡改成「上周几的课」），在那之前它不参与上一/下一上学日推算。
  - 法定节假日不再清空课表，画面与你数据里的课表模版一致。
- 原版没有、macOS 版独有的四件事（都只在本机生效，不改变数据契约）：**撤销/重做**、
  放映期间的**不熄屏/锁定切换/指定屏幕**、**复制图片与文字版/分享/拖拽**、
  **事件驱动的跨天重算与数据文件外部改动重载**。详见上面的对应小节。

## 放映

放映窗口独立成 Scene，进房即原生全屏；放映期间有三条系统级保障（设置 → 放映，只对本机生效，
不写进共享数据文件）：

- **不熄屏**：`ProcessInfo.beginActivity(.idleDisplaySleepDisabled)`，投影中途不会黑屏。
- **锁定切换**：`NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching]`，
  学生碰键盘也切不出去（`⌘⌥Esc` 强制退出保留，ESC / F5 / `⌘.` 退出放映）。
- **指定屏幕**：接投影后在设置里选定那块屏（或放映窗口右键「放映屏幕」），窗口会挪过去并重新全屏；
  投影热插拔时自动跟随——新插入的屏接管，拔掉的屏自动退回，指定的屏消失时回落到当前屏幕。
  设置项的变更立即生效，退出放映（含直接关窗）时全部复原。

## 复制 / 分享 / 拖拽

老师最常用的三条出口（都在工具栏「出图」下拉、`每日作业` 菜单和放映右键菜单里）：

| 动作 | 快捷键 | 说明 |
| --- | --- | --- |
| 复制图片 | `⇧⌘C` | 画面 PNG 写进剪贴板（同时给 `public.png` 与 `public.tiff`），直接粘进微信 |
| 复制文字版 | `⌥⌘C` | 纯文本 + RTF，学科加粗、多条作业带序号、「明天交」跟在条目后 |
| 分享… | — | `NSSharingServicePicker`：AirDrop / 信息 / 邮件（先落盘成 PNG，AirDrop 要的是文件） |

侧边栏底部的缩略图是**拖拽源**：直接拖进微信窗口即可发送（图片走 `NSItemProvider` 的 PNG 数据，
不用先去目录里找文件）；点一下等于 `⌘D` 出图。

文字版的内容与放映一致：日期 →【作业】→【演讲提醒】→【公告】，全空时给节日问候或「今天没有作业」；
课表不进文字版（每周固定，图片里有）。

## 事件驱动与外部改动

没有轮询定时器（早先是 30 秒 relocation tick + 2 秒出图 tick）：

- **跨天**（`NSCalendarDayChanged`）、**合盖唤醒**（`NSWorkspace.didWakeNotification`）、
  **改时钟/时区**（`NSSystemClockDidChange` / `NSSystemTimeZoneDidChange`）→ 重算「今天」与自动定位。
- **早晨分界线**只在跨越那一刻重算：按 `Schedule.nextCutoff` 排一个一次性定时（今天还没到就是今天 8:00，
  过了就是明天 8:00）。
- **自动出图**改成一次性定时：最后一次编辑满 `image_interval_secs` 秒才出图（放映中不打扰，
  退出放映时重新排队）。
- **数据文件外部改动**：监听数据目录（保存是 tmp+rename 原子替换，换的是目录项，所以盯目录），
  比对 `data.json` 的 inode/大小/修改时间，自己写完调 `acknowledge()` 刷新基线。
  无未保存改动时自动重载并提示；本机还有未保存改动时**不覆盖**，只提示，可用
  `文件 › 从磁盘重新载入`（`⌘R`）放弃本机改动载入外部版本。

## 撤销 / 重做

`⌘Z` / `⇧⌘Z`，菜单里带动作名（撤销 编辑作业 / 删除公告 / 删除天数 …）。

- 快照式：整份 `AppData` + 页面日，`UndoHistory` 在 `HomeworkKit` 里（可单测）。
- 每次变更的收口是 `AppState.touch()`：它保存「变更前」的基线快照，所以视图里任何一处改动都会进历史，
  不必逐个改动点写反向操作。
- 同一个输入框内的连续编辑按时间窗（2.5s）合并成一步，换字段、换天、撤销之后立刻断开；
  输入框名与合并键取自 `currentField`（鼠标点击也会同步），栈深 60。
- 删除天数、删除公告、删除作业条目都可撤销；换数据目录会清空历史（文件已经搬走了，撤销指针没意义）。

## 快捷键

| 按键 | 作用 |
| --- | --- |
| `F5` / `⌘↩` | 进入放映；放映中 `F5` / `Esc` / `⌘.` 退出 |
| `⌘Z` / `⇧⌘Z` | 撤销 / 重做 |
| `⇧⌘C` / `⌥⌘C` | 复制作业图片 / 复制文字版作业 |
| `⌥1`~`⌥4` | 跳到 公告 / 作业 / 演讲 / 课表 |
| `⌥↑` `⌥↓` | 在条目之间上下切换 |
| `↩` | 新建下一条；`⌃↩` 标记当前条目 |
| `←` `→` | 切换上一天 / 下一天 |
| `⌘T` `⌘D` `⌘S` `⌘R` `⌘K` `⌘,` | 今天 / 出图 / 保存 / 重新载入 / 课表总览 / 设置 |
