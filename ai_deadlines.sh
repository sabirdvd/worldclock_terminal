#!/usr/bin/env bash
set -euo pipefail

DEADLINES_FILE=${DEADLINES_FILE:-deadlines.txt}
INTERVAL=${INTERVAL:-1}
DEADLINE_SOON_HOURS=${DEADLINE_SOON_HOURS:-168} # 7 days
STAGE_FILTER=${STAGE_FILTER:-all}
SHOW_WEBSITE=${SHOW_WEBSITE:-0}
USE_ALT_SCREEN=0
IS_MAC=0
if [[ "$(uname -s)" == "Darwin" ]]; then
  IS_MAC=1
fi

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

fmt_countdown () {
  local secs="$1" sign="T-"
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
  if command -v gdate >/dev/null 2>&1; then
    TZ="$tz" gdate -d "$when" +%s 2>/dev/null && return 0
  fi

  if (( IS_MAC == 0 )); then
    TZ="$tz" date -d "$when" +%s 2>/dev/null && return 0
  else
    local f
    for f in \
      "%Y-%m-%d %H:%M" \
      "%Y-%m-%d" \
      "%Y-%m-%dT%H:%M" \
      "%B %e, %Y %H:%M" \
      "%B %e, %Y %I:%M %p" \
      "%B %e, %Y" \
      "%b %e, %Y %H:%M" \
      "%b %e, %Y %I:%M %p" \
      "%b %e, %Y"
    do
      TZ="$tz" date -j -f "$f" "$when" +%s 2>/dev/null && return 0
    done
  fi

  return 1
}

epoch_to_local () {
  local epoch="$1"
  if command -v gdate >/dev/null 2>&1; then
    gdate -d "@$epoch" +'%Y-%m-%d %H:%M %Z'
    return 0
  fi

  if (( IS_MAC == 0 )); then
    date -d "@$epoch" +'%Y-%m-%d %H:%M %Z'
  else
    date -r "$epoch" +'%Y-%m-%d %H:%M %Z'
  fi
}

epoch_to_tz_compact () {
  local epoch="$1" tz="$2"
  if command -v gdate >/dev/null 2>&1; then
    TZ="$tz" gdate -d "@$epoch" +'%Y-%m-%d %H:%M'
    return 0
  fi

  if (( IS_MAC == 0 )); then
    TZ="$tz" date -d "@$epoch" +'%Y-%m-%d %H:%M'
  else
    TZ="$tz" date -r "$epoch" +'%Y-%m-%d %H:%M'
  fi
}

extract_host () {
  local url="$1"
  url="${url#http://}"
  url="${url#https://}"
  printf '%s' "${url%%/*}"
}

score_line_for_stage () {
  local line_lc="$1" stage_lc="$2" score=0

  [[ "$line_lc" == *"deadline"* ]] && score=$((score + 4))
  [[ "$line_lc" == *"due"* ]] && score=$((score + 2))
  [[ "$line_lc" == *"submission"* ]] && score=$((score + 2))
  [[ "$line_lc" == *"call for papers"* ]] && score=$((score + 1))

  case "$stage_lc" in
    abstract)
      [[ "$line_lc" == *"abstract"* ]] && score=$((score + 7))
      [[ "$line_lc" == *"submission"* ]] && score=$((score + 3))
      [[ "$line_lc" == *"paper"* ]] && score=$((score + 2))
      ;;
    rebuttal)
      [[ "$line_lc" == *"rebuttal"* ]] && score=$((score + 8))
      [[ "$line_lc" == *"author response"* ]] && score=$((score + 6))
      [[ "$line_lc" == *"response"* ]] && score=$((score + 3))
      ;;
    decision)
      [[ "$line_lc" == *"decision"* ]] && score=$((score + 8))
      [[ "$line_lc" == *"notification"* ]] && score=$((score + 6))
      [[ "$line_lc" == *"acceptance"* ]] && score=$((score + 4))
      ;;
    *)
      [[ "$line_lc" == *"$stage_lc"* ]] && score=$((score + 6))
      ;;
  esac

  [[ "$line_lc" == *"camera-ready"* ]] && score=$((score - 2))
  [[ "$line_lc" == *"registration"* ]] && score=$((score - 2))

  printf '%s' "$score"
}

