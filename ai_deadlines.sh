#!/usr/bin/env bash
set -euo pipefail

DEADLINES_FILE=${DEADLINES_FILE:-deadlines.txt}
INTERVAL=${INTERVAL:-1}
DEADLINE_SOON_HOURS=${DEADLINE_SOON_HOURS:-168} # 7 days

DEADLINE_ENTRIES=()

if [[ -n "${NO_COLOR:-}" ]]; then
  S_RESET_ALL=""; S_BOLD=""; S_DIM=""; S_BLINK=""; S_BLINK_OFF=""
  C_BORDER=""; C_LABEL=""; C_OK=""; C_WARN=""; C_BAD=""
else
  S_RESET_ALL=$'\033[0m'
  S_BOLD=$'\033[1m'
  S_DIM=$'\033[2m'
  S_BLINK=$'\033[5m'
  S_BLINK_OFF=$'\033[25m'

  C_BORDER=$'\033[38;5;33m'
  C_LABEL=$'\033[38;5;250m'
  C_OK=$'\033[38;5;84m'
  C_WARN=$'\033[38;5;220m'
  C_BAD=$'\033[38;5;203m'
fi

repeat_char () {
  local ch="$1" n="$2" s
  (( n <= 0 )) && return 0
  printf -v s '%*s' "$n" ''
  printf '%s' "${s// /$ch}"
}

