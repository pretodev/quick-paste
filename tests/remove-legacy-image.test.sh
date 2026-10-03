#!/bin/bash
set -euo pipefail

test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p -- "$test_root/state/omarchy/clipboard-images" "$test_root/state/omarchy/qick-paste-items"
source_image="$test_root/state/omarchy/qick-paste-items/old-image"
printf 'older image' >"$source_image"
digest=$(sha256sum -- "$source_image" | awk '{print $1}')
history="$test_root/state/omarchy/clipboard-history.json"
jq -n --arg image "$test_root/state/omarchy/clipboard-images/$digest.png" \
  '[{type:"text",text:"keep"},{type:"image",path:$image}]' >"$history"

env XDG_STATE_HOME="$test_root/state" "$(dirname "$0")/../scripts/remove-legacy-image.py" "$source_image"
[[ $(jq -r 'length' "$history") == 1 ]]
[[ $(jq -r '.[0].text' "$history") == keep ]]

echo "legacy image removal tests passed"
