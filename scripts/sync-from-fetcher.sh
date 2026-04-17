#!/usr/bin/env bash
# sync-from-fetcher.sh
# youtube-fetcherで取得済みのトランスクリプトをmarketing-contextに取り込む
# ダウンロード完了分から順次処理するために手動または定期実行する

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
FETCHER_ROOT="${FETCHER_ROOT:-$REPO_ROOT/../youtube-fetcher}"

# タイトルを日本語に更新（新規分のみ）
echo "[sync] タイトル取得中..."
python3 - "$REPO_ROOT/raw/transcripts" "$FETCHER_ROOT/data/video-list.jsonl" "$REPO_ROOT/knowledge/index.jsonl" << 'PYEOF'
import json, os, subprocess, sys

raw_dir = sys.argv[1]
video_list_file = sys.argv[2]
index_file = sys.argv[3]

# 既存indexのタイトルを読み込み
existing_titles = {}
if os.path.exists(index_file):
    with open(index_file) as f:
        for line in f:
            obj = json.loads(line)
            existing_titles[obj['id']] = obj.get('title', '')

# raw/のうちタイトルが英語のもの（ASCII比率>0.7）を更新対象に
to_update = []
for fname in os.listdir(raw_dir):
    if not fname.endswith('.json'):
        continue
    vid = fname[:-5]
    fpath = os.path.join(raw_dir, fname)
    with open(fpath) as f:
        data = json.load(f)
    title = data.get('title', '')
    ascii_ratio = sum(1 for c in title if ord(c) < 128) / max(len(title), 1)
    if ascii_ratio > 0.7:
        to_update.append(vid)

if not to_update:
    print('[sync] タイトル更新不要')
    sys.exit(0)

print(f'[sync] タイトル取得対象: {len(to_update)}本')
for vid in to_update:
    result = subprocess.run(
        ['yt-dlp', '--dump-json', f'https://www.youtube.com/watch?v={vid}'],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        continue
    try:
        d = json.loads(result.stdout)
        title = d.get('title', '')
        ascii_ratio = sum(1 for c in title if ord(c) < 128) / max(len(title), 1)
        if ascii_ratio <= 0.7:
            fpath = os.path.join(raw_dir, f'{vid}.json')
            with open(fpath) as f:
                data = json.load(f)
            data['title'] = title
            with open(fpath, 'w') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            print(f'[sync] タイトル更新: {vid}: {title[:40]}')
    except Exception:
        pass
PYEOF

# export → chunks → index
MARKETING_CONTEXT_PATH="$REPO_ROOT" bash "$FETCHER_ROOT/scripts/export-to-context.sh"
bash "$SCRIPT_DIR/build-index.sh"

echo "[sync] 完了"
