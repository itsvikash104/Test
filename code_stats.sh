#!/usr/bin/env bash

# ── config ────────────────────────────────────────────────────────────────────
BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
MONTHS=30
SINCE=$(date -d "$MONTHS months ago" +%Y-%m-%d 2>/dev/null \
        || date -v-${MONTHS}m +%Y-%m-%d)   # macOS fallback
UNTIL=$(date +%Y-%m-%d)

SEP="─────────────────────────────────────────────────────"

# suppress git's rename-detection chatter on large repos
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=diff.renameLimit
export GIT_CONFIG_VALUE_0=0

# ── helpers ───────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
head1() { echo; bold "$SEP"; bold "  $*"; bold "$SEP"; }
head2() { echo; printf '\033[1;34m  ▶ %s\033[0m\n' "$*"; }

# count lines safely — never exits non-zero
count_lines() { wc -l | tr -d ' \t'; }

# ── sanity check ──────────────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "ERROR: not inside a git repository." >&2; exit 1
fi
if ! git rev-parse --verify "$BRANCH" &>/dev/null; then
  echo "ERROR: branch '$BRANCH' not found." >&2; exit 1
fi

# ── base git args ─────────────────────────────────────────────────────────────
LOG_ARGS=(log "$BRANCH" --since="$SINCE" --until="$UNTIL" --no-merges)

# ── gather data ───────────────────────────────────────────────────────────────
COMMITS=$(git "${LOG_ARGS[@]}" --oneline 2>/dev/null | count_lines)
MERGE_COMMITS=$(git log "$BRANCH" --since="$SINCE" --until="$UNTIL" \
                    --merges --oneline 2>/dev/null | count_lines)

