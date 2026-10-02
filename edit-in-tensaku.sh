#!/bin/bash

# Edit a private copy of a history image and emit a new history entry on save.
set -euo pipefail

index="${1:-}"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
history_path="$state_root/qick-paste-history.json"
bundle_root="$state_root/qick-paste-items"
tensaku_bin="${QICK_PASTE_TENSAKU:-tensaku}"

[[ $index =~ ^[0-9]+$ ]] || exit 1
[[ -r $history_path ]] || exit 1

entry_type=$(jq -er --argjson index "$index" '.[$index].type' "$history_path")
[[ $entry_type == image ]] || exit 1
source_path=$(jq -er --argjson index "$index" '.[$index].path' "$history_path")
mime=$(jq -er --argjson index "$index" '.[$index].mime // "image/png"' "$history_path")
[[ -r $source_path ]] || exit 1

case "$mime" in
  image/jpeg) extension="jpg" ;;
  image/webp) extension="webp" ;;
  image/gif) extension="gif" ;;
  image/bmp) extension="bmp" ;;
  image/tiff) extension="tiff" ;;
  image/*) extension="png"; mime="image/png" ;;
  *) exit 1 ;;
esac

mkdir -p -- "$bundle_root"
work_dir=$(mktemp -d --tmpdir="$bundle_root" .tensaku.XXXXXX)
trap 'rm -rf -- "$work_dir"' EXIT
output_path="$work_dir/edited.$extension"
source_hash=$(sha256sum -- "$source_path" | awk '{print $1}')

"$tensaku_bin" "$source_path" --output-filename "$output_path" --early-exit

[[ -s $output_path ]] || exit 0
edited_hash=$(sha256sum -- "$output_path" | awk '{print $1}')
[[ $edited_hash != "$source_hash" ]] || exit 0

bundle_id=$(printf '%s\0%s\n' "$mime" "$edited_hash" | sha256sum | awk '{print $1}')
bundle_dir="$bundle_root/$bundle_id"
final_path="$bundle_dir/edited.$extension"
if [[ ! -d $bundle_dir ]]; then
  mv -- "$work_dir" "$bundle_dir"
else
  rm -rf -- "$work_dir"
fi
trap - EXIT

jq -cn --arg id "$bundle_id" --arg mime "$mime" --arg path "$final_path" \
  '{type:"image",mime:$mime,path:$path,bundleId:$id,formats:[{mime:$mime,path:$path}]}'
