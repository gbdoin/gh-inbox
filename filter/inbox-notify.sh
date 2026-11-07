#!/usr/bin/env bash
# Inbox notify: decide if a GitHub event concerns INBOX_LOGIN, and if so fire that person's
# Claude scheduled task (API trigger) with the issue or PR number and URL only.
#
# Inputs (environment):
#   GITHUB_EVENT_NAME   issues | issue_comment | pull_request_target | pull_request_review | pull_request_review_comment
#   GITHUB_EVENT_PATH   path to the event JSON
#   INBOX_LOGIN         the GitHub login to watch (repo variable)
#   INBOX_FIRE_URL      the task's fire URL (repo variable)
#   INBOX_FIRE_TOKEN    the task's fire token (repo secret)
#   INBOX_DRY_RUN=1     print the decision and the payload, send nothing (tests)
#
# Output on stdout: "fire <reason>" or "skip <reason>". Exit 0 on fire or skip.
# Exit 1 on a failed fire or a missing input, so the run shows red.
#
# The event text (comment, body) never leaves this script: the payload holds the number, URL,
# event name and actor only. The receiver reads the thread on GitHub itself.
set -euo pipefail

: "${GITHUB_EVENT_NAME:?missing}" "${GITHUB_EVENT_PATH:?missing}" "${INBOX_LOGIN:?missing}"
ev="$GITHUB_EVENT_PATH"
login="$(printf '%s' "$INBOX_LOGIN" | tr '[:upper:]' '[:lower:]')"

j() { jq -r "$1 // empty" "$ev"; }
lc() { tr '[:upper:]' '[:lower:]'; }

action="$(j .action)"
actor="$(j .sender.login | lc)"
item='(.issue // .pull_request)'
repo="$(j .repository.full_name)"; repo="${repo:-unknown}"
number="$(j "$item.number")"
url="$(j "$item.html_url")"
author="$(j "$item.user.login" | lc)"
assignees="$(jq -r "[$item.assignees[]?.login] | map(ascii_downcase) | join(\" \")" "$ev")"

# Text that can carry a mention, per event.
case "$GITHUB_EVENT_NAME" in
  issues|pull_request_target) text="$(j "$item.body")" ;;
  issue_comment|pull_request_review_comment) text="$(j .comment.body)" ;;
  pull_request_review) text="$(j .review.body)" ;;
  *) echo "skip unsupported-event"; exit 0 ;;
esac

decide() {
  [ -n "$number" ] || { echo "skip no-item"; return; }
  [ "$actor" != "$login" ] || { echo "skip own-action"; return; }
  if [ "$action" = "assigned" ] && [ "$(j .assignee.login | lc)" = "$login" ]; then echo "fire assigned"; return; fi
  if [ "$action" = "review_requested" ] && [ "$(j .requested_reviewer.login | lc)" = "$login" ]; then echo "fire review-requested"; return; fi
  # A mention: @login not followed by a login character (so @bob does not match @bobby).
  if printf '%s' "$text" | lc | grep -Eq "(^|[^a-z0-9_-])@${login}([^a-z0-9-]|$)"; then echo "fire mentioned"; return; fi
  # Activity on an item the person owns, except label, unassign and other bookkeeping actions.
  case "$GITHUB_EVENT_NAME:$action" in
    issue_comment:created|pull_request_review:submitted|pull_request_review_comment:created|issues:closed|issues:reopened)
      if [ "$author" = "$login" ]; then echo "fire on-own-item"; return; fi
      for a in $assignees; do [ "$a" = "$login" ] && { echo "fire on-assigned-item"; return; }; done ;;
  esac
  echo "skip not-involved"
}

decision="$(decide)"
echo "$decision"
case "$decision" in fire*) ;; *) exit 0 ;; esac

payload="$(jq -n --arg p "$repo" --arg n "$number" --arg u "$url" --arg e "$GITHUB_EVENT_NAME.$action" --arg a "$actor" --arg r "${decision#fire }" \
  '{text: ($p + "#" + $n + " " + $u + " event=" + $e + " actor=" + $a + " reason=" + $r)}')"

if [ "${INBOX_DRY_RUN:-0}" = "1" ]; then echo "$payload"; exit 0; fi

: "${INBOX_FIRE_URL:?missing}" "${INBOX_FIRE_TOKEN:?missing}"
code="$(curl -sS -o /tmp/inbox-fire.out -w '%{http_code}' -X POST "$INBOX_FIRE_URL" \
  -H "Authorization: Bearer $INBOX_FIRE_TOKEN" \
  -H "anthropic-beta: experimental-cc-routine-2026-04-01" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  --data "$payload")"
# Print the status only. The body can echo session URLs; it is not needed in the log.
echo "fire-status $code"
case "$code" in 2*) exit 0 ;; *) exit 1 ;; esac
