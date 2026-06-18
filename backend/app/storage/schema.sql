CREATE TABLE IF NOT EXISTS jobs (
    id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    type TEXT NOT NULL,
    status TEXT NOT NULL,
    input_path TEXT,
    output_path TEXT,
    metadata_json TEXT,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    error_msg TEXT
);

CREATE INDEX IF NOT EXISTS idx_jobs_device ON jobs(device_id, created_at DESC);

CREATE TABLE IF NOT EXISTS devices (
    device_id TEXT PRIMARY KEY,
    nickname TEXT,
    daily_budget_cny REAL DEFAULT 500.0,
    daily_video_limit INTEGER DEFAULT 10,
    preferred_style TEXT,
    enable_video INTEGER DEFAULT 1,
    enable_animate_old INTEGER DEFAULT 0,
    config_json TEXT,
    created_at INTEGER NOT NULL
);
