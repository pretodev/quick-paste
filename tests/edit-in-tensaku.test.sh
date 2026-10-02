#!/bin/bash

set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
export XDG_STATE_HOME="$test_root/state"
state_dir="$XDG_STATE_HOME/omarchy"
mkdir -p -- "$state_dir/qick-paste-items/original"
source_path="$state_dir/qick-paste-items/original/image.png"
printf 'original image' >"$source_path"
jq -n --arg path "$source_path" \
  '[{type:"image",mime:"image/png",path:$path}]' >"$state_dir/qick-paste-history.json"

fake_tensaku="$test_root/tensaku"
cat >"$fake_tensaku" <<'EOF'
#!/bin/bash
set -euo pipefail
input=$1
shift
while (($#)); do
  if [[ $1 == --output-filename ]]; then output=$2; shift 2; else shift; fi
done
case "${TEST_EDIT_MODE:-changed}" in
  changed) printf 'edited image' >"$output" ;;
  unchanged) cp -- "$input" "$output" ;;
  cancelled) : ;;
esac
EOF
chmod +x "$fake_tensaku"
export QICK_PASTE_TENSAKU="$fake_tensaku"

result=$($repo_dir/edit-in-tensaku.sh 0)
[[ $(jq -r '.type' <<<"$result") == image ]]
[[ $(jq -r '.mime' <<<"$result") == image/png ]]
edited_path=$(jq -r '.path' <<<"$result")
[[ -f $edited_path ]]
[[ $(<"$edited_path") == 'edited image' ]]
[[ $(<"$source_path") == 'original image' ]]

export TEST_EDIT_MODE=unchanged
result=$($repo_dir/edit-in-tensaku.sh 0)
[[ -z $result ]]
export TEST_EDIT_MODE=cancelled
result=$($repo_dir/edit-in-tensaku.sh 0)
[[ -z $result ]]

printf 'edit-in-tensaku tests passed\n'
