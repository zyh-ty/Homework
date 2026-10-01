use crate::model::AppData;
use std::fs;
use std::path::{Path, PathBuf};

const INI_NAME: &str = "每日作业配置.ini";
const DEFAULT_DIR: &str = "每日作业数据";
const DATA_FILE: &str = "data.json";
const MAX_BACKUPS: usize = 30;

pub fn exe_dir() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .unwrap_or_else(|| PathBuf::from("."))
}

fn ini_path() -> PathBuf {
    exe_dir().join(INI_NAME)
}

/// 数据目录：ini 指针优先，否则 exe 同级默认目录
pub fn data_dir() -> PathBuf {
    if let Ok(content) = fs::read_to_string(ini_path()) {
        for line in content.lines() {
            if let Some(v) = line.strip_prefix("data_dir=") {
                let v = v.trim();
                if !v.is_empty() {
                    return PathBuf::from(v);
                }
            }
        }
    }
    exe_dir().join(DEFAULT_DIR)
}

fn write_ini(dir: &Path) -> std::io::Result<()> {
    fs::write(ini_path(), format!("data_dir={}\n", dir.display()))
}

pub fn data_file(dir: &Path) -> PathBuf {
    dir.join(DATA_FILE)
}

fn backups_dir(dir: &Path) -> PathBuf {
    dir.join("backups")
}

pub fn load(dir: &Path) -> Result<AppData, String> {
    let path = data_file(dir);
    let text = fs::read_to_string(&path).map_err(|e| format!("读取 {} 失败：{e}", path.display()))?;
    let mut data: AppData =
        serde_json::from_str(&text).map_err(|e| format!("解析 {} 失败：{e}", path.display()))?;
    data.normalize();
    Ok(data)
}

/// 加载，失败时按备份新到旧恢复，成功则回写主文件；返回 (数据, 提示)
pub fn load_or_recover(dir: &Path) -> (AppData, Option<String>) {
    match load(dir) {
        Ok(d) => (d, None),
        Err(e) => {
            let mut candidates = list_backups(dir);
            candidates.sort_by(|a, b| b.cmp(a));
            for b in candidates {
                if let Ok(text) = fs::read_to_string(&b) {
                    if let Ok(mut data) = serde_json::from_str::<AppData>(&text) {
                        data.normalize();
                        let _ = fs::copy(&b, data_file(dir));
                        return (
                            data,
                            Some(format!("主数据损坏（{e}），已从备份 {} 恢复", b.file_name().unwrap_or_default().to_string_lossy())),
                        );
                    }
                }
            }
            (AppData::default(), Some(format!("数据文件不可用（{e}），已创建空数据")))
        }
    }
}

fn list_backups(dir: &Path) -> Vec<PathBuf> {
    let bd = backups_dir(dir);
    let mut out = Vec::new();
    if let Ok(rd) = fs::read_dir(&bd) {
        for e in rd.flatten() {
            let p = e.path();
            if p.extension().map(|x| x == "json").unwrap_or(false) {
                out.push(p);
            }
        }
    }
    out
}

/// 原子保存：先备份旧文件，写 tmp + fsync + rename；然后修剪备份
pub fn save(dir: &Path, data: &AppData) -> Result<(), String> {
    fs::create_dir_all(backups_dir(dir)).map_err(|e| e.to_string())?;
    let target = data_file(dir);
    if target.exists() {
        let stamp = chrono::Local::now().format("%Y%m%d_%H%M%S");
        let backup = backups_dir(dir).join(format!("data_{stamp}.json"));
        fs::copy(&target, &backup).map_err(|e| format!("备份失败：{e}"))?;
    }
    let tmp = dir.join("data.json.tmp");
    let json = serde_json::to_string_pretty(data).map_err(|e| e.to_string())?;
    {
        use std::io::Write;
        let mut f = fs::File::create(&tmp).map_err(|e| e.to_string())?;
        f.write_all(json.as_bytes()).map_err(|e| e.to_string())?;
        f.sync_all().map_err(|e| e.to_string())?;
    }
    fs::rename(&tmp, &target).map_err(|e| format!("替换数据文件失败：{e}"))?;
    prune_backups(dir);
    Ok(())
}

