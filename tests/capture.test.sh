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

second=$(env XDG_STATE_HOME="$test_root/state" PATH="$test_root/bin:$PATH" \
  "$(dirname "$0")/../capture.sh")
[[ $(jq -r '.bundleId' <<<"$entry") == "$(jq -r '.bundleId' <<<"$second")" ]]

echo "capture helper tests passed"
