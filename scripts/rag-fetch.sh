#!/usr/bin/env bash
# rag-fetch.sh <質問> <chunk_id> [chunk_id...]
# 2段階RAGのStep2: chunk_idを指定して全文取得し、回答プロンプトをstdoutに出力する
# rag-screen.sh → LLM選択 → rag-fetch.sh の流れで使う
#
# 使い方:
#   bash rag-fetch.sh "顧客リピートを増やすには？" vid1_000 vid2_001
#   bash rag-fetch.sh "顧客リピート" vid1_000 vid2_001 | claude -p

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

QUESTION="${1:-}"
shift || true

if [[ -z "$QUESTION" ]] || [[ $# -eq 0 ]]; then
  echo "Usage: $0 <質問> <chunk_id> [chunk_id...]" >&2
  exit 1
fi

# 残りの引数がchunk_id
CHUNK_IDS=("$@")

python3 - "$QUESTION" "$REPO_ROOT" "${CHUNK_IDS[@]}" << 'PYEOF'
import sys
sys.path.insert(0, sys.argv[2])
from knowledge.search import fetch_chunks, format_context

question = sys.argv[1]
chunk_ids = sys.argv[3:]

chunks = fetch_chunks(chunk_ids)
if not chunks:
    print(f"[rag-fetch] 指定されたchunk_idが見つかりません: {chunk_ids}", file=sys.stderr)
    sys.exit(1)

context = format_context(chunks, mode='compact')

import os
thinking_path = os.path.join(sys.argv[2], 'knowledge', 'thinking-model.md')
thinking = ''
if os.path.exists(thinking_path):
    with open(thinking_path) as f:
        thinking = f.read()

print(f"""あなたはマーケティング侍（小山竜央/りゅう先生）の思考をインストールしたアシスタントです。
以下の「思考モデル」と「参考資料」を使い、りゅう先生ならどう考えるかの視点で質問に答えてください。

## 思考モデル（小山竜央の判断パターン）
{thinking}

## 参考資料（動画トランスクリプト）
{context}

---
## 質問
{question}

## 回答の指示
- まず思考モデルのどの原則が該当するかを判断し、その視点で回答する
- 参考資料の内容を根拠にして答える
- 根拠のある内容のみ答え、参考資料にない内容は「資料に記載なし」と明示する
- 動画タイトルとURLを出典として引用する""")
PYEOF
