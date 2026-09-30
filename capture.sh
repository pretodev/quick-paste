#!/bin/bash

set -o pipefail

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"
image_dir="$state_dir/qick-paste-images"
mkdir -p "$image_dir"

if [[ ${1:-} == "--init" ]]; then
  exit 0
fi

types=$(wl-paste --list-types 2>/dev/null || true)
if [[ ${CLIPBOARD_STATE:-} == "sensitive" ]] || grep -qx 'x-kde-passwordManagerHint' <<<"$types"; then
  exit 0
fi

emit_image() {
  local mime="$1"
  local ext tmp hash file
  ext=${mime#image/}
  [[ $ext == jpeg ]] && ext=jpg
  tmp=$(mktemp --tmpdir="$image_dir" clipboard.XXXXXX) || return 0
  cat >"$tmp"
  if [[ ! -s $tmp ]]; then
    rm -f "$tmp"
    return 0
  fi
  hash=$(sha256sum "$tmp" | awk '{print $1}')
  file="$image_dir/$hash.$ext"
  if [[ -e $file ]]; then rm -f "$tmp"; else mv "$tmp" "$file"; fi
  jq -cn --arg mime "$mime" --arg path "$file" '{type:"image",mime:$mime,path:$path}'
}

emit_text() {
  perl -MEncode=decode,FB_CROAK,LEAVE_SRC -MJSON::PP=encode_json -0777 -e '
    my $raw = <STDIN>;
    exit unless length $raw;
    my $text = eval { decode("UTF-8", $raw, FB_CROAK | LEAVE_SRC) };
    $text = decode("UTF-8", $raw) unless defined $text;
    print "{\"type\":\"text\",\"text\":", encode_json($text), "}\n";
  '
}

case "${1:-}" in
  text) emit_text; exit 0 ;;
  image/*) emit_image "$1"; exit 0 ;;
esac

for mime in image/png image/jpeg image/webp image/gif image/bmp image/tiff; do
  if grep -qx "$mime" <<<"$types"; then
    timeout 2s wl-paste --type "$mime" 2>/dev/null | emit_image "$mime"
    exit 0
  fi
done

if grep -q '^text/' <<<"$types" || grep -qx 'UTF8_STRING' <<<"$types" || grep -qx 'STRING' <<<"$types"; then
  wl-paste --type text --no-newline 2>/dev/null | emit_text
fi
