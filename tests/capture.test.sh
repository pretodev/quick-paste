#!/bin/bash

set -euo pipefail

test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p -- "$test_root/bin" "$test_root/state"

cat >"$test_root/bin/wl-paste" <<'EOF'
#!/bin/bash
if [[ $1 == "--list-types" ]]; then
  printf '%s\n' 'text/plain;charset=utf-8' 'text/html' 'application/x-test'
  exit 0
fi
case "$2" in
  'text/plain;charset=utf-8'|text) printf 'Hello rich world' ;;
  text/html) printf '<b>Hello rich world</b>' ;;
  application/x-test) printf '\001\002binary' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$test_root/bin/wl-paste"

cat >"$test_root/bin/curl" <<'EOF'
#!/bin/bash
cat <<'HTML'
<meta property="og:description" content="A rich &amp; useful page">
<meta content="/preview.png" property="og:image">
<meta property="og:url" content="https://example.com/canonical">
HTML
EOF
chmod +x "$test_root/bin/curl"

entry=$(env XDG_STATE_HOME="$test_root/state" PATH="$test_root/bin:$PATH" \
  "$(dirname "$0")/../capture.sh")

[[ $(jq -r '.type' <<<"$entry") == text ]]
[[ $(jq -r '.text' <<<"$entry") == 'Hello rich world' ]]
[[ $(jq -r '.formats | length' <<<"$entry") == 3 ]]
for mime in 'text/plain;charset=utf-8' text/html application/x-test; do
  path=$(jq -er --arg mime "$mime" '.formats[] | select(.mime == $mime) | .path' <<<"$entry")
  [[ -r $path ]]
done
html_path=$(jq -r '.formats[] | select(.mime == "text/html") | .path' <<<"$entry")
[[ $(<"$html_path") == '<b>Hello rich world</b>' ]]
[[ $(jq -r '.linkPreview // empty' <<<"$entry") == '' ]]

second=$(env XDG_STATE_HOME="$test_root/state" PATH="$test_root/bin:$PATH" \
  "$(dirname "$0")/../capture.sh")
[[ $(jq -r '.bundleId' <<<"$entry") == "$(jq -r '.bundleId' <<<"$second")" ]]

sed -i "s/printf 'Hello rich world'/printf 'https:\/\/example.com\/article'/" "$test_root/bin/wl-paste"
link_entry=$(env XDG_STATE_HOME="$test_root/state" PATH="$test_root/bin:$PATH" \
  "$(dirname "$0")/../capture.sh")
[[ $(jq -r '.text' <<<"$link_entry") == 'https://example.com/article' ]]
[[ $(jq -r '.linkPreview.description' <<<"$link_entry") == 'A rich & useful page' ]]
[[ $(jq -r '.linkPreview.image' <<<"$link_entry") == 'https://example.com/preview.png' ]]
[[ $(jq -r '.linkPreview.url' <<<"$link_entry") == 'https://example.com/canonical' ]]

cat >"$test_root/bin/wl-paste" <<'EOF'
#!/bin/bash
if [[ $1 == "--list-types" ]]; then
  printf '%s\n' 'x-special/gnome-copied-files' 'text/uri-list' 'text/plain'
  exit 0
fi
case "$2" in
  x-special/gnome-copied-files) printf 'copy\nfile:///home/user/Ol%%C3%%A1%%20mundo.txt\nfile:///tmp/photo.png\n' ;;
  text/uri-list) printf 'file:///home/user/Ol%%C3%%A1%%20mundo.txt\r\nfile:///tmp/photo.png\r\n' ;;
  text/plain) printf '/home/user/Olá mundo.txt\n/tmp/photo.png' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$test_root/bin/wl-paste"
file_entry=$(env XDG_STATE_HOME="$test_root/state" PATH="$test_root/bin:$PATH" \
  "$(dirname "$0")/../capture.sh")
[[ $(jq -r '.type' <<<"$file_entry") == file ]]
[[ $(jq -r '.paths | length' <<<"$file_entry") == 2 ]]
[[ $(jq -r '.paths[0]' <<<"$file_entry") == '/home/user/Olá mundo.txt' ]]
[[ $(jq -r '.formats | length' <<<"$file_entry") == 3 ]]
[[ $(jq -r '.isDirectory // false' <<<"$file_entry") == false ]]

mkdir -p -- "$test_root/folder"
cat >"$test_root/bin/wl-paste" <<'EOF'
#!/bin/bash
if [[ $1 == "--list-types" ]]; then
  printf '%s\n' 'text/uri-list'
  exit 0
fi
[[ $2 == text/uri-list ]] || exit 1
printf 'file://%s\r\n' "$QICK_PASTE_TEST_FOLDER"
EOF
chmod +x "$test_root/bin/wl-paste"
folder_entry=$(env XDG_STATE_HOME="$test_root/state" QICK_PASTE_TEST_FOLDER="$test_root/folder" \
  PATH="$test_root/bin:$PATH" "$(dirname "$0")/../capture.sh")
[[ $(jq -r '.type' <<<"$folder_entry") == file ]]
[[ $(jq -r '.paths | length' <<<"$folder_entry") == 1 ]]
[[ $(jq -r '.isDirectory' <<<"$folder_entry") == true ]]

printf 'file:///tmp/one\r\nfile:///tmp/two\r\n' >"$test_root/uris.txt"
[[ $(python3 "$(dirname "$0")/../file-uris.py" "$test_root/uris.txt" text/uri-list \
  | jq -r 'length') == 2 ]]
printf 'https://example.com\n' >"$test_root/uris.txt"
[[ $(python3 "$(dirname "$0")/../file-uris.py" "$test_root/uris.txt" text/uri-list) == '[]' ]]

echo "capture helper tests passed"
