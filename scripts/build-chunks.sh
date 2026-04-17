#!/usr/bin/env bash
# build-chunks.sh [VIDEO_ID]
# トランスクリプトを2000文字/300重複でチャンク分割してknowledge/chunks.jsonlに書き出す
# LLM不使用。aranobot方式のチャンク制御を実装。
# VIDEO_IDを省略すると全rawを処理する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RAW_DIR="$REPO_ROOT/raw/transcripts"
CHUNKS_FILE="$REPO_ROOT/knowledge/chunks.jsonl"

TARGET_ID="${1:-}"

python3 <<PYEOF
import json, os, re

raw_dir = "$RAW_DIR"
chunks_file = "$CHUNKS_FILE"
target_id = "$TARGET_ID"

MAX_CHARS = 2000
OVERLAP   = 300
MIN_CHARS = 50   # 短すぎるチャンクは除外（aranobot準拠）

# 独立行として現れる相槌・フィラー（budoux分割後の1行がこれだけの行を除去）
STANDALONE_FILLERS = {
    'はい', 'うん', 'えー', 'あー', 'まあ', 'ねー', 'ねえ',
    'そう', 'なる', 'うむ', 'おー', 'へー',
}

# 改行除去後に除去する連続相槌パターン
# 「はいはい」「そうですねはい」「なるほどなるほど」等
INLINE_FILLER_PATTERNS = [
    r'(はい){2,}',           # 「はいはいはい」
    r'(うんうん)+',           # 「うんうんうん」
    r'(そうですね){2,}',      # 「そうですねそうですね」
    r'(なるほど){2,}',        # 「なるほどなるほど」
]

def clean_transcript(raw_text):
    """budoux分割済みテキストをLLM向けにクレンジング"""
    # Step1: 独立行フィラーを除去（budoux改行があるうちに処理）
    lines = raw_text.split('\n')
    cleaned_lines = [l for l in lines if l.strip() not in STANDALONE_FILLERS]
    removed_lines = len(lines) - len(cleaned_lines)

    # Step2: 改行除去（budoux改行を結合して連続テキストに戻す）
    text = ''.join(cleaned_lines)

    # Step3: 連続相槌パターンを除去
    for pat in INLINE_FILLER_PATTERNS:
        text = re.sub(pat, '', text)

    # Step4: 空白の正規化（連続スペース除去）
    text = re.sub(r' {2,}', ' ', text).strip()

    return text, removed_lines

def make_chunks(text, max_chars, overlap):
    """オーバーラップ付きチャンク分割（aranobot方式）"""
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

# 既存チャンクを読み込み（同じvideo_idは上書き）
existing = []
if os.path.exists(chunks_file):
    with open(chunks_file, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            c = json.loads(line)
            if target_id and c.get("video_id") == target_id:
                continue  # 上書き対象はスキップ
            existing.append(c)

# 処理対象のrawファイルを決定
raw_files = sorted(
    f for f in os.listdir(raw_dir)
    if f.endswith(".json") and (not target_id or f == target_id + ".json")
)

new_chunks = []
for fname in raw_files:
    fpath = os.path.join(raw_dir, fname)
    video_id = fname.replace(".json", "")

    with open(fpath, encoding="utf-8") as f:
        data = json.load(f)

    raw_transcript = data.get("transcript", "").strip()
    if not raw_transcript or raw_transcript == "# NO_SUBTITLE":
        continue

    # クレンジング適用
    transcript, removed_lines = clean_transcript(raw_transcript)

    title = data.get("title", "")
    url   = data.get("url", f"https://www.youtube.com/watch?v={video_id}")

    chunks = make_chunks(transcript, MAX_CHARS, OVERLAP)
    for i, chunk_text in enumerate(chunks):
        new_chunks.append({
            "chunk_id":   f"{video_id}_{i:03d}",
            "video_id":   video_id,
            "chunk_index": i,
            "total_chunks": len(chunks),
            "title":      title,
            "url":        url,
            "text":       chunk_text,
            "char_count": len(chunk_text),
        })

    print(f"[build-chunks] {video_id}: {len(raw_transcript)}文字 → {len(transcript)}文字 (-{removed_lines}行) → {len(chunks)}チャンク")

all_chunks = existing + new_chunks
with open(chunks_file, "w", encoding="utf-8") as f:
    for c in all_chunks:
        f.write(json.dumps(c, ensure_ascii=False) + "\n")

total_chars = sum(c["char_count"] for c in new_chunks)
print(f"[build-chunks] 完了: {len(new_chunks)}チャンク追加 / 合計{len(all_chunks)}チャンク")
print(f"[build-chunks] 新規テキスト総量: {total_chars:,}文字")
PYEOF
