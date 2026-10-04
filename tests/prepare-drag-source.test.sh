#!/bin/bash
set -euo pipefail

test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
helper="$(dirname "$0")/../scripts/prepare-drag-source.py"
source_image="$test_root/Olá image"
printf 'image bytes' >"$source_image"

exported=$(env XDG_STATE_HOME="$test_root/state" python3 "$helper" "$source_image" image/png)
[[ $exported == "$test_root/state/omarchy/qick-paste-drag-images/"*.png ]]
cmp "$source_image" "$exported"
[[ $(env XDG_STATE_HOME="$test_root/state" python3 "$helper" "$source_image" image/png) == "$exported" ]]

printf 'new image bytes' >"$source_image"
updated=$(env XDG_STATE_HOME="$test_root/state" python3 "$helper" "$source_image" image/png)
[[ $updated != "$exported" ]]
cmp "$source_image" "$updated"

mkdir -p -- "$test_root/folder"
files=$(jq -cn --arg image "$source_image" --arg folder "$test_root/folder" '[$image,$folder]')
[[ $(python3 "$helper" --files "$files") == 1 ]]
[[ -z $(python3 "$helper" --files '["/missing-file"]') ]]

echo "drag source helper tests passed"
