#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UBUNTU_DIR="$(cd -- "$MODULE_DIR/.." && pwd)"
PROJECT_ROOT="$(cd -- "$UBUNTU_DIR/.." && pwd)"
BACKUP_HELPER="$UBUNTU_DIR/backup.sh"

UUID="downloads-fan@macstyle.local"
EXT_REL=".local/share/gnome-shell/extensions/$UUID"
HELPER_REL=".local/libexec/downloads-stack"
LAUNCHER_REL=".local/share/applications/downloads-folder.desktop"
FAVORITE="downloads-folder.desktop"

EXT_SOURCE="$PROJECT_ROOT/extensions/$UUID"
HELPER_SOURCE="$PROJECT_ROOT/libexec/downloads-stack"

EXT_DEST="$HOME/$EXT_REL"
HELPER_DEST="$HOME/$HELPER_REL"
LAUNCHER_DEST="$HOME/$LAUNCHER_REL"

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/macstyle-ubuntu"
FAN_STATE="$STATE/downloads-fan"
STATE_FILE="$FAN_STATE/original-state"

DRY_RUN=0

log() {
    printf '[MacStyle Downloads Fan] %s\n' "$*"
}

fail() {
    log "ERROR: $*" >&2
    exit 1
}

usage() {
    cat <<'USAGE'
Usage: downloads-fan.sh [--dry-run]

Install the Downloads Fan extension, stable helper and Dock launcher.

Options:
  --dry-run    Validate and display operations without changing anything.
  --help       Show this help.
USAGE
}

is_tracked() {
    [[ -f "$STATE/installed.list" ]] &&
        grep -Fqx -- "$1" "$STATE/installed.list"
}

is_backed_up() {
    [[ -f "$STATE/backed-up.list" ]] &&
        grep -Fqx -- "$1" "$STATE/backed-up.list"
}

verify_backup() {
    local relative="$1"
    local backup="$STATE/original/$relative"

    is_backed_up "$relative" ||
        fail "Backup record missing for existing path: $relative"

    [[ -e "$backup" || -L "$backup" ]] ||
        fail "Original backup missing for existing path: $relative"
}

backup_existing() {
    local relative="$1"

    "$BACKUP_HELPER" backup "$relative"
    verify_backup "$relative"
}

track_new() {
    local relative="$1"

    if ! is_tracked "$relative"; then
        "$BACKUP_HELPER" track "$relative"
    fi
}

validate() {
    [[ "$EUID" -ne 0 ]] || fail "Do not run as root."
    [[ -n "${HOME:-}" && -d "$HOME" ]] || fail "Invalid HOME."
    [[ -x "$BACKUP_HELPER" ]] || fail "Backup helper missing."
    [[ -d "$EXT_SOURCE" && -f "$EXT_SOURCE/metadata.json" ]] ||
        fail "Downloads Fan extension source missing."
    [[ -f "$HELPER_SOURCE" ]] || fail "Downloads helper source missing."

    command -v gnome-extensions >/dev/null 2>&1 ||
        fail "gnome-extensions unavailable."
    command -v gsettings >/dev/null 2>&1 ||
        fail "gsettings unavailable."
    command -v python3 >/dev/null 2>&1 ||
        fail "python3 unavailable."

    local shell_version uuid supports
    shell_version="$(gnome-shell --version 2>/dev/null || true)"
    [[ "$shell_version" == *"50"* ]] ||
        fail "GNOME Shell 50 required; detected: ${shell_version:-unknown}"

    uuid="$(python3 -c \
        'import json,sys; print(json.load(open(sys.argv[1]))["uuid"])' \
        "$EXT_SOURCE/metadata.json")"
    [[ "$uuid" == "$UUID" ]] || fail "Unexpected extension UUID: $uuid"

    supports="$(python3 -c '
import json,sys
print(" ".join(json.load(open(sys.argv[1])).get("shell-version", [])))
' "$EXT_SOURCE/metadata.json")"

    [[ " $supports " == *" 50 "* ]] ||
        fail "Extension does not declare GNOME 50 support."

    local destination
    for destination in "$EXT_DEST" "$HELPER_DEST" "$LAUNCHER_DEST"; do
        [[ ! -L "$destination" ]] ||
            fail "Refusing to replace symlink: $destination"
    done

    local staging_path
    for staging_path in \
        "${EXT_DEST}.macstyle-staging" \
        "${EXT_DEST}.macstyle-previous" \
        "${HELPER_DEST}.macstyle-staging" \
        "${LAUNCHER_DEST}.macstyle-staging"; do
        [[ ! -e "$staging_path" && ! -L "$staging_path" ]] ||
            fail "Unexpected staging or previous-version path exists: $staging_path"
    done

    [[ ! -L "$FAN_STATE" ]] ||
        fail "Recovery state directory must not be a symlink."

    [[ ! -L "$STATE_FILE" ]] ||
        fail "Recovery state file must not be a symlink."

    [[ ! -e "${STATE_FILE}.tmp" && ! -L "${STATE_FILE}.tmp" ]] ||
        fail "Unexpected temporary recovery state file exists."

    if [[ -e "$STATE_FILE" ]]; then
        [[ -f "$STATE_FILE" ]] ||
            fail "Recovery state path is not a regular file."

        python3 - "$STATE_FILE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
values = {}
for line in path.read_text(encoding="utf-8").splitlines():
    if "=" not in line:
        raise SystemExit("Invalid Downloads Fan recovery state.")
    key, value = line.split("=", 1)
    if key in values or value not in ("0", "1"):
        raise SystemExit("Invalid Downloads Fan recovery state.")
    values[key] = value

if set(values) != {"extension_enabled_before", "favorite_before"}:
    raise SystemExit("Incomplete Downloads Fan recovery state.")
PY
    fi

    log "Environment and source validation passed."
}

