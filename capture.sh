#!/bin/bash

# Snapshot every representation offered by the current Wayland clipboard.
set -uo pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
bundle_root="$state_dir/qick-paste-items"
mkdir -p -- "$bundle_root"

[[ ${CLIPBOARD_STATE:-} != "sensitive" ]] || exit 0
types=$(wl-paste --list-types 2>/dev/null || true)
if [[ -z $types ]] || grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then exit 0; fi

tmp_dir=$(mktemp -d --tmpdir="$bundle_root" .capture.XXXXXX) || exit 0
trap 'rm -rf -- "$tmp_dir"' EXIT
formats_json='[]'
plain_path=""
image_path=""
image_mime=""

while IFS= read -r mime; do
  [[ -n $mime ]] || continue
  case "$mime" in TARGETS|SAVE_TARGETS|TIMESTAMP|MULTIPLE|x-kde-passwordManagerHint) continue ;; esac
  name=$(printf '%s' "$mime" | sha256sum | awk '{print $1}')
  payload="$tmp_dir/$name"
  if ! timeout 5s wl-paste --type "$mime" >"$payload" 2>/dev/null; then
    rm -f -- "$payload"
    continue
  fi
  formats_json=$(jq -cn --argjson formats "$formats_json" --arg mime "$mime" \
    --arg path "$payload" '$formats + [{mime:$mime,path:$path}]')
  case "$mime" in
    'text/plain;charset=utf-8') plain_path="$payload" ;;
    text/plain) [[ -n $plain_path ]] || plain_path="$payload" ;;
    UTF8_STRING|STRING|TEXT) [[ -n $plain_path ]] || plain_path="$payload" ;;
  esac
  if [[ -z $image_path && $mime == image/* ]]; then image_path="$payload"; image_mime="$mime"; fi
done <<<"$types"

[[ $formats_json != '[]' ]] || exit 0
if [[ -z $plain_path ]] && grep -qE '^(text/|UTF8_STRING$|STRING$|TEXT$)' <<<"$types"; then
  payload="$tmp_dir/plain-fallback"
  if timeout 5s wl-paste --type text --no-newline >"$payload" 2>/dev/null; then
    plain_path="$payload"
    formats_json=$(jq -cn --argjson formats "$formats_json" --arg path "$payload" \
      '$formats + [{mime:"text/plain",path:$path}]')
  fi
fi

bundle_hash=$(while IFS= read -r mime && IFS= read -r path; do
  printf '%s\0' "$mime"
  sha256sum -- "$path" | awk '{print $1}'
done < <(jq -r '.[] | .mime, .path' <<<"$formats_json") | sha256sum | awk '{print $1}')
bundle_dir="$bundle_root/$bundle_hash"
if [[ -d $bundle_dir ]]; then rm -rf -- "$tmp_dir"; else mv -- "$tmp_dir" "$bundle_dir"; fi
trap - EXIT

formats_json=$(jq -cn --argjson formats "$formats_json" --arg old "$tmp_dir/" \
  --arg new "$bundle_dir/" \
  '$formats | map(.path |= if startswith($old) then $new + ltrimstr($old) else . end)')
[[ -z $plain_path ]] || plain_path=${plain_path/#$tmp_dir\//$bundle_dir/}
[[ -z $image_path ]] || image_path=${image_path/#$tmp_dir\//$bundle_dir/}

if [[ -n $plain_path ]]; then
  text_json=$(perl -MEncode=decode,FB_CROAK,LEAVE_SRC -MJSON::PP=encode_json -0777 \
    -e '$raw=<STDIN>; $text=eval{decode("UTF-8",$raw,FB_CROAK|LEAVE_SRC)};
        $text=decode("UTF-8",$raw) unless defined $text; print encode_json($text)' <"$plain_path")
  jq -cn --arg id "$bundle_hash" --argjson text "$text_json" --argjson formats "$formats_json" \
    '{type:"text",text:$text,mime:"text/plain",bundleId:$id,formats:$formats}'
elif [[ -n $image_path ]]; then
  jq -cn --arg id "$bundle_hash" --arg mime "$image_mime" --arg path "$image_path" \
    --argjson formats "$formats_json" \
    '{type:"image",mime:$mime,path:$path,bundleId:$id,formats:$formats}'
fi
