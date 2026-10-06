# AppImage Integration Scripts (Kubuntu / KDE Plasma)

Two small scripts to properly integrate AppImages into the Kubuntu desktop:
give them a real `.desktop` entry (so they show up in the app menu) and,
optionally, a right-click "Integrate this AppImage" action in Dolphin /
Nautilus.

## `integrate-appimage.sh`

Integrates a single AppImage into the desktop (creates its menu entry, icon, and proper .desktop file).

```bash
chmod +x integrate-appimage.sh
./integrate-appimage.sh /path/to/YourApp.AppImage
```

What it does:

1. Extracts the AppImage (`--appimage-extract`) to read its **original**
   `.desktop` file and icon.
2. Creates a folder named after the app, next to the AppImage, and moves the
   AppImage + icon into it.
3. Copies the original `.desktop` file to `~/.local/share/applications/`,
   only patching `Exec=`, `Icon=`, `TryExec=` and `Path=` so they point to
   the new location. Everything else (`Comment=`, `Categories=`,
   `Keywords=`, etc.) is kept as-is.

The app then appears in your application menu and can be pinned to the
taskbar.

## `setup-context-menu.sh`

One-time setup that adds a right-click **"Integrate this AppImage"** entry to
your file manager, so you no longer need the terminal at all.

```bash
chmod +x setup-context-menu.sh
./setup-context-menu.sh
```

By default it looks for `integrate-appimage.sh` in the same folder; pass a
path explicitly if needed:

```bash
./setup-context-menu.sh /path/to/integrate-appimage.sh
```

It detects your desktop environment automatically:

- **KDE Plasma 6** → creates a service menu in `~/.local/share/kio/servicemenus/`
- **KDE Plasma 5** → creates a service menu in `~/.local/share/kservices5/ServiceMenus/`
- **GNOME (Nautilus)** → creates a script in `~/.local/share/nautilus/scripts/`
  (accessible via right-click → Scripts)
- **Other (XFCE, Cinnamon, MATE...)** → not automated; these file managers
  configure custom actions through their own GUI.

After running it, restart your file manager (e.g. `kquitapp6 dolphin` then
reopen it) for the new entry to appear.

**Note:** on KDE, the generated `.desktop` file itself must be executable
(the script already does `chmod +x` on it) — without it, KDE treats the
entry as untrusted and refuses to run it.

## Requirements

- The target `.AppImage` must support `--appimage-extract` (true for
  virtually all AppImages built with `appimagetool`).
- Bash, `sed`, `grep`, `find` (standard on Kubuntu).