extract_candidate_dates () {
  local line="$1"
  # Emit one candidate per line.
  printf '%s\n' "$line" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}' || true
  printf '%s\n' "$line" | grep -Eo '[A-Z][a-z]+[[:space:]]+[0-9]{1,2},[[:space:]]+[0-9]{4}([[:space:]]+[0-9]{1,2}:[0-9]{2}([[:space:]]*[AP]M)?)?' || true
  printf '%s\n' "$line" | grep -Eo '[0-9]{4}-[0-9]{2}-[0-9]{2}' || true
}

fetch_date_from_website () {
  local url="$1" tz="$2" stage="$3"
  local html stage_lc
  local best_score=-999 best_epoch=0 best_when=""
  local now_epoch
  now_epoch="$(date +%s)"
  stage_lc="${stage,,}"

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required for --add-auto" >&2
    return 1
  fi

  html="$(curl -fsSL "$url" 2>/dev/null || true)"
  [[ -z "$html" ]] && return 1

  # Strip tags to text lines and score each line against stage/deadline intent.
  local line line_lc score cand normalized epoch
  while IFS= read -r line; do
    line="$(trim "$line")"
    [[ -z "$line" ]] && continue
    line_lc="${line,,}"

    score="$(score_line_for_stage "$line_lc" "$stage_lc")"
    while IFS= read -r cand; do
      [[ -z "$cand" ]] && continue
      epoch="$(deadline_to_epoch "$cand" "$tz" 2>/dev/null || true)"
      [[ -z "$epoch" ]] && continue
      normalized="$(epoch_to_tz_compact "$epoch" "$tz" 2>/dev/null || true)"
      [[ -z "$normalized" ]] && continue

      # Prefer future dates; slight bonus if still upcoming.
      local final_score
      final_score="$score"
      if (( epoch >= now_epoch )); then
        final_score=$((final_score + 3))
      fi

      if (( final_score > best_score )) || { (( final_score == best_score )) && (( epoch < best_epoch || best_epoch == 0 )); }; then
        best_score="$final_score"
        best_epoch="$epoch"
        best_when="$normalized"
      fi
    done < <(extract_candidate_dates "$line")
  done < <(printf '%s' "$html" | sed -E 's/<[^>]+>/\n/g' | sed -E 's/&nbsp;/ /g; s/&amp;/\\&/g')

  [[ -z "$best_when" ]] && return 1
  printf '%s' "$best_when"
}

show_usage () {
  cat <<'USAGE'
Usage:
  bash ai_deadlines.sh
  bash ai_deadlines.sh --add -n "Conference" -s "Stage" -d "YYYY-MM-DD HH:MM" -z "IANA_Timezone" [-w "https://..."]
  bash ai_deadlines.sh --add-row -n "Conference" -a "YYYY-MM-DD HH:MM" -d "YYYY-MM-DD HH:MM" -z "IANA_Timezone" [-w "https://..."]
  bash ai_deadlines.sh --add-auto -n "Conference" -s "Stage" -u "https://..." -z "IANA_Timezone"
  bash ai_deadlines.sh --remove --id 3
  bash ai_deadlines.sh --remove -n "Conference" [-s "Stage"]
  bash ai_deadlines.sh --list
  bash ai_deadlines.sh --help

Stage examples: Abstract, Rebuttal, Decision
USAGE
}

parse_line () {
  # Supports both:
  # 1) name|when|tz
  # 2) name|stage|when|tz
  # 3) name|stage|when|tz|website
  local line="$1"
  local f1 f2 f3 f4 f5
  IFS='|' read -r f1 f2 f3 f4 f5 <<< "$line"

  local name stage when tz website
  name="$(trim "${f1:-}")"
  if [[ -n "${f5:-}" ]]; then
    stage="$(trim "${f2:-}")"
    when="$(trim "${f3:-}")"
    tz="$(trim "${f4:-}")"
    website="$(trim "${f5:-}")"
  elif [[ -n "${f4:-}" ]]; then
    stage="$(trim "${f2:-}")"
    when="$(trim "${f3:-}")"
    tz="$(trim "${f4:-}")"
    website="-"
  else
    stage="Deadline"
    when="$(trim "${f2:-}")"
    tz="$(trim "${f3:-}")"
    website="-"
  fi

  [[ -z "$name" || -z "$when" || -z "$tz" ]] && return 1
  [[ -z "$stage" ]] && stage="Deadline"
  [[ -z "$website" ]] && website="-"

  printf '%s|%s|%s|%s|%s\n' "$name" "$stage" "$when" "$tz" "$website"
}

