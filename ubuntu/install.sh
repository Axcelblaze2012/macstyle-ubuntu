#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    cat <<'USAGE'
MacStyle Ubuntu Installer

Usage:
  ./ubuntu/install.sh [OPTION]

Options:
  --help       Display this help message
  --check           Validate Ubuntu, GNOME and installer configuration
  --packages-check  Check APT package availability without installing
  --install-packages Install missing configured APT packages

--install-packages installs missing configured APT packages after confirmation.
No desktop settings are changed and no existing packages are removed.
USAGE
}

MODE="check"

for arg in "$@"; do
    case "$arg" in
        --help|-h)
            usage
            exit 0
            ;;
        --check)
            MODE="check"
            ;;
        --packages-check)
            MODE="packages-check"
            ;;
        --install-packages)
            MODE="install-packages"
            ;;
        *)
            echo "ERROR: Unknown option: $arg" >&2
            usage
            exit 2
            ;;
    esac
done

source "$SCRIPT_DIR/config.sh"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

validate_environment() {
    [[ "$EUID" -ne 0 ]] || fail "Do not run as root."

    [[ "$MACSTYLE_PLATFORM" == "ubuntu" ]] \
        || fail "Invalid platform configuration."

    [[ -f /etc/os-release ]] \
        || fail "Cannot identify operating system."

    source /etc/os-release

    [[ "${ID:-}" == "ubuntu" ]] \
        || fail "Ubuntu is required."

    [[ "${VERSION_ID:-}" == "$MACSTYLE_UBUNTU_VERSION" ]] \
        || fail "Ubuntu $MACSTYLE_UBUNTU_VERSION is required."

    command -v gnome-shell >/dev/null 2>&1 \
        || fail "GNOME Shell is not installed."

    GNOME_VERSION="$(gnome-shell --version | awk '{print $3}')"

    [[ "$GNOME_VERSION" == "$MACSTYLE_GNOME_VERSION"* ]] \
        || fail "GNOME Shell $MACSTYLE_GNOME_VERSION is required. Found: $GNOME_VERSION"

    command -v dpkg >/dev/null 2>&1 \
        || fail "dpkg is unavailable."

    SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
    ARCHITECTURE="$(dpkg --print-architecture)"

    [[ ${#MACSTYLE_APT_PACKAGES[@]} -gt 0 ]] \
        || fail "APT package configuration is empty."

    echo "======================================"
    echo "       MacStyle Ubuntu Installer"
    echo "======================================"
    echo
    echo "Platform       : $PRETTY_NAME"
    echo "GNOME Shell    : $GNOME_VERSION"
    echo "Session        : $SESSION_TYPE"
    echo "Architecture   : $ARCHITECTURE"
    echo "Project        : $PROJECT_DIR"
    echo "APT packages   : ${#MACSTYLE_APT_PACKAGES[@]}"
    echo
    echo "Environment validation: PASS"
    echo "Configuration validation: PASS"
    echo "No system or desktop changes were made."
}

check_packages() {
    command -v apt-cache >/dev/null 2>&1 \
        || fail "apt-cache is unavailable."

    command -v dpkg-query >/dev/null 2>&1 \
        || fail "dpkg-query is unavailable."

    local unavailable=0

    echo
    echo "APT PACKAGE PREFLIGHT"
    echo "---------------------"

    for pkg in "${MACSTYLE_APT_PACKAGES[@]}"; do
        [[ "$pkg" =~ ^[a-zA-Z0-9.+-]+$ ]] \
            || fail "Invalid package name: $pkg"

        local installed candidate

        installed="$(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null || true)"
        candidate="$(apt-cache policy "$pkg" | awk '/Candidate:/ {print $2; exit}')"

        if [[ "$installed" == "installed" ]]; then
            printf "INSTALLED   %-30s candidate: %s\\n" "$pkg" "${candidate:-unknown}"
        elif [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
            printf "AVAILABLE   %-30s candidate: %s\\n" "$pkg" "$candidate"
        else
            printf "UNAVAILABLE %s\\n" "$pkg"
            unavailable=1
        fi
    done

    echo
    if (( unavailable == 0 )); then
        echo "APT preflight: PASS"
    else
        echo "APT preflight: FAILED — unavailable packages found."
        return 1
    fi

    echo "No packages were installed or modified."
}


install_packages() {
    local missing=()
    local unavailable=()

    echo
    echo "APT INSTALLATION PREFLIGHT"
    echo "-------------------------"

    for pkg in "${MACSTYLE_APT_PACKAGES[@]}"; do
        [[ "$pkg" =~ ^[a-zA-Z0-9.+-]+$ ]] \
            || fail "Invalid package name: $pkg"

        local installed candidate
        installed="$(dpkg-query -W -f='${db:Status-Status}' "$pkg" 2>/dev/null || true)"
        candidate="$(apt-cache policy "$pkg" | awk '/Candidate:/ {print $2; exit}')"

        if [[ "$installed" == "installed" ]]; then
            echo "Already installed: $pkg"
        elif [[ -n "$candidate" && "$candidate" != "(none)" ]]; then
            missing+=("$pkg")
            echo "Will install: $pkg ($candidate)"
        else
            unavailable+=("$pkg")
            echo "Unavailable: $pkg"
        fi
    done

    if ((${#unavailable[@]} > 0)); then
        fail "Unavailable packages found. Nothing will be installed."
    fi

    if ((${#missing[@]} == 0)); then
        echo "All configured packages are already installed."
        return 0
    fi

    echo
    echo "Packages to install: ${#missing[@]}"
    printf '  - %s\n' "${missing[@]}"
    echo
    read -r -p "Proceed with APT installation? [y/N] " answer

    case "$answer" in
        y|Y|yes|YES) ;;
        *)
            echo "Installation cancelled. No packages were installed."
            return 0
            ;;
    esac

    command -v sudo >/dev/null 2>&1 || fail "sudo is unavailable."
    sudo -v

    sudo apt-get install -y --no-install-recommends -- "${missing[@]}"

    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/macstyle-ubuntu"
    mkdir -p "$state_dir"
    touch "$state_dir/packages-requested.list"

    for pkg in "${missing[@]}"; do
        if ! grep -Fqx -- "$pkg" "$state_dir/packages-requested.list"; then
            printf '%s\n' "$pkg" >> "$state_dir/packages-requested.list"
        fi
    done

    echo
    echo "APT installation completed."
    echo "Requested package list: $state_dir/packages-requested.list"
    echo "Packages are intentionally not removed by the uninstaller."
}

case "$MODE" in
    check)
        validate_environment
        ;;
    packages-check)
        validate_environment
        check_packages
        ;;
    install-packages)
        validate_environment
        install_packages
        ;;
esac
