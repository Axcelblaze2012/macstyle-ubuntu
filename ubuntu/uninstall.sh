#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/macstyle-ubuntu"
BACKUP_HELPER="$SCRIPT_DIR/backup.sh"
DCONF_MODULE="$SCRIPT_DIR/modules/dconf.sh"
UNIT="macstyle-darkswitch.service"

EXPECTED_INSTALLED=(
    ".local/share/gnome-shell/extensions/dash2dock-motion@unmade.space"
    ".local/bin/macstyle-darkswitch"
    ".config/systemd/user/macstyle-darkswitch.service"
)

EXPECTED_BACKED_UP=(
    ".zshrc"
    ".local/share/gnome-shell/extensions/dash2dock-motion@unmade.space"
    ".local/share/gnome-shell/extensions/blur-my-shell@aunetx"
    ".local/share/gnome-shell/extensions/compiz-alike-magic-lamp-effect@hermes83.github.com"
    ".local/share/gnome-shell/extensions/user-theme@gnome-shell-extensions.gcampax.github.com"
)

fail() {
    printf '[MacStyle Uninstaller] ERROR: %s\n' "$*" >&2
    exit 1
}

usage() {
    echo "Usage: ./ubuntu/uninstall.sh {--dry-run|--uninstall}"
}

MODE="${1:---help}"
case "$MODE" in
    --help|-h) usage; exit 0 ;;
    --dry-run|--uninstall) ;;
    *) usage >&2; exit 2 ;;
esac

[[ "$EUID" -ne 0 ]] || fail "Do not run as root."
command -v realpath >/dev/null 2>&1 || fail "realpath is unavailable."
[[ -x "$BACKUP_HELPER" ]] || fail "Backup helper missing."
[[ -x "$DCONF_MODULE" ]] || fail "DConf module missing."
[[ -f "$STATE/installed.list" ]] || fail "Installed-path record missing."
[[ -f "$STATE/backed-up.list" ]] || fail "Original-path record missing."

