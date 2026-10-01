# AGENTS.md — 每日作业客户端

## 架构

Tauri 2 + Vue 3（TypeScript + Vite）。**领域状态单一事实源在 Rust 后端**；前端只做渲染与交互，
通过 `invoke` 发变更命令、订阅 `state-changed` 事件拿完整快照（AppData，几 KB）。

```
src-tauri/src/
  main.rs      入口、AppState、全部 Tauri 命令、后台线程（1s 防抖自动保存 / 跨天重定位 /
               公告自动完成 / 自动出图触发）、关窗保存
  model.rs     serde 数据模型（AppData/Day/HomeworkItem/SpeechEntry/Announcement/Settings）
  store.rs     持久化：ini 指针、原子保存(tmp+fsync+rename)、滚动备份、损坏恢复、目录迁移
  schedule.rs  默认周课表、当日 override 合成、调休来源、学科建议（英语→英语A/B）、
               上一上学日、公告可见性、启动定位 launch_view、演讲空检测
src/
  api.ts       invoke 封装、全局 store/view/vm、toast、对话框开关 ui
  draft.ts     当前编辑天的草稿（watch view.date 重载，300ms 防抖 set_day）；ALL_SUBJECTS
  layout.ts    排版引擎：ViewModel → DrawCmd[]（1920×1080 设计画布，与渲染无关）
  render-canvas.ts  DrawCmd → Canvas2D（放映屏幕与导出 PNG 共用，严格 WYSIWYG）
  image.ts     生成「今天·全部」画面 → PNG 字节 → export_image 命令
  views/EditView.vue     编辑页（工具栏/天数导航/卡片）
  views/PresentView.vue  放映页（等比缩放 + 黑边 letterbox，禁切换）
  components/  公告/作业/演讲/课表卡片 + 设置/课表总览/新增天数/删除天数弹窗
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
      "homework": [{"subject","text","submit_next"}],
      "speeches": [{"subject","students"}],
      "copied_from_weekday": null                       // 调休来源（0=周一）
    }
  },
  "announcements": [{"id","text","created_date","done","done_date"}],
  "settings": {"data_dir": null, "image_interval_secs": 60, "morning_cutoff": "08:00",
               "show_badge": true, "last_seen_date": null}
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

1. 作业建议 = 当天有效课表去重（"英语"拆 英语A/英语B）；演讲建议 = **明天**课表去重。空内容不显示。
2. 放映编号：英语A/英语B 合占一个编号（两行）；只有一边有内容则只占一行。分组逻辑在 layout.ts。
3. 公告可见性：`created_date <= 查看日 && (!done || done_date > 查看日)`。后台线程发现
   `last_seen_date != 今天` 时，把 `created_date < 今天` 且未完成的公告自动 done（done_date=今天），可手动取消。
4. 启动/重定位（schedule::launch_view）：早于 morning_cutoff → 「只显示要交」（view_date=今天，
   homework_date=上一上学日，作业过滤 submit_next）；晚于 → 今天+全部。前端 30s tick，
   仅在用户未手动偏离自动定位时跟随跨越。手动关闭「仅要交」时切到 homework_date 的整天。
5. 演讲全空 → 放映页演讲区显示「⚠ 演讲提醒未填写」，编辑页顶部红色横幅。
6. 出图：后台线程在「距上次 > image_interval_secs 且 image_dirty 且非放映中」时向前端发
   `auto-image-request`；前端渲染今天「全部」画面回传字节 → 写 `exe同级/家庭作业_今天.png` 并删除
   其他日期的家庭作业图片。Ctrl+D/工具栏可手动出图。
7. 放映中锁定天数切换；F5/Esc 退出。编辑页快捷键：F5/Ctrl+T/Ctrl+K/Ctrl+,/Ctrl+S/Ctrl+D/←→。

## 视图模型

前端渲染所需的一切由 `get_view_model(date, submit_only)` 一条命令算出（课表合成、公告过滤、
作业过滤与来源日、建议学科、speech_warn），前端不重算领域规则。课表总览用 `get_week(monday)`。

## 构建 / 测试

```bash
npm install
npm run build              # 仅前端 → dist/
cd src-tauri && cargo test # 23 个单元测试（store/schedule）
npm run tauri build        # 完整发布构建 → src-tauri/target/release/homework-client.exe
cp src-tauri/target/release/homework-client.exe 每日作业.exe
npm run tauri dev          # 开发模式
```

注意：本机 cargo registry 走 aliyun sparse 镜像；npm 如拉取失败可切 npmmirror。
运行依赖系统 WebView2（Win11/新版 Win10 自带）。

## 代码约定

- 中文 UI 文案；标识符英文 snake_case（Rust）/ camelCase（TS）。
- 不写解释性注释；代码与 git 历史自解释。
- 提交信息 conventional 风格中文：`feat:` / `fix:` / `chore:` / `docs:`；不提交 target/、node_modules/、dist/。
- 不新增计划外依赖；无网络功能。

## 已知取舍

- DrawCmd::text 的 `y` 是**行垂直中心**，Canvas 用 `textBaseline="middle"` 绘制，不做基线换算。
- 文字换行按字符贪心切分（CJK 友好），测量用屏幕同一 Canvas 引擎，导出严格 WYSIWYG。
- 编辑卡片共享一份 `draft`（draft.ts），300ms 防抖整体 set_day；防抖快照按编辑时的日期保存，切天先 flush。
- 天数导航列出 days 中已有天 + 今天 + 明天；被删除的天从导航消失。
- 单 exe 指不打包安装器；运行时需系统 WebView2。窗口 `additionalBrowserArgs` 强制 `direct://` 绕过系统代理，
  防止教室机代理把 `http://tauri.localhost` 拦成「无法访问」。
- **不要直接运行 `cargo build` 出的 debug exe**：dev profile 下页面走 devUrl（http://localhost:1420），
  没有 vite dev server 时 WebView2 会显示「无法访问」；开发一律 `npm run tauri dev`，交付用 `npm run tauri build` 的 release exe（windows subsystem，无控制台窗口）。
- release 用 thin LTO + codegen-units=4（fat LTO 单编译单元在本机要 50 分钟以上，UI 应用无感收益）。
