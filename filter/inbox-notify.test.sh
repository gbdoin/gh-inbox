#!/usr/bin/env bash
# SYNTHETIC test data: logins below are invented.
# Hermetic tests for scripts/inbox-notify.sh: no network (curl is stubbed).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT="$HERE/inbox-notify.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export INBOX_LOGIN=watched-dev
fail=0; n=0

# ev <file> <jq program building the event>
ev() { jq -n "$2" > "$T/$1.json"; }
# expect <event-name> <file> <expected first line prefix>
expect() {
  n=$((n+1))
  out="$(GITHUB_EVENT_NAME="$1" GITHUB_EVENT_PATH="$T/$2.json" INBOX_DRY_RUN=1 bash "$SUT" 2>&1)"
  first="${out%%$'\n'*}"
  if [ "$first" = "$3" ]; then echo "ok   $2: $first"; else echo "FAIL $2: got '$first', want '$3'"; fail=1; fi
}

issue='{number: 7, html_url: "https://github.com/o/r/issues/7", user: {login: "other-dev"}, assignees: [], body: ""}'
ev assigned-me      "{action: \"assigned\", sender: {login: \"lead-dev\"}, assignee: {login: \"Watched-Dev\"}, issue: $issue}"
ev assigned-other   "{action: \"assigned\", sender: {login: \"lead-dev\"}, assignee: {login: \"other-dev\"}, issue: $issue}"
ev review-me        '{action: "review_requested", sender: {login: "other-dev"}, requested_reviewer: {login: "watched-dev"}, pull_request: {number: 8, html_url: "u", user: {login: "other-dev"}, assignees: [], body: ""}}'
ev mention          "{action: \"created\", sender: {login: \"other-dev\"}, comment: {body: \"Can you check this, @Watched-Dev?\"}, issue: $issue}"
ev mention-start    "{action: \"created\", sender: {login: \"other-dev\"}, comment: {body: \"@watched-dev see above\"}, issue: $issue}"
ev mention-prefix   "{action: \"created\", sender: {login: \"other-dev\"}, comment: {body: \"cc @watched-devops\"}, issue: $issue}"
ev mention-hyphen   "{action: \"created\", sender: {login: \"other-dev\"}, comment: {body: \"cc @watched-dev-bot\"}, issue: $issue}"
ev mention-email    "{action: \"created\", sender: {login: \"other-dev\"}, comment: {body: \"mail x@watched-dev.example\"}, issue: $issue}"
ev own-action       "{action: \"created\", sender: {login: \"watched-dev\"}, comment: {body: \"note to @watched-dev\"}, issue: $issue}"
ev own-item         '{action: "created", sender: {login: "other-dev"}, comment: {body: "done"}, issue: {number: 9, html_url: "u", user: {login: "watched-dev"}, assignees: [], body: ""}}'
ev assigned-item    '{action: "created", sender: {login: "other-dev"}, comment: {body: "done"}, issue: {number: 9, html_url: "u", user: {login: "other-dev"}, assignees: [{login: "watched-dev"}], body: ""}}'
ev label-own-item   '{action: "labeled", sender: {login: "other-dev"}, issue: {number: 9, html_url: "u", user: {login: "watched-dev"}, assignees: [], body: ""}}'
ev review-own-pr    '{action: "submitted", sender: {login: "other-dev"}, review: {body: null}, pull_request: {number: 10, html_url: "u", user: {login: "watched-dev"}, assignees: [], body: ""}}'
ev unrelated        "{action: \"created\", sender: {login: \"other-dev\"}, comment: {body: \"looks good\"}, issue: $issue}"
ev leak             "{action: \"created\", sender: {login: \"other-dev\"}, comment: {body: \"@watched-dev SECRETWORD-123\"}, issue: $issue}"

expect issues        assigned-me     "fire assigned"
expect issues        assigned-other  "skip not-involved"
expect pull_request_target review-me "fire review-requested"
ev review-other '{action: "review_requested", sender: {login: "other-dev"}, requested_reviewer: {login: "third-dev"}, pull_request: {number: 8, html_url: "u", user: {login: "other-dev"}, assignees: [], body: ""}}'
expect pull_request_target review-other "skip not-involved"
# The watched login is set in mixed case in the repo variable.
INBOX_LOGIN=Watched-Dev expect issue_comment mention "fire mentioned"
expect issue_comment mention         "fire mentioned"
expect issue_comment mention-start   "fire mentioned"
expect issue_comment mention-prefix  "skip not-involved"
expect issue_comment mention-hyphen  "skip not-involved"
expect issue_comment mention-email   "skip not-involved"
expect issue_comment own-action      "skip own-action"
expect issue_comment own-item        "fire on-own-item"
expect issue_comment assigned-item   "fire on-assigned-item"
expect issues        label-own-item  "skip not-involved"
expect pull_request_review review-own-pr "fire on-own-item"
expect issue_comment unrelated       "skip not-involved"
expect workflow_run  unrelated       "skip unsupported-event"

# The payload must not carry the comment text.
n=$((n+1))
out="$(GITHUB_EVENT_NAME=issue_comment GITHUB_EVENT_PATH="$T/leak.json" INBOX_DRY_RUN=1 bash "$SUT")"
if printf '%s' "$out" | grep -q SECRETWORD; then echo "FAIL leak: comment text in payload"; fail=1
elif printf '%s' "$out" | grep -q '#7 https'; then echo "ok   leak: payload holds the number only"
else echo "FAIL leak: no payload printed (control)"; fail=1; fi

# Exit status follows the HTTP status of the fire (curl stub).
mkdir -p "$T/bin"
cat > "$T/bin/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s' "${STUB_CODE}"
EOF
chmod +x "$T/bin/curl"
for code in 200 401 500; do
  n=$((n+1))
  PATH="$T/bin:$PATH" STUB_CODE=$code GITHUB_EVENT_NAME=issue_comment GITHUB_EVENT_PATH="$T/mention.json" \
    INBOX_FIRE_URL=https://example.invalid/fire INBOX_FIRE_TOKEN=test-only bash "$SUT" >/dev/null 2>&1
  rc=$?; want=1; [ "$code" = 200 ] && want=0
  if [ "$rc" = "$want" ]; then echo "ok   http $code: exit $rc"; else echo "FAIL http $code: exit $rc, want $want"; fail=1; fi
done

echo "$n checks, $([ $fail = 0 ] && echo all passed || echo FAILURES)"
exit $fail
