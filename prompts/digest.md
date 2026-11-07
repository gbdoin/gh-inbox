# Daily digest prompt (scheduled task "Solam daily digest")

Scheduled run: Solam daily digest for gbdoin (every day, weekends included). Read-only on GitHub.
Event routing lives in the inbox session <INBOX_SESSION_ID> and its per-issue thread sessions
(tag `solam-inbox`).

1. Health: get_session on the inbox. If status_bucket is failed, or its last events show no poller
   restart in the last 2 hours, say so first, with the fix.
2. Threads: the list_sessions tags filter is not available (2026-11-07). Use list_sessions with
   mine:true and keep titles that start with "#<number> ·"; the inbox also keeps the registry in
   ~/solam-inbox/threads.tsv. For each thread, read its last assistant message (list_events, kinds
   ["assistant"]). Collect the current status line.
3. Safety net: run the search for gbdoin involvement updated in the last 24 h (assignee, mentions,
   review-requested, author, commenter; with the repo-wide control count first). Name any item that
   changed but has no thread, and send it to the inbox with send_message.
4. Post, short: ACTION items first (one imperative line each, link to the issue and to its thread
   session, due date), then overdue items, then WATCH and DONE counts. Wednesday and Thursday: add the
   prep list for the next client meeting (the open `meeting` issue) with the open client-decision
   issues assigned to gbdoin and what to ask for each.
5. PushNotification only if an ACTION item is overdue or the inbox is broken.
