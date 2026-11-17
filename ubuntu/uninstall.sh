#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/macstyle-ubuntu"
BACKUP_HELPER="$SCRIPT_DIR/backup.sh"
DCONF_MODULE="$SCRIPT_DIR/modules/dconf.sh"
UNIT="macstyle-darkswitch.service"

DOWNLOADS_FAN_UUID="downloads-fan@macstyle.local"
DOWNLOADS_FAN_FAVORITE="downloads-folder.desktop"
DOWNLOADS_FAN_STATE="$STATE/downloads-fan/original-state"

DOWNLOADS_FAN_PATHS=(
    ".local/share/gnome-shell/extensions/downloads-fan@macstyle.local"
    ".local/libexec/downloads-stack"
    ".local/share/applications/downloads-folder.desktop"
)

OWNED_INSTALLED=()
OWNED_BACKED_UP=()

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

is_owned_installed() {
    local item="$1"
    if is_extension "$item"; then return 0; fi
    if contains "$item" "${DOWNLOADS_FAN_PATHS[@]}"; then return 0; fi
    case "$item" in
        ".local/bin/macstyle-darkswitch"|".config/systemd/user/macstyle-darkswitch.service"|".zshrc")
            return 0 ;;
    esac
    return 1
}

is_owned_backup() {
    local item="$1"
    if is_extension "$item"; then return 0; fi
    if contains "$item" "${DOWNLOADS_FAN_PATHS[@]}"; then return 0; fi
    [[ "$item" == ".zshrc" ]]
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

        [[ -z "${seen_installed[$relative]+x}" ]] ||
            fail "Duplicate installed path: $relative"
        seen_installed["$relative"]=1
        safe_home_path "$relative"

        if is_owned_installed "$relative"; then
            OWNED_INSTALLED+=("$relative")
        else
            echo "[MacStyle Uninstaller] WARNING: Foreign installed path will be preserved: $relative"
        fi
    done

    for relative in "${BACKED_UP[@]}"; do
        [[ -n "$relative" ]] || fail "Empty backup-path entry."

        is_owned_backup "$relative" ||
            fail "Unexpected backup path; refusing unsafe restore: $relative"

        [[ -z "${seen_backed[$relative]+x}" ]] ||
            fail "Duplicate backup path: $relative"
        seen_backed["$relative"]=1
        safe_home_path "$relative"
        OWNED_BACKED_UP+=("$relative")

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

    if [[ -e "$DOWNLOADS_FAN_STATE" || -L "$DOWNLOADS_FAN_STATE" ]]; then
        [[ -f "$DOWNLOADS_FAN_STATE" && ! -L "$DOWNLOADS_FAN_STATE" ]] ||
            fail "Downloads Fan recovery state is not a regular file."

        python3 - "$DOWNLOADS_FAN_STATE" <<'PY_STATE'
import sys
from pathlib import Path

values = {}
for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    if "=" not in line:
        raise SystemExit("Malformed Downloads Fan recovery state.")
    key, value = line.split("=", 1)
    if key in values or value not in ("0", "1"):
        raise SystemExit("Malformed Downloads Fan recovery state.")
    values[key] = value

expected = {"extension_enabled_before", "favorite_before"}
if set(values) != expected:
    raise SystemExit("Incomplete Downloads Fan recovery state.")
PY_STATE
    fi

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
    for ((i=${#OWNED_INSTALLED[@]}-1; i>=0; i--)); do
        relative="${OWNED_INSTALLED[$i]}"
        [[ "$relative" == ".zshrc" ]] && continue

        safe_home_path "$relative"
        destination="$HOME/$relative"

        if [[ -e "$destination" || -L "$destination" ]]; then
            rm -rf -- "$destination"
            echo "Removed: $relative"
        fi
    done

    # Replace each previously existing extension directory completely.
    for ((i=${#OWNED_BACKED_UP[@]}-1; i>=0; i--)); do
        relative="${OWNED_BACKED_UP[$i]}"
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

restore_downloads_fan_settings() {
    [[ -f "$DOWNLOADS_FAN_STATE" ]] || {
        echo "No Downloads Fan GNOME state snapshot; settings unchanged."
        return 0
    }

    python3 - "$DOWNLOADS_FAN_STATE" "$DOWNLOADS_FAN_UUID" "$DOWNLOADS_FAN_FAVORITE" <<'PY_GSETTINGS'
import ast
import subprocess
import sys

state_path, uuid, favorite = sys.argv[1:]
state = {}
for line in open(state_path, encoding="utf-8"):
    key, value = line.rstrip("\n").split("=", 1)
    state[key] = value

def read_array(key):
    result = subprocess.run(
        ["gsettings", "get", "org.gnome.shell", key],
        check=True, capture_output=True, text=True
    )
    value = ast.literal_eval(result.stdout.strip())
    if not isinstance(value, list) or not all(isinstance(x, str) for x in value):
        raise SystemExit(f"Unexpected GSettings array for {key}")
    return value

def quote_gvariant(value):
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"

def write_array(key, values):
    serialized = "[" + ", ".join(quote_gvariant(x) for x in values) + "]"
    subprocess.run(
        ["gsettings", "set", "org.gnome.shell", key, serialized],
        check=True
    )

enabled = read_array("enabled-extensions")
favorites = read_array("favorite-apps")

if state["extension_enabled_before"] == "1" and uuid not in enabled:
    enabled.append(uuid)
elif state["extension_enabled_before"] == "0":
    enabled = [item for item in enabled if item != uuid]

if state["favorite_before"] == "1" and favorite not in favorites:
    favorites.append(favorite)
elif state["favorite_before"] == "0":
    favorites = [item for item in favorites if item != favorite]

write_array("enabled-extensions", enabled)
write_array("favorite-apps", favorites)
print("Restored original Downloads Fan enablement and Dock membership.")
PY_GSETTINGS
}

validate_manifest

echo "[MacStyle Uninstaller] Recovery records validated."

if [[ "$MODE" == "--dry-run" ]]; then
    echo
    echo "========== TRACKED PATHS TO REMOVE =========="
    printf '%s\n' "${OWNED_INSTALLED[@]}"
    echo "Foreign manifest entries are preserved and will not be removed."

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
    echo "APT packages, wallpaper, selected themes and unrelated GNOME settings"
    echo "will be preserved. Downloads Fan enablement and favorite membership"
    echo "will be restored to their recorded original state."
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

echo
echo "========== RESTORE DOWNLOADS FAN GNOME STATE =========="
restore_downloads_fan_settings ||
    fail "Could not restore Downloads Fan GNOME state."

systemctl --user daemon-reload ||
    echo "WARNING: systemd daemon reload failed."

echo
echo "MacStyle Ubuntu managed components restored."
echo "Original recovery backups retained at: $STATE"
echo "APT packages were not removed."
echo "Log out and log back in to reload GNOME extensions."
