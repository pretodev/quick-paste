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
- Build tools used by the installer: `make`, `gcc`, `pkg-config`,
  `wayland-scanner`, Wayland client headers, and the wlr-data-control protocol

## Validate

```bash
make validate
```

## Try it locally

Copy the checkout into the user plugin directory, rescan it, then place the
button in the right bar section before the power widget:

```bash
mkdir -p ~/.config/omarchy/plugins/qick-paste
make
cp -a BarWidget.qml QuickPaste.qml ClipboardHistory.js capture.sh paste.sh manifest.json \
  ~/.config/omarchy/plugins/qick-paste/
cp -a build/qick-paste-clipboard-provider ~/.config/omarchy/plugins/qick-paste/
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
- Use Left/Right to select, Enter to paste with every original MIME type,
  Shift+Enter to paste only `text/plain`, and Escape to close.
- Scroll vertically or horizontally over the row to move through the history.

The plugin stores its enriched history at
`~/.local/state/omarchy/qick-paste-history.json` and deduplicated images under
`~/.local/state/omarchy/qick-paste-images/`. Source-application detection is
best effort because Wayland does not expose clipboard ownership metadata.
