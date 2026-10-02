# Qick Paste

A visual clipboard history for the Omarchy 4.x bar, inspired by macOS Paste.
It opens as a full-width bottom panel with horizontally scrollable cards for
text, images, and files.

Copied HTTP(S) links get an Open Graph preview when the destination provides
`og:description`, `og:image`, or `og:url`. Preview retrieval is best effort,
with short timeouts and a one-megabyte response limit; the original URL remains
the clipboard item and is always what gets pasted.

Each new item records its source application, relative age, and its
Unicode character count, image dimensions, or file count. Existing Omarchy clipboard
history is imported on first run; metadata unavailable in those older entries
is shown as unknown.

## Requirements

- Omarchy 4.x with the Quickshell-based shell
- `wl-clipboard`, `wtype`, `jq`, `perl`, `python`, `curl`, and `setpriv` (included by Omarchy)
- `tensaku` for image editing
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
cp -a BarWidget.qml QuickPaste.qml ClipboardHistory.js capture.sh edit-in-tensaku.sh file-action.sh file-uris.py link-preview.py paste.sh manifest.json \
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
- Type to search copied text, links, and file names, or click the search field.
  Results update as you type, and Enter pastes the first match. Escape closes
  the panel and clears the search for the next opening.
- Click a card once to select it; click it again to paste and close.
- Use Left/Right to select, Enter to paste with every original MIME type,
  Shift+Enter to paste only `text/plain`, and Escape to close.
- Use Ctrl+Enter to open a selected HTTP(S) link in the default browser. The
  same action appears first in the card's context menu.
- Right-click an image and choose **Abrir no Tensaku**. Saving the edit creates
  a new history item and leaves the original image untouched.
- Copied files and folders appear together in one card. Click twice or press
  Enter to paste the original file selection. The context menu can open the
  files, reveal them in Files, or paste absolute paths or `~/` paths. Path
  actions paste one path per line; `~/` is available only when every item is
  inside the home directory. Use Ctrl+O to open, Ctrl+Shift+O to reveal,
  Ctrl+P to paste absolute paths, or Ctrl+Shift+P to paste `~/` paths.
- Scroll vertically or horizontally over the row to move through the history.

The plugin stores its enriched history at
`~/.local/state/omarchy/qick-paste-history.json` by default and captured clipboard formats under
`~/.local/state/omarchy/qick-paste-items/`. Source-application detection is
best effort because Wayland does not expose clipboard ownership metadata.
