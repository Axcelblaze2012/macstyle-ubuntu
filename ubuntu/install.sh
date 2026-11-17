#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_HELPER="$SCRIPT_DIR/backup.sh"
MODE="check"

usage() {
    cat <<'EOF'
MacStyle Ubuntu Installer — Ubuntu 26.04 / GNOME 50

Usage:
  ./ubuntu/install.sh [OPTION]

Options:
  --check              Validate environment
  --packages-check     Check APT packages without installing
  --install-packages   Install missing APT packages only
  --install            Install packages, extensions, DConf and Zsh integration
  --help               Show help

The installer does not remove packages, change wallpaper, or select themes.
It enables Downloads Fan and adds its Dock launcher while preserving
unrelated GNOME extensions and existing Dock favorites.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --help|-h) usage; exit 0 ;;
        --check) MODE="check" ;;
        --packages-check) MODE="packages-check" ;;
        --install-packages) MODE="install-packages" ;;
        --install) MODE="install" ;;
        *) echo "ERROR: Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

source "$SCRIPT_DIR/config.sh"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

validate_environment() {
    [[ "$EUID" -ne 0 ]] || fail "Do not run as root."
    [[ -f /etc/os-release ]] || fail "Cannot identify operating system."
    source /etc/os-release

    [[ "${ID:-}" == ubuntu ]] || fail "Ubuntu is required."
    [[ "${VERSION_ID:-}" == "$MACSTYLE_UBUNTU_VERSION" ]] ||
        fail "Ubuntu $MACSTYLE_UBUNTU_VERSION is required."

    command -v gnome-shell >/dev/null 2>&1 ||
        fail "GNOME Shell is not installed."

    local version
    version="$(gnome-shell --version | awk '{print $3}')"
    [[ "$version" == "$MACSTYLE_GNOME_VERSION"* ]] ||
        fail "GNOME Shell $MACSTYLE_GNOME_VERSION required; found $version."

    command -v dpkg >/dev/null 2>&1 || fail "dpkg is unavailable."
    [[ -x "$BACKUP_HELPER" ]] || fail "Backup helper is missing or not executable."
    [[ -x "$SCRIPT_DIR/modules/extensions.sh" ]] ||
        fail "Extensions module is missing or not executable."
    [[ -x "$SCRIPT_DIR/modules/dconf.sh" ]] ||
        fail "DConf module is missing or not executable."
    [[ -x "$SCRIPT_DIR/modules/downloads-fan.sh" ]] ||
        fail "Downloads Fan module is missing or not executable."
    [[ -r "$SCRIPT_DIR/zsh-integration.zsh" ]] ||
        fail "Zsh integration file is missing."

    echo "MacStyle Ubuntu environment: PASS"
    echo "Ubuntu: $PRETTY_NAME"
    echo "GNOME: $version"
    echo "Session: ${XDG_SESSION_TYPE:-unknown}"
}

