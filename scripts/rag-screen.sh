#!/usr/bin/env bash
# rag-screen.sh <質問> [top_k=10]
# 2段階RAGのStep1: snippet検索で候補一覧をstdoutに出力する
# LLMが必要なchunk_idを選んだ後、rag-fetch.sh に渡す
#
# 使い方（2段階RAG）:
#   Step1: bash rag-screen.sh "顧客リピート" 10
#          → chunk_id一覧+snippetが出力される
#   Step2: LLMまたは人間がchunk_idを選んで rag-fetch.sh に渡す
#          bash rag-fetch.sh "顧客リピート" vid1_000 vid2_001 vid3_005
#
# パイプで繋ぐ場合（LLMにchunk_id選択させる）:
#   bash rag-screen.sh "顧客リピート" | claude -p | xargs bash rag-fetch.sh "顧客リピート"
#   ※ LLMの出力がchunk_idのみのリストになるようプロンプトで指示している

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

QUESTION="${1:-}"
TOP_K="${2:-10}"

if [[ -z "$QUESTION" ]]; then
  echo "Usage: $0 <質問> [top_k]" >&2
  exit 1
fi

python3 - "$QUESTION" "$TOP_K" "$REPO_ROOT" << 'PYEOF'
import sys
sys.path.insert(0, sys.argv[3])
from knowledge.search import search

question = sys.argv[1]
top_k = int(sys.argv[2])

results = search(question, top_k=top_k, full_text=False, snippet_tokens=50)

# 候補一覧をテキスト形式で出力
candidates = '\n'.join(
    f"- {r['chunk_id']} | {r['title'][:40]} | {r['snippet'][:80]}"
    for r in results
)

print(f"""以下は「{question}」に関連する動画チャンクの候補です。
各行の形式: chunk_id | タイトル | 抜粋

{candidates}

---
上記の候補から、質問「{question}」に答えるために最も有用なchunk_idを最大3件選んでください。
chunk_idのみを1行ずつ出力してください。他のテキストは一切出力しないでください。

例:
vid1_000
vid2_003
vid3_007""")
PYEOF
