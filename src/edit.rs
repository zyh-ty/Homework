use crate::model::{Announcement, SUBJECTS};
use crate::schedule::{self, WEEKDAY_CN};
use crate::{App, AppMode};
use chrono::{Duration, NaiveDate};
use eframe::egui;

const PRIMARY: egui::Color32 = egui::Color32::from_rgb(36, 86, 166);
const RED: egui::Color32 = egui::Color32::from_rgb(208, 48, 48);
const CARD_STROKE: egui::Color32 = egui::Color32::from_rgb(226, 230, 238);
const MUTED: egui::Color32 = egui::Color32::from_rgb(122, 130, 142);

fn card(ui: &mut egui::Ui, add: impl FnOnce(&mut egui::Ui)) {
    let w = ui.available_width();
    egui::Frame::new()
        .fill(egui::Color32::WHITE)
        .stroke(egui::Stroke::new(1.0, CARD_STROKE))
        .corner_radius(egui::CornerRadius::same(12))
        .inner_margin(egui::Margin::same(16))
        .show(ui, |ui| {
            ui.set_min_width((w - 34.0).max(100.0));
            add(ui);
        });
}

fn card_title(ui: &mut egui::Ui, text: &str) {
    ui.label(egui::RichText::new(text).strong().size(22.0).color(PRIMARY));
}

fn subject_label(ui: &mut egui::Ui, subject: &str) {
    ui.add_sized(
        egui::vec2(84.0, 34.0),
        egui::Label::new(egui::RichText::new(subject).strong().size(19.0)),
    );
}

fn nav_dates(app: &App) -> Vec<NaiveDate> {
    let mut set: Vec<NaiveDate> = app
        .data
        .days
        .keys()
        .filter_map(|k| schedule::parse_date(k))
        .collect();
    let today = app.view_date;
    set.push(today);
    set.push(today + Duration::days(1));
    set.sort();
    set.dedup();
    set
}

fn nav_panel(app: &mut App, ui: &mut egui::Ui) {
    let today = chrono::Local::now().date_naive();
    let tomorrow = today + Duration::days(1);
    egui::ScrollArea::vertical().show(ui, |ui| {
        let dates = nav_dates(app);
        let mut week_key = String::new();
        for d in dates {
            let key = schedule::fmt_date(d);
            let wk = schedule::week_monday(d);
            let label = format!(
                "{}（{}）",
                schedule::week_monday(wk).format("%m/%d"),
                ""
            );
            let _ = label;
            let wk_str = wk.format("%Y-%m-%d").to_string();
            if wk_str != week_key {
                week_key = wk_str;
                ui.add_space(8.0);
                ui.label(
                    egui::RichText::new(format!("{} 当周", wk.format("%m月%d日")))
                        .strong()
                        .color(MUTED),
                );
            }
            let tag = if d == today {
                " · 今天"
            } else if d == tomorrow {
                " · 明天"
            } else {
                ""
            };
            let selected = d == app.view_date;
            let text = format!("{}{}", key, tag);
            if ui
                .selectable_label(selected, text)
                .clicked()
            {
                app.view_date = d;
                app.sync_day_rows();
            }
        }
    });
}

fn announcement_card(app: &mut App, ui: &mut egui::Ui) {
    card(ui, |ui| {
        card_title(ui, "公告");
        let mut remove: Option<usize> = None;
        let key = schedule::fmt_date(app.view_date);
        let visible_count = app
            .data
            .announcements
            .iter()
            .filter(|a| crate::layout::announcement_visible(a, &key))
            .count();
        let mut changed = false;
        for (i, a) in app.data.announcements.iter_mut().enumerate() {
            ui.horizontal(|ui| {
                let mut done = a.done;
                if ui.checkbox(&mut done, "").changed() {
                    a.done = done;
                    if done {
                        a.done_date = Some(key.clone());
                    } else {
                        a.done_date = None;
                    }
                    changed = true;
                }
                let mut text = a.text.clone();
                let w = ui.available_width() - 40.0;
                if ui
                    .add(egui::TextEdit::singleline(&mut text).desired_width(w.max(200.0)).font(egui::TextStyle::Body))
                    .changed()
                {
                    a.text = text;
                    changed = true;
                }
                if ui.button("✕").clicked() {
                    remove = Some(i);
                }
            });
        }
        if changed {
            app.mark_dirty();
        }
        if let Some(i) = remove {
            app.data.announcements.remove(i);
            app.mark_dirty();
        }
        ui.horizontal(|ui| {
            if ui.button("＋ 新增公告").clicked() {
                app.data.announcements.push(Announcement {
                    id: app.next_ann_id,
                    text: String::new(),
                    created_date: key.clone(),
                    done: false,
                    done_date: None,
                });
                app.next_ann_id += 1;
                app.mark_dirty();
            }
            ui.label(
                egui::RichText::new(format!("放映时显示 {} 条未完成公告；勾选完成即不再显示", visible_count))
                    .small()
                    .color(MUTED),
            );
        });
    });
}

