# gh-inbox

Personal tooling. GitHub activity that needs me goes to Claude sessions: one thread per issue or PR,
with the task, the link and the doc to read. The goal: the team never waits on me without my knowing.

## Parts

| Part | Where it runs | State |
|---|---|---|
| Dispatcher ("inbox") | A Claude cloud session. It routes events to thread sessions. | Running (Solam) |
| Thread per issue or PR | A Claude cloud session per item, tags `solam-inbox` and `solam-#N` | Running |
| PR events | Native PR subscription, from each PR thread | Running |
| Poller | `filter/poll-once.sh`, called every 10 min by the inbox | Running |
| Heartbeat | Scheduled task, hourly: restarts the poller if it stopped | Running |
| Daily digest | Scheduled task, 07:43 America/Toronto, every day | Running |
| Issue push | Org webhook → relay → fire API of the inbox's scheduled task | To build |

## Filter rules (`filter/inbox-notify.sh`)

An event concerns `INBOX_LOGIN` when the actor is someone else and one of these is true:
- the person was assigned, or a review was requested from them;
- the text has `@login` (case-insensitive, whole login only: `@bob` does not match `@bobby` or `x@bob.com`);
- it is a comment, a review, a close or a reopen on an item the person authored or is assigned to.

The payload carries `owner/repo#N`, URL, event name, actor and reason. Never the comment text.

Tests: `bash filter/inbox-notify.test.sh` (21 checks, no network, curl stubbed). A mutation check
removed each guard alone, and its test went red.

## Next: the relay for issue push

A GitHub webhook cannot send the `Authorization: Bearer` header that the fire API needs. So:
1. A small HTTPS function (Vercel) receives the org webhook and checks `X-Hub-Signature-256`.
2. It applies the filter rules above (port of `inbox-notify.sh`, same tests as fixtures).
3. It calls `POST https://api.anthropic.com/v1/claude_code/routines/<trigger_id>/fire` with the
   headers from code.claude.com/docs/en/routines (`anthropic-beta: experimental-cc-routine-2026-04-01`).

Open points before the build:
- Probe: does a fire of a scheduled task bound to an existing session reach that session, or start a
  new one? The docs say an API fire starts a new session.
- The fire token is generated in the claude.ai UI only. It lives in 1Password and in the relay's env.
- The org webhook needs an org owner of Neo-Carbone. Scope it to issue, comment and review events.

## Session prompts

The dispatcher and thread briefs are in `prompts/`. They are the source of truth: a new inbox session
starts from `prompts/dispatcher.md`.
