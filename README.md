# Qick Paste

A visual clipboard history for the Omarchy 4.x bar, inspired by macOS Paste.
It opens as a full-width bottom panel with horizontally scrollable cards for
text and images.

Each new item records its source application, relative age, and either its
Unicode character count or image dimensions. Existing Omarchy clipboard
history is imported on first run; metadata unavailable in those older entries
is shown as unknown.

## Requirements

- Omarchy 4.x with the Quickshell-based shell
- `wl-clipboard`, `wtype`, `jq`, `perl`, and `setpriv` (included by Omarchy)

## Validate

```bash
make validate
```

## Try it locally

Copy the checkout into the user plugin directory, rescan it, then place the
button in the right bar section before the power widget:

```bash
mkdir -p ~/.config/omarchy/plugins/qick-paste
cp -a BarWidget.qml QuickPaste.qml ClipboardHistory.js capture.sh paste.sh manifest.json \
  ~/.config/omarchy/plugins/qick-paste/
omarchy-shell shell rescanPlugins
omarchy plugin enable qick-paste --section right --before omarchy.power
```

Files under `~/.config/omarchy/plugins/` hot-reload. To remove the development
copy later, run `omarchy plugin remove qick-paste`.

Once this repository has a Git remote, install it through the regular plugin
flow, then position it explicitly:

```bash
omarchy plugin add https://github.com/OWNER/qick-paste.git --enable
omarchy bar move qick-paste --section right --before omarchy.power
```

## Usage

- Click the bar icon to open or close the panel.
- Click a card once to select it; click it again to paste and close.
- Use Left/Right to select, Enter to paste, and Escape to close.
- Scroll vertically or horizontally over the row to move through the history.

The plugin stores its enriched history at
`~/.local/state/omarchy/qick-paste-history.json` and deduplicated images under
`~/.local/state/omarchy/qick-paste-images/`. Source-application detection is
best effort because Wayland does not expose clipboard ownership metadata.