save_original_state() {
    mkdir -p "$FAN_STATE"

    if [[ ! -e "$STATE_FILE" ]]; then
        local temporary="${STATE_FILE}.tmp"
        python3 - "$temporary" <<'PY'
import ast
import subprocess
import sys

def read_array(schema, key):
    result = subprocess.run(
        ["gsettings", "get", schema, key],
        check=True, capture_output=True, text=True
    )
    value = ast.literal_eval(result.stdout.strip())
    if not isinstance(value, list) or not all(isinstance(x, str) for x in value):
        raise SystemExit(f"Unexpected GSettings array for {key}")
    return value

enabled = read_array("org.gnome.shell", "enabled-extensions")
favorites = read_array("org.gnome.shell", "favorite-apps")

with open(sys.argv[1], "x", encoding="utf-8") as output:
    output.write(f"extension_enabled_before={int('downloads-fan@macstyle.local' in enabled)}\n")
    output.write(f"favorite_before={int('downloads-folder.desktop' in favorites)}\n")
PY
        chmod 600 "$temporary"
        mv -- "$temporary" "$STATE_FILE"
    fi
}

install_extension() {
    local staging="${EXT_DEST}.macstyle-staging"
    local previous="${EXT_DEST}.macstyle-previous"

    mkdir -p "$(dirname "$EXT_DEST")"
    cp -a -- "$EXT_SOURCE" "$staging"

    if [[ -e "$EXT_DEST" ]]; then
        backup_existing "$EXT_REL"

        if ! mv -- "$EXT_DEST" "$previous"; then
            rm -rf -- "$staging"
            fail "Could not move existing extension aside."
        fi

        if ! mv -- "$staging" "$EXT_DEST"; then
            mv -- "$previous" "$EXT_DEST" ||
                fail "CRITICAL: Could not restore previous extension."
            rm -rf -- "$staging"
            fail "Could not install Downloads Fan extension."
        fi

        rm -rf -- "$previous"
    else
        mv -- "$staging" "$EXT_DEST"
    fi

    track_new "$EXT_REL"
    log "Extension files installed."
}

install_helper() {
    local temporary="${HELPER_DEST}.macstyle-staging"

    mkdir -p "$(dirname "$HELPER_DEST")"

    if [[ -e "$HELPER_DEST" ]]; then
        backup_existing "$HELPER_REL"
    fi

    install -m 755 "$HELPER_SOURCE" "$temporary"
    mv -f -- "$temporary" "$HELPER_DEST"

    track_new "$HELPER_REL"
    log "Stable helper installed."
}

install_launcher() {
    local temporary="${LAUNCHER_DEST}.macstyle-staging"

    mkdir -p "$(dirname "$LAUNCHER_DEST")"

    if [[ -e "$LAUNCHER_DEST" ]]; then
        backup_existing "$LAUNCHER_REL"
    fi

    cat > "$temporary" <<EOF_LAUNCHER
[Desktop Entry]
Type=Application
Name=Downloads
Comment=Show the newest downloads; opens the Downloads folder when the Downloads Fan extension is off
Icon=folder-download
Exec="$HELPER_DEST" toggle
Terminal=false
StartupNotify=false
Categories=Utility;
Actions=folder;latest;reveal;

[Desktop Action folder]
Name=Open Downloads Folder
Exec="$HELPER_DEST" open-folder

[Desktop Action latest]
Name=Open Most Recent Download
Exec="$HELPER_DEST" open-latest

[Desktop Action reveal]
Name=Show Most Recent in Files
Exec="$HELPER_DEST" reveal-latest
EOF_LAUNCHER

    chmod 644 "$temporary"
    mv -f -- "$temporary" "$LAUNCHER_DEST"

    track_new "$LAUNCHER_REL"
    log "Dock launcher installed."
}

