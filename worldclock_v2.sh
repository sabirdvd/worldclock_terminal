#!/usr/bin/env bash
set -euo pipefail

# label|IANA_timezone
ZONES=(
  "tallinn|Europe/Tallinn"
  "barcelona|Europe/Madrid"
  "tokyo|Asia/Tokyo"
  "houston|America/Chicago"
  "utc|UTC"
)

SCALE_MIN_PER_DASH=${SCALE_MIN_PER_DASH:-60}   # 1 dash per hour (try 30 for finer spacing)
BASE_DASHES=${BASE_DASHES:-5}                  # left padding before the left-most marker
INTERVAL=${INTERVAL:-1}                        # seconds between redraws (set 0 for one-shot)
DEADLINES_FILE=${DEADLINES_FILE:-deadlines.txt}
DEADLINE_SOON_HOURS=${DEADLINE_SOON_HOURS:-168} # 7 days

DEADLINE_ENTRIES=()

# --- ANSI helpers ---
if [[ -n "${NO_COLOR:-}" ]]; then
  S_RESET_ALL=""; S_FG_DEFAULT=""; S_BG_DEFAULT=""; S_DIM=""; S_BOLD=""; S_INT_NORM=""; S_BLINK=""; S_BLINK_OFF=""
  C_BORDER=""; C_LABEL=""; C_TIME_DAY=""; C_TIME_NIGHT=""; C_DELTA=""; C_MARK_A=""; C_MARK_B=""; BG1=""; BG2=""
  C_OK=""; C_WARN=""; C_BAD=""
else
  S_RESET_ALL=$'\033[0m'
  S_FG_DEFAULT=$'\033[39m'
  S_BG_DEFAULT=$'\033[49m'
  S_DIM=$'\033[2m'
  S_BOLD=$'\033[1m'
  S_INT_NORM=$'\033[22m'
  S_BLINK=$'\033[5m'       # many terminals ignore this; we also pulse color/shape
  S_BLINK_OFF=$'\033[25m'

  C_BORDER=$'\033[38;5;33m'
  C_LABEL=$'\033[38;5;250m'
  C_TIME_DAY=$'\033[38;5;51m'
  C_TIME_NIGHT=$'\033[38;5;69m'
  C_DELTA=$'\033[38;5;244m'
  C_MARK_A=$'\033[1;38;5;214m'
  C_MARK_B=$'\033[1;38;5;196m'
  BG1=$'\033[48;5;235m'
  BG2=$'\033[48;5;234m'

  C_OK=$'\033[38;5;84m'
  C_WARN=$'\033[38;5;220m'
  C_BAD=$'\033[38;5;203m'
fi

