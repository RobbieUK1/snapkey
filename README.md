# Snapkey

An Omarchy shell plugin for assigning keys to Omarchy's screenshot actions.
No bar icon: open it from the apps menu.

![Snapkey icon](icon/snapkey.svg)

## Actions

| Action | Command |
|---|---|
| Smart screenshot | `omarchy capture screenshot smart` |
| Region | `omarchy capture screenshot region` |
| Window | `omarchy capture screenshot windows` |
| Full screen | `omarchy capture screenshot fullscreen` |
| Full screen (save) | `omarchy capture screenshot fullscreen save` |
| Scrolling region | `omarchy capture screenshot scroll` |
| Text (OCR) | `omarchy capture text` |
| QR code | `omarchy capture qr` |
| Capture menu | `omarchy menu toggle capture` |

Snapkey shows Omarchy's current defaults (Print for a screenshot,
`Super + Ctrl + Print` for OCR, and so on). Assigning a key replaces the
default for that action; resetting puts the default back.

## Install

```bash
./bin/install
```

The script validates the plugin, copies it to
`~/.config/omarchy/plugins/robbie.snapkey`, installs the apps-menu entry and
icon, rescans the shell, and enables the plugin without adding a bar widget.

Open **Snapkey** from the apps menu, or run:

```bash
omarchy-shell shell summon robbie.snapkey '{}'
```

## Use

| Key | Does |
|---|---|
| `↑` / `↓` or `J` / `K` | Move between actions |
| `Enter` / `Space` | Record a key combination |
| `Delete` / `Backspace` | Reset the selected action |
| `?` | Show help |
| `Esc` / `Q` | Close |

While recording, press a combination such as `Super + Shift + S`, or a bare
`Print` / `F1`-`F24`. `Esc` cancels. If the key is already bound to something
else, Snapkey asks before replacing it.

## How it works

Choices are written to a managed block at the end of
`~/.config/hypr/bindings.lua`:

```lua
-- Snapkey: screenshot keys (start)
-- Managed by Snapkey. Change these in Snapkey; edits here are replaced.
o.rebind("PRINT", "Snapkey: Region", "omarchy capture screenshot region")
-- Snapkey: screenshot keys (end)
```

`o.rebind` keeps Hyprland's default binding list intact while replacing the
keys you choose. The rest of `bindings.lua` is never touched. The first change
copies the original file to `bindings.lua.bak.snapkey`, then each change is
written atomically, applied with `hyprctl reload`, checked with
`hyprctl configerrors`, and rolled back automatically if Hyprland rejects it.

The helper (`plugin/snapkey`) emits JSON for every command, so the UI can show
errors without parsing prose:

```bash
plugin/snapkey status
plugin/snapkey check region "PRINT"
plugin/snapkey set region "PRINT"
plugin/snapkey reset region
plugin/snapkey reset-all
```

## Test

```bash
./bin/test
```

The tests run the helper against a temporary `bindings.lua` and a fake
`hyprctl`; they never touch the live Hyprland configuration.

## Uninstall

```bash
plugin/snapkey reset-all
omarchy plugin disable robbie.snapkey
rm -rf ~/.config/omarchy/plugins/robbie.snapkey
rm -f ~/.local/share/applications/snapkey.desktop
rm -f ~/.local/share/icons/hicolor/scalable/apps/snapkey.svg
```

## License

MIT
