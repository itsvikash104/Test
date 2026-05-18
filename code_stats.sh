#!/usr/bin/env bash

set -euo pipefail

# ── config ────────────────────────────────────────────────────────────────────
BRANCH="${1:-$(git rev-parse --abbrev-ref HEAD)}"
MONTHS=30
SINCE=$(date -d "$MONTHS months ago" +%Y-%m-%d 2>/dev/null \
        || date -v-${MONTHS}m +%Y-%m-%d)   # macOS fallback
UNTIL=$(date +%Y-%m-%d)

SEP="─────────────────────────────────────────────────────"

# ── helpers ───────────────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
head1() { echo; bold "$SEP"; bold "  $*"; bold "$SEP"; }
head2() { echo; printf '\033[1;34m  ▶ %s\033[0m\n' "$*"; }

# ── sanity check ──────────────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "ERROR: not inside a git repository." >&2; exit 1
fi
if ! git rev-parse --verify "$BRANCH" &>/dev/null; then
  echo "ERROR: branch '$BRANCH' not found." >&2; exit 1
fi

# ── gather raw data ───────────────────────────────────────────────────────────
LOG_ARGS=(log "$BRANCH" --since="$SINCE" --until="$UNTIL" --no-merges)

COMMITS=$(git "${LOG_ARGS[@]}" --oneline | wc -l | tr -d ' ')
MERGE_COMMITS=$(git log "$BRANCH" --since="$SINCE" --until="$UNTIL" \
                    --merges --oneline | wc -l | tr -d ' ')

# lines added / removed across all commits
DIFF_STAT=$(git "${LOG_ARGS[@]}" --numstat \
            | awk 'NF==3 && $1~/^[0-9]+$/ {add+=$1; del+=$2}
                   END {printf "%d %d", add, del}')
LINES_ADDED=$(echo "$DIFF_STAT" | cut -d' ' -f1)
LINES_REMOVED=$(echo "$DIFF_STAT" | cut -d' ' -f2)
NET_LINES=$(( LINES_ADDED - LINES_REMOVED ))

# unique files touched
FILES_CHANGED=$(git "${LOG_ARGS[@]}" --name-only --format="" \
                | sort -u | grep -c . || true)

# contributors
CONTRIBUTORS=$(git "${LOG_ARGS[@]}" --format="%ae" \
               | sort -u | grep -c . || true)

# date of first / last commit in window
FIRST_COMMIT=$(git "${LOG_ARGS[@]}" --format="%ad" --date=short \
               | tail -1)
LAST_COMMIT=$(git "${LOG_ARGS[@]}" --format="%ad" --date=short \
              | head -1)

# ── print summary ─────────────────────────────────────────────────────────────
head1 "CODE STATS — $BRANCH"
printf '  Period  : %s → %s  (%d months)\n' "$SINCE" "$UNTIL" "$MONTHS"
printf '  Analysed: %s → %s\n' "${FIRST_COMMIT:-(none)}" "${LAST_COMMIT:-(none)}"

head2 "Commit Activity"
printf '  %-28s %s\n' "Total commits (no merges):" "$COMMITS"
printf '  %-28s %s\n' "Merge commits:"             "$MERGE_COMMITS"
printf '  %-28s %s\n' "Files changed (unique):"    "$FILES_CHANGED"

head2 "Line Changes"
printf '  %-28s +%s\n' "Lines added:"              "$LINES_ADDED"
printf '  %-28s -%s\n' "Lines removed:"            "$LINES_REMOVED"
printf '  %-28s %s%s\n' "Net change:" \
       "$([ "$NET_LINES" -ge 0 ] && echo '+' || echo '')" "$NET_LINES"

head2 "Contributors"
printf '  %-28s %s\n' "Unique authors:" "$CONTRIBUTORS"
echo
git "${LOG_ARGS[@]}" --format="%aN" \
  | sort | uniq -c | sort -rn \
  | awk '{printf "  %5s commits  %s\n", $1, $2}'

# ── monthly breakdown ─────────────────────────────────────────────────────────
head2 "Monthly Commit Breakdown"
printf '  %-10s  %7s  %10s  %10s\n' "Month" "Commits" "+Lines" "-Lines"
printf '  %-10s  %7s  %10s  %10s\n' "----------" "-------" "----------" "----------"

# iterate month-by-month from oldest to newest
MONTH_DATE="$SINCE"
while [[ "$MONTH_DATE" < "$UNTIL" || "$MONTH_DATE" == "$UNTIL" ]]; do
  NEXT=$(date -d "$MONTH_DATE +1 month" +%Y-%m-%d 2>/dev/null \
         || date -v+1m -jf%Y-%m-%d "$MONTH_DATE" +%Y-%m-%d)

  MONTH_LABEL=$(date -d "$MONTH_DATE" +%Y-%m 2>/dev/null \
                || date -jf%Y-%m-%d "$MONTH_DATE" +%Y-%m)

  MC=$(git log "$BRANCH" --since="$MONTH_DATE" --until="$NEXT" \
           --no-merges --oneline | wc -l | tr -d ' ')

  if [[ "$MC" -gt 0 ]]; then
    MSTAT=$(git log "$BRANCH" --since="$MONTH_DATE" --until="$NEXT" \
                --no-merges --numstat \
                | awk 'NF==3 && $1~/^[0-9]+$/ {a+=$1; d+=$2}
                       END {printf "%d %d", a, d}')
    MA=$(echo "$MSTAT" | cut -d' ' -f1)
    MD=$(echo "$MSTAT" | cut -d' ' -f2)
  else
    MA=0; MD=0
  fi

  printf '  %-10s  %7s  %+10d  %10d\n' "$MONTH_LABEL" "$MC" "$MA" "-$MD"
  MONTH_DATE="$NEXT"
done

# ── top changed files ─────────────────────────────────────────────────────────
head2 "Top 10 Most-Changed Files"
printf '  %7s  %s\n' "Changes" "File"
printf '  %7s  %s\n' "-------" "----"
git "${LOG_ARGS[@]}" --name-only --format="" \
  | sort | uniq -c | sort -rn | head -10 \
  | awk '{printf "  %7s  %s\n", $1, $2}'

# ── extension breakdown ───────────────────────────────────────────────────────
head2 "Changes by File Extension"
printf '  %7s  %s\n' "Count" "Extension"
printf '  %7s  %s\n' "-------" "---------"
git "${LOG_ARGS[@]}" --name-only --format="" \
  | grep '\.' \
  | sed 's/.*\./\./' \
  | sort | uniq -c | sort -rn | head -15 \
  | awk '{printf "  %7s  %s\n", $1, $2}'

# ── done ──────────────────────────────────────────────────────────────────────
echo
bold "$SEP"
printf '  Generated on %s for branch: %s\n' "$(date '+%Y-%m-%d %H:%M %Z')" "$BRANCH"
bold "$SEP"
echo