repeat_char () {
  # repeat_char <char> <count>
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

ellipsize () {
  local s="$1" max="$2"
  if (( ${#s} <= max )); then
    printf '%s' "$s"
    return 0
  fi
  if (( max <= 3 )); then
    printf '%s' "${s:0:max}"
    return 0
  fi
  printf '%s...' "${s:0:max-3}"
}

min_since_midnight () {
  local tz="$1" hh mm
  hh="$(TZ="$tz" date +%H)"
  mm="$(TZ="$tz" date +%M)"
  echo $((10#$hh * 60 + 10#$mm))
}

floor_div () {
  # floor(a/b) for integers, even when a is negative
  local a="$1" b="$2"
  if (( a >= 0 )); then
    echo $(( a / b ))
  else
    echo $(( - (( -a + b - 1 ) / b ) ))
  fi
}

normalize_delta () {
  # closest signed delta in [-12h, +12h]
  local d="$1"
  (( d > 720 )) && d=$((d - 1440))
  (( d < -720 )) && d=$((d + 1440))
  echo "$d"
}

fmt_delta () {
  local mins="$1" sign="+"
  (( mins < 0 )) && sign="-" && mins=$(( -mins ))
  printf "%s%02d:%02d" "$sign" $(( mins / 60 )) $(( mins % 60 ))
}

is_daylight () {
  # 07:00-19:59
  local hh="$1"
  ((10#$hh >= 7 && 10#$hh < 20))
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

load_deadlines () {
  DEADLINE_ENTRIES=()

  if [[ ! -f "$DEADLINES_FILE" ]]; then
    return 0
  fi

  local line f1 f2 f3 f4 f5 name when tz
  while IFS= read -r line; do
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    [[ "${line:0:1}" == "#" ]] && continue

    # Supports:
    # 1) name|when|tz
    # 2) name|stage|when|tz
    # 3) name|abstract_when|deadline_when|tz|website
    IFS='|' read -r f1 f2 f3 f4 f5 <<< "$line"
    f1="$(trim "${f1:-}")"
    f2="$(trim "${f2:-}")"
    f3="$(trim "${f3:-}")"
    f4="$(trim "${f4:-}")"
    f5="$(trim "${f5:-}")"

    name="$f1"
    if [[ -n "$f5" ]]; then
      when="$f3"
      tz="$f4"
    elif [[ -n "$f4" ]]; then
      when="$f3"
      tz="$f4"
    else
      when="$f2"
      tz="$f3"
    fi

    [[ -z "$name" || -z "$when" || -z "$tz" ]] && continue
    DEADLINE_ENTRIES+=("$name|$when|$tz")
  done < "$DEADLINES_FILE"
}

render_deadlines () {
  local tick="$1"
  if (( ${#DEADLINE_ENTRIES[@]} == 0 )); then
    return 0
  fi

  local name_w=10 due_w=23 status_w=8 count_w=22
  local d name when tz rec len

  for rec in "${DEADLINE_ENTRIES[@]}"; do
    name="${rec%%|*}"
    d="${rec#*|}"
    when="${d%%|*}"
    tz="${d#*|}"

    len=${#name}
    (( len > name_w )) && name_w=$len

    len=$(( ${#when} + 1 + ${#tz} ))
    (( len > due_w )) && due_w=$len
  done

  (( name_w > 18 )) && name_w=18
  (( due_w > 32 )) && due_w=32

  # Row text width is sum(widths) + 13; border encloses inner area (+2),
  # so inner width must be sum(widths) + 11 for exact alignment.
  local inner_w=$(( name_w + due_w + status_w + count_w + 11 ))
  local top="+$(repeat_char '-' "$inner_w")+"
  local bot="+$(repeat_char '-' "$inner_w")+"

  local now_epoch soon_secs
  now_epoch="$(date +%s)"
  soon_secs=$(( DEADLINE_SOON_HOURS * 3600 ))

  printf "\n%b%s%b\n" "$C_BORDER$S_BOLD" "AI Conference Deadlines" "$S_RESET_ALL"
  printf "%b%s%b\n" "$C_BORDER" "$top" "$S_RESET_ALL"
  printf "| %b%-*s%b | %b%-*s%b | %b%-*s%b | %b%-*s%b |\n" \
    "$S_BOLD$C_LABEL" "$name_w" "Conference" "$S_RESET_ALL" \
    "$S_BOLD$C_LABEL" "$due_w" "Deadline (Local)" "$S_RESET_ALL" \
    "$S_BOLD$C_LABEL" "$status_w" "Status" "$S_RESET_ALL" \
    "$S_BOLD$C_LABEL" "$count_w" "Countdown" "$S_RESET_ALL"

  local epoch remaining status countdown status_color due_text status_cell pulse show_name show_due
  for rec in "${DEADLINE_ENTRIES[@]}"; do
    name="${rec%%|*}"
    d="${rec#*|}"
    when="${d%%|*}"
    tz="${d#*|}"

    due_text="$when $tz"
    if ! epoch="$(deadline_to_epoch "$when" "$tz")"; then
      status="BAD"
      countdown="invalid date"
      status_color="$C_BAD"
    else
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
      pulse="*"
      status_cell="$status $pulse"
    fi

    show_name="$(ellipsize "$name" "$name_w")"
    show_due="$(ellipsize "$due_text" "$due_w")"
    printf "| %-*s | %-*s | %b%-*s%b | %-*s |\n" \
      "$name_w" "$show_name" \
      "$due_w" "$show_due" \
      "$status_color$S_BOLD$S_BLINK" "$status_w" "$status_cell" "$S_BLINK_OFF$S_RESET_ALL" \
      "$count_w" "$countdown"
  done

  printf "%b%s%b\n" "$C_BORDER" "$bot" "$S_RESET_ALL"
}

cleanup () {
  tput cnorm 2>/dev/null || true
  printf "%b" "$S_RESET_ALL"
}
trap cleanup EXIT INT TERM

render_once () {
  local tick="$1"

  local ref_tz="${ZONES[0]#*|}"
  local ref_m
  ref_m="$(min_since_midnight "$ref_tz")"

  local labels=() times=() relpos=() deltas=() dayflags=()
  local label_w=0 min_rel=0 max_rel=0 first=1

  local z label tz hm hh m raw delta rel
  for z in "${ZONES[@]}"; do
    label="${z%%|*}"
    tz="${z#*|}"

    hm="$(TZ="$tz" date +%H:%M)"
    hh="${hm%%:*}"
    m="$(min_since_midnight "$tz")"

    raw=$(( m - ref_m ))
    delta="$(normalize_delta "$raw")"
    rel="$(floor_div "$delta" "$SCALE_MIN_PER_DASH")"

    labels+=("$label")
    times+=("$hm")
    relpos+=("$rel")
    deltas+=("$(fmt_delta "$delta")")
    if is_daylight "$hh"; then dayflags+=("day"); else dayflags+=("night"); fi

    (( ${#label} > label_w )) && label_w=${#label}

    if (( first == 1 )); then
      min_rel="$rel"; max_rel="$rel"; first=0
    else
      (( rel < min_rel )) && min_rel="$rel"
      (( rel > max_rel )) && max_rel="$rel"
    fi
  done

  local shift=$(( BASE_DASHES - min_rel ))
  local line_w=$(( shift + max_rel + 1 ))
  local ref_col=$(( shift + 0 ))

  # inside width between border chars
  # row layout: " %-*s  <line>  %5s  %6s "
  local inner_w=$(( label_w + line_w + 19 ))

  local top bot
  top="+$(repeat_char '-' "$inner_w")+"
  bot="+$(repeat_char '-' "$inner_w")+"

  # pulsing marker: color + shape alternates
  local MARK="*" MARK_C="$C_MARK_A"
  if (( tick % 2 == 1 )); then MARK="*"; MARK_C="$C_MARK_B"; fi

  # clear + home
  printf "\033[H\033[2J"

  local now
  now="$(date +%Y-%m-%d\ %H:%M:%S)"
  printf "%b%s%b\n" "$C_BORDER$S_BOLD" "World Time v2  •  $now" "$S_RESET_ALL"

  printf "%b%s%b\n" "$C_BORDER" "$top" "$S_RESET_ALL"

  local i rel_abs before_len after_len before after time_c bg
  for i in "${!labels[@]}"; do
    rel_abs=$(( shift + relpos[i] ))
    before_len="$rel_abs"
    after_len=$(( line_w - rel_abs - 1 ))

    # Build before/after track with a faint reference guide "|" at ref_col.
    if (( ref_col >= 0 && ref_col < before_len )); then
      before="$(repeat_char '-' "$ref_col")|$(repeat_char '-' $((before_len - ref_col - 1)))"
    else
      before="$(repeat_char '-' "$before_len")"
    fi

    if (( ref_col > rel_abs && ref_col < line_w )); then
      local gap=$(( ref_col - rel_abs - 1 ))
      local tail=$(( line_w - ref_col - 1 ))
      after="$(repeat_char '-' "$gap")|$(repeat_char '-' "$tail")"
    else
      after="$(repeat_char '-' "$after_len")"
    fi

    # Keep row background (if any) while changing only foreground/style.
    local line
    line="${S_DIM}${before}${S_INT_NORM}${MARK_C}${S_BLINK}${MARK}${S_BLINK_OFF}${S_INT_NORM}${S_DIM}${after}${S_INT_NORM}${S_FG_DEFAULT}"

    if [[ "${dayflags[$i]}" == "day" ]]; then time_c="$C_TIME_DAY"; else time_c="$C_TIME_NIGHT"; fi

    if [[ -z "${NO_COLOR:-}" ]]; then
      if (( i % 2 == 1 )); then bg="$BG1"; else bg="$BG2"; fi
    else
      bg=""
    fi

    # left border (no bg) + bg for inside + reset before right border
    printf "|%b %-*s  %b  %b%5s%b  %b%6s%b %b|\n" \
      "$bg$C_LABEL" "$label_w" "${labels[$i]}" \
      "$line" \
      "$time_c$S_BOLD" "${times[$i]}" "$S_INT_NORM$S_FG_DEFAULT" \
      "$C_DELTA" "${deltas[$i]}" "$S_FG_DEFAULT" \
      "$S_RESET_ALL"
  done

  printf "%b%s%b\n" "$C_BORDER" "$bot" "$S_RESET_ALL"

  render_deadlines "$tick"

  if [[ -z "${NO_COLOR:-}" ]]; then
    printf "%b%s%b\n" "$S_DIM" "Ctrl+C to quit • Edit deadlines.txt to add conferences • INTERVAL=0 for one-shot • NO_COLOR=1 to disable colors" "$S_RESET_ALL"
  fi
}

main () {
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