fn homework_card(app: &mut App, ui: &mut egui::Ui) {
    let key = schedule::fmt_date(app.view_date);
    card(ui, |ui| {
        ui.horizontal(|ui| {
            card_title(ui, "作业");
            ui.label(
                egui::RichText::new("（按当天课表生成学科行，空行放映时不显示）")
                    .small()
                    .color(MUTED),
            );
        });
        let mut changed = false;
        let day = app.data.day(&key);
        let mut remove: Option<usize> = None;
        let rows: Vec<(String, String, bool)> = day
            .homework
            .iter()
            .map(|h| (h.subject.clone(), h.text.clone(), h.submit_next))
            .collect();
        for (i, (subject, text, submit_next)) in rows.iter().enumerate() {
            let subject = subject.clone();
            let mut text = text.clone();
            let mut submit_next = *submit_next;
            ui.horizontal(|ui| {
                subject_label(ui, &subject);
                let w = ui.available_width() - 170.0;
                let resp = ui.add(
                    egui::TextEdit::multiline(&mut text)
                        .desired_rows(1)
                        .desired_width(w.max(200.0))
                        .font(egui::TextStyle::Body),
                );
                if resp.changed() {
                    changed = true;
                }
                ui.checkbox(&mut submit_next, "明天交");
                if ui.button("✕").clicked() {
                    remove = Some(i);
                }
            });
            let day = app.data.day(&key);
            day.homework[i].text = text;
            day.homework[i].submit_next = submit_next;
        }
        if let Some(i) = remove {
            app.data.day(&key).homework.remove(i);
            changed = true;
        }
        // 添加其他学科
        let suggested = schedule::homework_suggestions(&app.data, &key);
        let remaining = schedule::remaining_subjects(&suggested);
        let existing: Vec<String> = app.data.day(&key).homework.iter().map(|h| h.subject.clone()).collect();
        let addable: Vec<&str> = remaining
            .into_iter()
            .filter(|s| !existing.iter().any(|e| e == s))
            .collect();
        if !addable.is_empty() {
            egui::ComboBox::from_label(egui::RichText::new("添加学科").size(17.0))
                .selected_text("选择…")
                .show_ui(ui, |ui| {
                    for s in addable {
                        if ui.selectable_label(false, s).clicked() {
                            app.data.day(&key).homework.push(crate::model::HomeworkItem::new(s));
                            changed = true;
                        }
                    }
                });
        }
        if changed {
            app.mark_dirty();
        }
    });
}

