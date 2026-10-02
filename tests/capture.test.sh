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

echo "capture helper tests passed"
