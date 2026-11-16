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
  --check      Validate Ubuntu, GNOME and installer configuration

No installation mode is available yet.
Running this script makes no desktop or system changes.
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

case "$MODE" in
    check)
        validate_environment
        ;;
esac
