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

import os
thinking_path = os.path.join(sys.argv[3], 'knowledge', 'thinking-model.md')
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
- まず質問が4つの戦略階層（全社/事業/機能/財務）のどこに該当するか特定する
- 思考モデルの該当パターン（設計思考・順番・実験思考・因数分解等）を適用して回答する
- 参考資料の内容を根拠にして答える。根拠のない内容は「資料に記載なし」と明示する
- 動画タイトルとURLを出典として引用する""")
PYEOF
