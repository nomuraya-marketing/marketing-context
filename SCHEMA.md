# データスキーマ定義

## raw/transcripts/<VIDEO_ID>.json

youtube-fetcher からエクスポートされる生データ。

```json
{
  "id": "VIDEO_ID",
  "title": "動画タイトル",
  "upload_date": "YYYYMMDD",
  "url": "https://www.youtube.com/watch?v=VIDEO_ID",
  "duration": 秒数,
  "view_count": 再生回数,
  "transcript": "トランスクリプトテキスト全文",
  "summarized": false
}
```

## summaries/<VIDEO_ID>.md

`scripts/summarize.sh` が生成するサマリ。

```markdown
---
id: VIDEO_ID
title: 動画タイトル
upload_date: YYYYMMDD
url: https://www.youtube.com/watch?v=VIDEO_ID
categories: [集客, YouTube戦略]
key_concepts: [コンセプト1, コンセプト2]
summarized_at: YYYY-MM-DD
---

## 概要

（100-200字の要約）

## 主要ノウハウ

### ノウハウ1のタイトル
（具体的な手法・考え方）

### ノウハウ2のタイトル
（具体的な手法・考え方）

## 実践ポイント

- アクションアイテム1
- アクションアイテム2

## キーフレーズ

動画内で印象的だった発言。
```

## knowledge/index.jsonl

全ノウハウの検索用インデックス。1行1エントリ。

```jsonl
{"id":"VIDEO_ID","title":"動画タイトル","categories":["集客"],"key_concepts":["コンセプト"],"summary_path":"summaries/VIDEO_ID.md","upload_date":"YYYYMMDD","url":"https://..."}
```

## knowledge/<カテゴリ>/<CONCEPT>.md

カテゴリ横断でノウハウをまとめたファイル。
複数動画から抽出された同一概念をひとまとめにする（手動メンテ）。

```markdown
---
concept: コンセプト名
category: カテゴリ名
source_videos: [VIDEO_ID1, VIDEO_ID2]
last_updated: YYYY-MM-DD
---

## 定義

## なぜ重要か

## 具体的な手法

## 動画での言及

- [動画タイトル](URL): 要点
```
