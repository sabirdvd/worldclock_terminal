# World Clock + Conference Deadlines

Terminal tools for:
- world time timeline (`worldclock.sh`)
- AI conference deadline tracker (`deadline` command)

## Requirements

- Bash
- `date` (GNU date with timezone support)
- `tput`
- `curl` (only for `deadline add-auto`)

## 1) World Clock

Run:

```bash
bash worldclock.sh
```

One-shot:

```bash
INTERVAL=0 bash worldclock.sh
```

## 2) Install `deadline` Command (once)

From project directory:

```bash
chmod +x deadline ai_deadlines.sh
mkdir -p ~/.local/bin
ln -sf "$PWD/deadline" ~/.local/bin/deadline
```

If needed, ensure PATH includes `~/.local/bin`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
hash -r
```

Verify:

```bash
deadline help
```

## 3) Use `deadline`

Run tracker:

```bash
deadline
```

Interactive commands:

```bash
deadline add
deadline add-auto
deadline remove
deadline list
```

One-shot:

```bash
INTERVAL=0 deadline run
```

Show all stages (default view is `Abstract` only):

```bash
STAGE_FILTER=all deadline run
```

Show website column:

```bash
SHOW_WEBSITE=1 deadline run
```

## Advanced Commands

Manual add:

```bash
deadline add -n "NeurIPS 2026" -s "Abstract" -d "2026-05-10 13:00" -z "America/Los_Angeles" -w "https://neurips.cc"
```

Auto-fetch from website (best effort):

```bash
deadline add-auto -n "ICLR 2027" -s "Abstract" -u "https://iclr.cc/Conferences/2027/CallForPapers" -z "UTC"
```

Remove:

```bash
deadline remove --id 3
deadline remove -n "NeurIPS 2026" -s "Abstract"
```

## `deadlines.txt` format

```text
Conference Name|Stage|YYYY-MM-DD HH:MM|IANA_Timezone|Website
```

Example:

```text
NeurIPS 2026|Abstract|2026-05-10 13:00|America/Los_Angeles|https://neurips.cc
NeurIPS 2026|Rebuttal|2026-05-17 13:00|America/Los_Angeles|https://neurips.cc
NeurIPS 2026|Decision|2026-07-10 09:00|America/Los_Angeles|https://neurips.cc
```
