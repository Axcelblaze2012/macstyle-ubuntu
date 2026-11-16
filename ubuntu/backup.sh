#!/usr/bin/env bash
set -Eeuo pipefail

STATE="${MACSTYLE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/macstyle-ubuntu}"
ORIGINAL="$STATE/original"
BACKED_UP="$STATE/backed-up.list"
INSTALLED="$STATE/installed.list"

init() {
    mkdir -p "$ORIGINAL"
    touch "$BACKED_UP" "$INSTALLED"
}

validate() {
    local p="$1"
    local home_real target_real

    [[ -n "$p" && "$p" != /* && "$p" != *$'
'* ]] || {
        echo "ERROR: Invalid relative path: $p" >&2
        return 1
    }

    [[ "/$p/" != *"/../"* && "/$p/" != *"/./"* ]] || {
        echo "ERROR: Path traversal rejected: $p" >&2
        return 1
    }

    home_real="$(realpath -e -- "$HOME")" || return 1
    target_real="$(realpath -m -- "$home_real/$p")" || return 1

    case "$target_real" in
        "$home_real"/*) return 0 ;;
        *)
            echo "ERROR: Path escapes home through a symlink: $p" >&2
            return 1
            ;;
    esac
}

backup_path() {
    local p="$1"
    validate "$p" || { echo "Invalid path: $p"; return 1; }

    local src="$HOME/$p"
    local dst="$ORIGINAL/$p"

    [[ -e "$src" || -L "$src" ]] || {
        echo "Nothing to back up: $p"
        return 0
    }

    grep -Fqx -- "$p" "$BACKED_UP" && {
        echo "Already backed up: $p"
        return 0
    }

    [[ ! -e "$dst" && ! -L "$dst" ]] || return 1

    mkdir -p "$(dirname "$dst")"
    cp -a -- "$src" "$dst"
    printf '%s\n' "$p" >> "$BACKED_UP"
    echo "Backed up: $p"
}

track_path() {
    local p="$1"
    validate "$p" || { echo "Invalid path: $p"; return 1; }

    [[ -e "$HOME/$p" || -L "$HOME/$p" ]] || return 1

    if ! grep -Fqx -- "$p" "$INSTALLED"; then
        printf '%s\n' "$p" >> "$INSTALLED"
    fi
    echo "Tracked: $p"
}

backup_dconf() {
    init
    [[ -f "$STATE/dconf-backup.ini" ]] && {
        echo "DConf backup already exists."
        return 0
    }
    dconf dump / > "$STATE/dconf-backup.ini"
    echo "DConf backup created."
}


restore_dconf() {
    local backup="$STATE/dconf-backup.ini"

    [[ -s "$backup" ]] || {
        echo "ERROR: No DConf backup found." >&2
        return 1
    }

    command -v dconf >/dev/null 2>&1 || {
        echo "ERROR: dconf is not installed." >&2
        return 1
    }

    echo "WARNING: This restores the complete DConf snapshot."
    echo "Current desktop settings may be overwritten."
    read -r -p 'Type RESTORE to continue: ' confirmation

    [[ "$confirmation" == "RESTORE" ]] || {
        echo "DConf restoration cancelled."
        return 1
    }

    dconf load / < "$backup"
    echo "DConf restoration complete."
}

restore_paths() {
    init

    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        validate "$p" || return 1
        rm -rf -- "$HOME/$p"
        echo "Removed: $p"
    done < <(tac "$INSTALLED")

    while IFS= read -r p; do
        [[ -n "$p" ]] || continue
        validate "$p" || return 1

        src="$ORIGINAL/$p"
        dst="$HOME/$p"

        if [[ -e "$src" || -L "$src" ]]; then
            rm -rf -- "$dst"
            mkdir -p "$(dirname "$dst")"
            cp -a -- "$src" "$dst"
            echo "Restored: $p"
        fi
    done < <(tac "$BACKED_UP")

    echo "Restore complete. Backups retained at: $STATE"
}

case "${1:-}" in
    backup)
        [[ $# -eq 2 ]] || exit 2
        init
        backup_path "$2"
        ;;
    track)
        [[ $# -eq 2 ]] || exit 2
        init
        track_path "$2"
        ;;
    dconf-backup)
        init
        backup_dconf
        ;;
    restore)
        restore_paths
        ;;
    restore-dconf)
        [[ $# -eq 1 ]] || exit 2
        restore_dconf
        ;;
    *)
        echo "Usage: backup.sh {backup|track} RELATIVE_PATH"
        echo "       backup.sh {dconf-backup|restore|restore-dconf}"
        exit 2
        ;;
esac
