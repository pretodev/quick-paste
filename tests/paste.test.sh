#!/bin/bash

set -euo pipefail

test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/state/omarchy"
printf '%s' '[{"type":"text","text":"Olá\n  mundo"},{"type":"image","path":"/missing.png"}]' \
  >"$test_root/state/omarchy/clipboard-history.json"
cp "$test_root/state/omarchy/clipboard-history.json" \
  "$test_root/state/omarchy/qick-paste-history.json"
printf '%s' $'Olá\n  mundo' >"$test_root/expected.txt"
printf '%s' 'Olá rico' >"$test_root/plain.txt"
printf '%s' '<b>Olá rico</b>' >"$test_root/html.txt"
jq -cn --arg plain "$test_root/plain.txt" --arg html "$test_root/html.txt" \
  '[{type:"text",text:"Olá\n  mundo"},{type:"image",path:"/missing.png"},
    {type:"text",text:"Olá rico",formats:[{mime:"text/plain",path:$plain},{mime:"text/html",path:$html}]}]' \
  >"$test_root/state/omarchy/qick-paste-history.json"

printf '%s\n' '#!/bin/bash' \
  'printf "%s" "$*" >"$QICK_PASTE_TEST_ROOT/wl-copy.args"' \
  'tee "$QICK_PASTE_TEST_ROOT/wl-copy.payload" >/dev/null' \
  >"$test_root/bin/wl-copy"
printf '%s\n' '#!/bin/bash' \
  'printf "%s" "$*" >"$QICK_PASTE_TEST_ROOT/wtype.args"' \
  >"$test_root/bin/wtype"
chmod +x "$test_root/bin/wl-copy" "$test_root/bin/wtype"
printf '%s\n' '#!/bin/bash' \
  'printf "%s\n" "$@" >"$QICK_PASTE_TEST_ROOT/provider.args"' \
  >"$test_root/bin/provider"
chmod +x "$test_root/bin/provider"

run_paste() {
  env XDG_STATE_HOME="$test_root/state" \
    QICK_PASTE_TEST_ROOT="$test_root" \
    QICK_PASTE_PROVIDER="$test_root/bin/provider" \
    PATH="$test_root/bin:$PATH" \
    "$(dirname "$0")/../paste.sh" "$@"
}

run_paste 0 --plain
cmp "$test_root/expected.txt" "$test_root/wl-copy.payload"
[[ $(<"$test_root/wl-copy.args") == "--type text/plain" ]]
[[ $(<"$test_root/wtype.args") == "-M ctrl -M shift -k v -m shift -m ctrl" ]]

run_paste 0
cmp "$test_root/expected.txt" "$test_root/wl-copy.payload"
[[ ! -s "$test_root/wl-copy.args" ]]
[[ $(<"$test_root/wtype.args") == "-M shift -k Insert -m shift" ]]

if run_paste 1 --plain; then
  echo "plain-text mode unexpectedly accepted an image" >&2
  exit 1
fi

run_paste 2
mapfile -t provider_args <"$test_root/provider.args"
[[ ${provider_args[0]} == text/plain ]]
[[ ${provider_args[1]} == "$test_root/plain.txt" ]]
[[ ${provider_args[2]} == text/html ]]
[[ ${provider_args[3]} == "$test_root/html.txt" ]]

echo "paste helper tests passed"
