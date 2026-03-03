# World Clock (Terminal)

A Bash-based world clock that renders multiple time zones on a live horizontal timeline in your terminal.

```text
World Time  •  2026-03-03 12:02:39
┌───────────────────────────────────────────────────┐
│ tallinn    -------------●-------  12:02  +00:00 │
│ barcelona  ------------●|-------  11:02  -01:00 │
│ tokyo      -------------|------●  19:02  +07:00 │
│ houston    -----●-------|-------  04:02  -08:00 │
│ utc        -----------●-|-------  10:02  -02:00 │
└───────────────────────────────────────────────────┘
```

## Requirements

- Bash
- `date` (with IANA timezone support)
- `tput` (optional, used to hide/show cursor cleanly)

## Run

From this directory:

```bash
bash worldclock.sh
```

Or make it executable:

```bash
chmod +x worldclock.sh
./worldclock.sh
```

## Useful Options

You can control behavior with environment variables:

```bash
# one-shot render (no live refresh)
INTERVAL=0 bash worldclock.sh

# finer timeline spacing (1 dash = 30 minutes)
SCALE_MIN_PER_DASH=30 bash worldclock.sh

# disable colors/styles
NO_COLOR=1 bash worldclock.sh
```

Defaults:

- `SCALE_MIN_PER_DASH=60`
- `BASE_DASHES=5`
- `INTERVAL=1`



## Part 2: Standalone AI Deadline Tracker (Your Current Time)

```text
AI Deadlines (Standalone)  •  Your Time: 2026-03-03 12:17:42 EET
┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Conference   │ Stage    │ Deadline (Your Time)    │ Status    │ Countdown              │ Website    │
│ NeurIPS 2026 │ Abstract │ 2026-05-10 23:00 EEST   │ OPEN      │ T-68d 09h 42m 18s      │ neurips.cc │
│ ICML 2026    │ Abstract │ 2026-01-30 01:59 EET    │ CLOSED    │ +32d 10h 18m 42s       │ icml.cc    │
└─────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Run only the deadline tracker:

```bash
deadline
```

Or make it executable:

```bash
chmod +x ai_deadlines.sh
./ai_deadlines.sh
chmod +x deadline
deadline
```

One-shot:

```bash
INTERVAL=0 bash ai_deadlines.sh
```

Add from terminal with simple dash flags:

```bash
deadline add
deadline add-auto
deadline remove
deadline list
```

Optional advanced flags:

```bash
deadline add -n "NeurIPS 2026" -s "Abstract" -d "2026-05-10 13:00" -z "America/Los_Angeles" -w "https://neurips.cc"
deadline add -n "NeurIPS 2026" -s "Rebuttal" -d "2026-05-17 13:00" -z "America/Los_Angeles" -w "https://neurips.cc"
deadline add -n "NeurIPS 2026" -s "Decision" -d "2026-07-10 09:00" -z "America/Los_Angeles" -w "https://neurips.cc"
```

Auto-fetch date from conference website (best effort):

```bash
deadline add-auto -n "ICLR 2027" -s "Abstract" -u "https://iclr.cc/Conferences/2027/CallForPapers" -z "UTC"
```

Remove deadline with flags (optional):
`deadline remove --id 3`

Run tracker via shortcut:

```bash
deadline run
INTERVAL=0 deadline run
STAGE_FILTER=all deadline run
```

File format in `deadlines.txt`:

```text
Conference Name|Stage|YYYY-MM-DD HH:MM|IANA_Timezone|Website
```

Example stages: `Abstract`, `Rebuttal`, `Decision`.

This standalone view converts every conference deadline into your local timezone and shows live countdown with blink/pulse alerts for `SOON` and `CLOSED`.
Default view shows `Abstract` stage only. Use `STAGE_FILTER=all` to show all stages.
