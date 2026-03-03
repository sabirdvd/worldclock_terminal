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

SCALE_MIN_PER_DASH=${SCALE_MIN_PER_DASH:-60}  # 1 dash per hour (try 30 for finer spacing)
BASE_DASHES=${BASE_DASHES:-5}                 # left padding before the left-most marker
INTERVAL=${INTERVAL:-1}                       # seconds between redraws (set 0 for one-shot)

# --- ANSI helpers ---
if [[ -n "${NO_COLOR:-}" ]]; then
  S_RESET_ALL=""; S_FG_DEFAULT=""; S_BG_DEFAULT=""; S_DIM=""; S_BOLD=""; S_INT_NORM=""; S_BLINK=""; S_BLINK_OFF=""
  C_BORDER=""; C_LABEL=""; C_TIME_DAY=""; C_TIME_NIGHT=""; C_DELTA=""; C_MARK_A=""; C_MARK_B=""; BG1=""; BG2=""
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
fi

repeat_char () {
  # repeat_char <char> <count>
  local ch="$1" n="$2" s
  (( n <= 0 )) && return 0
  printf -v s '%*s' "$n" ''
  printf '%s' "${s// /$ch}"
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
  # 07:00–19:59
  local hh="$1"
  ((10#$hh >= 7 && 10#$hh < 20))
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
  local inner_w=$(( label_w + line_w + 21 ))

  local top bot
  top="┌$(repeat_char '─' "$inner_w")┐"
  bot="└$(repeat_char '─' "$inner_w")┘"

  # pulsing marker: color + shape alternates
  local MARK="●" MARK_C="$C_MARK_A"
  if (( tick % 2 == 1 )); then MARK="◉"; MARK_C="$C_MARK_B"; fi

  # clear + home
  printf "\033[H\033[2J"

  local now
  now="$(date +%Y-%m-%d\ %H:%M:%S)"
  printf "%b%s%b\n" "$C_BORDER$S_BOLD" "World Time  •  $now" "$S_RESET_ALL"

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
    printf "│%b %-*s  %b  %b%5s%b  %b%6s%b %b│\n" \
      "$bg$C_LABEL" "$label_w" "${labels[$i]}" \
      "$line" \
      "$time_c$S_BOLD" "${times[$i]}" "$S_INT_NORM$S_FG_DEFAULT" \
      "$C_DELTA" "${deltas[$i]}" "$S_FG_DEFAULT" \
      "$S_RESET_ALL"
  done

  printf "%b%s%b\n" "$C_BORDER" "$bot" "$S_RESET_ALL"

  if [[ -z "${NO_COLOR:-}" ]]; then
    printf "%b%s%b\n" "$S_DIM" "Ctrl+C to quit • SCALE_MIN_PER_DASH=30 for finer spacing • INTERVAL=0 for one-shot • NO_COLOR=1 to disable colors" "$S_RESET_ALL"
  fi
}

main () {
  tput civis 2>/dev/null || true

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
