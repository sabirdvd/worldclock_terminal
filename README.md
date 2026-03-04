# World Clock + AI Deadlines

Terminal tools for:
- world time timeline (`worldclock.sh`)
- AI conference deadline tracker (`deadline` command)

## Preview

![World Clock + AI Deadlines preview](./image.png)

## Platform Support

- Linux
- macOS

## Requirements

- Bash
- `tput`
- `date` with timezone support
- `curl` (only needed for `deadline add-auto`)

macOS note:

```bash
brew install coreutils
```

If installed, `gdate` is used automatically for better date parsing.

## Install On Your Machine

1. Clone the repo:

```bash
git clone <YOUR_REPO_URL> world-clock
cd world-clock
```

2. Make scripts executable:

```bash
chmod +x worldclock.sh worldclock_v2.sh worldclock_mgs.sh ai_deadlines.sh deadline
```

3. Install the `deadline` command:

```bash
mkdir -p ~/.local/bin
ln -sf "$PWD/deadline" ~/.local/bin/deadline
```

4. Add `~/.local/bin` to PATH.

Linux (`bash`):

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
hash -r
```

macOS (`zsh`):

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
hash -r
```

macOS (`bash`):

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bash_profile
source ~/.bash_profile
hash -r
```

5. Verify:

```bash
deadline help
```

## Run World Clock

Default clock:

```bash
bash worldclock.sh
```

One-shot:

```bash
INTERVAL=0 bash worldclock.sh
```

Optional extra (v2 alias):

```bash
ln -sf "$PWD/worldclock_v2.sh" ~/.local/bin/worldclock
INTERVAL=0 worldclock
```

## Run AI Deadlines

Run tracker:

```bash
deadline
```

One-shot:

```bash
INTERVAL=0 deadline run
```

Show website column:

```bash
SHOW_WEBSITE=1 deadline run
```

## Deadlines File Location

Default location:

```text
~/.local/share/world-clock/deadlines.txt
```

- Works from any directory.
- File is auto-created on first run.
- If repo `deadlines.txt` exists, it is copied as starter data on first run.

Override location:

```bash
DEADLINES_FILE=/path/to/deadlines.txt deadline
```

## Deadline Commands

Interactive:

```bash
deadline add
deadline add-row
deadline add-auto
deadline remove
deadline list
```

Advanced examples:

```bash
deadline add -n "NeurIPS 2026" -s "Abstract" -d "2026-05-10 13:00" -z "America/Los_Angeles" -w "https://neurips.cc"
deadline add-row -n "NeurIPS 2026" -a "2026-05-10 13:00" -d "2026-05-17 13:00" -z "America/Los_Angeles" -w "https://neurips.cc"
deadline add-auto -n "ICLR 2027" -s "Abstract" -u "https://iclr.cc/Conferences/2027/CallForPapers" -z "UTC"
deadline remove --id 3
deadline remove -n "NeurIPS 2026" -s "Abstract"
```

## `deadlines.txt` Format

```text
Conference Name|Abstract Date|Deadline Date|IANA_Timezone|Website
```

Example:

```text
NeurIPS 2026|2026-05-10 13:00|2026-05-17 13:00|America/Los_Angeles|https://neurips.cc
ICML 2026|2026-01-29 23:59|2026-02-15 23:59|UTC|https://icml.cc
```
