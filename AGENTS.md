# AGENTS.md — 每日作业客户端

## 架构

Tauri 2 + Vue 3（TypeScript + Vite）。**领域状态单一事实源在 Rust 后端**；前端只做渲染与交互，
通过 `invoke` 发变更命令、订阅 `state-changed` 事件拿完整快照（AppData，几 KB）。

```
src-tauri/src/
  main.rs      入口、AppState、全部 Tauri 命令、后台线程（1s 防抖自动保存 / 自动出图触发）、关窗保存
  model.rs     serde 数据模型（AppData/Day/HomeworkItem/SpeechEntry/Announcement/Settings）
  store.rs     持久化：ini 指针、原子保存(tmp+fsync+rename)、滚动备份、损坏恢复、目录迁移
  schedule.rs  默认周课表、当日 override 合成、调休来源、学科建议（英语→英语A/B）、
               上一上学日、公告可见性、启动定位 launch_view、演讲空检测
src/
  api.ts       invoke 封装、全局 store/view/vm、toast、整页路由 ui.page（edit|settings|week）
  draft.ts     当前编辑天的草稿（watch view.date 重载，300ms 防抖 set_day）；ALL_SUBJECTS
  layout.ts    排版引擎：ViewModel → DrawCmd[]（1920×1080 设计画布，与渲染无关）
  render-canvas.ts  DrawCmd → Canvas2D（放映屏幕与导出 PNG 共用，严格 WYSIWYG）
  image.ts     生成「今天·全部」画面 → PNG 字节 → export_image 命令
  views/EditView.vue     编辑页（工具栏/天数导航/显示滑块/卡片）
  views/PresentView.vue  放映页（等比缩放 + 黑边 letterbox，禁切换；右键菜单可切模式/出图/退出）
  views/SettingsView.vue 设置整页：常规 / 天数管理 / 快捷键 / 关于
  views/WeekView.vue     课表总览整页：7×9 本周总览 + 周课表模版编辑
  components/  公告/作业/演讲/课表卡片
  components/ui/  Segmented.vue（分段滑块）、Select.vue（自绘下拉）
  nav.ts       条目级键盘导航：Alt+1~4 跳分区、Alt+↑↓ 在 [data-nav] 之间移动
```

关键约束：**排版与渲染分离**。layout.ts 只输出 `DrawCmd`（rect/text/image），
render-canvas.ts 负责屏幕与导出两条路径。新增视觉元素只改 layout.ts。

## 数据 schema（UTF-8 JSON，字段 snake_case）

```jsonc
{
  "version": 1,
  "weekly_schedule": [["语文","数学", …9节], …7天],   // index 0=周一，周六日为空
  "days": {
    "2026-10-01": {
      "schedule_override": [null, "体育", …],           // 长度9，null=用模版，Some=调课(红)
      "homework": [{"subject","text","submit_next"}],   // 同一 subject 可出现多条
      "speeches": [{"subject","students"}],
      "copied_from_weekday": null                       // 调休来源（0=周一）
    }
  },
  "announcements": [{"id","text","done"}],
  "settings": {"data_dir": null, "image_interval_secs": 60, "morning_cutoff": "08:00",
               "show_badge": true}
}
```

## 存储

- `exe同级/每日作业配置.ini`：`data_dir=路径` 一行；不存在则默认 `exe同级/每日作业数据/`。
- 保存：pretty JSON → `data.json.tmp`（flush + sync_all）→ rename 原子替换；保存前把旧
  `data.json` 复制到 `backups/data_YYYYMMDD_HHMMSS.json`，修剪为最近 30 份且同一天只留最新。
- 加载失败 → 按文件名新到旧尝试 backups，成功则回写主文件并 toast 提示。
- 换数据目录（store::migrate_data_dir）：对话框选目录 → 递归复制 → 校验可加载 → 才写 ini；旧目录保留。
- 自动保存：任何变更命令置 dirty，后台线程 1 秒防抖落盘；`CloseRequested` 时也保存。

## 行为规则要点

1. 作业建议 = 当天有效课表去重（"英语"拆 英语A/英语B）；演讲建议 = **下一上学日**课表去重。空内容不显示。
2. 一个学科可有多条作业（`homework` 里同一 subject 可重复出现），每条各自 `submit_next`。
   放映编号：英语A/英语B 合占一个编号（两行）；同一学科的多条在同一行内用「序号 + 空格」分隔并自动
   换行，**只有一条时不显示序号**，「明天交」紧跟在对应条目之后。分组与排布逻辑都在 layout.ts。
   只有一边有内容的英语只占一行。「仅要交」模式只保留 submit_next 的条目并重新从 1 编号。
