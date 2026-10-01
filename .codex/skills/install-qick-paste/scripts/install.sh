#!/usr/bin/env bash

set -euo pipefail

plugin_id="qick-paste"
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "$script_dir/../../../.." && pwd)
plugins_dir="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
target_dir="$plugins_dir/$plugin_id"
dry_run=0

if [[ ${1:-} == "--dry-run" ]]; then
  dry_run=1
  shift
fi
if (( $# > 0 )); then
  echo "Usage: ${0##*/} [--dry-run]" >&2
  exit 2
fi

runtime_files=(BarWidget.qml QuickPaste.qml ClipboardHistory.js capture.sh paste.sh manifest.json)
required_commands=(omarchy omarchy-shell jq wl-copy wl-paste wtype perl setpriv node)

for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

for file in "${runtime_files[@]}"; do
  if [[ ! -f $repo_dir/$file ]]; then
    echo "Missing plugin file: $repo_dir/$file" >&2
    exit 1
  fi
done

omarchy plugin validate "$repo_dir"

if (( dry_run )); then
  if [[ -d $target_dir/.git ]]; then
    echo "Would update the Git-managed plugin with: omarchy plugin update $plugin_id"
  else
    echo "Would install or update runtime files in: $target_dir"
  fi
  echo "Would enable and place $plugin_id in the right section before omarchy.power"
  echo "Would restart the Omarchy shell with: omarchy restart shell"
  exit 0
fi

if [[ -d $target_dir/.git ]]; then
  omarchy plugin update "$plugin_id"
  action="Updated Git-managed installation"
else
  if [[ -e $target_dir && ! -d $target_dir ]]; then
    echo "Installation target exists and is not a directory: $target_dir" >&2
    exit 1
  fi
  if [[ -d $target_dir ]]; then
    action="Updated local installation"
  else
    action="Installed local copy"
  fi
  mkdir -p -- "$target_dir"
  for file in "${runtime_files[@]}"; do
    mode=0644
    [[ $file == *.sh ]] && mode=0755
    install -m "$mode" -- "$repo_dir/$file" "$target_dir/$file"
  done
  omarchy-shell shell rescanPlugins >/dev/null
fi

omarchy plugin enable "$plugin_id" --section right --before omarchy.power

if ! omarchy plugin list --json | jq -e --arg id "$plugin_id" \
  'any(.[]; .id == $id and .enabled == true)' >/dev/null; then
  echo "Plugin was copied but is not reported as enabled: $plugin_id" >&2
  exit 1
fi

omarchy restart shell

echo "$action: $target_dir"
