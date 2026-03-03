# World Clock + AI Deadlines

Terminal tools for:
- world time timeline (`worldclock.sh`)
- AI conference deadline tracker (`deadline` command)

## Platform Support

Fully supported:
- Linux
- macOS

## Requirements

- Bash
- `tput`
- `curl` (for `deadline add-auto`)
- `date` with timezone support

Linux:
- Usually preinstalled.

macOS:
- Built-in `date` is supported.
- Recommended for best date parsing compatibility:

```bash
brew install coreutils
```

This provides `gdate`, which the script uses automatically when available.

## 1) World Clock

Run:

```bash
bash worldclock.sh
```

One-shot:

```bash
INTERVAL=0 bash worldclock.sh
```

Screenshot:

```text
World Time  •  2026-03-03 15:51:50
+--------------------------------------------------+
| tallinn    -------------*-------  15:51  +00:00 |
| barcelona  ------------*|-------  14:51  -01:00 |
| tokyo      -------------|------*  22:51  +07:00 |
| houston    -----*-------|-------  07:51  -08:00 |
| utc        -----------*-|-------  13:51  -02:00 |
+--------------------------------------------------+
```

## 2) Install `deadline` Command (once)

From project directory:

```bash
chmod +x deadline ai_deadlines.sh
mkdir -p ~/.local/bin
ln -sf "$PWD/deadline" ~/.local/bin/deadline
```

Linux (bash):

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
hash -r
```

macOS (zsh default):

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
hash -r
```

macOS (if using bash):

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bash_profile
source ~/.bash_profile
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

Screenshot:

```text
AI Deadlines ●  •  Your Time: 2026-03-03 15:51:50 EET
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ Conference   │ Stage    │ Deadline (Your Time)   │ Status   │ Countdown              │
│ NeurIPS 2026 │ Abstract │ 2026-05-10 23:00 EEST  │ OPEN     │ T-68d 06h 08m 10s      │
│ ICML 2026    │ Abstract │ 2026-01-30 01:59 EET   │ CLOSED   │ +32d 13h 52m 50s       │
│ SRW 2026     │ Abstract │ 2026-02-04 02:00 EET   │ CLOSED   │ +27d 13h 51m 50s       │
└──────────────────────────────────────────────────────────────────────────────────────┘
Ctrl+C to quit • deadline add/add-auto/list/remove • INTERVAL=0 for one-shot
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