fn speech_card(app: &mut App, ui: &mut egui::Ui) {
    let key = schedule::fmt_date(app.view_date);
    let all_empty = app
        .data
        .days
        .get(&key)
        .map(|d| d.speeches.iter().all(|s| s.students.trim().is_empty()) || d.speeches.is_empty())
        .unwrap_or(true);
    card(ui, |ui| {
        ui.horizontal(|ui| {
            card_title(ui, "演讲提醒");
            if all_empty {
                ui.label(
                    egui::RichText::new("⚠ 演讲提醒未填写")
                        .strong()
                        .size(19.0)
                        .color(RED),
                );
            } else {
                ui.label(
                    egui::RichText::new("（按明天课表生成学科行）")
                        .small()
                        .color(MUTED),
                );
            }
        });
        let mut changed = false;
        let day = app.data.day(&key);
        let mut remove: Option<usize> = None;
        let rows: Vec<(String, String)> = day
            .speeches
            .iter()
            .map(|s| (s.subject.clone(), s.students.clone()))
            .collect();
        for (i, (subject, students)) in rows.iter().enumerate() {
            let mut students = students.clone();
            ui.horizontal(|ui| {
                subject_label(ui, subject);
                let w = ui.available_width() - 60.0;
                if ui
                    .add(egui::TextEdit::singleline(&mut students).desired_width(w.max(200.0)).hint_text("学号，如 22 32 或 4组").font(egui::TextStyle::Body))
                    .changed()
                {
                    changed = true;
                }
                if ui.button("✕").clicked() {
                    remove = Some(i);
                }
            });
            app.data.day(&key).speeches[i].students = students;
        }
        if let Some(i) = remove {
            app.data.day(&key).speeches.remove(i);
            changed = true;
        }
        let suggested = schedule::speech_suggestions(&app.data, &key);
        let existing: Vec<String> = app.data.day(&key).speeches.iter().map(|s| s.subject.clone()).collect();
        let addable: Vec<&str> = schedule::remaining_subjects(&suggested)
            .into_iter()
            .filter(|s| !existing.iter().any(|e| e == s))
            .collect();
        if !addable.is_empty() {
            egui::ComboBox::from_label(egui::RichText::new("添加学科").size(17.0))
                .selected_text("选择…")
                .show_ui(ui, |ui| {
                    for s in addable {
                        if ui.selectable_label(false, s).clicked() {
                            app.data.day(&key).speeches.push(crate::model::SpeechEntry::new(s));
                            changed = true;
                        }
                    }
                });
        }
        if changed {
            app.mark_dirty();
        }
    });
}

fn schedule_card(app: &mut App, ui: &mut egui::Ui) {
    let key = schedule::fmt_date(app.view_date);
    card(ui, |ui| {
        card_title(ui, "当天课表（调课红色显示，改回即恢复）");
        let mut changed = false;
        let weekday = schedule::weekday_index(app.view_date);
        let template: Vec<String> = (0..9)
            .map(|i| {
                app.data
                    .weekly_schedule
                    .get(weekday)
                    .and_then(|v| v.get(i))
                    .cloned()
                    .unwrap_or_default()
            })
            .collect();
        let overrides: Vec<Option<String>> = app
            .data
            .days
            .get(&key)
            .map(|d| d.schedule_override.clone())
            .unwrap_or_else(|| vec![None; 9]);
        egui::Grid::new("sched_grid").num_columns(5).show(ui, |ui| {
            for i in 0..9 {
                let cur = overrides
                    .get(i)
                    .cloned()
                    .flatten()
                    .unwrap_or_else(|| template[i].clone());
                let is_override = overrides.get(i).cloned().flatten().is_some();
                ui.label(format!("{}.", i + 1));
                let mut selected = cur.clone();
                egui::ComboBox::from_id_salt(("slot", i))
                    .selected_text(if is_override {
                        egui::RichText::new(&cur).color(RED)
                    } else {
                        egui::RichText::new(if cur.is_empty() { "（空）" } else { &cur })
                    })
                    .show_ui(ui, |ui| {
                        if ui
                            .selectable_label(cur.is_empty(), "（空）")
                            .clicked()
                        {
                            selected.clear();
                        }
                        for s in SUBJECTS {
                            if ui.selectable_label(&cur == s, *s).clicked() {
                                selected = s.to_string();
                            }
                        }
                    });
                if selected != cur {
                    let day = app.data.day(&key);
                    if selected.is_empty() && template[i].is_empty() {
                        day.schedule_override[i] = None;
                    } else if selected == template[i] {
                        day.schedule_override[i] = None;
                    } else if selected.is_empty() {
                        day.schedule_override[i] = None;
                    } else {
                        day.schedule_override[i] = Some(selected);
                    }
                    changed = true;
                }
                if (i + 1) % 3 == 0 {
                    ui.end_row();
                }
            }
        });
        if changed {
            app.mark_dirty();
            app.sync_day_rows();
        }
    });
}

