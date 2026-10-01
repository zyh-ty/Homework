use crate::model::AppData;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

pub const INI_NAME: &str = "每日作业配置.ini";
pub const DATA_DIR_NAME: &str = "每日作业数据";

pub fn exe_dir() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|x| x.to_path_buf()))
        .unwrap_or_else(|| PathBuf::from("."))
}

fn read_ini(path: &Path) -> Option<String> {
    let content = fs::read_to_string(path).ok()?;
    for line in content.lines() {
        if let Some(v) = line.strip_prefix("data_dir=") {
            let v = v.trim();
            if !v.is_empty() {
                return Some(v.to_string());
            }
        }
    }
    None
}

fn write_ini(path: &Path, data_dir: &str) -> std::io::Result<()> {
    let mut f = fs::File::create(path)?;
    writeln!(f, "data_dir={}", data_dir)?;
    f.flush()?;
    f.sync_all()
}

pub struct Store {
    pub dir: PathBuf,
}

impl Store {
    /// 解析数据目录：ini 指针 > 默认 exe同级/每日作业数据/。
    pub fn open(exe_dir: &Path) -> Store {
        let ini = exe_dir.join(INI_NAME);
        let dir = read_ini(&ini)
            .map(PathBuf::from)
            .unwrap_or_else(|| exe_dir.join(DATA_DIR_NAME));
        fs::create_dir_all(&dir).ok();
        Store { dir }
    }

    pub fn data_path(&self) -> PathBuf {
        self.dir.join("data.json")
    }

    pub fn backup_dir(&self) -> PathBuf {
        self.dir.join("backups")
    }

    /// 加载；主文件失败则从备份恢复。返回 (data, recovered)。
    pub fn load(&self) -> (AppData, bool) {
        match self.load_from(&self.data_path()) {
            Ok(d) => (d, false),
            Err(_) => {
                let mut recovered = false;
                let mut data = AppData::new();
                if let Ok(mut entries) = fs::read_dir(self.backup_dir()) {
                    let mut paths: Vec<PathBuf> = entries
                        .flatten()
                        .map(|e| e.path())
                        .filter(|p| p.extension().map(|e| e == "json").unwrap_or(false))
                        .collect();
                    paths.sort();
                    paths.reverse();
                    for p in paths {
                        if let Ok(d) = self.load_from(&p) {
                            data = d;
                            recovered = true;
                            break;
                        }
                    }
                }
                if recovered {
                    self.save(&data).ok();
                }
                (data, recovered)
            }
        }
    }

    fn load_from(&self, p: &Path) -> Result<AppData, Box<dyn std::error::Error>> {
        let text = fs::read_to_string(p)?;
        Ok(serde_json::from_str(&text)?)
    }

    /// 原子保存：旧文件先备份，写 tmp → flush+sync → rename，修剪备份。
    pub fn save(&self, data: &AppData) -> std::io::Result<()> {
        fs::create_dir_all(&self.dir)?;
        let data_path = self.data_path();
        if data_path.exists() {
            self.make_backup(&data_path)?;
        }
        let tmp = self.dir.join("data.json.tmp");
        {
            let mut f = fs::File::create(&tmp)?;
            let text = serde_json::to_string_pretty(data)
                .map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
            f.write_all(text.as_bytes())?;
            f.flush()?;
            f.sync_all()?;
        }
        fs::rename(&tmp, &data_path)?;
        self.prune_backups()
    }

    fn make_backup(&self, data_path: &Path) -> std::io::Result<()> {
        let bdir = self.backup_dir();
        fs::create_dir_all(&bdir)?;
        let stamp = chrono::Local::now().format("%Y%m%d_%H%M%S");
        let dest = bdir.join(format!("data_{}.json", stamp));
        fs::copy(data_path, dest)?;
        Ok(())
    }

    /// 保留最近 30 份；同一天的只保留最新（每天至少一份）。
    fn prune_backups(&self) -> std::io::Result<()> {
        let bdir = self.backup_dir();
        let mut paths: Vec<PathBuf> = match fs::read_dir(&bdir) {
            Ok(rd) => rd
                .flatten()
                .map(|e| e.path())
                .filter(|p| {
                    p.file_name()
                        .and_then(|n| n.to_str())
                        .map(|n| n.starts_with("data_") && n.ends_with(".json"))
                        .unwrap_or(false)
                })
                .collect(),
            Err(_) => return Ok(()),
        };
        paths.sort();
        let keep = if paths.len() > 30 {
            paths.split_off(paths.len() - 30)
        } else {
            paths.clone()
        };
        // 同一天只保留最新一份
        let mut seen_days: Vec<String> = Vec::new();
        let mut to_delete: Vec<PathBuf> = Vec::new();
        for p in keep.iter().rev() {
            let name = p.file_name().unwrap().to_string_lossy().to_string();
            let day = name[5..13].to_string();
            if seen_days.contains(&day) {
                to_delete.push(p.clone());
            } else {
                seen_days.push(day);
            }
        }
        let mut removed: Vec<PathBuf> = paths;
        removed.retain(|p| !keep.contains(p) || to_delete.contains(p));
        for p in removed {
            fs::remove_file(p).ok();
        }
        Ok(())
    }
}