add_deadline () {
  local name="$1" stage="$2" when="$3" tz="$4" website="$5"

  if ! deadline_to_epoch "$when" "$tz" >/dev/null; then
    echo "Invalid date/time or timezone. Use: YYYY-MM-DD HH:MM and valid IANA timezone." >&2
    return 1
  fi

  [[ -z "$website" ]] && website="-"
  printf "%s|%s|%s|%s|%s\n" "$name" "$stage" "$when" "$tz" "$website" >> "$DEADLINES_FILE"
  echo "Added: $name | $stage | $when | $tz | $website"
}

add_deadline_row () {
  local name="$1" abstract_when="$2" deadline_when="$3" tz="$4" website="$5"

  if ! deadline_to_epoch "$abstract_when" "$tz" >/dev/null; then
    echo "Invalid abstract date/time or timezone." >&2
    return 1
  fi
  if ! deadline_to_epoch "$deadline_when" "$tz" >/dev/null; then
    echo "Invalid deadline date/time or timezone." >&2
    return 1
  fi

  [[ -z "$website" ]] && website="-"
  printf "%s|%s|%s|%s|%s\n" "$name" "$abstract_when" "$deadline_when" "$tz" "$website" >> "$DEADLINES_FILE"
  echo "Added row: $name | ABSTRACT=$abstract_when | DEADLINE=$deadline_when | $tz | $website"
}