fn toolbar(app: &mut App, ui: &mut egui::Ui) {
    ui.horizontal_wrapped(|ui| {
        if ui.button("← 前一天").clicked() {
            app.view_date -= Duration::days(1);
            app.sync_day_rows();
        }
        if ui.button("后一天 →").clicked() {
            app.view_date += Duration::days(1);
            app.data.day(&schedule::fmt_date(app.view_date));
            app.sync_day_rows();
        }
        let today = chrono::Local::now().date_naive();
        let tag = if app.view_date == today {
            "（今天）"
        } else if app.view_date == today + Duration::days(1) {
            "（明天）"
        } else {
            ""
        };
        ui.label(
            egui::RichText::new(format!(
                "{} {} {}",
                schedule::fmt_date(app.view_date),
                WEEKDAY_CN[schedule::weekday_index(app.view_date)],
                tag
            ))
            .strong()
            .size(22.0)
            .color(PRIMARY),
        );
        ui.separator();
        let mode_label = if app.submit_only { "显示：要交" } else { "显示：全部" };
        if ui.button(mode_label).on_hover_text("Ctrl+T").clicked() {
            app.submit_only = !app.submit_only;
        }
        if ui.button("▶ 放映 (F5)").clicked() {
            app.sync_day_rows();
            app.mode = AppMode::Present;
            ui.ctx().send_viewport_cmd(egui::ViewportCommand::Fullscreen(true));
        }
        if ui.button("生成图片 (Ctrl+S)").clicked() {
            app.save_now();
            match app.generate_image() {
                Ok(p) => app.set_status(format!("已生成：{}", p.display())),
                Err(e) => app.set_status(format!("生成失败：{}", e)),
            }
        }
        if ui.button("课表总览 (Ctrl+K)").clicked() {
            app.show_overview = true;
        }
        if ui.button("新增日期 (Ctrl+D)").clicked() {
            app.show_add_day = true;
        }
        if ui.button("删除日期").clicked() {
            app.confirm_delete = Some(schedule::fmt_date(app.view_date));
        }
        if ui.button("设置 (Ctrl+,)").clicked() {
            app.show_settings = true;
        }
    });
}

fn overview_window(app: &mut App, ctx: &egui::Context) {
    let mut open = app.show_overview;
    egui::Window::new("本周课表总览")
        .open(&mut open)
        .show(ctx, |ui| {
            let monday = schedule::week_monday(app.view_date);
            egui::Grid::new("overview").num_columns(6).show(ui, |ui| {
                ui.label("");
                for d in 0..5 {
                    let day = monday + Duration::days(d as i64);
                    ui.label(
                        egui::RichText::new(format!("{}\n{}", WEEKDAY_CN[d], day.format("%m/%d")))
                            .strong(),
                    );
                }
                ui.end_row();
                let key_of = |d: usize| schedule::fmt_date(monday + Duration::days(d as i64));
                for period in 0..9 {
                    ui.label(format!("{}", period + 1));
                    for d in 0..5 {
                        let key = key_of(d);
                        let ov = app
                            .data
                            .days
                            .get(&key)
                            .and_then(|day| day.schedule_override.get(period).cloned())
                            .flatten();
                        let tpl = app
                            .data
                            .weekly_schedule
                            .get(d)
                            .and_then(|v| v.get(period))
                            .cloned()
                            .unwrap_or_default();
                        let text = match ov {
                            Some(s) => egui::RichText::new(if s.is_empty() { "—".to_string() } else { s })
                                .color(RED),
                            None => egui::RichText::new(if tpl.is_empty() { "—".to_string() } else { tpl }),
                        };
                        ui.label(text);
                    }
                    ui.end_row();
                }
            });
        });
    app.show_overview = open;
}

