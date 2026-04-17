"""
marketing-context RAG検索モジュール
使い方:
    from knowledge.search import search, fetch_chunks

    # スクリーニング（トークン節約）
    results = search("SNS集客", top_k=5)
    # → [{'chunk_id': ..., 'title': ..., 'url': ..., 'snippet': ..., 'score': ...}, ...]

    # 全文取得（chunk_idを指定）
    chunks = fetch_chunks(['vid1_000', 'vid1_001'])
    # → [{'chunk_id': ..., 'title': ..., 'url': ..., 'text': ...}, ...]

    # 1ステップで全文取得まで（top_k件をそのまま使う場合）
    results = search("SNS集客", top_k=3, full_text=True)
"""

import sqlite3
import os
from typing import Optional

_DB_PATH = os.path.join(os.path.dirname(__file__), 'chunks.db')


def _make_bigrams(text: str) -> str:
    return ' '.join(text[i:i+2] for i in range(len(text) - 1))


def _get_con():
    con = sqlite3.connect(_DB_PATH)
    con.row_factory = sqlite3.Row
    return con


def search(
    query: str,
    top_k: int = 5,
    full_text: bool = False,
    snippet_tokens: int = 40,
) -> list[dict]:
    """
    trigram + bigram 統合検索。

    Args:
        query: 検索クエリ（日本語）
        top_k: 取得件数
        full_text: True のとき snippet ではなく text 全文を返す
        snippet_tokens: full_text=False のときの snippet 長（FTS5 トークン数）

    Returns:
        [{'chunk_id', 'title', 'url', 'score', 'snippet' or 'text'}, ...]
        score は小さいほど関連度が高い（FTS5 rank 値）
    """
    con = _get_con()
    cur = con.cursor()
    results: dict[str, dict] = {}

    # --- trigram 検索（3文字以上で有効）---
    if len(query) >= 3:
        snip_expr = f"snippet(chunks_fts, 0, '', '', '...', {snippet_tokens})"
        sql = f'''
            SELECT c.chunk_id, c.title, c.url,
                   {snip_expr} AS snip,
                   {"c.text" if full_text else "NULL"} AS text,
                   chunks_fts.rank AS score
            FROM chunks_fts
            JOIN chunks c ON chunks_fts.rowid = c.rowid
            WHERE chunks_fts MATCH ?
            ORDER BY rank
            LIMIT ?
        '''
        cur.execute(sql, (query, top_k))
        for row in cur.fetchall():
            results[row['chunk_id']] = dict(row)

    # --- bigram 検索（2文字語を補完）---
    bi_query = _make_bigrams(query)
    if bi_query:
        sql = f'''
            SELECT c.chunk_id, c.title, c.url,
                   {"c.text" if full_text else "NULL"} AS text,
                   chunks_bi.rank AS score
            FROM chunks_bi
            JOIN chunks c ON chunks_bi.rowid = c.rowid
            WHERE chunks_bi MATCH ?
            ORDER BY rank
            LIMIT ?
        '''
        cur.execute(sql, (bi_query, top_k))
        for row in cur.fetchall():
            if row['chunk_id'] not in results:
                r = dict(row)
                r['snip'] = None
                results[row['chunk_id']] = r

    con.close()

    # score でソートして top_k 件に絞る
    sorted_results = sorted(results.values(), key=lambda x: x.get('score') or 0)[:top_k]

    # 出力を整形
    output = []
    for r in sorted_results:
        entry = {
            'chunk_id': r['chunk_id'],
            'title':    r['title'],
            'url':      r['url'],
            'score':    r.get('score'),
        }
        if full_text:
            entry['text'] = r.get('text') or ''
        else:
            entry['snippet'] = r.get('snip') or ''
        output.append(entry)

    return output


def fetch_chunks(chunk_ids: list[str]) -> list[dict]:
    """
    chunk_id リストを指定して全文を取得する。
    search() で候補を絞った後に必要な chunk だけ取得するために使う。

    Returns:
        [{'chunk_id', 'title', 'url', 'text'}, ...]
    """
    if not chunk_ids:
        return []
    con = _get_con()
    cur = con.cursor()
    placeholders = ','.join('?' * len(chunk_ids))
    cur.execute(
        f'SELECT chunk_id, title, url, text FROM chunks WHERE chunk_id IN ({placeholders})',
        chunk_ids
    )
    rows = [dict(r) for r in cur.fetchall()]
    con.close()
    # 入力順を保持
    order = {cid: i for i, cid in enumerate(chunk_ids)}
    return sorted(rows, key=lambda r: order.get(r['chunk_id'], 999))


def format_context(chunks: list[dict], mode: str = 'full') -> str:
    """
    LLM へ渡すコンテキスト文字列を生成する。

    Args:
        chunks: search(full_text=True) または fetch_chunks() の戻り値
        mode:
            'full'    - タイトル + URL + 全文（デフォルト）
            'compact' - タイトル + URL + 全文（区切り線なし、最小）
            'snippet' - search(full_text=False) の結果をそのまま整形
    """
    parts = []
    for c in chunks:
        body = c.get('text') or c.get('snippet') or ''
        if mode == 'compact':
            parts.append(f"[{c['title']}]({c['url']})\n{body}")
        else:
            parts.append(f"## {c['title']}\n{c['url']}\n\n{body}")
    sep = '\n\n' if mode != 'compact' else '\n'
    return sep.join(parts)


if __name__ == '__main__':
    import sys
    query = sys.argv[1] if len(sys.argv) > 1 else 'SNS集客'
    mode  = sys.argv[2] if len(sys.argv) > 2 else 'snippet'

    print(f"検索: 「{query}」  mode={mode}\n")

    if mode == 'snippet':
        results = search(query, top_k=5)
        for r in results:
            print(f"[{r['chunk_id']}] {r['title'][:40]}")
            print(f"  {r['snippet'][:100]}")
        total_chars = sum(len(r['snippet']) + len(r['title']) + len(r['url']) for r in results)
        print(f"\nコンテキスト合計: {total_chars}文字")

    elif mode == 'full':
        results = search(query, top_k=3, full_text=True)
        ctx = format_context(results, mode='compact')
        print(ctx[:1000])
        print(f"\nコンテキスト合計: {len(ctx)}文字")

    elif mode == 'twostep':
        # 2段階: snippetでスクリーニング → chunk_id指定で全文取得
        candidates = search(query, top_k=10)
        print(f"候補 {len(candidates)} 件:")
        for r in candidates:
            print(f"  [{r['chunk_id']}] {r['title'][:40]} | {r['snippet'][:60]}")
        # ここでLLMが必要なchunk_idを選ぶ想定（デモ: 上位2件）
        selected_ids = [r['chunk_id'] for r in candidates[:2]]
        full = fetch_chunks(selected_ids)
        ctx = format_context(full, mode='compact')
        print(f"\n選択 {len(full)} 件の全文コンテキスト: {len(ctx)}文字")