/// 修改数据目录：复制全部数据 → 校验新目录可加载 → 写 ini。返回新 Store。
pub fn migrate_data_dir(exe_dir: &Path, new_dir: &Path) -> Result<Store, String> {
    if !new_dir.is_absolute() {
        return Err("请选择绝对路径".to_string());
    }
    let old = Store::open(exe_dir);
    fs::create_dir_all(new_dir).map_err(|e| e.to_string())?;
    let new_store = Store {
        dir: new_dir.to_path_buf(),
    };
    new_store.save(&AppData::new()).map_err(|e| e.to_string())?;
    if old.data_path().exists() {
        fs::copy(old.data_path(), new_store.data_path()).map_err(|e| e.to_string())?;
    }
    if old.backup_dir().exists() {
        copy_dir(&old.backup_dir(), &new_store.backup_dir()).map_err(|e| e.to_string())?;
    }
    let (data, _) = new_store.load();
    new_store.save(&data).map_err(|e| e.to_string())?;
    write_ini(&exe_dir.join(INI_NAME), &new_dir.to_string_lossy()).map_err(|e| e.to_string())?;
    Ok(new_store)
}

fn copy_dir(src: &Path, dst: &Path) -> std::io::Result<()> {
    fs::create_dir_all(dst)?;
    for e in fs::read_dir(src)? {
        let e = e?;
        let from = e.path();
        let to = dst.join(e.file_name());
        if from.is_dir() {
            copy_dir(&from, &to)?;
        } else {
            fs::copy(&from, &to)?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    fn tmpdir(tag: &str) -> PathBuf {
        let p = std::env::temp_dir().join(format!("hw_store_test_{}_{}", tag, std::process::id()));
        fs::remove_dir_all(&p).ok();
        p
    }

    fn make_data() -> AppData {
        let mut d = AppData::new();
        d.announcements.push(crate::model::Announcement {
            id: 1,
            text: "测试公告".into(),
            created_date: "2026-10-01".into(),
            done: false,
            done_date: None,
        });
        d
    }

    #[test]
    fn save_and_load() {
        let dir = tmpdir("roundtrip");
        let s = Store { dir: dir.clone() };
        let data = make_data();
        s.save(&data).unwrap();
        let (loaded, recovered) = s.load();
        assert!(!recovered);
        assert_eq!(loaded.announcements[0].text, "测试公告");
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn recover_from_backup_when_corrupt() {
        let dir = tmpdir("recover");
        let s = Store { dir: dir.clone() };
        let data = make_data();
        s.save(&data).unwrap();
        fs::write(s.data_path(), "{broken json").unwrap();
        let (loaded, recovered) = s.load();
        assert!(recovered);
        assert_eq!(loaded.announcements[0].text, "测试公告");
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn recover_from_backup_when_missing() {
        let dir = tmpdir("missing");
        let s = Store { dir: dir.clone() };
        s.save(&make_data()).unwrap();
        fs::remove_file(s.data_path()).unwrap();
        let (loaded, recovered) = s.load();
        assert!(recovered);
        assert_eq!(loaded.announcements.len(), 1);
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn backup_pruning() {
        let dir = tmpdir("prune");
        let s = Store { dir: dir.clone() };
        let mut data = make_data();
        s.save(&data).unwrap();
        for i in 0..40 {
            data.announcements[0].id = i;
            // 模拟不同时间戳：直接造备份文件
            let stamp = format!("202610{:02}_{:02}0000", i % 28 + 1, i % 24);
            let dest = s.backup_dir().join(format!("data_{}.json", stamp));
            fs::copy(s.data_path(), &dest).unwrap();
            std::thread::sleep(std::time::Duration::from_millis(5));
        }
        s.save(&data).unwrap();
        let files: Vec<_> = fs::read_dir(s.backup_dir())
            .unwrap()
            .flatten()
            .collect();
        assert!(files.len() <= 31, "backups: {}", files.len());
        fs::remove_dir_all(&dir).ok();
    }

    #[test]
    fn migrate_dir() {
        let exe = tmpdir("mig_exe");
        fs::create_dir_all(&exe).unwrap();
        let s = Store::open(&exe);
        let mut data = make_data();
        data.days.insert("2026-10-01".into(), Default::default());
        s.save(&data).unwrap();
        let new_dir = tmpdir("mig_new");
        let ns = migrate_data_dir(&exe, &new_dir).unwrap();
        let (loaded, _) = ns.load();
        assert!(loaded.days.contains_key("2026-10-01"));
        // ini 指针已写
        let ini = fs::read_to_string(exe.join(INI_NAME)).unwrap();
        assert!(ini.contains(new_dir.to_string_lossy().as_ref()));
        fs::remove_dir_all(&exe).ok();
        fs::remove_dir_all(&new_dir).ok();
    }

    #[test]
    fn default_dir_without_ini() {
        let exe = tmpdir("def_exe");
        fs::create_dir_all(&exe).unwrap();
        let s = Store::open(&exe);
        assert_eq!(s.dir, exe.join(DATA_DIR_NAME));
        fs::remove_dir_all(&exe).ok();
    }
}