fn settings_window(app: &mut App, ctx: &egui::Context) {
    let mut open = app.show_settings;
    let mut changed = false;
    egui::Window::new("设置").open(&mut open).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label("数据目录：");
            let dir = app
                .data
                .settings
                .data_dir
                .clone()
                .unwrap_or_else(|| app.store.dir.display().to_string());
            ui.label(&dir);
            if ui.button("更换…").clicked() {
                if let Some(new_dir) = rfd::FileDialog::new().pick_folder() {
                    match crate::store::migrate_data_dir(&app.exe_dir, &new_dir) {
                        Ok(new_store) => {
                            app.store = new_store;
                            app.data.settings.data_dir =
                                Some(app.store.dir.display().to_string());
                            app.set_status("数据目录已迁移".to_string());
                        }
                        Err(e) => app.set_status(format!("迁移失败：{}", e)),
                    }
                }
            }
        });
        ui.horizontal(|ui| {
            ui.label("图片生成间隔（秒）：");
            let mut v = app.data.settings.image_interval_secs;
            if ui.add(egui::DragValue::new(&mut v).range(0..=3600)).changed() {
                app.data.settings.image_interval_secs = v;
                changed = true;
            }
        });
        ui.horizontal(|ui| {
            ui.label("早 cut-off 时间（HH:MM）：");
            let mut t = app.data.settings.morning_cutoff.clone();
            if ui.add(egui::TextEdit::singleline(&mut t).desired_width(60.0)).changed() {
                app.data.settings.morning_cutoff = t;
                changed = true;
            }
        });
        let mut show_badge = app.data.settings.show_badge;
        if ui.checkbox(&mut show_badge, "显示班徽").changed() {
            app.data.settings.show_badge = show_badge;
            changed = true;
        }

        ui.separator();
        ui.label(egui::RichText::new("全局周课表（周一~周日 × 9 节）").strong());
        let mut sched_changed = false;
        egui::ScrollArea::both().max_height(320.0).show(ui, |ui| {
            egui::Grid::new("weekly_grid").num_columns(8).show(ui, |ui| {
                for d in 0..7 {
                    ui.label(egui::RichText::new(WEEKDAY_CN[d]).strong());
                    for i in 0..9 {
                        let mut cur = app
                            .data
                            .weekly_schedule
                            .get(d)
                            .and_then(|v| v.get(i))
                            .cloned()
                            .unwrap_or_default();
                        egui::ComboBox::from_id_salt(("w", d, i))
                            .width(64.0)
                            .selected_text(if cur.is_empty() { "—".to_string() } else { cur.clone() })
                            .show_ui(ui, |ui| {
                                if ui.selectable_label(cur.is_empty(), "—").clicked() {
                                    cur.clear();
                                }
                                for s in SUBJECTS {
                                    if ui.selectable_label(cur == *s, *s).clicked() {
                                        cur = s.to_string();
                                    }
                                }
                            });
                        if app
                            .data
                            .weekly_schedule
                            .get(d)
                            .and_then(|v| v.get(i))
                            .map(|x| *x != cur)
                            .unwrap_or(true)
                        {
                            if app.data.weekly_schedule.len() <= d {
                                app.data.weekly_schedule.resize(d + 1, Vec::new());
                            }
                            app.data.weekly_schedule[d].resize(9, String::new());
                            app.data.weekly_schedule[d][i] = cur;
                            sched_changed = true;
                        }
                    }
                    ui.end_row();
                }
            });
        });
        if sched_changed {
            changed = true;
            app.sync_day_rows();
        }
        if changed {
            app.mark_dirty();
        }
    });
    app.show_settings = open;
}

fn add_day_window(app: &mut App, ctx: &egui::Context) {
    let mut open = app.show_add_day;
    let mut create = false;
    egui::Window::new("新增日期（调休）").open(&mut open).show(ctx, |ui| {
        ui.horizontal(|ui| {
            ui.label("日期：");
            ui.add(egui::DragValue::new(&mut app.new_day.0).range(2020..=2100).prefix("年 "));
            ui.add(egui::DragValue::new(&mut app.new_day.1).range(1..=12).prefix("月 "));
            ui.add(egui::DragValue::new(&mut app.new_day.2).range(1..=31).prefix("日 "));
        });
        ui.horizontal(|ui| {
            ui.label("按周几的课：");
            egui::ComboBox::from_id_salt("from_wd")
                .selected_text(WEEKDAY_CN[app.new_day.3])
                .show_ui(ui, |ui| {
                    for d in 0..5 {
                        if ui.selectable_label(app.new_day.3 == d, WEEKDAY_CN[d]).clicked() {
                            app.new_day.3 = d;
                        }
                    }
                });
        });
        if ui.button("创建").clicked() {
            create = true;
        }
    });
    if create {
        if let Some(d) = NaiveDate::from_ymd_opt(app.new_day.0, app.new_day.1, app.new_day.2) {
            schedule::add_extra_day(&mut app.data, d, app.new_day.3);
            app.view_date = d;
            app.sync_day_rows();
            app.mark_dirty();
            app.set_status(format!("已新增 {}（按{}的课）", schedule::fmt_date(d), WEEKDAY_CN[app.new_day.3]));
            open = false;
        } else {
            app.set_status("日期无效".to_string());
        }
    }
    app.show_add_day = open;
}