list_deadlines () {
  load_deadlines
  if (( ${#DEADLINE_ENTRIES[@]} == 0 )); then
    echo "No valid deadlines found."
    return 0
  fi

  local i=0 rec name abs_when ddl_when tz website
  for rec in "${DEADLINE_ENTRIES[@]}"; do
    i=$((i + 1))
    IFS='|' read -r name abs_when ddl_when tz website <<< "$rec"
    printf "%d | %s | ABSTRACT=%s | DEADLINE=%s | %s | %s\n" \
      "$i" "$name" "${abs_when:--}" "${ddl_when:--}" "$tz" "$website"
  done
}

remove_deadline_by_id () {
  local target_id="$1"
  [[ -f "$DEADLINES_FILE" ]] || { echo "No deadlines file found: $DEADLINES_FILE"; return 1; }

  local tmp_file
  tmp_file="$(mktemp)"

  awk -v id="$target_id" '
    BEGIN {n=0; removed=0}
    {
      raw=$0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", raw)
      if (raw == "" || substr(raw,1,1) == "#") { print $0; next }
      n++
      if (n == id) { removed=1; next }
      print $0
    }
    END {
      if (!removed) exit 2
    }
  ' "$DEADLINES_FILE" > "$tmp_file" || {
    rm -f "$tmp_file"
    echo "ID not found: $target_id" >&2
    return 1
  }

  mv "$tmp_file" "$DEADLINES_FILE"
  echo "Removed deadline id $target_id"
}

remove_deadline_by_name_stage () {
  local target_name="$1" target_stage="$2"
  [[ -f "$DEADLINES_FILE" ]] || { echo "No deadlines file found: $DEADLINES_FILE"; return 1; }

  local tmp_file count_file
  tmp_file="$(mktemp)"
  count_file="$(mktemp)"

  awk -F'|' -v name="$target_name" -v stage="$target_stage" '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    BEGIN { removed=0 }
    {
      raw=$0
      clean=raw
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", clean)
      if (clean == "" || substr(clean,1,1) == "#") { print raw; next }

      f1=trim($1); f2=trim($2); f4=trim($4)
      if (f4 != "") {
        rec_name=f1; rec_stage=f2
      } else {
        rec_name=f1; rec_stage="Deadline"
      }

      if (rec_name == name && (stage == "" || rec_stage == stage)) {
        removed++
        next
      }

      print raw
    }
    END {
      if (removed == 0) exit 2
      print removed > "/dev/stderr"
    }
  ' "$DEADLINES_FILE" > "$tmp_file" 2>"$count_file" || {
    rm -f "$tmp_file" "$count_file"
    echo "No matching deadline found for name='$target_name' stage='${target_stage:-*}'" >&2
    return 1
  }

  local removed_count
  removed_count="$(cat "$count_file")"
  rm -f "$count_file"
  mv "$tmp_file" "$DEADLINES_FILE"
  echo "Removed $removed_count deadline(s)"
}

load_deadlines () {
  DEADLINE_ENTRIES=()
  [[ -f "$DEADLINES_FILE" ]] || return 0

  # Output unified rows:
  # name|abstract_when|deadline_when|timezone|website
  local merged
  merged="$(awk -F'|' '
    function trim(s){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    function isdt(s){ return (s ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}([ T][0-9]{2}:[0-9]{2})?$/) }
    BEGIN { n=0 }
    {
      raw=$0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", raw)
      if (raw=="" || substr(raw,1,1)=="#") next

      for (i=1; i<=NF; i++) f[i]=trim($i)
      name=f[1]
      if (name=="") next
      if (!(name in seen)) { seen[name]=1; order[++n]=name }

      # New compact format: name|abstract_when|deadline_when|tz|website
      if (NF>=5 && isdt(f[2]) && isdt(f[3])) {
        if (abs[name]=="") abs[name]=f[2]
        if (ddl[name]=="") ddl[name]=f[3]
        if (tz[name]=="") tz[name]=f[4]
        if (web[name]=="" || web[name]=="-") web[name]=f[5]
        next
      }

      # Existing staged format: name|stage|when|tz|website
      stage=tolower(f[2]); when=f[3]; t=f[4]; w=(NF>=5?f[5]:"-")
      if (stage ~ /abstract/) {
        if (abs[name]=="") abs[name]=when
      } else if (stage ~ /deadline|paper|submission/) {
        if (ddl[name]=="") ddl[name]=when
      } else if (stage ~ /decision|notification/) {
        if (ddl[name]=="") ddl[name]=when
      } else if (stage ~ /rebuttal/) {
        # ignore rebuttal in one-row mode
      } else {
        if (ddl[name]=="") ddl[name]=when
      }

      if (tz[name]=="") tz[name]=t
      if (web[name]=="" || web[name]=="-") web[name]=w
    }
    END {
      for (i=1; i<=n; i++) {
        k=order[i]
        if (abs[k]=="" && ddl[k]=="") continue
        if (tz[k]=="") tz[k]="UTC"
        if (web[k]=="") web[k]="-"
        print k "|" abs[k] "|" ddl[k] "|" tz[k] "|" web[k]
      }
    }
  ' "$DEADLINES_FILE")"

  local rec
  while IFS= read -r rec; do
    [[ -z "$rec" ]] && continue
    DEADLINE_ENTRIES+=("$rec")
  done <<< "$merged"
}

cleanup () {
  if (( USE_ALT_SCREEN == 1 )); then
    printf '\033[?1049l'
  fi
  tput cnorm 2>/dev/null || true
  printf "%b" "$S_RESET_ALL"
}

render_once () {
  local tick="$1"
  local now_local now_epoch soon_secs
  now_local="$(date +%Y-%m-%d\ %H:%M:%S\ %Z)"
  now_epoch="$(date +%s)"
  soon_secs=$(( DEADLINE_SOON_HOURS * 3600 ))

  local conf_w=10 abs_w=19 ddl_w=19 status_w=10 count_w=20 site_w=16
  local h_conf="Conference" h_abs="Abstract (Your Time)" h_ddl="Deadline (Your Time)" h_status="Status" h_count="Countdown" h_site="Website"
  local rec conf abs_when ddl_when tz website abs_local ddl_local len site_short

  for rec in "${DEADLINE_ENTRIES[@]}"; do
    IFS='|' read -r conf abs_when ddl_when tz website <<< "$rec"

    (( ${#conf} > conf_w )) && conf_w=${#conf}
    site_short="$website"
    [[ "$site_short" == "-" ]] || site_short="$(extract_host "$site_short")"
    (( ${#site_short} > site_w )) && site_w=${#site_short}

    abs_local="-"
    ddl_local="-"
    if [[ -n "$abs_when" ]] && epoch="$(deadline_to_epoch "$abs_when" "$tz")"; then
      abs_local="$(epoch_to_local "$epoch")"
    fi
    if [[ -n "$ddl_when" ]] && epoch="$(deadline_to_epoch "$ddl_when" "$tz")"; then
      ddl_local="$(epoch_to_local "$epoch")"
    fi
    len=${#abs_local}; (( len > abs_w )) && abs_w=$len
    len=${#ddl_local}; (( len > ddl_w )) && ddl_w=$len
  done

  # Keep widths within caps, but never below header text length.
  (( conf_w > 18 )) && conf_w=18
  (( abs_w > 22 )) && abs_w=22
  (( ddl_w > 22 )) && ddl_w=22
  (( count_w > 20 )) && count_w=20
  (( site_w > 16 )) && site_w=16

  (( conf_w < ${#h_conf} )) && conf_w=${#h_conf}
  (( abs_w < ${#h_abs} )) && abs_w=${#h_abs}
  (( ddl_w < ${#h_ddl} )) && ddl_w=${#h_ddl}
  (( status_w < ${#h_status} )) && status_w=${#h_status}
  (( count_w < ${#h_count} )) && count_w=${#h_count}
  (( site_w < ${#h_site} )) && site_w=${#h_site}

  local inner_w
  if [[ "$SHOW_WEBSITE" == "1" ]]; then
    # Row text width is sum(widths) + 19; border encloses inner area (+2),
    # so inner width must be sum(widths) + 17 for exact alignment.
    inner_w=$(( conf_w + abs_w + ddl_w + status_w + count_w + site_w + 17 ))
  else
    # Row text width is sum(widths) + 16; border encloses inner area (+2),
    # so inner width must be sum(widths) + 14 for exact alignment.
    inner_w=$(( conf_w + abs_w + ddl_w + status_w + count_w + 14 ))
  fi
  local top="+$(repeat_char '-' "$inner_w")+"
  local bot="+$(repeat_char '-' "$inner_w")+"
  local title_mark="●"
  (( tick % 2 == 1 )) && title_mark="◉"

  printf "\033[H\033[2J"
  printf "%b%s%b\n" "$C_BORDER$S_BOLD" "AI Deadlines $title_mark  •  Your Time: $now_local" "$S_RESET_ALL"
  printf "%b%s%b\n" "$C_BORDER" "$top" "$S_RESET_ALL"

  if [[ "$SHOW_WEBSITE" == "1" ]]; then
    printf "| %b%-*s%b | %b%-*s%b | %b%-*s%b | %b%-*s%b | %b%-*s%b | %b%-*s%b |\n" \
      "$S_BOLD$C_LABEL" "$conf_w" "$h_conf" "$S_RESET_ALL" \
      "$S_BOLD$C_LABEL" "$abs_w" "$h_abs" "$S_RESET_ALL" \
      "$S_BOLD$C_LABEL" "$ddl_w" "$h_ddl" "$S_RESET_ALL" \
      "$S_BOLD$C_LABEL" "$status_w" "$h_status" "$S_RESET_ALL" \
      "$S_BOLD$C_LABEL" "$count_w" "$h_count" "$S_RESET_ALL" \
      "$S_BOLD$C_LABEL" "$site_w" "$h_site" "$S_RESET_ALL"
  else
    printf "| %b%-*s%b | %b%-*s%b | %b%-*s%b | %b%-*s%b | %b%-*s%b |\n" \
      "$S_BOLD$C_LABEL" "$conf_w" "$h_conf" "$S_RESET_ALL" \
      "$S_BOLD$C_LABEL" "$abs_w" "$h_abs" "$S_RESET_ALL" \
      "$S_BOLD$C_LABEL" "$ddl_w" "$h_ddl" "$S_RESET_ALL" \
      "$S_BOLD$C_LABEL" "$status_w" "$h_status" "$S_RESET_ALL" \
      "$S_BOLD$C_LABEL" "$count_w" "$h_count" "$S_RESET_ALL"
  fi

  if (( ${#DEADLINE_ENTRIES[@]} == 0 )); then
    printf "| %-*s |\n" "$inner_w" "No deadlines found. Use: deadline add -n ... -s ... -d ... -z ..."
    printf "%b%s%b\n" "$C_BORDER" "$bot" "$S_RESET_ALL"
    return 0
  fi

  local remaining status countdown status_color status_cell pulse show_abs show_ddl show_count
  local abs_epoch ddl_epoch next_epoch next_label
  prev_conf=""
  for rec in "${DEADLINE_ENTRIES[@]}"; do
    IFS='|' read -r conf abs_when ddl_when tz website <<< "$rec"

    abs_local="-"
    ddl_local="-"
    abs_epoch=""
    ddl_epoch=""

    if [[ -n "$abs_when" ]] && abs_epoch="$(deadline_to_epoch "$abs_when" "$tz")"; then
      abs_local="$(epoch_to_local "$abs_epoch")"
    fi
    if [[ -n "$ddl_when" ]] && ddl_epoch="$(deadline_to_epoch "$ddl_when" "$tz")"; then
      ddl_local="$(epoch_to_local "$ddl_epoch")"
    fi

    next_epoch=""
    next_label="NONE"
    if [[ -n "$abs_epoch" && "$abs_epoch" -ge "$now_epoch" ]]; then
      next_epoch="$abs_epoch"; next_label="ABSTRACT"
    fi
    if [[ -n "$ddl_epoch" && "$ddl_epoch" -ge "$now_epoch" ]]; then
      if [[ -z "$next_epoch" || "$ddl_epoch" -lt "$next_epoch" ]]; then
        next_epoch="$ddl_epoch"; next_label="DEADLINE"
      fi
    fi
    if [[ -z "$next_epoch" ]]; then
      if [[ -n "$ddl_epoch" ]]; then
        next_epoch="$ddl_epoch"; next_label="CLOSED"
      elif [[ -n "$abs_epoch" ]]; then
        next_epoch="$abs_epoch"; next_label="CLOSED"
      fi
    fi

    if [[ -z "$next_epoch" ]]; then
      status="BAD"
      countdown="invalid date"
      status_color="$C_BAD"
    else
      remaining=$(( next_epoch - now_epoch ))
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
      if [[ "$next_label" == "ABSTRACT" ]]; then
        status="${status}/A"
      elif [[ "$next_label" == "DEADLINE" ]]; then
        status="${status}/D"
      fi
    fi

    status_cell="$status"
    if [[ "$status" == "SOON" || "$status" == "CLOSED" || "$status" == "BAD" ]]; then
      pulse="*"
      status_cell="$status $pulse"
    fi

    site_short="$website"
    [[ "$site_short" == "-" ]] || site_short="$(extract_host "$site_short")"
    display_conf="$conf"
    if [[ "$conf" == "$prev_conf" ]]; then
      display_conf=""
    fi
    prev_conf="$conf"

    display_conf="$(ellipsize "$conf" "$conf_w")"
    show_abs="$(ellipsize "$abs_local" "$abs_w")"
    show_ddl="$(ellipsize "$ddl_local" "$ddl_w")"
    show_count="$(ellipsize "$countdown" "$count_w")"
    site_short="$(ellipsize "$site_short" "$site_w")"

    if [[ "$SHOW_WEBSITE" == "1" ]]; then
      printf "| %-*s | %-*s | %-*s | %b%-*s%b | %-*s | %-*s |\n" \
        "$conf_w" "$display_conf" \
        "$abs_w" "$show_abs" \
        "$ddl_w" "$show_ddl" \
        "$status_color$S_BOLD$S_BLINK" "$status_w" "$status_cell" "$S_BLINK_OFF$S_RESET_ALL" \
        "$count_w" "$show_count" \
        "$site_w" "$site_short"
    else
      printf "| %-*s | %-*s | %-*s | %b%-*s%b | %-*s |\n" \
        "$conf_w" "$display_conf" \
        "$abs_w" "$show_abs" \
        "$ddl_w" "$show_ddl" \
        "$status_color$S_BOLD$S_BLINK" "$status_w" "$status_cell" "$S_BLINK_OFF$S_RESET_ALL" \
        "$count_w" "$show_count"
    fi
  done

  printf "%b%s%b\n" "$C_BORDER" "$bot" "$S_RESET_ALL"
  printf "%b%s%b\n" "$S_DIM" "Ctrl+C to quit • deadline add-row/add/add-auto/list/remove • INTERVAL=0 for one-shot" "$S_RESET_ALL"
}

main () {
  if (( $# > 0 )); then
    case "${1:-}" in
      --add-row)
        shift
        local name="" abstract_when="" deadline_when="" tz="" website="-"
        while (( $# > 0 )); do
          case "$1" in
            -n|--name) name="${2:-}"; shift 2 ;;
            -a|--abstract) abstract_when="${2:-}"; shift 2 ;;
            -d|--deadline) deadline_when="${2:-}"; shift 2 ;;
            -z|--tz|--timezone) tz="${2:-}"; shift 2 ;;
            -w|--website) website="${2:-}"; shift 2 ;;
            *) echo "Unknown add-row option: $1" >&2; show_usage; return 1 ;;
          esac
        done
        if [[ -z "$name" || -z "$abstract_when" || -z "$deadline_when" || -z "$tz" ]]; then
          show_usage
          return 1
        fi
        add_deadline_row "$name" "$abstract_when" "$deadline_when" "$tz" "$website"
        return 0
        ;;
      --add)
        shift
        local name="" stage="Deadline" when="" tz="" website="-"

        while (( $# > 0 )); do
          case "$1" in
            -n|--name) name="${2:-}"; shift 2 ;;
            -s|--stage) stage="${2:-}"; shift 2 ;;
            -d|--date) when="${2:-}"; shift 2 ;;
            -z|--tz|--timezone) tz="${2:-}"; shift 2 ;;
            -w|--website) website="${2:-}"; shift 2 ;;
            *) echo "Unknown add option: $1" >&2; show_usage; return 1 ;;
          esac
        done

        if [[ -z "$name" || -z "$when" || -z "$tz" ]]; then
          show_usage
          return 1
        fi

        add_deadline "$name" "$stage" "$when" "$tz" "$website"
        return 0
        ;;
      --add-auto)
        shift
        local name="" stage="Deadline" tz="UTC" url=""
        local website="-"

        while (( $# > 0 )); do
          case "$1" in
            -n|--name) name="${2:-}"; shift 2 ;;
            -s|--stage) stage="${2:-}"; shift 2 ;;
            -u|--url) url="${2:-}"; shift 2 ;;
            -z|--tz|--timezone) tz="${2:-}"; shift 2 ;;
            *) echo "Unknown add-auto option: $1" >&2; show_usage; return 1 ;;
          esac
        done

        if [[ -z "$name" || -z "$url" ]]; then
          show_usage
          return 1
        fi

        local when
        if ! when="$(fetch_date_from_website "$url" "$tz" "$stage")"; then
          echo "Could not auto-detect a date from website. Use manual --add -d \"YYYY-MM-DD HH:MM\"." >&2
          return 1
        fi

        website="$url"
        add_deadline "$name" "$stage" "$when" "$tz" "$website"
        return 0
        ;;
      --remove)
        shift
        local id="" name="" stage=""

        while (( $# > 0 )); do
          case "$1" in
            --id) id="${2:-}"; shift 2 ;;
            -n|--name) name="${2:-}"; shift 2 ;;
            -s|--stage) stage="${2:-}"; shift 2 ;;
            *) echo "Unknown remove option: $1" >&2; show_usage; return 1 ;;
          esac
        done

        if [[ -n "$id" ]]; then
          remove_deadline_by_id "$id"
          return 0
        fi

        if [[ -n "$name" ]]; then
          remove_deadline_by_name_stage "$name" "$stage"
          return 0
        fi

        show_usage
        return 1
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

  trap cleanup EXIT INT TERM

  # For live mode in a real terminal, draw in alternate screen so frames do not stack.
  if (( INTERVAL > 0 )) && [[ -t 1 ]]; then
    USE_ALT_SCREEN=1
    printf '\033[?1049h\033[H'
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
