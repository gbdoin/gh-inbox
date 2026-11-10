# Daily digest prompt (scheduled task "Solam daily digest", 07:43 America/Toronto, every day)

The live copy is the scheduled task's prompt (trigger trig_01KxnyQXueTsn9PKMT6UzjMY). Steps:

1. Health: get_session on the inbox; failed, or no poller restart in 2 h → say so first, with the fix.
2. Threads: list_sessions mine:true, keep titles "#<N> ·" (tags filter not available). Use each
   post_turn_summary; read the last result only when the summary is empty or unclear.
3. FYI log: ask the inbox for the last 24 h of ~/solam-inbox/fyi.log; summarize in at most 3 lines.
4. Safety net: 24 h search for gbdoin involvement, repo-wide control count first; send items with no
   thread to the inbox.
5. Post: NOW first (imperative line, issue link, thread link, deadline), then LATER sorted by date,
   then WAITING by who, overdue, log summary,
   WATCH and DONE counts. Wednesday and Thursday: client meeting prep. Check due dates the threads named.
6. PushNotification only if an ACTION item is overdue or the inbox is broken.
