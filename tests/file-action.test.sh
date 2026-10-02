#!/bin/bash

set -euo pipefail

test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
mkdir -p -- "$test_root/bin" "$test_root/state/omarchy" "$test_root/files"
touch -- "$test_root/files/Olá mundo.txt" "$test_root/files/other.pdf"

jq -cn --arg first "$test_root/files/Olá mundo.txt" --arg second "$test_root/files/other.pdf" \
  '[{type:"file",paths:[$first,$second]}]' >"$test_root/state/omarchy/qick-paste-history.json"

cat >"$test_root/bin/gio" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >>"$QICK_PASTE_TEST_ROOT/gio.args"
EOF
cat >"$test_root/bin/uwsm-app" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >"$QICK_PASTE_TEST_ROOT/uwsm.args"
EOF
chmod +x "$test_root/bin/gio" "$test_root/bin/uwsm-app"

run_action() {
  env XDG_STATE_HOME="$test_root/state" QICK_PASTE_TEST_ROOT="$test_root" \
    PATH="$test_root/bin:$PATH" "$(dirname "$0")/../file-action.sh" "$@"
}

run_action 0 reveal
mapfile -t reveal_args <"$test_root/uwsm.args"
[[ ${reveal_args[0]} == -- && ${reveal_args[1]} == nautilus ]]
[[ ${reveal_args[2]} == --select ]]
[[ ${reveal_args[3]} == "$test_root/files/Olá mundo.txt" ]]
[[ ${reveal_args[4]} == "$test_root/files/other.pdf" ]]

run_action 0 open
sleep 0.1
mapfile -t open_args <"$test_root/gio.args"
[[ ${open_args[0]} == open && ${open_args[1]} == "$test_root/files/Olá mundo.txt" ]]
[[ ${open_args[2]} == open && ${open_args[3]} == "$test_root/files/other.pdf" ]]

echo "file action helper tests passed"
