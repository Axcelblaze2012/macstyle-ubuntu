#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/macstyle-ubuntu"
BACKUP_HELPER="$SCRIPT_DIR/backup.sh"
DCONF_MODULE="$SCRIPT_DIR/modules/dconf.sh"
UNIT="macstyle-darkswitch.service"

EXTENSIONS=(
    ".local/share/gnome-shell/extensions/dash2dock-motion@unmade.space"
    ".local/share/gnome-shell/extensions/blur-my-shell@aunetx"
    ".local/share/gnome-shell/extensions/compiz-alike-magic-lamp-effect@hermes83.github.com"
    ".local/share/gnome-shell/extensions/user-theme@gnome-shell-extensions.gcampax.github.com"
)

fail() {
    echo "[MacStyle Uninstaller] ERROR: $*" >&2
    exit 1
}

contains() {
    local item="$1"
    shift
    local entry
    for entry in "$@"; do
        [[ "$entry" == "$item" ]] && return 0
    done
    return 1
}

is_extension() {
    contains "$1" "${EXTENSIONS[@]}"
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
command -v python3 >/dev/null 2>&1 || fail "python3 is unavailable."
[[ -x "$BACKUP_HELPER" ]] || fail "Backup helper missing."
[[ -x "$DCONF_MODULE" ]] || fail "DConf module missing."
[[ -f "$STATE/installed.list" ]] || fail "Installed-path record missing."
[[ -f "$STATE/backed-up.list" ]] || fail "Original-path record missing."

HOME_REAL="$(realpath -e -- "$HOME")"
STATE_REAL="$(realpath -e -- "$STATE")"

mapfile -t INSTALLED < "$STATE/installed.list"
mapfile -t BACKED_UP < "$STATE/backed-up.list"

safe_home_path() {
    local relative="$1"
    local resolved
    [[ -n "$relative" && "$relative" != /* ]] ||
        fail "Invalid relative path: $relative"

    [[ "/$relative/" != *"/../"* ]] ||
        fail "Path traversal rejected: $relative"

    resolved="$(realpath -m -- "$HOME/$relative")"
    case "$resolved" in
        "$HOME_REAL"/*) ;;
        *) fail "Path escapes home directory: $relative" ;;
    esac
}

validate_manifest() {
    local relative source resolved
    local -A seen_installed=()
    local -A seen_backed=()

    for relative in "${INSTALLED[@]}"; do
        [[ -n "$relative" ]] || fail "Empty installed-path entry."

        if ! is_extension "$relative" &&
           [[ "$relative" != ".local/bin/macstyle-darkswitch" ]] &&
           [[ "$relative" != ".config/systemd/user/macstyle-darkswitch.service" ]] &&
           [[ "$relative" != ".zshrc" ]]; then
            fail "Unexpected installed path: $relative"
        fi

        [[ -z "${seen_installed[$relative]+x}" ]] ||
            fail "Duplicate installed path: $relative"
        seen_installed["$relative"]=1
        safe_home_path "$relative"
    done

    for relative in "${BACKED_UP[@]}"; do
        [[ -n "$relative" ]] || fail "Empty backup-path entry."

        if ! is_extension "$relative" && [[ "$relative" != ".zshrc" ]]; then
            fail "Unexpected backup path: $relative"
        fi

        [[ -z "${seen_backed[$relative]+x}" ]] ||
            fail "Duplicate backup path: $relative"
        seen_backed["$relative"]=1
        safe_home_path "$relative"

        source="$STATE/original/$relative"
        [[ -e "$source" || -L "$source" ]] ||
            fail "Original backup missing: $relative"

        resolved="$(realpath -e -- "$source")"
        case "$resolved" in
            "$STATE_REAL/original/"*) ;;
            *) fail "Backup escapes recovery directory: $relative" ;;
        esac
    done

    for relative in "${EXTENSIONS[@]}"; do
        if ! contains "$relative" "${INSTALLED[@]}" &&
           ! contains "$relative" "${BACKED_UP[@]}"; then
            fail "No install or backup record for extension: $relative"
        fi
    done

    for relative in blur-my-shell.ini dash2dock-motion.ini user-theme.ini magic-lamp.ini; do
        [[ -f "$STATE/dconf-module-original/$relative" ]] ||
            fail "DConf recovery snapshot missing: $relative"
    done

    local zrc="$HOME/.zshrc"
    [[ ! -L "$zrc" ]] || fail ".zshrc is a symlink; refusing to edit."

    if [[ -e "$zrc" ]]; then
        [[ -f "$zrc" ]] || fail ".zshrc is not a regular file."

        local starts ends
        starts="$(grep -Fxc '# >>> MacStyle Ubuntu Zsh Integration >>>' "$zrc" || true)"
        ends="$(grep -Fxc '# <<< MacStyle Ubuntu Zsh Integration <<<' "$zrc" || true)"

        [[ "$starts" == "$ends" ]] ||
            fail "Incomplete Zsh integration markers."
        [[ "$starts" == 0 || "$starts" == 1 ]] ||
            fail "Duplicate Zsh integration blocks."
    fi
}

remove_zsh_block() {
    local had_original=0
    contains ".zshrc" "${BACKED_UP[@]}" && had_original=1

    python3 - "$HOME/.zshrc" "$had_original" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
had_original = sys.argv[2] == "1"

if not path.exists():
    raise SystemExit(0)

text = path.read_text(encoding="utf-8")
start = "# >>> MacStyle Ubuntu Zsh Integration >>>"
end = "# <<< MacStyle Ubuntu Zsh Integration <<<"

if start in text or end in text:
    if text.count(start) != 1 or text.count(end) != 1:
        raise SystemExit("Invalid Zsh markers; refusing to modify .zshrc.")

    begin = text.index(start)
    finish = text.index(end, begin) + len(end)

    if text[finish:finish + 2] == "\r\n":
        finish += 2
    elif text[finish:finish + 1] == "\n":
        finish += 1

    text = text[:begin] + text[finish:]
    path.write_text(text, encoding="utf-8")
    print("Removed only the MacStyle Zsh block.")
else:
    print("No MacStyle Zsh block found.")

# Remove the file only when MacStyle created it and it is now empty.
if not had_original and not text.strip():
    path.unlink(missing_ok=True)
    print("Removed the empty Zsh file created by MacStyle.")
PY
}

restore_files() {
    local relative source destination
    local i

    # Remove paths created/tracked by the installer, except .zshrc.
    for ((i=${#INSTALLED[@]}-1; i>=0; i--)); do
        relative="${INSTALLED[$i]}"
        [[ "$relative" == ".zshrc" ]] && continue

        safe_home_path "$relative"
        destination="$HOME/$relative"

        if [[ -e "$destination" || -L "$destination" ]]; then
            rm -rf -- "$destination"
            echo "Removed: $relative"
        fi
    done

    # Replace each previously existing extension directory completely.
    for ((i=${#BACKED_UP[@]}-1; i>=0; i--)); do
        relative="${BACKED_UP[$i]}"
        [[ "$relative" == ".zshrc" ]] && continue

        safe_home_path "$relative"
        source="$STATE/original/$relative"
        destination="$HOME/$relative"

        rm -rf -- "$destination"
        mkdir -p -- "$(dirname "$destination")"
        cp -a -- "$source" "$destination"
        echo "Restored original: $relative"
    done

    remove_zsh_block
}

validate_manifest

echo "[MacStyle Uninstaller] Recovery records validated."

if [[ "$MODE" == "--dry-run" ]]; then
    echo
    echo "========== TRACKED PATHS TO REMOVE =========="
    printf '%s\n' "${INSTALLED[@]}"

    echo
    echo "========== ORIGINAL EXTENSIONS TO RESTORE =========="
    for relative in "${BACKED_UP[@]}"; do
        [[ "$relative" == ".zshrc" ]] || echo "$relative"
    done

    echo
    echo "========== ZSH =========="
    echo "Remove only the managed MacStyle block."
    echo "Preserve all other user content."

    echo
    echo "========== DCONF =========="
    echo "Blur My Shell"
    echo "Dash2Dock Motion"
    echo "User Theme"
    echo "Magic Lamp"

    echo
    echo "APT packages, wallpaper, selected themes, extension enablement"
    echo "and unrelated GNOME settings will be preserved."
    echo "Recovery backups will be retained."
    echo
    echo "DRY RUN complete. No changes made."
    exit 0
fi

echo
echo "This restores original extension directories and removes"
echo "the tracked MacStyle components."
read -r -p 'Type UNINSTALL to continue: ' answer

[[ "$answer" == "UNINSTALL" ]] || {
    echo "Uninstall cancelled."
    exit 0
}

if contains ".config/systemd/user/$UNIT" "${INSTALLED[@]}" &&
   [[ -f "$HOME/.config/systemd/user/$UNIT" ]]; then
    systemctl --user disable --now "$UNIT" ||
        fail "Could not stop the dark-switcher service."
fi

echo
echo "========== TARGETED DCONF RESTORE =========="
"$DCONF_MODULE" --rollback ||
    fail "DConf rollback failed. Original file backups remain."

echo
echo "========== FILE RESTORE =========="
restore_files

systemctl --user daemon-reload ||
    echo "WARNING: systemd daemon reload failed."

echo
echo "MacStyle Ubuntu managed components restored."
echo "Original recovery backups retained at: $STATE"
echo "APT packages were not removed."
echo "Log out and log back in to reload GNOME extensions."