trim () {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

fmt_countdown () {
  local secs="$1"
  local sign="T-"
  if (( secs < 0 )); then
    sign="+"
    secs=$(( -secs ))
  fi

  local d h m s
  d=$(( secs / 86400 ))
  h=$(( (secs % 86400) / 3600 ))
  m=$(( (secs % 3600) / 60 ))
  s=$(( secs % 60 ))
  printf "%s%dd %02dh %02dm %02ds" "$sign" "$d" "$h" "$m" "$s"
}

deadline_to_epoch () {
  local when="$1" tz="$2"
  TZ="$tz" date -d "$when" +%s 2>/dev/null
}

show_usage () {
  cat <<'EOF'
Usage:
  bash ai_deadlines.sh
  bash ai_deadlines.sh --add "Conference Name" "YYYY-MM-DD HH:MM" "IANA_Timezone"
  bash ai_deadlines.sh --list
  bash ai_deadlines.sh --help
EOF
}

add_deadline () {
  local name="$1" when="$2" tz="$3"

  if ! deadline_to_epoch "$when" "$tz" >/dev/null; then
    echo "Invalid date/time or timezone. Use: YYYY-MM-DD HH:MM and valid IANA timezone." >&2
    return 1
  fi

  printf "%s|%s|%s\n" "$name" "$when" "$tz" >> "$DEADLINES_FILE"
  echo "Added: $name | $when | $tz"
}

list_deadlines () {
  if [[ ! -f "$DEADLINES_FILE" ]]; then
    echo "No deadlines file found: $DEADLINES_FILE"
    return 0
  fi

  awk 'NF && $1 !~ /^#/' "$DEADLINES_FILE"
}

load_deadlines () {
  DEADLINE_ENTRIES=()
  [[ -f "$DEADLINES_FILE" ]] || return 0

  local line name when tz
  while IFS= read -r line; do
    line="$(trim "$line")"
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

    IFS='|' read -r name when tz <<< "$line"
    name="$(trim "${name:-}")"
    when="$(trim "${when:-}")"
    tz="$(trim "${tz:-}")"
    [[ -z "$name" || -z "$when" || -z "$tz" ]] && continue

    DEADLINE_ENTRIES+=("$name|$when|$tz")
  done < "$DEADLINES_FILE"
}

cleanup () {
  tput cnorm 2>/dev/null || true
  printf "%b" "$S_RESET_ALL"
}
trap cleanup EXIT INT TERM

render_once () {
  local tick="$1"
  local now_local now_epoch soon_secs
  now_local="$(date +%Y-%m-%d\ %H:%M:%S\ %Z)"
  now_epoch="$(date +%s)"
  soon_secs=$(( DEADLINE_SOON_HOURS * 3600 ))

  local name_w=10 local_due_w=23 status_w=8 count_w=22
  local rec name d when tz due_local epoch len

  for rec in "${DEADLINE_ENTRIES[@]}"; do
    name="${rec%%|*}"
    d="${rec#*|}"
    when="${d%%|*}"
    tz="${d#*|}"

    (( ${#name} > name_w )) && name_w=${#name}

    if epoch="$(deadline_to_epoch "$when" "$tz")"; then
      due_local="$(date -d "@$epoch" +'%Y-%m-%d %H:%M %Z')"
    else
      due_local="invalid date/time"
    fi
    len=${#due_local}
    (( len > local_due_w )) && local_due_w=$len
  done

  local inner_w=$(( name_w + local_due_w + status_w + count_w + 13 ))
  local top="┌$(repeat_char '─' "$inner_w")┐"
  local bot="└$(repeat_char '─' "$inner_w")┘"

  printf "\033[H\033[2J"
  printf "%b%s%b\n" "$C_BORDER$S_BOLD" "AI Deadlines (Standalone)  •  Your Time: $now_local" "$S_RESET_ALL"
  printf "%b%s%b\n" "$C_BORDER" "$top" "$S_RESET_ALL"

  printf "│ %b%-*s%b │ %b%-*s%b │ %b%-*s%b │ %b%-*s%b │\n" \
    "$S_BOLD$C_LABEL" "$name_w" "Conference" "$S_RESET_ALL" \
    "$S_BOLD$C_LABEL" "$local_due_w" "Deadline (Your Time)" "$S_RESET_ALL" \
    "$S_BOLD$C_LABEL" "$status_w" "Status" "$S_RESET_ALL" \
    "$S_BOLD$C_LABEL" "$count_w" "Countdown" "$S_RESET_ALL"

  if (( ${#DEADLINE_ENTRIES[@]} == 0 )); then
    printf "│ %-*s │\n" "$inner_w" "No deadlines found. Add lines to $DEADLINES_FILE"
    printf "%b%s%b\n" "$C_BORDER" "$bot" "$S_RESET_ALL"
    return 0
  fi

  local remaining status countdown status_color status_cell pulse
  for rec in "${DEADLINE_ENTRIES[@]}"; do
    name="${rec%%|*}"
    d="${rec#*|}"
    when="${d%%|*}"
    tz="${d#*|}"

    if ! epoch="$(deadline_to_epoch "$when" "$tz")"; then
      due_local="invalid date/time"
      status="BAD"
      countdown="invalid date"
      status_color="$C_BAD"
    else
      due_local="$(date -d "@$epoch" +'%Y-%m-%d %H:%M %Z')"
      remaining=$(( epoch - now_epoch ))
      if (( remaining < 0 )); then
        status="CLOSED"
        status_color="$C_BAD"
      elif (( remaining <= soon_secs )); then
        status="SOON"
        status_color="$C_WARN"
      else
        status="OPEN"
        status_color="$C_OK"
      fi
      countdown="$(fmt_countdown "$remaining")"
    fi

    status_cell="$status"
    if [[ "$status" == "SOON" || "$status" == "CLOSED" || "$status" == "BAD" ]]; then
      pulse="●"
      if (( tick % 2 == 1 )); then pulse="◉"; fi
      status_cell="$status $pulse"
    fi

    printf "│ %-*s │ %-*s │ %b%-*s%b │ %-*s │\n" \
      "$name_w" "$name" \
      "$local_due_w" "$due_local" \
      "$status_color$S_BOLD$S_BLINK" "$status_w" "$status_cell" "$S_BLINK_OFF$S_RESET_ALL" \
      "$count_w" "$countdown"
  done

  printf "%b%s%b\n" "$C_BORDER" "$bot" "$S_RESET_ALL"
  printf "%b%s%b\n" "$S_DIM" "Ctrl+C to quit • Use --add to add conferences • INTERVAL=0 for one-shot" "$S_RESET_ALL"
}

main () {
  if (( $# > 0 )); then
    case "${1:-}" in
      --add)
        if (( $# != 4 )); then
          show_usage
          return 1
        fi
        add_deadline "$2" "$3" "$4"
        return 0
        ;;
      --list)
        list_deadlines
        return 0
        ;;
      --help|-h)
        show_usage
        return 0
        ;;
      *)
        show_usage
        return 1
        ;;
    esac
  fi

  tput civis 2>/dev/null || true
  load_deadlines

  local tick=0
  render_once "$tick"
  (( INTERVAL <= 0 )) && return 0

  while :; do
    sleep "$INTERVAL"
    tick=$((tick + 1))
    render_once "$tick"
  done
}

main "$@"
