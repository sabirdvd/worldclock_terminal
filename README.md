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



