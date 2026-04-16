#!/usr/bin/env bash
# summarize.sh <VIDEO_ID>
# トランスクリプトをスクリプトで前処理してsummaries/に保存する
# LLM不使用（aranobot知見: クリーニングはスクリプトで十分）
# カテゴリ分類はタイトルキーワードマッチによる仮分類

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RAW_DIR="$REPO_ROOT/raw/transcripts"
SUMMARY_DIR="$REPO_ROOT/summaries"

VIDEO_ID="${1:-}"
if [[ -z "$VIDEO_ID" ]]; then
  echo "Usage: $0 <VIDEO_ID>" >&2
  exit 1
fi

RAW_FILE="$RAW_DIR/${VIDEO_ID}.json"
if [[ ! -f "$RAW_FILE" ]]; then
  echo "[summarize] raw データなし: $RAW_FILE" >&2
  exit 1
fi

SUMMARY_FILE="$SUMMARY_DIR/${VIDEO_ID}.md"
if [[ -f "$SUMMARY_FILE" ]]; then
  echo "[summarize] スキップ（処理済み）: $VIDEO_ID"
  exit 0
fi

python3 <<PYEOF
import json, re, os
from datetime import date

raw_path = "$RAW_FILE"
out_path = "$SUMMARY_FILE"

with open(raw_path, encoding='utf-8') as f:
    data = json.load(f)

title = data.get('title', '')
url = data.get('url', f"https://www.youtube.com/watch?v=$VIDEO_ID")
upload_date = data.get('upload_date', '')
transcript = data.get('transcript', '')

# --- カテゴリ仮分類（キーワードマッチ） ---
CATEGORY_KEYWORDS = {
    '集客':              ['集客', '見込み客', 'リード', 'アクセス', '認知', 'SEO', 'MEO'],
    '販売':              ['販売', '売上', '成約', 'クロージング', 'セールス', '購入', 'LP', 'ランディングページ'],
    '商品設計':          ['商品設計', 'コンセプト', '価値設計', '商品開発', 'サービス設計'],
    'YouTube戦略':       ['YouTube', 'チャンネル', '動画', 'サムネ', 'タイトル', '再生', '登録'],
    'ニューロマーケティング': ['行動経済学', '心理', 'バイアス', 'ニューロ', '脳', '感情', 'イエスセット'],
    'SNS':               ['インスタ', 'Instagram', 'X(Twitter)', 'SNS', 'TikTok', 'threads', 'Threads'],
}

categories = []
combined = title + ' ' + transcript[:2000]
for cat, keywords in CATEGORY_KEYWORDS.items():
    if any(kw in combined for kw in keywords):
        categories.append(cat)
if not categories:
    categories = ['その他']

# --- トランスクリプト前処理 ---
# 1. フィラー除去
filler_patterns = [
    r'えー+', r'あー+', r'まあ+', r'んー+', r'うー+',
    r'はい、はい', r'そうですね、そうですね',
]
cleaned = transcript
for pat in filler_patterns:
    cleaned = re.sub(pat, '', cleaned)

# 2. 重複連続行を1行に圧縮
lines = cleaned.splitlines()
deduped = []
prev = ''
for line in lines:
    line = line.strip()
    if line and line != prev:
        deduped.append(line)
        prev = line

# 3. 段落分割（。や！?で区切り、N文字以上を1段落とする）
text = '\n'.join(deduped)
sentences = re.split(r'([。！？!?])', text)
paragraphs = []
buf = ''
for i, s in enumerate(sentences):
    buf += s
    if s in '。！？!?' and len(buf) > 80:
        paragraphs.append(buf.strip())
        buf = ''
if buf.strip():
    paragraphs.append(buf.strip())

cleaned_text = '\n\n'.join(paragraphs)

# --- Markdown出力 ---
today = date.today().isoformat()
cats_str = '[' + ', '.join(categories) + ']'

content = f"""---
id: $VIDEO_ID
title: {title}
upload_date: {upload_date}
url: {url}
categories: {cats_str}
key_concepts: []
summarized_at: {today}
processed_by: script
---

## 動画情報

- **タイトル**: {title}
- **URL**: {url}
- **カテゴリ（仮）**: {', '.join(categories)}

## トランスクリプト（前処理済み）

{cleaned_text}
"""

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f"[summarize] 保存: {out_path} ({len(paragraphs)}段落)")
PYEOF

echo "[summarize] 完了: $VIDEO_ID"

# raw の summarized フラグ更新
python3 - "$RAW_FILE" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
data['summarized'] = True
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PYEOF