3. 公告是**全局一列、不分日期**：`announcement_visible(a) = !a.done`，所有日期看到的是同一份公告列表，
   勾选完成后放映不再显示（可取消）。**没有「自动完成」机制**，公告会一直留着，直到手动勾完或删除。
   `Announcement` 只有 `{id, text, done}`；旧的 `created_date`/`done_date`/`last_seen_date` 已被移除，
   旧数据文件靠 serde 忽略未知字段继续可用（回归用例：store.rs 的 `ignores_legacy_fields_on_load`）。
4. **日期模型**：页面日 `date` = **作业所属的那一天**（编辑页正在编辑的就是这一天）；`submit_only`
   只决定「画面上的日期」和作业过滤——全部 → `display_date = date`；仅要交 → `display_date =
   next_school_day(date)`。两种情况作业都取自 `date`（仅要交只留 `submit_next`），课表与公告用
   `display_date`，作业建议用 `date`（编辑页预填学科要是本页日的课），演讲建议用 `date` 的下一上学日。
   所以**切换全部/仅要交不会换天**，正在编辑的草稿不会被切走（曾经的实现会改 `view.date`，导致切一次
   往回跳一天、看起来像数据被清空）。
5. 上一/下一上学日（schedule::prev_school_day / next_school_day，同一份 step_school_day）：工作日，
   或 `days` 中存在条目的调休上学日。周五的下一日是周一；周日有课时 周五→周日、周日→周一。
6. 启动/重定位（schedule::launch_view）：早于 morning_cutoff → 页面日 = 上一上学日 + 仅要交
   （于是画面显示今天、作业是上一日勾了明天交的）；晚于 → 今天 + 全部。前端 30s tick，
   仅在用户未手动偏离自动定位时跟随跨越；Ctrl+T 重新回到自动定位结果。
7. 演讲全空 → 放映页演讲区显示「⚠ 演讲提醒未填写」，编辑页顶部红色横幅。
8. 出图：后台线程在「距上次 > image_interval_secs 且 image_dirty 且非放映中」时向前端发
   `auto-image-request`；前端渲染今天「全部」画面回传字节 → 写 `exe同级/家庭作业_今天.png` 并删除
   其他日期的家庭作业图片。Ctrl+D/工具栏可手动出图。
9. 放映中锁定天数切换；F5/Esc 退出。工具栏不再有「新增天数/删除天数」，改到设置页天数管理。
   编辑页键盘操作（全局在 App.vue，条目级在各卡片，导航工具在 nav.ts）：`Alt+1~4` 跳到
   公告/作业/演讲/课表的第一项（靠 `[data-nav]` 的 DOM 顺序，也就是阅读顺序）；`Enter` 在当前
   输入框新建下一条（公告=新公告，作业=同学科再加一条并聚焦，演讲=补下一个学科，课表=下一节）；
   `Ctrl+Enter` 标记当前条目（作业「明天交」/ 公告「完成」）；`Alt+↑/↓` 在条目间上下移动。
   其余：F5 放映、Esc 返回编辑页、Ctrl+T 今天、Ctrl+K 课表总览、Ctrl+, 设置、Ctrl+S 保存、Ctrl+D 出图、←→ 切天。
10. 启动流程：窗口以 `visible: false` + 最大化（还原尺寸 1280×800）创建，底色 `#eef2f9`；前端
   `onMounted` 并行完成徽标解码 / `get_state` / 事件订阅后调 `frontend_ready` 才 `show()`，
   Rust 侧另有 3 秒兜底 show，避免前端异常时窗口永不出现。

## 视图模型

前端渲染所需的一切由 `get_view_model(date, submit_only)` 一条命令算出：`date` 是页面日（作业所属），
`display_date` 是画面上显示的日期，课表/公告按 `display_date`、作业与作业建议按 `date`、演讲建议按
`date` 的下一上学日。前端不重算领域规则（切换全部/仅要交只改 `view.submitOnly` 再重取）。课表总览用 `get_week(monday)`。

## 构建 / 测试

```bash
npm install
npm run build              # 仅前端 → dist/
cd src-tauri && cargo test # 27 个单元测试（store/schedule，含 fixtures/ 共享契约）
npm run tauri build        # 完整发布构建 → src-tauri/target/release/homework-client.exe
cp src-tauri/target/release/homework-client.exe 每日作业.exe
npm run tauri dev          # 开发模式
```

