#!/usr/bin/env bash
# Duplicate the divider that was right-clicked.
#
# The shell has no API for adding a second copy of a bar widget: `omarchy bar
# put` deliberately leaves a widget that is already on the bar alone, and a
# bar-widget plugin's shell facade cannot write bar.layout (only a plugin with
# the "bar" kind gets mutateShellConfig). So this edits shell.json atomically
# and asks the running shell to reload it.
#
# Usage: duplicate-divider.sh [widget-id] [divider-id] [style-json]
#
# The optional argument is the clicked entry's `dividerId`. Entries without one
# get a stable id on the first duplicate, so every divider can be addressed
# separately from then on. `style-json` (optional) is merged into the entry
# before it is cloned, so a duplicate made while the style menu is open picks
# up the shape, size and colour the user is looking at.

set -euo pipefail

# Two quick right-clicks must not read the same shell.json and lose one copy.
lock_dir="${XDG_RUNTIME_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/omarchy}"
mkdir -p "$lock_dir"
exec 9>"$lock_dir/nik-divider.lock"
flock 9

token="${2:-}"
widget_id="${1:-io.github.nikhill-666.divider}"
style="${3:-}"
[[ -z $style ]] && style='{}'
# The style script does the full validation; this only keeps a malformed or
# foreign key out of the config. Anything unparseable is ignored.
patch=$(jq -c '
  (if type == "object" then . else {} end)
  | with_entries(select(.key | IN("shape", "width", "height", "color")))
' <<<"$style" 2>/dev/null) || patch='{}'
new_token="divider-$(date +%s%N)-${RANDOM}"

config="${DIVIDER_SHELL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json}"
if [[ ! -s $config ]]; then
  config="${OMARCHY_PATH:-/usr/share/omarchy}/config/omarchy/shell.json"
fi

tmp="$(mktemp "${config}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

jq -S --arg token "$token" --arg id "$widget_id" --arg newToken "$new_token" \
      --argjson patch "$patch" '
  def sections: ["left", "centerBegin", "center", "centerEnd", "right", "tray"];
  def is_divider: type == "object" and .id == $id;
  def divider_list($section):
    (.bar.layout[$section] // [])
    | if type == "array" then . else [] end;

  # The entry the caller named, then the first untagged one, then any divider.
  # A stale id (for example after editing shell.json by hand) still duplicates
  # something rather than silently doing nothing.
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
      # Give every untagged divider a unique id. Usually only the clicked one
      # is untagged; if several were added by hand, this makes the next click
      # exact instead of ambiguous.
      reduce sections[] as $section (.;
        .bar.layout[$section] |= (
          if type == "array" then
            to_entries | map(
              if (.value | is_divider) and ((.value.dividerId // "") == "") then
                .value + {
                  dividerId: ($newToken + "-src-" + $section + "-" + (.key | tostring))
                }
              else .value end
            )
          else . end
        )
      )
      # Apply whatever the style menu has on screen but has not saved yet, so
      # the copy is cloned from exactly what the user sees.
      | .bar.layout[$target.section][$target.index] += $patch
      | .bar.layout[$target.section] as $entries
      | ($entries[$target.index]
          | del(.dividerId)
          | .dividerId = $newToken) as $fresh
      | .bar.layout[$target.section] |= (
          .[0:($target.index + 1)] + [$fresh] + .[($target.index + 1):]
        )
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
