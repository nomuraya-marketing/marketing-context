#!/usr/bin/env bash
# build-index.sh
# raw/transcripts/ 配下の全JSONを読み込み、knowledge/index.jsonl を再構築
# LLM不使用。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RAW_DIR="$REPO_ROOT/raw/transcripts"
INDEX_FILE="$REPO_ROOT/knowledge/index.jsonl"

echo "[build-index] インデックス再構築中..."

python3 - "$RAW_DIR" "$INDEX_FILE" <<'PYEOF'
import os, sys, json

raw_dir = sys.argv[1]
index_file = sys.argv[2]

entries = []

for fname in sorted(os.listdir(raw_dir)):
    if not fname.endswith('.json'):
        continue

    fpath = os.path.join(raw_dir, fname)
    with open(fpath, encoding='utf-8') as f:
        data = json.load(f)

    video_id = data.get('id', fname[:-5])
    entry = {
        'id':          video_id,
        'title':       data.get('title', ''),
        'upload_date': data.get('upload_date', ''),
        'url':         data.get('url', f'https://www.youtube.com/watch?v={video_id}'),
        'duration':    data.get('duration', 0),
        'raw_path':    f'raw/transcripts/{fname}',
    }
    entries.append(entry)

with open(index_file, 'w', encoding='utf-8') as f:
    for e in entries:
        f.write(json.dumps(e, ensure_ascii=False) + '\n')

print(f"[build-index] {len(entries)}件のエントリを書き込みました")

# chunks.jsonl の統計も表示
chunks_file = os.path.join(os.path.dirname(index_file), 'chunks.jsonl')
if os.path.exists(chunks_file):
    chunks = [json.loads(l) for l in open(chunks_file) if l.strip()]
    total_chars = sum(c['char_count'] for c in chunks)
    avg_chars = total_chars // len(chunks) if chunks else 0
    print(f"[build-index] chunks: {len(chunks)}件 / 総文字数: {total_chars:,} / 平均: {avg_chars}文字/chunk")
PYEOF

echo "[build-index] 完了: $INDEX_FILE"