重新生成应用图标（只有改了班徽素材才需要）：

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/make-icons.ps1
```

注意：本机 cargo registry 走 aliyun sparse 镜像；npm 如拉取失败可切 npmmirror。
运行依赖系统 WebView2（Win11/新版 Win10 自带）。图标脚本依赖 Windows PowerShell 5.1 的
`System.Drawing`，不引入任何新依赖。

## 代码约定

- 中文 UI 文案；标识符英文 snake_case（Rust）/ camelCase（TS）。
- 不写解释性注释；代码与 git 历史自解释。
- 提交信息 conventional 风格中文：`feat:` / `fix:` / `chore:` / `docs:`；不提交 target/、node_modules/、dist/。
- 不新增计划外依赖；无网络功能。

## 已知取舍

- 编辑页布局：两列网格（作业 | 右列），公告卡单独占一行；右列里演讲提醒与课表**上下排布**，两者内部
  各自两列（`.card-body` 是 `1fr 1fr` 网格）。`grid-template-rows: auto minmax(0, 1fr)` 配
  `.card-body { flex:1; min-height:0; overflow-y:auto }`，让卡片内部滚动、**页面任何窗口尺寸都不出现
  滚动条**；公告区固定显示 4 行（行高固定 34px，切断正好落在行边界，其余在块内滚动）。
- DrawCmd::text 的 `y` 是**墨迹垂直中心**（不是基线）：render-canvas 用 `textBaseline="middle"`
  再补 `size * 0.07`，因为「Microsoft YaHei」的中文字形墨迹中心比 em 盒中心高约 0.07em。
  不补这一下，所有以 y 为视觉中心的元素都会整体偏上，多行文本的上下留白也会不相等。
- `DrawCmd::image` 按**素材墨迹范围**等比居中（render-canvas 在 loadBadge 时量出透明边距），
  否则素材自带的非对称留白会让「按框居中」变成视觉偏心（班徽素材上边距 18% / 下边距 13%）。
- 文字换行按字符贪心切分（CJK 友好），测量用屏幕同一 Canvas 引擎，导出严格 WYSIWYG。
- 放映版式（layout.ts，1920×1080，外边距 28）：顶部蓝色标题带（班徽 + 日期/星期）；公告条
  **只在有公告时才画**（琥珀底、无「公告」标签，行首「• 」宽度要在换行宽度里预留，否则整行顶出边界）；
  左列作业卡（编号徽章 + 学科内多条作业行内排布，`flow()` 负责字符级贪心换行与「明天交」胶囊整体不拆）；右列课表两栏编号行
  （1-5 左列 / 6-9 右列）+ 演讲提醒（学科标签字号固定，学号首位钉在同一缩进）。右列高度先满足
  课表（行距/字号可按可用高度自适应收缩）与演讲（字号在 36/32/28/26/24 里挑最大放得下的）。
  字号基准：公告 52（最大，主视觉），面板标题 36，作业自适应 28~46，课表行 40，演讲 36。
- 编辑卡片共享一份 `draft`（draft.ts），300ms 防抖整体 set_day；防抖快照按编辑时的日期保存，切天先 flush。
  快照必须 `structuredClone(toRaw(x))`：Vue 响应式是 Proxy，`structuredClone` 按规范拒绝 Proxy（DataCloneError）。
- 天数导航列出 days 中已有天 + 今天 + 明天；被删除的天从导航消失；调休来源在设置页天数管理里改。
- 单 exe 指不打包安装器；运行时需系统 WebView2。窗口 `additionalBrowserArgs` 强制 `direct://` 绕过系统代理，
  防止教室机代理把 `http://tauri.localhost` 拦成「无法访问」。
- **不要直接运行 `cargo build` 出的 debug exe**：dev profile 下页面走 devUrl（http://localhost:1420），
  没有 vite dev server 时 WebView2 会显示「无法访问」；开发一律 `npm run tauri dev`，交付用 `npm run tauri build` 的 release exe（windows subsystem，无控制台窗口）。
- release 用 thin LTO + codegen-units=4 + strip + panic=abort（fat LTO 单编译单元在本机要 50 分钟以上，
  UI 应用无感收益）。前端 `build.target = esnext`（WebView2 是近期 Chromium）。
- 图标：`icon.ico` 每帧必须按 Windows 惯例编码——16/20/24/32/40/48/64/96/128 用 32bpp DIB、256 用 PNG；
  脚手架给的那份全是 PNG 帧且缺 20/40/96/128，会让任务栏与资源管理器抽到不同帧而显示不一致。
  换 exe 后若仍显示旧图标，是 Windows 图标缓存（`tauri.conf.json` 的 version 影响 exe 版本资源，
  bump 版本可强制刷新；必要时 `ie4uinit.exe -show`）。
