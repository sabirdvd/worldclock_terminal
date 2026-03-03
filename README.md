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
┌──────────────────────────────────────────────────────────────────────────────────────────┐
│ Conference               │ Deadline (Your Time)    │ Status   │ Countdown                │
│ NeurIPS 2026 Abstract    │ 2026-05-10 23:00 EEST   │ OPEN     │ T-68d 09h 42m 18s        │
│ NeurIPS 2026 Full Paper  │ 2026-05-17 23:00 EEST   │ OPEN     │ T-75d 09h 42m 18s        │
│ ICML 2026 Paper          │ 2026-01-30 01:59 EET    │ CLOSED   │ +32d 10h 18m 42s         │
│ ACL 2026 Main Conference │ 2026-05-16 02:59 EEST   │ OPEN     │ T-73d 13h 41m 18s        │
└──────────────────────────────────────────────────────────────────────────────────────────┘
```

Run only the deadline tracker:

```bash
bash ai_deadlines.sh
```

One-shot:

```bash
INTERVAL=0 bash ai_deadlines.sh
```

Add a conference from terminal:

```bash
bash ai_deadlines.sh --add "CVPR 2027 Paper" "2026-11-15 23:59" "America/Los_Angeles"
```

List conferences from terminal:

```bash
bash ai_deadlines.sh --list
```

File format in `deadlines.txt`:

```text
Conference Name|YYYY-MM-DD HH:MM|IANA_Timezone
```

Example:

```text
NeurIPS 2026 Abstract|2026-05-10 13:00|America/Los_Angeles
ICLR 2027 Paper|2026-09-29 17:00|UTC
```

This standalone view converts every conference deadline into your local timezone and shows live countdown with blink/pulse alerts for `SOON` and `CLOSED`.
