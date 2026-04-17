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
import sys, os, re
from datetime import date, datetime
sys.path.insert(0, sys.argv[3])
from knowledge.search import search, format_context

question = sys.argv[1]
top_k = int(sys.argv[2])
repo_root = sys.argv[3]

results = search(question, top_k=top_k, full_text=True)
context = format_context(results, mode='compact')

thinking_path = os.path.join(repo_root, 'knowledge', 'thinking-model.md')
thinking = ''
if os.path.exists(thinking_path):
    with open(thinking_path) as f:
        thinking = f.read()

# --- 事業スナップショット自動注入 + 鮮度チェック ---
snapshot_path = os.path.join(repo_root, 'knowledge', 'business-snapshot.md')
snapshot_block = ''
if os.path.exists(snapshot_path):
    with open(snapshot_path) as f:
        snapshot_text = f.read()
    m = re.search(r'^last_updated:\s*(\d{4}-\d{2}-\d{2})', snapshot_text, re.MULTILINE)
    days_since_update = None
    if m:
        try:
            last = datetime.strptime(m.group(1), '%Y-%m-%d').date()
            days_since_update = (date.today() - last).days
        except ValueError:
            pass
    if days_since_update is not None and days_since_update > 30:
        print(
            f"[rag-simple] ⚠️  事業スナップショットが {days_since_update} 日間更新されていません "
            f"({m.group(1)} 以降)。knowledge/business-snapshot.md を更新してください。",
            file=sys.stderr,
        )
    snapshot_block = f"""
## 自社事業スナップショット（判断の根拠になる事業データ）
{snapshot_text}
"""

print(f"""あなたはマーケティング侍（小山竜央/りゅう先生）の思考をインストールしたアシスタントです。
以下の「思考モデル」「自社事業スナップショット」「参考資料」を使い、りゅう先生ならどう考えるかの視点で質問に答えてください。

## 思考モデル（小山竜央の判断パターン）
{thinking}
{snapshot_block}
## 参考資料（動画トランスクリプト）
{context}

---
## 質問
{question}

## 回答の指示
- まず質問が4つの戦略階層（全社/事業/機能/財務）のどこに該当するか特定する
- 思考モデルの該当パターン（設計思考・順番・実験思考・因数分解・事例逆引き・数値ベンチマーク等）を適用して回答する
- 参考資料の内容を根拠にして答える。根拠のない内容は「資料に記載なし」と明示する
- **自社事業スナップショットの数字・顧客像・課題を前提条件として使う**。一般論ではなくこの事業固有の判断を返す
- スナップショットに未記入の項目があれば、回答に「この判断には◯◯の情報が必要」と明示する
- 一般的なマーケティングの教科書的回答ではなく、思考モデルに基づく回答をする

## 文体の指示（重要）
- 参考資料は**思考の根拠**として使う。口調・語尾・話し方は真似しない
- 「〜なんですよ」「〜だよね」「ま、」「〜っていう」等の話し言葉は使わない
- 普通のビジネス日本語（ですます調または常体）で、結論を明確に書く
- 動画の語り口を再現するのではなく、思考パターンを再現する""")
PYEOF
