#!/usr/bin/env bash
# db-upsert.sh <VIDEO_ID>
# 1動画分のチャンクをchunks.jsonlとchunks.dbにupsertする
# build-chunks.sh + build-db.sh の全量rebuild不要版

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
CHUNKS_FILE="$REPO_ROOT/knowledge/chunks.jsonl"
DB_FILE="$REPO_ROOT/knowledge/chunks.db"
RAW_DIR="$REPO_ROOT/raw/transcripts"

VIDEO_ID="${1:-}"
if [[ -z "$VIDEO_ID" ]]; then
  echo "Usage: $0 <VIDEO_ID>" >&2
  exit 1
fi

RAW_JSON="$RAW_DIR/${VIDEO_ID}.json"
if [[ ! -f "$RAW_JSON" ]]; then
  echo "[db-upsert] raw JSONが存在しません: $RAW_JSON" >&2
  exit 1
fi

python3 - "$VIDEO_ID" "$RAW_JSON" "$CHUNKS_FILE" "$DB_FILE" << 'PYEOF'
import json, os, re, sqlite3, sys

video_id  = sys.argv[1]
raw_json  = sys.argv[2]
chunks_file = sys.argv[3]
db_file   = sys.argv[4]

MAX_CHARS = 2000
OVERLAP   = 300
MIN_CHARS = 50

STANDALONE_FILLERS = {
    'はい', 'うん', 'えー', 'あー', 'まあ', 'ねー', 'ねえ',
    'そう', 'なる', 'うむ', 'おー', 'へー',
}

INLINE_FILLER_PATTERNS = [
    r'(はい){2,}',
    r'(うんうん)+',
    r'(そうですね){2,}',
    r'(なるほど){2,}',
]

BOILERPLATE_PATTERNS = [
    r'時は令和.{0,100}?マーケティング侍.{0,50}?(り|龍|竜)です',
    r'時は令和.{0,80}?マーケティング侍',
    r'の非常識な.{0,20}?マーケティング侍',
    r'(ちゃ?お?、?)?マーケティング侍の?.{0,5}(り|龍|竜)(です|でございます)',
    r'このチャンネルでは.{0,10}?(実践的|今すぐ使える).{0,30}?(シェア|公開|してい)',
    r'このチャンネルではですね.{0,50}?(チャンネル|していく)',
    r'チャンネル登録よろしくお願いします',
    r'いいね.{0,3}ボタン.{0,5}押して.{0,20}',
]

def clean_transcript(raw_text):
    lines = raw_text.split('\n')
    cleaned_lines = [l for l in lines if l.strip() not in STANDALONE_FILLERS]
    text = ''.join(cleaned_lines)
    for pat in BOILERPLATE_PATTERNS:
        text = re.sub(pat, '', text)
    for pat in INLINE_FILLER_PATTERNS:
        text = re.sub(pat, '', text)
    text = re.sub(r' {2,}', ' ', text).strip()
    return text

def make_chunks(text, max_chars, overlap):
    chunks = []
    start = 0
    while start < len(text):
        end = min(start + max_chars, len(text))
        chunk = text[start:end]
        if len(chunk) >= MIN_CHARS:
            chunks.append(chunk)
        if end == len(text):
            break
        start = end - overlap
    return chunks

with open(raw_json, encoding='utf-8') as f:
    data = json.load(f)

raw_transcript = data.get('transcript', '').strip()
if not raw_transcript or raw_transcript == '# NO_SUBTITLE':
    print(f'[db-upsert] スキップ（字幕なし）: {video_id}')
    sys.exit(0)

transcript = clean_transcript(raw_transcript)
title = data.get('title', '')
url   = data.get('url', f'https://www.youtube.com/watch?v={video_id}')

chunk_texts = make_chunks(transcript, MAX_CHARS, OVERLAP)
new_chunks = []
for i, chunk_text in enumerate(chunk_texts):
    new_chunks.append({
        'chunk_id':    f'{video_id}_{i:03d}',
        'video_id':    video_id,
        'chunk_index': i,
        'total_chunks': len(chunk_texts),
        'title':       title,
        'url':         url,
        'text':        chunk_text,
        'char_count':  len(chunk_text),
    })

# --- chunks.jsonl を更新（同video_idを削除して追記）---
if os.path.exists(chunks_file):
    with open(chunks_file, encoding='utf-8') as f:
        existing = [json.loads(l) for l in f if l.strip() and json.loads(l).get('video_id') != video_id]
else:
    existing = []

with open(chunks_file, 'w', encoding='utf-8') as f:
    for c in existing + new_chunks:
        f.write(json.dumps(c, ensure_ascii=False) + '\n')

# --- chunks.db をupsert（差分: rowid指定でFTS削除 → chunks削除 → 再INSERT）---
if not os.path.exists(db_file):
    print(f'[db-upsert] DBが存在しません。build-db.sh を先に実行してください: {db_file}', file=sys.stderr)
    sys.exit(1)

con = sqlite3.connect(db_file)
cur = con.cursor()

# FTSからrowid指定で削除（content-table modeはchunksを先に参照してからdelete）
cur.execute('SELECT rowid, text FROM chunks WHERE video_id = ?', (video_id,))
old_rows = cur.fetchall()
for rowid, text in old_rows:
    cur.execute('INSERT INTO chunks_fts(chunks_fts, rowid, text) VALUES(?, ?, ?)', ('delete', rowid, text))

# chunksから削除
cur.execute('DELETE FROM chunks WHERE video_id = ?', (video_id,))
deleted = len(old_rows)

# 新チャンクをINSERT
for c in new_chunks:
    cur.execute(
        'INSERT INTO chunks VALUES (?,?,?,?,?,?,?,?)',
        (c['chunk_id'], c['video_id'], c['chunk_index'],
         c['total_chunks'], c['title'], c['url'], c['char_count'], c['text'])
    )
    # 追加したrowidを取得してFTSにも登録
    new_rowid = cur.lastrowid
    cur.execute('INSERT INTO chunks_fts(rowid, text) VALUES (?, ?)', (new_rowid, c['text']))

con.commit()

cur.execute('SELECT COUNT(*) FROM chunks')
total = cur.fetchone()[0]
con.close()

print(f'[db-upsert] {video_id}: {deleted}件削除 → {len(new_chunks)}チャンク挿入 / DB合計: {total:,}件')
PYEOF