add_favorite() {
    python3 - "$FAVORITE" <<'PY'
import ast
import subprocess
import sys

favorite = sys.argv[1]
schema = "org.gnome.shell"
key = "favorite-apps"

result = subprocess.run(
    ["gsettings", "get", schema, key],
    check=True, capture_output=True, text=True
)
items = ast.literal_eval(result.stdout.strip())

if not isinstance(items, list) or not all(isinstance(x, str) for x in items):
    raise SystemExit("Unexpected Dock favorites format.")

if favorite not in items:
    items.append(favorite)

    def quote(value):
        return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"

    serialized = "[" + ", ".join(quote(item) for item in items) + "]"
    subprocess.run(["gsettings", "set", schema, key, serialized], check=True)
    print("Downloads added to Dock favorites.")
else:
    print("Downloads already exists in Dock favorites; unchanged.")
PY
}


INSTALL_IN_PROGRESS=0

rollback_failed_install() {
    local relative backup destination
    local rollback_failed=0
    local paths=("$LAUNCHER_REL" "$HELPER_REL" "$EXT_REL")

    log "Installation failed. Starting targeted rollback."

    rm -rf -- \
        "${EXT_DEST}.macstyle-staging" \
        "${EXT_DEST}.macstyle-previous" \
        "${HELPER_DEST}.macstyle-staging" \
        "${LAUNCHER_DEST}.macstyle-staging" || rollback_failed=1

    for relative in "${paths[@]}"; do
        destination="$HOME/$relative"
        backup="$STATE/original/$relative"

        if ! rm -rf -- "$destination"; then
            log "WARNING: Could not remove failed installation path: $relative"
            rollback_failed=1
            continue
        fi

        if is_backed_up "$relative"; then
            if [[ ! -e "$backup" && ! -L "$backup" ]]; then
                log "WARNING: Original backup missing: $relative"
                rollback_failed=1
                continue
            fi

            if ! mkdir -p -- "$(dirname "$destination")" ||
               ! cp -a -- "$backup" "$destination"; then
                log "WARNING: Could not restore original path: $relative"
                rollback_failed=1
                continue
            fi

            log "Restored original: $relative"
        else
            log "Removed newly created path: $relative"
        fi
    done

    if [[ -f "$STATE_FILE" ]]; then
        if ! python3 - "$STATE_FILE" "$UUID" "$FAVORITE" <<'PY_GSETTINGS_ROLLBACK'
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
        raise SystemExit(f"Unexpected GSettings array: {key}")
    return value

def quote(value):
    return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"

def write_array(key, values):
    serialized = "[" + ", ".join(quote(x) for x in values) + "]"
    subprocess.run(
        ["gsettings", "set", "org.gnome.shell", key, serialized],
        check=True
    )

enabled = read_array("enabled-extensions")
favorites = read_array("favorite-apps")

if state["extension_enabled_before"] == "1":
    if uuid not in enabled:
        enabled.append(uuid)
else:
    enabled = [item for item in enabled if item != uuid]

if state["favorite_before"] == "1":
    if favorite not in favorites:
        favorites.append(favorite)
else:
    favorites = [item for item in favorites if item != favorite]

write_array("enabled-extensions", enabled)
write_array("favorite-apps", favorites)
print("Original Downloads Fan GNOME state restored.")
PY_GSETTINGS_ROLLBACK
        then
            log "WARNING: Could not restore original GNOME settings."
            rollback_failed=1
        fi
    fi

    if (( rollback_failed )); then
        log "ROLLBACK INCOMPLETE. Original backups retained at: $STATE/original"
        return 1
    fi

    log "Targeted rollback completed. Original backups retained."
}

rollback_on_exit() {
    local status=$?
    trap - EXIT

    if (( status != 0 && INSTALL_IN_PROGRESS )); then
        rollback_failed_install || log "WARNING: Manual recovery may be required."
    fi

    exit "$status"
}

main() {
    case "${1:-}" in
        --dry-run) DRY_RUN=1 ;;
        --help|-h) usage; exit 0 ;;
        "") ;;
        *) usage >&2; exit 2 ;;
    esac

    validate

    if (( DRY_RUN )); then
        log "DRY RUN: would preserve original extension/helper/launcher backups."
        log "DRY RUN: would install the extension and stable helper."
        log "DRY RUN: would create and track the Dock launcher."
        log "DRY RUN: would add only downloads-folder.desktop to favorites."
        log "DRY RUN: would enable Downloads Fan and retain original state for uninstall."
        log "DRY RUN complete. No changes made."
        return 0
    fi

    save_original_state

    if [[ -e "$EXT_DEST" ]]; then
        backup_existing "$EXT_REL"
    fi

    if [[ -e "$HELPER_DEST" ]]; then
        backup_existing "$HELPER_REL"
    fi

    if [[ -e "$LAUNCHER_DEST" ]]; then
        backup_existing "$LAUNCHER_REL"
    fi

    # All original files are now safely backed up.
    # Only failures after this point trigger targeted rollback.
    INSTALL_IN_PROGRESS=1

    install_extension
    install_helper
    install_launcher
    add_favorite

    gnome-extensions enable "$UUID" ||
        fail "Could not enable Downloads Fan. Recovery state and backups were retained."

    log "Downloads Fan enabled."
    INSTALL_IN_PROGRESS=0
    log "Installation complete."
}

trap rollback_on_exit EXIT

main "$@"
