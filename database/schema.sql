-- 简谱译 (JianPuYi) 数据库架构
-- SQLite 3

-- 乐谱作品表
CREATE TABLE IF NOT EXISTS scores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    title TEXT DEFAULT '未命名乐谱',
    image_path TEXT,
    notes TEXT,                          -- JSON 格式音符序列
    key_sig TEXT DEFAULT '1=C',          -- 调号
    tempo INTEGER DEFAULT 85,            -- BPM
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_favorite INTEGER DEFAULT 0
);

-- 用户设置表
CREATE TABLE IF NOT EXISTS settings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    instrument TEXT DEFAULT 'Piano',     -- 默认乐器
    theme TEXT DEFAULT 'Dark'            -- 主题
);

-- 插入默认设置
INSERT INTO settings (instrument, theme) VALUES ('Piano', 'Dark');