package_preflight() {
    command -v apt-cache >/dev/null 2>&1 || fail "apt-cache is unavailable."
    command -v dpkg-query >/dev/null 2>&1 || fail "dpkg-query is unavailable."

    local unavailable=0
    local pkg installed candidate

    echo
    echo "========== APT PACKAGE PREFLIGHT =========="

    for pkg in "${MACSTYLE_APT_PACKAGES[@]}"; do
        [[ "$pkg" =~ ^[a-zA-Z0-9.+-]+$ ]] || fail "Invalid package name: $pkg"

        installed="$(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null || true)"
        candidate="$(apt-cache policy "$pkg" | awk '/Candidate:/ {print $2; exit}')"

        if [[ "$installed" == installed ]]; then
            printf 'INSTALLED   %s\n' "$pkg"
        elif [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
            printf 'AVAILABLE   %s (%s)\n' "$pkg" "$candidate"
        else
            printf 'UNAVAILABLE %s\n' "$pkg"
            unavailable=1
        fi
    done

    (( unavailable == 0 )) || fail "Unavailable APT packages found."
    echo "APT preflight: PASS"
}

install_packages() {
    local missing=()
    local pkg installed candidate

    package_preflight

    for pkg in "${MACSTYLE_APT_PACKAGES[@]}"; do
        installed="$(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null || true)"
        candidate="$(apt-cache policy "$pkg" | awk '/Candidate:/ {print $2; exit}')"

        if [[ "$installed" != installed ]]; then
            [[ -n "$candidate" && "$candidate" != "(none)" ]] ||
                fail "No APT candidate for $pkg"
            missing+=("$pkg")
        fi
    done

    if ((${#missing[@]} == 0)); then
        echo "All configured APT packages are already installed."
        return 0
    fi

    echo
    echo "Packages to install:"
    printf '  %s\n' "${missing[@]}"
    echo
    read -r -p "Install these packages? [y/N] " answer

    case "$answer" in
        y|Y|yes|YES) ;;
        *) echo "Package installation cancelled."; return 3 ;;
    esac

    command -v sudo >/dev/null 2>&1 || fail "sudo is unavailable."
    sudo -v
    sudo apt-get install -y --no-install-recommends -- "${missing[@]}"

    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/macstyle-ubuntu"
    mkdir -p "$state_dir"
    touch "$state_dir/packages-requested.list"

    for pkg in "${missing[@]}"; do
        grep -Fqx -- "$pkg" "$state_dir/packages-requested.list" ||
            printf '%s\n' "$pkg" >> "$state_dir/packages-requested.list"
    done

    echo "APT package installation complete."
}

install_zsh_integration() {
    local rc="$HOME/.zshrc"
    local start="# >>> MacStyle Ubuntu Zsh Integration >>>"
    local end="# <<< MacStyle Ubuntu Zsh Integration <<<"

    [[ ! -L "$rc" ]] || fail "$rc is a symlink; refusing to modify it."

    if [[ -f "$rc" ]] && grep -Fq "$start" "$rc"; then
        grep -Fq "$end" "$rc" ||
            fail "Incomplete MacStyle Zsh block found in $rc."
        echo "Zsh integration already present."
        return
    fi

    if [[ -e "$rc" ]]; then
        "$BACKUP_HELPER" backup .zshrc
    else
        : > "$rc"
        if ! "$BACKUP_HELPER" track .zshrc; then
            rm -f -- "$rc"
            fail "Could not track newly created .zshrc"
        fi
    fi

    cat >> "$rc" <<EOF

$start
if [[ -r "$SCRIPT_DIR/zsh-integration.zsh" ]]; then
  source "$SCRIPT_DIR/zsh-integration.zsh"
fi
$end
EOF

    echo "Zsh integration added to $rc."
}

install_desktop_components() {
    echo
    echo "========== MODULE PREFLIGHT =========="
    "$SCRIPT_DIR/modules/extensions.sh" --dry-run
    "$SCRIPT_DIR/modules/dconf.sh" --dry-run
    "$SCRIPT_DIR/modules/downloads-fan.sh" --dry-run

    echo
    echo "========== INSTALL EXTENSIONS =========="
    "$SCRIPT_DIR/modules/extensions.sh"

    echo
    echo "========== APPLY EXTENSION SETTINGS =========="
    "$SCRIPT_DIR/modules/dconf.sh" --apply

    echo
    echo "========== INSTALL DOWNLOADS FAN =========="
    "$SCRIPT_DIR/modules/downloads-fan.sh"

    echo
    echo "========== CONFIGURE ZSH =========="
    install_zsh_integration

    echo
    echo "MacStyle Ubuntu installation steps completed."
    echo "Log out and log back in if GNOME needs to reload extension files."
    echo "Wallpaper and theme selection were not changed."
    echo "Downloads Fan was enabled and added to Dock favorites if missing."
    echo "All other Dock favorites and extension enablement states were preserved."
}

case "$MODE" in
    check)
        validate_environment
        ;;
    packages-check)
        validate_environment
        package_preflight
        ;;
    install-packages)
        validate_environment
        install_packages
        ;;
    install)
        validate_environment
        install_packages || fail "Installation stopped because package installation was cancelled or failed."
        install_desktop_components
        ;;
esac
