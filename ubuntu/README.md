# MacStyle Ubuntu — Ubuntu 26.04 / GNOME 50

This is the Ubuntu-specific integration path for MacStyle.
The root install.sh and uninstall.sh remain Fedora-specific.

## Requirements

- Ubuntu 26.04
- GNOME Shell 50
- Logged-in GNOME session

## Installation

Run from the project root:

    ./ubuntu/install.sh --check
    ./ubuntu/install.sh --packages-check
    ./ubuntu/install.sh --install

## Managed extensions

- Dash2Dock Motion
- Blur My Shell
- Compiz Alike Magic Lamp Effect
- User Theme

## DConf recovery

Apply:

    ./ubuntu/modules/dconf.sh --apply

Rollback:

    ./ubuntu/modules/dconf.sh --rollback

Rollback restores only the four managed extension settings paths.

## What the installer does not change

- Wallpaper
- GTK theme, icons or cursor
- GNOME extension enablement or disablement
- Ubuntu Dock or Dash2Dock Lite enablement
- Unrelated extension settings

Existing system packages are not removed.
