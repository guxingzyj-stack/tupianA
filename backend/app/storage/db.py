from __future__ import annotations

import json
import sqlite3
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator
from uuid import uuid4

from app.config import get_settings


SCHEMA_PATH = Path(__file__).with_name("schema.sql")


def _resolve_db_path(db_path: str | None = None) -> str:
    return db_path or get_settings().db_path


def _connect(db_path: str | None = None) -> sqlite3.Connection:
    resolved = Path(_resolve_db_path(db_path))
    resolved.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(resolved))
    conn.row_factory = sqlite3.Row
    return conn


@contextmanager
def get_db(db_path: str | None = None) -> Iterator[sqlite3.Connection]:
    conn = _connect(db_path)
    try:
        yield conn
    finally:
        conn.close()


def init_db(db_path: str | None = None) -> None:
    schema = SCHEMA_PATH.read_text(encoding="utf-8")
    with get_db(db_path) as conn:
        conn.executescript(schema)
        conn.commit()


def _now() -> int:
    return int(time.time())


def _json_dumps(value: Any) -> str | None:
    if value is None:
        return None
    return json.dumps(value, ensure_ascii=False)


def _row_to_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    data = dict(row)
    metadata = data.get("metadata_json")
    config = data.get("config_json")
    if metadata:
        data["metadata"] = json.loads(metadata)
    else:
        data["metadata"] = {}
    if config:
        data["config"] = json.loads(config)
    elif "config_json" in data:
        data["config"] = {}
    return data