fn delete_window(app: &mut App, ctx: &egui::Context) {
    let key = match app.confirm_delete.clone() {
        Some(k) => k,
        None => return,
    };
    let mut open = true;
    let mut do_delete = false;
    egui::Window::new("确认删除").collapsible(false).show(ctx, |ui| {
        ui.label(format!("确定要删除 {} 这一天的全部数据吗？", key));
        ui.horizontal(|ui| {
            if ui.button("删除").clicked() {
                do_delete = true;
                open = false;
            }
            if ui.button("取消").clicked() {
                open = false;
            }
        });
    });
    if do_delete {
        schedule::remove_day(&mut app.data, &key);
        app.mark_dirty();
        app.set_status(format!("已删除 {}", key));
    }
    if !open {
        app.confirm_delete = None;
    }
}

pub fn show(app: &mut App, ctx: &egui::Context) {
    egui::TopBottomPanel::top("toolbar")
        .frame(egui::Frame::new().fill(egui::Color32::WHITE).inner_margin(egui::Margin::symmetric(12, 8)))
        .show(ctx, |ui| {
        toolbar(app, ui);
        if app.font_missing {
            ui.label(
                egui::RichText::new("未找到中文字体，界面可能无法正常显示中文")
                    .color(RED),
            );
        }
    });
    egui::SidePanel::left("nav")
        .resizable(false)
        .default_width(220.0)
        .width_range(200.0..=240.0)
        .frame(egui::Frame::new().fill(egui::Color32::from_rgb(238, 241, 246)).inner_margin(egui::Margin::symmetric(12, 10)))
        .show(ctx, |ui| {
            ui.label(egui::RichText::new("天数导航").strong().size(22.0).color(PRIMARY));
            ui.add_space(4.0);
            nav_panel(app, ui);
        });
    egui::TopBottomPanel::bottom("statusbar")
        .frame(egui::Frame::new().fill(egui::Color32::WHITE).inner_margin(egui::Margin::symmetric(12, 6)))
        .show(ctx, |ui| {
        ui.horizontal(|ui| {
            if !app.status.is_empty() {
                ui.label(egui::RichText::new(&app.status).color(PRIMARY));
            }
            if app.dirty {
                ui.label(egui::RichText::new("● 未保存修改").small().color(MUTED));
            }
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                ui.label(
                    egui::RichText::new(
                        "F5 放映 | ←/→ 翻页 | Ctrl+T 要交/全部 | Ctrl+K 课表总览 | Ctrl+, 设置 | Ctrl+S 保存+出图 | Ctrl+D 新增日期",
                    )
                    .small()
                    .color(MUTED),
                );
            });
        });
    });
    egui::CentralPanel::default()
        .frame(egui::Frame::new().fill(egui::Color32::from_rgb(245, 246, 248)).inner_margin(egui::Margin::symmetric(14, 12)))
        .show(ctx, |ui| {
        app.sync_day_rows();
        egui::ScrollArea::vertical().show(ui, |ui| {
            announcement_card(app, ui);
            ui.add_space(10.0);
            homework_card(app, ui);
            ui.add_space(10.0);
            speech_card(app, ui);
            ui.add_space(10.0);
            schedule_card(app, ui);
            ui.add_space(10.0);
        });
    });
    overview_window(app, ctx);
    settings_window(app, ctx);
    add_day_window(app, ctx);
    delete_window(app, ctx);
}
