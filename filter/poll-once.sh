#!/usr/bin/env bash
# Poll once: list items in INBOX_REPO that involve INBOX_LOGIN and changed since a timestamp.
# Usage: check.sh [SINCE_ISO]   (default: value in state file, else 24h ago)
# Output: TSV  number  kind  updated_at  last_actor_hint(author)  reasons  labels  title
set -euo pipefail
DIR="${INBOX_STATE_DIR:-$HOME/.gh-inbox}"; mkdir -p "$DIR"
STATE="$DIR/last_check"
SINCE="${1:-$(cat "$STATE" 2>/dev/null || date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)}"
# The search index can lag by more than 40 minutes (seen 2026-11-09: an update at 01:01Z was not
# returned at 01:41Z). Search from SINCE minus LAG, and drop (number, updated_at) pairs seen before.
LAG="${INBOX_LAG:-2 hours}"
QSINCE="$(date -u -d "$SINCE - $LAG" +%Y-%m-%dT%H:%M:%SZ)"
SEEN="$DIR/seen"; touch "$SEEN"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
: "${INBOX_REPO:?set INBOX_REPO=owner/name}" "${INBOX_LOGIN:?set INBOX_LOGIN}"
R="repo:$INBOX_REPO"
U="$INBOX_LOGIN"
TMP="$(mktemp -d)"

# Control (CLAUDE.md section 3 rule 4): the repo must return non-zero open items, else the search is broken.
CTRL=$(gh api -X GET search/issues -f q="$R is:issue is:open" -f per_page=1 --jq .total_count)
if [ "${CTRL:-0}" -eq 0 ]; then echo "CONTROL FAILED: repo search returned 0 open issues" >&2; exit 2; fi

q() { # $1 reason, $2 query
  gh api -X GET search/issues -f q="$R $2 updated:>=$QSINCE" -f per_page=100 --paginate \
    --jq ".items[] | [.number, (if .pull_request then \"pr\" else \"issue\" end), .state, .updated_at, .user.login, \"$1\", ([.labels[].name]|join(\",\")), .title] | @tsv" >> "$TMP/all.tsv" || true
}
q assigned          "assignee:$U is:issue"
q assigned          "assignee:$U is:pr"
q mentioned         "mentions:$U is:issue"
q mentioned         "mentions:$U is:pr"
q review-requested  "review-requested:$U is:pr is:open"
q author            "author:$U is:issue"
q author            "author:$U is:pr"
q commenter         "commenter:$U is:issue"
q commenter         "commenter:$U is:pr"

echo "# since=$SINCE query_since=$QSINCE now=$NOW control_open_issues=$CTRL"
# Keep only pairs not in SEEN. An empty SEEN keeps every line (awk reads SEEN first only when non-empty).
if [ -s "$TMP/all.tsv" ]; then
  awk -F'\t' 'FNR==NR && FILENAME==ARGV[1] {seen[$0]=1; next} !(($1"\t"$4) in seen)' "$SEEN" "$TMP/all.tsv" > "$TMP/new.tsv"
  cut -f1,4 "$TMP/new.tsv" >> "$SEEN"
  mv "$TMP/new.tsv" "$TMP/all.tsv"
fi
if [ -s "$TMP/all.tsv" ]; then
  awk -F'\t' 'BEGIN{OFS="\t"} {k=$1; if(!(k in row)){row[k]=$0; why[k]=$6} else if(index(why[k],$6)==0){why[k]=why[k]","$6}}
    END{for(k in row){split(row[k],f,"\t"); print f[1],f[2],f[3],f[4],f[5],why[k],f[7],f[8]}}' "$TMP/all.tsv" | sort -t$'\t' -k4,4r
fi
echo "$NOW" > "$STATE"
rm -rf "$TMP"
