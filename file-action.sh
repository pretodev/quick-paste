#!/bin/bash

set -euo pipefail

index="${1:-}"
mode="${2:-}"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
history_path="$state_root/qick-paste-history.json"
[[ $index =~ ^[0-9]+$ ]] || exit 1
[[ $mode == open || $mode == reveal ]] || exit 1
[[ -r $history_path ]] || exit 1
[[ $(jq -er --argjson index "$index" '.[$index].type' "$history_path") == file ]] || exit 1

paths=()
while IFS= read -r -d '' path; do
  [[ $path == /* && -e $path ]] || exit 1
  paths+=("$path")
done < <(jq -j --argjson index "$index" '.[$index].paths[] | ., "\u0000"' "$history_path")
(( ${#paths[@]} > 0 )) || exit 1

if [[ $mode == reveal ]]; then
  exec uwsm-app -- nautilus --select "${paths[@]}"
fi

for path in "${paths[@]}"; do
  gio open "$path" >/dev/null 2>&1 &
done
