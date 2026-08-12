# Knowledge index

One entry per `rule`/`trap` card in this directory. Read this file first
(`AGENTS.md` session-start step); if a line's symptoms match your task, read that card
only. Hard cap: **80 lines**. See `README.md` for the card contract and the write path.

merge-is-not-deploy — Merging a fix does not run anything on the server; if its mechanism is a manual step, the fix is not live.
  Symptoms: A pull request merged and its checks are green, but the metric/config/rule it was supposed to change has not moved after a full deploy window; the fix's last step is a runbook line telling a human to run something over ssh.
