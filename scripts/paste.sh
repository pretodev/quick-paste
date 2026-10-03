#!/bin/bash

set -euo pipefail

index="${1:-}"
mode="${2:-}"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
provider="${QICK_PASTE_PROVIDER:-$plugin_dir/qick-paste-clipboard-provider}"
history_path="$state_root/qick-paste-history.json"
[[ $index =~ ^[0-9]+$ ]] || exit 1
[[ -z $mode || $mode == "--plain" || $mode == "--path-absolute" || $mode == "--path-home" ]] || exit 1
[[ -r $history_path ]] || exit 1

entry_type=$(jq -er --argjson index "$index" '.[$index].type' "$history_path")
case "$entry_type" in
  text)
    if [[ $mode == "--plain" ]]; then
      jq -j --argjson index "$index" '.[$index].text' "$history_path" \
        | wl-copy --type 'text/plain'
    elif [[ $(jq -r --argjson index "$index" '.[$index].formats | length // 0' "$history_path") -gt 0 ]]; then
      [[ -x $provider ]] || exit 1
      provider_args=()
      while IFS= read -r -d '' mime && IFS= read -r -d '' path; do
        [[ -r $path ]] || exit 1
        provider_args+=("$mime" "$path")
      done < <(jq -j --argjson index "$index" \
        '.[$index].formats[] | .mime, "\u0000", .path, "\u0000"' "$history_path")
      "$provider" "${provider_args[@]}" >/dev/null 2>&1 &
    else
      jq -j --argjson index "$index" '.[$index].text' "$history_path" | wl-copy
    fi
    ;;
  image)
    [[ -z $mode ]] || exit 1
    if [[ $(jq -r --argjson index "$index" '.[$index].formats | length // 0' "$history_path") -gt 0 ]]; then
      [[ -x $provider ]] || exit 1
      provider_args=()
      while IFS= read -r -d '' mime && IFS= read -r -d '' path; do
        [[ -r $path ]] || exit 1
        provider_args+=("$mime" "$path")
      done < <(jq -j --argjson index "$index" \
        '.[$index].formats[] | .mime, "\u0000", .path, "\u0000"' "$history_path")
      "$provider" "${provider_args[@]}" >/dev/null 2>&1 &
    else
      mime=$(jq -er --argjson index "$index" '.[$index].mime // "image/png"' "$history_path")
      path=$(jq -er --argjson index "$index" '.[$index].path' "$history_path")
      [[ -r $path ]] || exit 1
      wl-copy --type "$mime" <"$path"
    fi
    ;;
  file)
    [[ $mode != "--plain" ]] || exit 1
    if [[ $mode == --path-absolute || $mode == --path-home ]]; then
      paths=()
      while IFS= read -r -d '' path; do
        [[ $path == /* ]] || exit 1
        if [[ $mode == --path-home ]]; then
          case "$path" in
            "$HOME") path='~' ;;
            "$HOME"/*) path="~/${path#"$HOME"/}" ;;
            *) exit 1 ;;
          esac
        fi
        paths+=("$path")
      done < <(jq -j --argjson index "$index" '.[$index].paths[] | ., "\u0000"' "$history_path")
      (( ${#paths[@]} > 0 )) || exit 1
      printf '%s\n' "${paths[@]}" | wl-copy --type 'text/plain'
    else
      [[ -x $provider ]] || exit 1
      provider_args=()
      while IFS= read -r -d '' mime && IFS= read -r -d '' path; do
        [[ -r $path ]] || exit 1
        provider_args+=("$mime" "$path")
      done < <(jq -j --argjson index "$index" \
        '.[$index].formats[] | .mime, "\u0000", .path, "\u0000"' "$history_path")
      (( ${#provider_args[@]} > 0 )) || exit 1
      "$provider" "${provider_args[@]}" >/dev/null 2>&1 &
    fi
    ;;
  *) exit 1 ;;
esac

sleep 0.15
if [[ $mode == "--plain" ]]; then
  wtype -M ctrl -M shift -k v -m shift -m ctrl 2>/dev/null || true
else
  wtype -M shift -k Insert -m shift 2>/dev/null || true
fi
