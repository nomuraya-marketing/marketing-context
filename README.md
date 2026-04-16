# marketing-context

マーケティング侍（りゅう先生・小山竜央）のノウハウを構造化・蓄積するコンテキスト管理リポジトリ。

**りゅう先生について:**
- チャンネル登録者: 約10万人
- 専門: 集客マーケティング・ニューロマーケティング・YouTube戦略

`youtube-fetcher` で取得した生トランスクリプトを、LLMで要約・分類して
カテゴリ別ノウハウDBとして蓄積する。

## ディレクトリ構成

```
marketing-context/
├── raw/
│   └── transcripts/          # youtube-fetcher からのエクスポート先（生データ）
├── knowledge/
│   ├── index.jsonl           # 全ノウハウのインデックス
│   ├── 集客/                 # カテゴリ別ノウハウ
│   ├── 販売/
│   ├── 商品設計/
│   ├── YouTube戦略/
│   ├── ニューロマーケティング/
│   ├── SNS/
│   └── その他/
├── summaries/                # 動画サマリ（動画ID単位）
├── scripts/
│   ├── summarize.sh          # 1動画を要約してknowledgeに投入（手動実行）
│   └── build-index.sh        # knowledge/index.jsonlを再構築
└── SCHEMA.md                 # データスキーマ定義
```

## 使い方

```bash
# 1動画を要約してノウハウ抽出（LLM 1回呼び出し）
# VIDEO_ID は raw/transcripts/<VIDEO_ID>.json のID
bash scripts/summarize.sh <VIDEO_ID>

# インデックス再構築
bash scripts/build-index.sh

# ノウハウ検索（grep ベース）
grep -r "集客" knowledge/ --include="*.md" -l
```

## ノウハウカテゴリ

| カテゴリ | 説明 |
|---------|------|
| 集客 | 見込み客を集める手法・導線設計 |
| 販売 | クロージング・セールス手法 |
| 商品設計 | 商品・サービスの価値設計 |
| YouTube戦略 | チャンネル運営・動画制作・アルゴリズム対策 |
| ニューロマーケティング | 脳科学・消費者心理ベースの手法 |
| SNS | SNS各プラットフォームの活用戦略 |
| その他 | マインドセット・経営全般 |

## 設計原則

- ノウハウは動画1本につき **1 Markdownファイル** + `knowledge/index.jsonl` エントリ
- LLMによる要約は `scripts/summarize.sh` が手動実行する（自動実行・ループ禁止）
- 要約の品質が悪い場合は手動で編集して commit
- 生トランスクリプト（`raw/`）はgitで管理するが、LLMには食わせない前処理済みデータのみ使用
