# LLMトークン制御ガイドライン（aranobot知見）

出典: `~/workspace-ai/nomuraya-job-fde/arano-bot/.claude/worktrees/clever-faraday/scripts/convert_to_verbatim.py`

## 原則

LLMを使う処理では、入力テキストを**文字数ベースでチャンク分割**してから呼び出す。
トランスクリプト全文をそのまま渡さない。

## 制御パラメータ

```python
MAX_BATCH_CHARS = 2000   # 1回のLLM呼び出しに渡す最大文字数
MAX_CHARS = 1500         # ブラッシュアップ処理のチャンクサイズ
OVERLAP = 300            # チャンク間の文脈保持（スライディングウィンドウ）
SEGMENT_LIMIT = 200      # 各セグメントの文字数上限
SLEEP_SEC = 2            # API呼び出し間のインターバル（429回避）
```

## チャンク分割の実装パターン

```python
def process_in_chunks(text, max_chars=1500, overlap=300):
    """テキストをオーバーラップ付きチャンクに分割"""
    chunks = []
    start = 0
    while start < len(text):
        end = min(start + max_chars, len(text))
        chunks.append(text[start:end])
        start = end - overlap  # 文脈保持のため300文字戻る
        if start + overlap >= len(text):
            break
    return chunks
```

## LLM呼び出しが必要な処理と不要な処理

| 処理 | LLM必要？ | 理由 |
|------|-----------|------|
| VTT→テキスト変換 | 不要 | 正規表現で十分 |
| フィラー除去 | 不要 | 正規表現で十分 |
| 重複行除去 | 不要 | 文字列比較で十分 |
| カテゴリ仮分類 | 不要 | キーワードマッチで十分 |
| 話者推定 | 必要 | チャンク分割して呼ぶ（MAX_BATCH_CHARS=2000） |
| ノウハウ抽出 | 必要 | チャンク分割して呼ぶ（MAX_CHARS=1500） |
| 語彙クリーニング | 場合による | 単純置換ならsed、文脈判断が必要ならLLM |

## 適用ルール

1. LLMなしで済む処理は必ずスクリプトで完結させる
2. LLMが必要な場合はチャンク分割+オーバーラップで呼ぶ
3. 1回のLLM呼び出しに2000文字以上渡さない
4. 呼び出し間に2秒のインターバルを入れる
5. 全文を渡して「要約して」は禁止
