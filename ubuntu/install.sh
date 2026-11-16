#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/config.sh"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

echo "======================================"
echo "       MacStyle Ubuntu Installer"
echo "======================================"

[[ "$EUID" -ne 0 ]] || fail "Do not run as root."

[[ -f /etc/os-release ]] || fail "Cannot identify operating system."
source /etc/os-release

[[ "${ID:-}" == "ubuntu" ]] || fail "Ubuntu is required."
[[ "${VERSION_ID:-}" == "$MACSTYLE_UBUNTU_VERSION" ]] \
    || fail "Ubuntu $MACSTYLE_UBUNTU_VERSION is required."

command -v gnome-shell >/dev/null 2>&1 \
    || fail "GNOME Shell is not installed."

GNOME_VERSION="$(gnome-shell --version | awk '{print $3}')"

[[ "$GNOME_VERSION" == "$MACSTYLE_GNOME_VERSION"* ]] \
    || fail "GNOME Shell $MACSTYLE_GNOME_VERSION is required. Found: $GNOME_VERSION"

SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"

echo
echo "Platform       : $PRETTY_NAME"
echo "GNOME Shell    : $GNOME_VERSION"
echo "Session        : $SESSION_TYPE"
echo "Architecture   : $(dpkg --print-architecture)"
echo "Project        : $PROJECT_DIR"
echo
echo "Environment validation: PASS"
echo "No system or desktop changes were made."
