#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$MODULE_DIR/../.." && pwd)"
CONFIG="$PROJECT_ROOT/ubuntu/settings/extensions.dconf"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/macstyle-ubuntu/dconf-module-original"

NAMES=(
    blur-my-shell
    dash2dock-motion
    user-theme
    magic-lamp
)

PATHS=(
    /org/gnome/shell/extensions/blur-my-shell/
    /org/gnome/shell/extensions/dash2dock-motion/
    /org/gnome/shell/extensions/user-theme/
    /org/gnome/shell/extensions/ncom/github/hermes83/compiz-alike-magic-lamp-effect/
)

fail() {
    printf '[MacStyle DConf] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    echo "Usage: dconf.sh {--dry-run|--apply|--rollback}"
}

validate() {
    [[ "$(id -u)" -ne 0 ]] || fail "Do not run as root."
    command -v dconf >/dev/null 2>&1 || fail "dconf is missing."
    command -v python3 >/dev/null 2>&1 || fail "python3 is missing."
    [[ -s "$CONFIG" ]] || fail "Ubuntu DConf configuration is missing."

    python3 - "$CONFIG" <<'PY'
import configparser
import sys

p = configparser.ConfigParser(interpolation=None, strict=False, delimiters=("=",))
p.optionxform = str
p.read(sys.argv[1], encoding="utf-8")

allowed = (
    "org/gnome/shell/extensions/blur-my-shell",
    "org/gnome/shell/extensions/dash2dock-motion",
    "org/gnome/shell/extensions/user-theme",
)

if not p.sections():
    raise SystemExit("Configuration has no sections.")

for section in p.sections():
    if not any(section == x or section.startswith(x + "/") for x in allowed):
        raise SystemExit(f"Unexpected DConf section: {section}")

print(f"Validated {len(p.sections())} managed DConf sections.")
PY
}

save_originals() {
    mkdir -p "$STATE"

    for i in "${!NAMES[@]}"; do
        local file="$STATE/${NAMES[$i]}.ini"

        if [[ ! -e "$file" ]]; then
            local tmp="${file}.tmp.$$"
            dconf dump "${PATHS[$i]}" > "$tmp"
            mv -- "$tmp" "$file"
            echo "Saved original: ${NAMES[$i]}"
        else
            echo "Original already preserved: ${NAMES[$i]}"
        fi
    done
}

rollback_targets() {
    for i in "${!NAMES[@]}"; do
        [[ -f "$STATE/${NAMES[$i]}.ini" ]] ||
            fail "Missing backup for ${NAMES[$i]}"
    done

    for ((i=${#NAMES[@]}-1; i>=0; i--)); do
        dconf reset -f "${PATHS[$i]}"
        dconf load "${PATHS[$i]}" < "$STATE/${NAMES[$i]}.ini"
        echo "Restored: ${NAMES[$i]}"
    done
}

case "${1:-}" in
    --dry-run)
        validate
        echo
        echo "DRY RUN: No desktop settings will be changed."
        cat "$CONFIG"
        echo
        echo "Targets: ${NAMES[*]}"
        ;;
    --apply)
        validate
        save_originals

        if ! dconf load / < "$CONFIG"; then
            echo "Apply failed. Attempting targeted rollback." >&2
            rollback_targets
            fail "Apply failed; original extension settings restored."
        fi

        echo "Ubuntu extension settings applied."
        echo "No extensions were enabled, disabled, or removed."
        ;;
    --rollback)
        validate
        rollback_targets
        echo "Targeted extension rollback complete."
        ;;
    --help|-h)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
