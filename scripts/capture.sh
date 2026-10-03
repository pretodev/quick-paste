#!/bin/bash

# Snapshot every representation offered by the current Wayland clipboard.
set -uo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

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
uri_path=""
uri_mime=""
fallback_uri_path=""

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
  case "$mime" in
    x-special/gnome-copied-files) uri_path="$payload"; uri_mime="$mime" ;;
    text/uri-list) fallback_uri_path="$payload"; if [[ -z $uri_path ]]; then uri_path="$payload"; uri_mime="$mime"; fi ;;
  esac
  if [[ -z $image_path && $mime == image/* ]]; then image_path="$payload"; image_mime="$mime"; fi
done <<<"$types"

[[ $formats_json != '[]' ]] || exit 0
file_paths='[]'
if [[ -n $uri_path ]]; then
  file_paths=$(python3 "$script_dir/file-uris.py" "$uri_path" "$uri_mime" 2>/dev/null || printf '[]')
fi
if [[ $file_paths == '[]' && -n $fallback_uri_path ]]; then
  file_paths=$(python3 "$script_dir/file-uris.py" "$fallback_uri_path" text/uri-list 2>/dev/null || printf '[]')
fi
if [[ -z $plain_path ]] && grep -qE '^(text/|UTF8_STRING$|STRING$|TEXT$)' <<<"$types"; then
  payload="$tmp_dir/plain-fallback"
  if timeout 5s wl-paste --type text --no-newline >"$payload" 2>/dev/null; then
    plain_path="$payload"
    formats_json=$(jq -cn --argjson formats "$formats_json" --arg path "$payload" \
      '$formats + [{mime:"text/plain",path:$path}]')
  fi
fi

if [[ $file_paths == '[]' && -z $plain_path && -z $image_path ]]; then exit 0; fi

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

if [[ $file_paths != '[]' ]]; then
  is_directory=false
  if [[ $(jq 'length' <<<"$file_paths") -eq 1 ]]; then
    IFS= read -r -d '' single_path < <(jq -j '.[0], "\u0000"' <<<"$file_paths")
    [[ ! -d $single_path ]] || is_directory=true
  fi
  jq -cn --arg id "$bundle_hash" --argjson paths "$file_paths" --argjson formats "$formats_json" \
    --argjson isDirectory "$is_directory" \
    '{type:"file",paths:$paths,mime:"text/uri-list",bundleId:$id,formats:$formats}
     | if $isDirectory then . + {isDirectory:true} else . end'
elif [[ -n $plain_path ]]; then
  text_json=$(perl -MEncode=decode,FB_CROAK,LEAVE_SRC -MJSON::PP=encode_json -0777 \
    -e '$raw=<STDIN>; $text=eval{decode("UTF-8",$raw,FB_CROAK|LEAVE_SRC)};
        $text=decode("UTF-8",$raw) unless defined $text; print encode_json($text)' <"$plain_path")
  link_preview='null'
  link_url=$(jq -r 'select(test("^https?://[^[:space:]]+$"; "i"))' <<<"$text_json" 2>/dev/null || true)
  if [[ -n $link_url ]]; then
    link_preview=$(curl --silent --show-error --location --max-time 5 --connect-timeout 2 \
      --max-filesize 1048576 --proto '=http,https' --proto-redir '=http,https' \
      --user-agent 'Qick-Paste/0.4 (+OpenGraph preview)' -- "$link_url" 2>/dev/null \
      | python3 "$script_dir/link-preview.py" "$link_url" 2>/dev/null || printf 'null')
  fi
  jq -cn --arg id "$bundle_hash" --argjson text "$text_json" --argjson formats "$formats_json" \
    --argjson linkPreview "$link_preview" \
    '{type:"text",text:$text,mime:"text/plain",bundleId:$id,formats:$formats}
     | if $linkPreview == null then . else . + {linkPreview:$linkPreview} end'
elif [[ -n $image_path ]]; then
  image_hash=$(sha256sum -- "$image_path" | awk '{print $1}')
  jq -cn --arg id "$bundle_hash" --arg mime "$image_mime" --arg path "$image_path" \
    --arg imageHash "$image_hash" \
    --argjson formats "$formats_json" \
    '{type:"image",mime:$mime,path:$path,bundleId:$id,imageHash:$imageHash,formats:$formats}'
fi
