# MacStyle Ubuntu — Ubuntu 26.04 / GNOME 50

MacStyle includes a dedicated Ubuntu integration path, separate from the original Fedora installer.

The root `install.sh` and `uninstall.sh` remain Fedora-specific. All Ubuntu operations are handled through the `ubuntu/` directory.

## Requirements

- Ubuntu 26.04 LTS
- GNOME Shell 50
- Active GNOME desktop session
- Git and standard Ubuntu utilities

Tested on Ubuntu 26.04.1 LTS with GNOME 50.1 (Wayland).

## Installation

Run these commands from the project root:

```bash
./ubuntu/install.sh --check
./ubuntu/install.sh --packages-check
./ubuntu/install.sh --install
```

Log out and log back in if required to activate the desktop changes.

## Managed GNOME Extensions

The Ubuntu integration manages these four extensions:

- Dash2Dock Motion
- Blur My Shell
- Compiz Alike Magic Lamp Effect
- User Theme

Extension files are installed in the user's local GNOME extensions directory.

## Downloads Fan Integration

The Ubuntu installer also integrates Downloads Fan:

- Installs the Downloads Fan GNOME extension.
- Installs its stable helper.
- Adds the Dock launcher.
- Preserves existing Dock favorites.
- Enables Downloads Fan as part of the integration.

## DConf Configuration

The installer applies 13 managed DConf configuration sections.

Apply the managed configuration manually:

```bash
./ubuntu/modules/dconf.sh --apply
```

Rollback:

```bash
./ubuntu/modules/dconf.sh --rollback
```

Rollback restores only the four managed extension settings paths. It does not reset unrelated GNOME settings.

## Backup and Recovery

Before applying managed changes, the installer preserves the original state of the files and settings it manages.

This allows tracked changes to be restored during uninstallation.

## Uninstallation

Run the Ubuntu-specific uninstaller from the project root:

```bash
./ubuntu/uninstall.sh
```

Follow the confirmation prompt. The uninstaller requires the exact confirmation phrase `UNINSTALL`.

It restores tracked original files and settings while preserving unrelated extensions and Dock favorites.

## What the Installer Does Not Change

- Wallpaper selection
- GTK theme, icons or cursor
- Existing enablement states of unrelated GNOME extensions
- Unrelated Dock favorites
- Unrelated GNOME settings
- Existing system packages

Downloads Fan is enabled as part of the integration. Existing unrelated extension states are preserved.

## Important Notes

- Do not use the root Fedora `install.sh` or `uninstall.sh` for Ubuntu.
- Use the scripts inside `ubuntu/` for Ubuntu installation and recovery.
- Existing system packages are not automatically removed.
- The Ubuntu integration is maintained separately from the Fedora installation path.