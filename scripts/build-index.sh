#!/usr/bin/env bash
# build-index.sh
# summaries/ 配下の全Markdownを読み込み、knowledge/index.jsonl を再構築
# LLM不使用。フロントマターのみパース。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SUMMARY_DIR="$REPO_ROOT/summaries"
INDEX_FILE="$REPO_ROOT/knowledge/index.jsonl"

echo "[build-index] インデックス再構築中..."

python3 - "$SUMMARY_DIR" "$INDEX_FILE" <<'PYEOF'
import os, sys, json, re

summary_dir = sys.argv[1]
index_file = sys.argv[2]

entries = []

for fname in sorted(os.listdir(summary_dir)):
    if not fname.endswith('.md'):
        continue

    fpath = os.path.join(summary_dir, fname)
    with open(fpath, encoding='utf-8') as f:
        content = f.read()

    # フロントマターをパース
    fm_match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
    if not fm_match:
        continue

    fm_text = fm_match.group(1)
    meta = {}
    for line in fm_text.splitlines():
        if ':' not in line:
            continue
        key, _, val = line.partition(':')
        key = key.strip()
        val = val.strip()
        # リスト形式をパース: [a, b, c]
        if val.startswith('[') and val.endswith(']'):
            val = [v.strip() for v in val[1:-1].split(',') if v.strip()]
        meta[key] = val

    video_id = meta.get('id', fname.replace('.md', ''))
    entry = {
        'id': video_id,
        'title': meta.get('title', ''),
        'categories': meta.get('categories', []),
        'key_concepts': meta.get('key_concepts', []),
        'upload_date': meta.get('upload_date', ''),
        'url': meta.get('url', f'https://www.youtube.com/watch?v={video_id}'),
        'summary_path': f'summaries/{fname}',
        'summarized_at': meta.get('summarized_at', ''),
    }
    entries.append(entry)

with open(index_file, 'w', encoding='utf-8') as f:
    for e in entries:
        f.write(json.dumps(e, ensure_ascii=False) + '\n')

print(f"[build-index] {len(entries)}件のエントリを書き込みました")
PYEOF

echo "[build-index] 完了: $INDEX_FILE"
