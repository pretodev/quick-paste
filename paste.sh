#!/bin/bash

set -euo pipefail

index="${1:-}"
history_path="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/qick-paste-history.json"
[[ $index =~ ^[0-9]+$ ]] || exit 1
[[ -r $history_path ]] || exit 1

entry_type=$(jq -er --argjson index "$index" '.[$index].type' "$history_path")
case "$entry_type" in
  text)
    jq -j --argjson index "$index" '.[$index].text' "$history_path" | wl-copy
    ;;
  image)
    mime=$(jq -er --argjson index "$index" '.[$index].mime // "image/png"' "$history_path")
    path=$(jq -er --argjson index "$index" '.[$index].path' "$history_path")
    [[ -r $path ]] || exit 1
    wl-copy --type "$mime" <"$path"
    ;;
  *) exit 1 ;;
esac

sleep 0.15
wtype -M shift -k Insert -m shift 2>/dev/null || true