DIFF_STAT=$(git "${LOG_ARGS[@]}" --numstat 2>/dev/null \
            | awk 'NF==3 && $1~/^[0-9]+$/ {add+=$1; del+=$2}
                   END {printf "%d %d", add+0, del+0}')
LINES_ADDED=$(  echo "$DIFF_STAT" | cut -d' ' -f1)
LINES_REMOVED=$(echo "$DIFF_STAT" | cut -d' ' -f2)
NET_LINES=$(( LINES_ADDED - LINES_REMOVED ))

FILES_CHANGED=$(git "${LOG_ARGS[@]}" --name-only --format="" 2>/dev/null \
                | grep -v '^[[:space:]]*$' | sort -u | count_lines)

CONTRIBUTORS=$(git "${LOG_ARGS[@]}" --format="%ae" 2>/dev/null \
               | grep -v '^[[:space:]]*$' | sort -u | count_lines)

FIRST_COMMIT=$(git "${LOG_ARGS[@]}" --format="%ad" --date=short 2>/dev/null | tail -1)
LAST_COMMIT=$( git "${LOG_ARGS[@]}" --format="%ad" --date=short 2>/dev/null | head -1)

# ── summary ───────────────────────────────────────────────────────────────────
head1 "CODE STATS — $BRANCH"
printf '  Period  : %s → %s  (%d months)\n' "$SINCE" "$UNTIL" "$MONTHS"
printf '  Analysed: %s → %s\n' "${FIRST_COMMIT:-(none)}" "${LAST_COMMIT:-(none)}"

head2 "Commit Activity"
printf '  %-28s %s\n' "Total commits (no merges):" "$COMMITS"
printf '  %-28s %s\n' "Merge commits:"             "$MERGE_COMMITS"
printf '  %-28s %s\n' "Files changed (unique):"    "$FILES_CHANGED"

head2 "Line Changes"
printf '  %-28s +%s\n' "Lines added:"   "$LINES_ADDED"
printf '  %-28s -%s\n' "Lines removed:" "$LINES_REMOVED"
if [[ "$NET_LINES" -ge 0 ]]; then
  printf '  %-28s +%s\n' "Net change:" "$NET_LINES"
else
  printf '  %-28s %s\n'  "Net change:" "$NET_LINES"
fi

head2 "Contributors  (top 20)"
printf '  %-28s %s\n' "Unique authors:" "$CONTRIBUTORS"
echo
git "${LOG_ARGS[@]}" --format="%aN" 2>/dev/null \
  | grep -v '^[[:space:]]*$' \
  | sort | uniq -c | sort -rn | head -20 \
  | awk '{printf "  %6s commits  %s\n", $1, $2}'

# ── monthly breakdown ─────────────────────────────────────────────────────────
head2 "Monthly Commit Breakdown"
printf '  %-10s  %7s  %12s  %12s\n' "Month" "Commits" "+Lines" "-Lines"
printf '  %-10s  %7s  %12s  %12s\n' "----------" "-------" "------------" "------------"

MONTH_DATE="$SINCE"
while [[ "$MONTH_DATE" < "$UNTIL" || "$MONTH_DATE" == "$UNTIL" ]]; do
  NEXT=$(date -d "$MONTH_DATE +1 month" +%Y-%m-%d 2>/dev/null \
         || date -v+1m -jf%Y-%m-%d "$MONTH_DATE" +%Y-%m-%d)
  MONTH_LABEL=$(date -d "$MONTH_DATE" +%Y-%m 2>/dev/null \
                || date -jf%Y-%m-%d "$MONTH_DATE" +%Y-%m)

  MC=$(git log "$BRANCH" --since="$MONTH_DATE" --until="$NEXT" \
           --no-merges --oneline 2>/dev/null | count_lines)

  if [[ "$MC" -gt 0 ]]; then
    MSTAT=$(git log "$BRANCH" --since="$MONTH_DATE" --until="$NEXT" \
                --no-merges --numstat 2>/dev/null \
                | awk 'NF==3 && $1~/^[0-9]+$/ {a+=$1; d+=$2}
                       END {printf "%d %d", a+0, d+0}')
    MA=$(echo "$MSTAT" | cut -d' ' -f1)
    MD=$(echo "$MSTAT" | cut -d' ' -f2)
  else
    MA=0; MD=0
  fi

  printf '  %-10s  %7d  %+12d  %12d\n' "$MONTH_LABEL" "$MC" "$MA" "-$MD"
  MONTH_DATE="$NEXT"
done

# ── top changed files ─────────────────────────────────────────────────────────
head2 "Top 15 Most-Changed Files"
printf '  %7s  %s\n' "Changes" "File"
printf '  %7s  %s\n' "-------" "----"
git "${LOG_ARGS[@]}" --name-only --format="" 2>/dev/null \
  | grep -v '^[[:space:]]*$' \
  | sort | uniq -c | sort -rn | head -15 \
  | awk '{printf "  %7d  %s\n", $1, $2}'

# ── extension breakdown ───────────────────────────────────────────────────────
head2 "Changes by File Extension"
printf '  %7s  %s\n' "Count" "Extension"
printf '  %7s  %s\n' "-------" "---------"
git "${LOG_ARGS[@]}" --name-only --format="" 2>/dev/null \
  | grep -v '^[[:space:]]*$' \
  | grep '\.' \
  | sed 's/.*\(\.[^.]*\)$/\1/' \
  | sort | uniq -c | sort -rn | head -15 \
  | awk '{printf "  %7d  %s\n", $1, $2}'

# ── active days ───────────────────────────────────────────────────────────────
head2 "Commit Frequency"
ACTIVE_DAYS=$(git "${LOG_ARGS[@]}" --format="%ad" --date=short 2>/dev/null \
              | sort -u | count_lines)
TOTAL_DAYS=$(( ( $(date -d "$UNTIL" +%s 2>/dev/null || date -jf%Y-%m-%d "$UNTIL" +%s) \
              - $(date -d "$SINCE" +%s 2>/dev/null || date -jf%Y-%m-%d "$SINCE" +%s) ) / 86400 ))
if [[ "$ACTIVE_DAYS" -gt 0 && "$TOTAL_DAYS" -gt 0 ]]; then
  AVG=$(awk "BEGIN {printf \"%.1f\", $COMMITS / $ACTIVE_DAYS}")
  printf '  %-28s %s\n' "Active commit days:"   "$ACTIVE_DAYS / $TOTAL_DAYS total"
  printf '  %-28s %s\n' "Avg commits/active day:" "$AVG"
fi

# ── done ──────────────────────────────────────────────────────────────────────
echo
bold "$SEP"
printf '  Generated %s  |  branch: %s\n' "$(date '+%Y-%m-%d %H:%M %Z')" "$BRANCH"
bold "$SEP"
echo
