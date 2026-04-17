#!/usr/bin/env bash
# rag-simple.sh <質問> [top_k=3]
# RAG検索して質問+コンテキストのプロンプトをstdoutに出力する
# シンプル版: search(full_text=True) で上位K件の全文をそのまま使う
#
# 使い方:
#   bash rag-simple.sh "顧客リピートを増やすには？" | claude -p
#   bash rag-simple.sh "SNS集客の方法" 5 | oh-dispatch sonnet

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

QUESTION="${1:-}"
TOP_K="${2:-3}"

if [[ -z "$QUESTION" ]]; then
  echo "Usage: $0 <質問> [top_k]" >&2
  exit 1
fi

python3 - "$QUESTION" "$TOP_K" "$REPO_ROOT" << 'PYEOF'
import sys
sys.path.insert(0, sys.argv[3])
from knowledge.search import search, format_context

question = sys.argv[1]
top_k = int(sys.argv[2])

results = search(question, top_k=top_k, full_text=True)
context = format_context(results, mode='compact')

print(f"""あなたはマーケティング専門家のアシスタントです。
以下の参考動画トランスクリプト（マーケティング侍/小山竜央チャンネル）を根拠に、質問に答えてください。

## 参考資料
{context}

---
## 質問
{question}

## 回答の指示
- 参考資料の内容を根拠にして答える
- 根拠のある内容のみ答え、参考資料にない内容は「資料に記載なし」と明示する
- 動画タイトルとURLを出典として引用する""")
PYEOF
