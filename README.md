# claude-code-config

My Claude Code global settings (`~/.claude/`), shared as a reference.

## Contents

- `settings.json`: model and effort defaults, skill overrides (most of the stock catalog is off), status line, plugins (ponytail, caveman), spinner verbs.
- `statusline.ps1`: a PowerShell status line. It shows model and effort, cost, context %, clock, session duration, lines changed, 5-hour and weekly rate-limit usage with reset times, and the directory and branch. It also appends the ponytail and caveman badges when those plugins are installed.

## Use

1. Copy both files into `~/.claude/`.
2. In `settings.json`, change the `statusLine.command` path (`C:\Users\aljuh\...`) to your own home directory.
3. Restart Claude Code.

This is Windows-only as written, because the status line is PowerShell.

## Not included

The following are left out:

- credentials and `.claude.json`, which hold account and machine state
- history, transcripts, logs and caches
- my `autoMode` trust-boundary block and commit attribution, which are specific to my own repos
