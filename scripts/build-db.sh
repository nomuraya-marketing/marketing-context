#!/usr/bin/env bash
# build-db.sh
# chunks.jsonlからSQLite FTSデータベースを構築する
# 生成物: knowledge/chunks.db（git管理外）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CHUNKS_FILE="$REPO_ROOT/knowledge/chunks.jsonl"
DB_FILE="$REPO_ROOT/knowledge/chunks.db"

echo "[build-db] データベース構築中: $DB_FILE"

python3 - "$CHUNKS_FILE" "$DB_FILE" << 'PYEOF'
import json, sqlite3, sys, os

chunks_file = sys.argv[1]
db_file = sys.argv[2]

# 既存DBを削除して再構築
if os.path.exists(db_file):
    os.remove(db_file)

con = sqlite3.connect(db_file)
cur = con.cursor()

# メタデータ+テキストテーブル（FTSのcontent tableとして使用）
cur.execute('''
    CREATE TABLE chunks (
        chunk_id    TEXT PRIMARY KEY,
        video_id    TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        total_chunks INTEGER NOT NULL,
        title       TEXT,
        url         TEXT,
        char_count  INTEGER,
        text        TEXT
    )
''')

# FTS5全文検索テーブル（content-table modeでchunksテーブルを参照）
# content-table modeにすることでsnippet()とJOINが正しく動作する
cur.execute('''
    CREATE VIRTUAL TABLE chunks_fts USING fts5(
        text,
        content='chunks',
        content_rowid='rowid',
        tokenize='trigram'
    )
''')

with open(chunks_file, encoding='utf-8') as f:
    rows = []
    for line in f:
        line = line.strip()
        if not line:
            continue
        c = json.loads(line)
        rows.append((
            c['chunk_id'], c['video_id'], c['chunk_index'],
            c['total_chunks'], c.get('title',''), c.get('url',''), c['char_count'],
            c['text']
        ))

cur.executemany('INSERT INTO chunks VALUES (?,?,?,?,?,?,?,?)', rows)

# FTSインデックスを構築（content-table modeはINSERT後に再構築）
cur.execute("INSERT INTO chunks_fts(chunks_fts) VALUES('rebuild')")

con.commit()

# 統計
cur.execute('SELECT COUNT(*) FROM chunks')
count = cur.fetchone()[0]
con.close()

size_mb = os.path.getsize(db_file) / 1024 / 1024
print(f'[build-db] 完了: {count:,}件 / {size_mb:.1f}MB -> {db_file}')
PYEOF
