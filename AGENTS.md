# AGENTS.md — 每日作业客户端

## 架构

单一 binary crate（`homework-client`），eframe 0.32（glow-only，default-features 精简）+ egui 自绘 UI。

```
main.rs      入口、字体加载、App 状态、自动保存/自动出图/跨天检查、--selftest
model.rs     serde 数据模型（AppData/Day/HomeworkItem/SpeechEntry/Announcement/Settings）
store.rs     持久化：ini 指针、原子保存(tmp+fsync+rename)、滚动备份、损坏恢复、目录迁移
schedule.rs  周课表模版、当日 override、调休增删、学科建议推导（英语→英语A/B）、日期工具
layout.rs    排版引擎：输入一天数据 → Vec<DrawCmd>（1920×1080 设计画布，与渲染无关）
             文字测量/换行用 fontdue；板块自适应高度 + 字号二分；英语A/B 合并编号
present.rs   放映：把 DrawCmd 画到 egui Painter（等比缩放 + 黑边 letterbox），全屏无边框
export.rs    导出：同一批 DrawCmd 用 tiny-skia 光栅化到 1920×1080 PNG（字体 glyph 逐像素混合）
edit.rs      编辑界面：工具栏、天数导航、公告/作业/演讲/课表卡片、设置/总览/新增/删除窗口
keys.rs      快捷键映射（编辑页 F5/Ctrl+T/Ctrl+K/Ctrl+,/Ctrl+S/Ctrl+D/←→；放映页 F5/Esc）
```

关键约束：**排版与渲染分离**。layout.rs 只输出 `DrawCmd::{FillRoundRect, StrokeRoundRect, Text, Image}`，
present.rs 和 export.rs 各自解释。新增视觉元素时只改 layout.rs + 两个渲染器。

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
  "settings": {"data_dir": null, "image_interval_secs": 60, "morning_cutoff": "08:00", "show_badge": true}
}
```

## 存储格式

- `exe同级/每日作业配置.ini`：`data_dir=路径` 一行；不存在则默认 `exe同级/每日作业数据/`。
- 保存：pretty JSON → `data.json.tmp`（flush + sync_all）→ rename 原子替换；保存前把旧 `data.json`
  复制到 `backups/data_YYYYMMDD_HHMMSS.json`，修剪为最近 30 份且同一天只留最新。
- 加载失败 → 按文件名新到旧尝试 backups，成功则回写主文件并在 UI 提示。
- 换数据目录（store::migrate_data_dir）：rfd 选目录 → 递归复制 → 校验可加载 → 才写 ini；旧目录保留。
- 自动保存：修改置 dirty，1 秒防抖落盘；`on_exit` 也保存。

## 行为规则要点

1. 作业建议行 = 当天课表去重（"英语"拆成 英语A/英语B）；演讲建议 = **明天**课表去重。空行放映不显示。
2. 放映编号：英语A/英语B 合占一个编号（两行）；只有一边有内容则只占一行。
3. 公告可见性：`created_date <= 查看日 && (!done || done_date > 查看日)`。每天首次以"今天"打开时，
   把 `created_date < 今天` 且未完成的公告自动 done（done_date=今天），可手动取消。
4. 启动定位：早于 morning_cutoff → "只显示要交"模式（作业来自上一上学日 submit_next，日期/课表/公告仍是今天）；
   晚于 cutoff → 今天 + 全部。跨天/跨 cutoff 每分钟自动重定位。
5. 演讲全空 → 放映/编辑都显示 "⚠ 演讲提醒未填写"。
6. 图片：距最后修改超过 image_interval_secs 且有 dirty → 生成 `exe同级/家庭作业_今天.png`
   （今天"显示全部"画面）并清理旧图；放映中不自动生成；今天无作业内容仍生成（空状态图）。

## 字体

启动时依次尝试 `C:\Windows\Fonts\{msyh.ttc, simhei.ttf, simsun.ttc, Deng.ttf}`（粗体：`msyhbd.ttc` → `simhei.ttf`）。
TTC 集合通过 `index` 字段加载（egui `FontData{index}` 与 fontdue `collection_index` 均支持），egui 侧注册
regular 到 Proportional 族、粗体到 `FontFamily::Name("bold")` 族；fontdue 两份实例供排版测量与 PNG 导出。
全部失败 → egui 默认字体 + 界面顶部红色提示。不内嵌字体文件。

## 构建 / 测试

```bash
cargo test                 # 18 个单元测试（store/schedule/layout）
cargo build --release      # target/release/homework-client.exe（LTO fat、单 codegen-unit、strip）
cp target/release/homework-client.exe 每日作业.exe
./target/debug/homework-client.exe --selftest   # 无窗口自检，退出码 0 即通过
```

注意：本机 cargo registry 已切换为 aliyun sparse 镜像（~/.cargo/config.toml），git 协议镜像不可用。

## 代码约定

- 中文 UI 文案；标识符英文 snake_case。
- 不写解释性注释；代码与 git 历史自解释。
- 提交信息 conventional 风格中文：`feat:` / `fix:` / `chore:` / `docs:`；不提交 target/。
- 不新增 Cargo.toml 之外的依赖；无网络功能。

## 已知取舍

- DrawCmd::Text 的 `y` 一律是**基线**；垂直居中用 `LayoutFont::vcenter_baseline`（按字形实际包围盒计算，
  不要用 line metrics——msyh 的 hhea 值会导致明显偏移）。
- present.rs 放映用 egui 渲染（bold 走 "bold" 字体族），export.rs 用 fontdue 逐 glyph 混合，两者同源于 layout.rs。
- 天数导航只列 days 中已有天 + 今天 + 明天；"已删除"的天从导航消失（无法追踪）。
- 课间序号在课表卡片中与学科同行显示（`"1 语文"` 分两列布局）。
- debug 构建下 egui 会对新 widget 显示 "First use of widget ID" 红色提示，release 无此现象。