/// 保留最近 MAX_BACKUPS 份，且同一天只留最新
fn prune_backups(dir: &Path) {
    let mut files = list_backups(dir);
    files.sort();
    // files 按文件名排序即按时间排序（data_YYYYMMDD_HHMMSS）
    let mut keep_latest_per_day: std::collections::BTreeMap<String, PathBuf> = Default::default();
    for f in &files {
        let name = f.file_name().unwrap_or_default().to_string_lossy().to_string();
        let day = name.get(5..13).unwrap_or("").to_string();
        keep_latest_per_day.insert(day, f.clone());
    }
    let mut survivors: Vec<PathBuf> = keep_latest_per_day.into_values().collect();
    survivors.sort();
    while survivors.len() > MAX_BACKUPS {
        survivors.remove(0);
    }
    for f in files {
        if !survivors.contains(&f) {
            let _ = fs::remove_file(f);
        }
    }
}

fn copy_recursive(src: &Path, dst: &Path) -> std::io::Result<()> {
    fs::create_dir_all(dst)?;
    for e in fs::read_dir(src)? {
        let e = e?;
        let from = e.path();
        let to = dst.join(e.file_name());
        if from.is_dir() {
            copy_recursive(&from, &to)?;
        } else {
            fs::copy(&from, &to)?;
        }
    }
    Ok(())
}

/// 迁移数据目录：复制 → 校验可加载 → 写 ini；旧目录保留
pub fn migrate_data_dir(current: &Path, new_dir: &Path) -> Result<PathBuf, String> {
    if new_dir == current {
        return Err("新目录与当前目录相同".into());
    }
    copy_recursive(current, new_dir).map_err(|e| format!("复制数据失败：{e}"))?;
    load(new_dir).map_err(|e| format!("新目录数据校验失败：{e}"))?;
    write_ini(new_dir).map_err(|e| format!("写入配置失败：{e}"))?;
    Ok(new_dir.to_path_buf())
}

pub fn reset_ini() {
    let _ = fs::remove_file(ini_path());
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::HomeworkItem;

    fn temp_dir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("hwclient_test_{tag}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn sample() -> AppData {
        let mut d = AppData::default();
        let mut day = crate::model::Day::default();
        day.homework.push(HomeworkItem {
            subject: "语文".into(),
            text: "背书".into(),
            submit_next: true,
        });
        d.days.insert("2026-10-01".into(), day);
        d
    }

    #[test]
    fn save_and_load_roundtrip() {
        let dir = temp_dir("roundtrip");
        let d = sample();
        save(&dir, &d).unwrap();
        let loaded = load(&dir).unwrap();
        assert_eq!(loaded, d);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn backup_created_and_pruned_per_day() {
        let dir = temp_dir("backup");
        let mut d = sample();
        save(&dir, &d).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(1100));
        d.announcements.push(crate::model::Announcement {
            id: 1,
            text: "v2".into(),
            created_date: "2026-10-01".into(),
            done: false,
            done_date: None,
        });
        save(&dir, &d).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(1100));
        save(&dir, &d).unwrap();
        let backups = list_backups(&dir);
        assert_eq!(backups.len(), 1, "同一天只保留最新备份");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn recover_from_corrupt_main() {
        let dir = temp_dir("recover");
        let d = sample();
        save(&dir, &d).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(1100));
        save(&dir, &d).unwrap();
        fs::write(data_file(&dir), "{ 损坏").unwrap();
        let (recovered, notice) = load_or_recover(&dir);
        assert_eq!(recovered, d);
        assert!(notice.is_some());
        assert!(load(&dir).is_ok(), "恢复后应回写主文件");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn empty_dir_gives_default_with_notice() {
        let dir = temp_dir("empty");
        let (d, notice) = load_or_recover(&dir);
        assert!(d.days.is_empty());
        assert!(notice.is_some());
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn migrate_copies_and_verifies() {
        let src = temp_dir("migrate_src");
        let dst = temp_dir("migrate_dst");
        save(&src, &sample()).unwrap();
        migrate_data_dir(&src, &dst).unwrap();
        assert_eq!(load(&dst).unwrap(), sample());
        assert!(src.join(DATA_FILE).exists(), "旧目录保留");
        reset_ini();
        let _ = fs::remove_dir_all(&src);
        let _ = fs::remove_dir_all(&dst);
    }

    #[test]
    fn migrate_rejects_same_dir() {
        let src = temp_dir("migrate_same");
        save(&src, &sample()).unwrap();
        assert!(migrate_data_dir(&src, &src).is_err());
        let _ = fs::remove_dir_all(&src);
    }
}
