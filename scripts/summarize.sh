#!/usr/bin/env bash
# summarize.sh <VIDEO_ID>
# 1動画のトランスクリプトを読み込み、Claude CLIで要約してsummaries/に保存
# LLM呼び出しは1回のみ。ループ禁止ルール準拠。

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
  echo "先に youtube-fetcher/scripts/export-to-context.sh を実行してください" >&2
  exit 1
fi

SUMMARY_FILE="$SUMMARY_DIR/${VIDEO_ID}.md"
if [[ -f "$SUMMARY_FILE" ]]; then
  echo "[summarize] スキップ（要約済み）: $VIDEO_ID"
  exit 0
fi

# メタデータ取得
TITLE=$(python3 -c "import json; d=json.load(open('$RAW_FILE')); print(d['title'])")
UPLOAD_DATE=$(python3 -c "import json; d=json.load(open('$RAW_FILE')); print(d.get('upload_date',''))")
URL=$(python3 -c "import json; d=json.load(open('$RAW_FILE')); print(d.get('url',''))")
TRANSCRIPT=$(python3 -c "import json; d=json.load(open('$RAW_FILE')); print(d.get('transcript','')[:8000])")

echo "[summarize] 要約中: $VIDEO_ID - $TITLE"

# プロンプトを一時ファイルに書く
PROMPT_FILE=$(mktemp)
trap 'rm -f "$PROMPT_FILE"' EXIT

cat > "$PROMPT_FILE" <<PROMPT
以下はYouTubeチャンネル「マーケティング侍の非常識なビジネス学」（りゅう先生）の動画トランスクリプトです。
マーケティング初心者が実践できるノウハウを抽出してください。

## 動画情報
- タイトル: $TITLE
- URL: $URL

## トランスクリプト
$TRANSCRIPT

## 出力形式（以下のMarkdownで出力してください）

---
id: $VIDEO_ID
title: $TITLE
upload_date: $UPLOAD_DATE
url: $URL
categories: [カテゴリ1, カテゴリ2]
key_concepts: [概念1, 概念2]
summarized_at: $(date +%Y-%m-%d)
---

## 概要

（この動画で伝えたいことを100-200字で）

## 主要ノウハウ

### ノウハウ1のタイトル
（具体的な手法・考え方を箇条書きなしで説明）

### ノウハウ2のタイトル
（同上）

## 実践ポイント

- 明日からできるアクション1
- 明日からできるアクション2

## キーフレーズ

動画内で特に重要な発言や表現を1-2つ引用。

---

categoriesは以下から選んでください（複数可）: 集客, 販売, 商品設計, YouTube戦略, ニューロマーケティング, SNS, その他
PROMPT

# Claude CLI で要約（1回のみ呼び出し）
claude --model claude-haiku-4-5-20251001 -p "$(cat "$PROMPT_FILE")" > "$SUMMARY_FILE"

echo "[summarize] 保存: $SUMMARY_FILE"

# raw/transcripts/<VIDEO_ID>.json の summarized フラグを更新
python3 - "$RAW_FILE" <<'PYEOF'
import json, sys

path = sys.argv[1]
with open(path, encoding='utf-8') as f:
    data = json.load(f)
data['summarized'] = True
with open(path, 'w', encoding='utf-8') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
PYEOF

echo "[summarize] 完了: $VIDEO_ID"
