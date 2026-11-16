#!/usr/bin/env bash

MACSTYLE_PLATFORM="ubuntu"
MACSTYLE_UBUNTU_VERSION="26.04"
MACSTYLE_GNOME_VERSION="50"

MACSTYLE_APT_PACKAGES=(
    zsh
    zsh-autosuggestions
    zsh-syntax-highlighting
    fastfetch
    lsd
    fzf
    zoxide
)

MACSTYLE_REMOVE_EXTENSIONS=(
    apps-menu@gnome-shell-extensions.gcampax.github.com
    background-logo@fedorahosted.org
)

MACSTYLE_CONFLICTING_EXTENSIONS=(
    dash-to-dock@micxgx.gmail.com
    ubuntu-dock@ubuntu.com
    dash2dock-lite@icedman.github.com
)