check_manifest() {
    local file="$1"
    shift
    local expected=("$@")
    local actual=()
    mapfile -t actual < "$file"

    ((${#actual[@]} == ${#expected[@]})) ||
        fail "Unexpected number of paths in $(basename "$file")."

    local i
    for i in "${!expected[@]}"; do
        [[ "${actual[$i]}" == "${expected[$i]}" ]] ||
            fail "Unexpected recovery path in $(basename "$file"): ${actual[$i]:-empty}"
    done
}

HOME_REAL="$(realpath -e -- "$HOME")"
STATE_REAL="$(realpath -e -- "$STATE")"

safe_home_path() {
    local relative="$1"
    local resolved

    [[ "$relative" != /* && "$relative" != *".."* ]] ||
        fail "Unsafe relative path: $relative"

    resolved="$(realpath -m -- "$HOME/$relative")"
    case "$resolved" in
        "$HOME_REAL"/*) ;;
        *) fail "Path escapes home directory: $relative" ;;
    esac
}

validate_recovery() {
    check_manifest "$STATE/installed.list" "${EXPECTED_INSTALLED[@]}"
    check_manifest "$STATE/backed-up.list" "${EXPECTED_BACKED_UP[@]}"

    local relative source resolved

    for relative in "${EXPECTED_INSTALLED[@]}" "${EXPECTED_BACKED_UP[@]}"; do
        safe_home_path "$relative"
    done

    for relative in "${EXPECTED_BACKED_UP[@]}"; do
        source="$STATE/original/$relative"
        [[ -e "$source" || -L "$source" ]] ||
            fail "Original backup missing: $relative"

        resolved="$(realpath -e -- "$source")"
        case "$resolved" in
            "$STATE_REAL/original/"*) ;;
            *) fail "Backup path escapes recovery directory: $relative" ;;
        esac
    done

    for relative in blur-my-shell.ini dash2dock-motion.ini user-theme.ini magic-lamp.ini; do
        [[ -f "$STATE/dconf-module-original/$relative" ]] ||
            fail "DConf recovery snapshot missing: $relative"
    done

    local zrc="$HOME/.zshrc"
    [[ ! -L "$zrc" ]] || fail ".zshrc is a symlink; refusing to modify it."

    if [[ -e "$zrc" ]]; then
        [[ -f "$zrc" ]] || fail ".zshrc exists but is not a regular file."
        local starts ends
        starts="$(grep -Fxc '# >>> MacStyle Ubuntu Zsh Integration >>>' "$zrc" || true)"
        ends="$(grep -Fxc '# <<< MacStyle Ubuntu Zsh Integration <<<' "$zrc" || true)"
        if [[ "$starts" != "$ends" || ( "$starts" != 0 && "$starts" != 1 ) ]]; then
            fail "Zsh integration markers are incomplete or duplicated."
        fi
    fi
}

remove_zsh_block() {
    local zrc="$HOME/.zshrc"
    [[ -f "$zrc" ]] || return 0

    python3 - "$zrc" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
start = "# >>> MacStyle Ubuntu Zsh Integration >>>"
end = "# <<< MacStyle Ubuntu Zsh Integration <<<"

if start not in text and end not in text:
    print("No managed Zsh block found; existing .zshrc preserved.")
    raise SystemExit(0)

if text.count(start) != 1 or text.count(end) != 1:
    raise SystemExit("Incomplete or duplicated Zsh markers; refusing to edit .zshrc.")

begin = text.index(start)
finish = text.index(end, begin) + len(end)

if text[finish:finish + 2] == "\r\n":
    finish += 2
elif text[finish:finish + 1] == "\n":
    finish += 1

path.write_text(text[:begin] + text[finish:], encoding="utf-8")
print("Removed only the MacStyle-managed Zsh block.")
PY
}

restore_files() {
    local relative source destination

    # Remove paths created by MacStyle, in reverse manifest order.
    for ((i=${#EXPECTED_INSTALLED[@]}-1; i>=0; i--)); do
        relative="${EXPECTED_INSTALLED[$i]}"
        destination="$HOME/$relative"
        safe_home_path "$relative"

        if [[ -e "$destination" || -L "$destination" ]]; then
            rm -rf -- "$destination"
            echo "Removed: $relative"
        fi
    done

    # Restore original extension folders, excluding .zshrc.
    for ((i=${#EXPECTED_BACKED_UP[@]}-1; i>=0; i--)); do
        relative="${EXPECTED_BACKED_UP[$i]}"
        [[ "$relative" == ".zshrc" ]] && continue

        source="$STATE/original/$relative"
        destination="$HOME/$relative"

        safe_home_path "$relative"
        mkdir -p -- "$(dirname "$destination")"
        cp -a -- "$source" "$destination"
        echo "Restored: $relative"
    done

    # Keep all user edits outside the marked integration block.
    remove_zsh_block
}

validate_recovery

echo "MacStyle Ubuntu recovery records: PASS"

if [[ "$MODE" == "--dry-run" ]]; then
    echo
    echo "========== FILE ACTIONS =========="
    printf 'Remove: %s\n' "${EXPECTED_INSTALLED[@]}"
    printf 'Restore original: %s\n' "${EXPECTED_BACKED_UP[@]:1}"
    echo "Remove only the marked MacStyle block from .zshrc."

    echo
    echo "========== DCONF TARGETS =========="
    echo "Blur My Shell"
    echo "Dash2Dock Motion"
    echo "User Theme"
    echo "Magic Lamp"

    echo
    echo "========== PRESERVED =========="
    echo "APT packages"
    echo "Wallpaper and background selection"
    echo "GTK theme, icons and cursor selections"
    echo "GNOME extension enablement state"
    echo "Ubuntu Dock and unrelated extension settings"
    echo "User .zshrc content outside the MacStyle block"
    echo "Original recovery backups"

    echo
    echo "DRY RUN complete. No changes made."
    exit 0
fi

echo
echo "WARNING: This restores the original extension folders and removes"
echo "the MacStyle dark-switcher files and managed Zsh block."
echo "APT packages and unrelated desktop settings will remain."
read -r -p 'Type UNINSTALL to continue: ' answer
[[ "$answer" == "UNINSTALL" ]] || {
    echo "Uninstall cancelled."
    exit 0
}

if [[ -f "$HOME/.config/systemd/user/$UNIT" ]]; then
    systemctl --user disable --now "$UNIT" ||
        fail "Could not stop/disable $UNIT. No files were restored."
fi

echo
echo "========== TARGETED DCONF RESTORE =========="
if ! "$DCONF_MODULE" --rollback; then
    echo "DConf rollback failed. Attempting to restart the switcher." >&2
    [[ ! -f "$HOME/.config/systemd/user/$UNIT" ]] ||
        systemctl --user enable --now "$UNIT" || true
    fail "Stopped before file restoration. Original backups remain."
fi

echo
echo "========== FILE RESTORE =========="
restore_files

systemctl --user daemon-reload ||
    echo "WARNING: systemd user daemon-reload did not complete."

echo
echo "MacStyle Ubuntu managed components restored."
echo "Recovery backups retained at: $STATE"
echo "Log out and log back in to reload GNOME extension files."
echo "APT packages were not removed."
