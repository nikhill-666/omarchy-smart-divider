#!/usr/bin/env bash
# Set the style of one divider in shell.json.
#
# Usage: set-divider-style.sh [widget-id] [divider-id] [style-json]
#
# style-json is an object with any of:
#   shape   "line" | "dot" | "oval" | "square" | "rounded"
#   width   percent of bar height, 2-40
#   height  percent of bar height, 6-100
#   color   "theme" | "accent" | "foreground" | "urgent" | "#rrggbb"
#
# A divider's style lives in its own bar layout entry, beside its dividerId, so
# two dividers can differ and a duplicate inherits the style of the one it was
# copied from. The shell's updateEntryInline cannot do this: for an
# allowMultiple widget it rewrites every matching entry with the same settings,
# which would give all dividers one style (and one dividerId).
#
# Entries without a dividerId are given one here, exactly as the duplicate
# script does, so the next change addresses the right divider. When the caller
# names no id and several dividers are untagged, the first untagged one is
# changed — the same fallback duplicate-divider.sh uses.

set -euo pipefail

widget_id="${1:-io.github.nikhill-666.divider}"
token="${2:-}"
style="${3:-}"
[[ -z $style ]] && style='{}'

# Whitelist the keys, coerce the values into the ranges the widget draws, and
# drop anything that does not belong in a divider entry. This runs before the
# lock: a malformed argument should fail without touching the config.
if ! style_json=$(jq -c '
  def num($default; $min; $max):
    (if type == "number" then .
     elif type == "string" then (tonumber? // $default)
     else $default end)
    | floor
    | if . < $min then $min elif . > $max then $max else . end;

  (if type == "object" then . else {} end)
  | with_entries(select(.key | IN("shape", "width", "height", "color")))
  | if has("shape") then
      .shape |= (if IN("line", "dot", "oval", "square", "rounded") then . else "line" end)
    else . end
  | if has("width") then .width |= num(8; 2; 40) else . end
  | if has("height") then .height |= num(62; 6; 100) else . end
  | if has("color") then
      .color |= (if type != "string" then "theme"
                 elif IN("theme", "accent", "foreground", "urgent") then .
                 elif test("^#[0-9a-fA-F]{6}$") then ascii_downcase
                 else "theme" end)
    else . end
' <<<"$style"); then
  echo "set-divider-style: style must be a JSON object" >&2
  exit 2
fi

# Share duplicate-divider.sh's lock: a style change and a duplicate must not
# read the same shell.json and lose one of the writes.
lock_dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy}"
mkdir -p "$lock_dir"
exec 9>"$lock_dir/nik-divider.lock"
flock 9

new_token="divider-$(date +%s%N)-${RANDOM}"

config="${DIVIDER_SHELL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json}"
if [[ ! -s $config ]]; then
  config="${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json"
fi

tmp="$(mktemp "${config}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

jq -S --arg id "$widget_id" --arg token "$token" \
      --arg newToken "$new_token" --argjson patch "$style_json" '
  def sections: ["left", "centerBegin", "center", "centerEnd", "right", "tray"];
  def is_divider: type == "object" and .id == $id;
  def divider_list($section):
    (.bar.layout[$section] // [])
    | if type == "array" then . else [] end;

  # The entry the caller named, then the first untagged one, then any divider.
  def find_divider($wanted):
    [sections[] as $section
     | divider_list($section) | to_entries[]
     | select(.value | is_divider)
     | select(if $wanted == "" then ((.value.dividerId // "") == "")
              else .value.dividerId == $wanted end)
     | { section: $section, index: .key }][0];

  (find_divider($token)
   // find_divider("")
   // ([sections[] as $section
        | divider_list($section) | to_entries[]
        | select(.value | is_divider)
        | { section: $section, index: .key }][0])) as $target
  | if $target == null then
      .
    else
      # Give every untagged divider a unique id so the next change is exact.
      # Only sections that are already lists are touched, so a section the
      # user never filled stays absent rather than becoming an empty one.
      reduce sections[] as $section (.;
        if (.bar.layout[$section] | type) == "array" then
          .bar.layout[$section] |= (
            to_entries | map(
              if (.value | is_divider) and ((.value.dividerId // "") == "") then
                .value + {
                  dividerId: ($newToken + "-src-" + $section + "-" + (.key | tostring))
                }
              else .value end
            )
          )
        else . end
      )
      # Tagging keeps every index, so the target found above is still the one
      # the clicked divider pointed at.
      | .bar.layout[$target.section][$target.index] += $patch
    end
' "$config" >"$tmp"

mv "$tmp" "$config"
trap - EXIT

# The shell owns the config it has in memory, so ask it to read the file back.
if [[ ${DIVIDER_SKIP_RELOAD:-0} != 1 ]] && command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell reloadConfig >/dev/null 2>&1 \
    || omarchy-shell -q shell rescanPlugins >/dev/null 2>&1 \
    || true
fi