def create_job(
    device_id: str,
    job_type: str,
    *,
    status: str = "pending",
    input_path: str | None = None,
    output_path: str | None = None,
    metadata: dict[str, Any] | None = None,
    error_msg: str | None = None,
    job_id: str | None = None,
    db_path: str | None = None,
) -> dict[str, Any]:
    init_db(db_path)
    current = _now()
    new_id = job_id or str(uuid4())
    with get_db(db_path) as conn:
        try:
            conn.execute("BEGIN")
            conn.execute(
                """
                INSERT INTO jobs (
                    id, device_id, type, status, input_path, output_path,
                    metadata_json, created_at, updated_at, error_msg
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    new_id,
                    device_id,
                    job_type,
                    status,
                    input_path,
                    output_path,
                    _json_dumps(metadata),
                    current,
                    current,
                    error_msg,
                ),
            )
            conn.commit()
        except Exception:
            conn.rollback()
            raise
    job = get_job(new_id, db_path=db_path)
    assert job is not None
    return job


def update_job_status(
    job_id: str,
    status: str,
    *,
    input_path: str | None = None,
    output_path: str | None = None,
    metadata: dict[str, Any] | None = None,
    error_msg: str | None = None,
    db_path: str | None = None,
) -> dict[str, Any] | None:
    fields: list[str] = ["status = ?", "updated_at = ?"]
    values: list[Any] = [status, _now()]
    if input_path is not None:
        fields.append("input_path = ?")
        values.append(input_path)
    if output_path is not None:
        fields.append("output_path = ?")
        values.append(output_path)
    if metadata is not None:
        fields.append("metadata_json = ?")
        values.append(_json_dumps(metadata))
    if error_msg is not None:
        fields.append("error_msg = ?")
        values.append(error_msg)
    values.append(job_id)

    with get_db(db_path) as conn:
        try:
            conn.execute("BEGIN")
            conn.execute(f"UPDATE jobs SET {', '.join(fields)} WHERE id = ?", values)
            conn.commit()
        except Exception:
            conn.rollback()
            raise
    return get_job(job_id, db_path=db_path)


def get_job(job_id: str, *, db_path: str | None = None) -> dict[str, Any] | None:
    init_db(db_path)
    with get_db(db_path) as conn:
        row = conn.execute("SELECT * FROM jobs WHERE id = ?", (job_id,)).fetchone()
    return _row_to_dict(row)


def list_jobs_by_device(
    device_id: str,
    *,
    limit: int = 50,
    db_path: str | None = None,
) -> list[dict[str, Any]]:
    init_db(db_path)
    with get_db(db_path) as conn:
        rows = conn.execute(
            """
            SELECT * FROM jobs
            WHERE device_id = ?
            ORDER BY created_at DESC, rowid DESC
            LIMIT ?
            """,
            (device_id, limit),
        ).fetchall()
    return [item for row in rows if (item := _row_to_dict(row)) is not None]


def count_jobs_by_device_since(
    device_id: str,
    *,
    job_type: str,
    since_ts: int,
    db_path: str | None = None,
) -> int:
    init_db(db_path)
    with get_db(db_path) as conn:
        row = conn.execute(
            """
            SELECT COUNT(*) AS total
            FROM jobs
            WHERE device_id = ? AND type = ? AND created_at >= ?
            """,
            (device_id, job_type, since_ts),
        ).fetchone()
    return int(row["total"] if row else 0)


def list_jobs_by_device_since(
    device_id: str,
    *,
    since_ts: int,
    limit: int = 1000,
    db_path: str | None = None,
) -> list[dict[str, Any]]:
    init_db(db_path)
    with get_db(db_path) as conn:
        rows = conn.execute(
            """
            SELECT * FROM jobs
            WHERE device_id = ? AND created_at >= ?
            ORDER BY created_at DESC, rowid DESC
            LIMIT ?
            """,
            (device_id, since_ts, limit),
        ).fetchall()
    return [item for row in rows if (item := _row_to_dict(row)) is not None]


def list_jobs_since(
    since_ts: int,
    *,
    limit: int = 5000,
    db_path: str | None = None,
) -> list[dict[str, Any]]:
    init_db(db_path)
    with get_db(db_path) as conn:
        rows = conn.execute(
            """
            SELECT * FROM jobs
            WHERE created_at >= ?
            ORDER BY created_at DESC, rowid DESC
            LIMIT ?
            """,
            (since_ts, limit),
        ).fetchall()
    return [item for row in rows if (item := _row_to_dict(row)) is not None]


def list_jobs_older_than(
    cutoff_ts: int,
    *,
    db_path: str | None = None,
) -> list[dict[str, Any]]:
    init_db(db_path)
    with get_db(db_path) as conn:
        rows = conn.execute(
            """
            SELECT * FROM jobs
            WHERE created_at < ?
            ORDER BY created_at ASC
            """,
            (cutoff_ts,),
        ).fetchall()
    return [item for row in rows if (item := _row_to_dict(row)) is not None]


def delete_jobs_older_than(
    cutoff_ts: int,
    *,
    db_path: str | None = None,
) -> int:
    init_db(db_path)
    with get_db(db_path) as conn:
        try:
            conn.execute("BEGIN")
            cursor = conn.execute("DELETE FROM jobs WHERE created_at < ?", (cutoff_ts,))
            deleted = int(cursor.rowcount if cursor.rowcount is not None else 0)
            conn.commit()
            return deleted
        except Exception:
            conn.rollback()
            raise


def get_or_create_device(
    device_id: str,
    *,
    nickname: str | None = None,
    db_path: str | None = None,
) -> dict[str, Any]:
    init_db(db_path)
    with get_db(db_path) as conn:
        row = conn.execute("SELECT * FROM devices WHERE device_id = ?", (device_id,)).fetchone()
        if row:
            converted = _row_to_dict(row)
            assert converted is not None
            return converted

        try:
            conn.execute("BEGIN")
            conn.execute(
                """
                INSERT INTO devices (
                    device_id, nickname, daily_budget_cny, daily_video_limit,
                    preferred_style, enable_video, enable_animate_old,
                    config_json, created_at
                )
                VALUES (?, ?, 10.0, 10, NULL, 1, 0, NULL, ?)
                """,
                (device_id, nickname, _now()),
            )
            conn.commit()
        except Exception:
            conn.rollback()
            raise

    with get_db(db_path) as conn:
        row = conn.execute("SELECT * FROM devices WHERE device_id = ?", (device_id,)).fetchone()
    converted = _row_to_dict(row)
    assert converted is not None
    return converted


def update_device_config(
    device_id: str,
    *,
    nickname: str | None = None,
    daily_budget_cny: float | None = None,
    daily_video_limit: int | None = None,
    preferred_style: str | None = None,
    enable_video: bool | None = None,
    enable_animate_old: bool | None = None,
    config: dict[str, Any] | None = None,
    db_path: str | None = None,
) -> dict[str, Any]:
    get_or_create_device(device_id, db_path=db_path)
    fields: list[str] = []
    values: list[Any] = []
    optional_values = {
        "nickname": nickname,
        "daily_budget_cny": daily_budget_cny,
        "daily_video_limit": daily_video_limit,
        "preferred_style": preferred_style,
        "enable_video": None if enable_video is None else int(enable_video),
        "enable_animate_old": None if enable_animate_old is None else int(enable_animate_old),
        "config_json": None if config is None else _json_dumps(config),
    }
    for field, value in optional_values.items():
        if value is not None:
            fields.append(f"{field} = ?")
            values.append(value)
    if not fields:
        return get_or_create_device(device_id, db_path=db_path)

    values.append(device_id)
    with get_db(db_path) as conn:
        try:
            conn.execute("BEGIN")
            conn.execute(f"UPDATE devices SET {', '.join(fields)} WHERE device_id = ?", values)
            conn.commit()
        except Exception:
            conn.rollback()
            raise
    return get_or_create_device(device_id, db_path=db_path)
