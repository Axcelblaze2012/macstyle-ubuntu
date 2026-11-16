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
    [[ -n "$p" && "$p" != /* && "$p" != *$'\n'* ]] || return 1
    [[ "/$p/" != *"/../"* && "/$p/" != *"/./"* ]] || return 1
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
    *)
        echo "Usage: backup.sh {backup|track} RELATIVE_PATH"
        echo "       backup.sh {dconf-backup|restore}"
        exit 2
        ;;
esac
