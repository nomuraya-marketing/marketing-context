#!/usr/bin/env bash
# business-snapshot-reminder.sh
# 自社事業スナップショットが30日以上未更新の場合に macOS 通知を出す。
# launchd から月1回呼ばれる想定。

set -euo pipefail

SNAPSHOT="$HOME/workspace-ai/nomuraya-marketing/marketing-context/knowledge/business-snapshot.md"

if [[ ! -f "$SNAPSHOT" ]]; then
  exit 0
fi

LAST_UPDATED=$(grep '^last_updated:' "$SNAPSHOT" | head -1 | sed 's/last_updated: *//' | tr -d ' ')
if [[ -z "$LAST_UPDATED" ]]; then
  exit 0
fi

# 経過日数を計算（macOS date）
LAST_EPOCH=$(date -j -f "%Y-%m-%d" "$LAST_UPDATED" "+%s" 2>/dev/null || echo "")
if [[ -z "$LAST_EPOCH" ]]; then
  exit 0
fi
NOW_EPOCH=$(date "+%s")
DAYS=$(( (NOW_EPOCH - LAST_EPOCH) / 86400 ))

if [[ $DAYS -ge 30 ]]; then
  # macOS 通知
  osascript -e "display notification \"事業スナップショットが ${DAYS} 日間更新されていません。マーケ戦略の判断材料を最新化してください。\" with title \"マーケティング侍RAG\" sound name \"Ping\""
  echo "[snapshot-reminder] 警告通知: ${DAYS}日経過 (last_updated=${LAST_UPDATED})"
else
  echo "[snapshot-reminder] 正常: ${DAYS}日経過 (last_updated=${LAST_UPDATED})"
fi
