#!/usr/bin/env bash
set -Eeuo pipefail

MODULE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$MODULE_DIR/../.." && pwd)"
BACKUP_HELPER="$PROJECT_ROOT/ubuntu/backup.sh"

DRY_RUN=0

EXTENSIONS=(
    "extensions/dash2dock-motion@unmade.space"
    "extensions/blur-my-shell@aunetx"
    "extensions/compiz-alike-magic-lamp-effect@hermes83.github.com"
    "extensions-50/user-theme@gnome-shell-extensions.gcampax.github.com"
)

usage() {
    cat <<'USAGE'
Usage: extensions.sh [--dry-run]

Install the four MacStyle GNOME 50 core extensions.

Options:
  --dry-run    Validate and display planned operations without changes.
  --help       Show this help.

This module does not enable, disable, or remove extensions.
USAGE
}

log() {
    printf '[MacStyle Extensions] %s\n' "$*"
}

fail() {
    printf '[MacStyle Extensions] ERROR: %s\n' "$*" >&2
    exit 1
}

validate_environment() {
    [[ "$(id -u)" -ne 0 ]] || fail "Do not run as root."
    [[ -n "${HOME:-}" && -d "$HOME" ]] || fail "Invalid HOME directory."
    [[ -x "$BACKUP_HELPER" ]] || fail "Backup helper is missing or not executable."

    command -v gnome-extensions >/dev/null 2>&1 ||
        fail "gnome-extensions is unavailable."

    command -v glib-compile-schemas >/dev/null 2>&1 ||
        fail "glib-compile-schemas is unavailable."

    local shell_version
    shell_version="$(gnome-shell --version 2>/dev/null || true)"

    [[ "$shell_version" == *"50"* ]] ||
        fail "This module currently supports GNOME Shell 50 only. Detected: ${shell_version:-unknown}"

    for source in "${EXTENSIONS[@]}"; do
        local source_dir="$PROJECT_ROOT/$source"

        [[ -d "$source_dir" ]] || fail "Missing extension source: $source_dir"
        [[ -f "$source_dir/metadata.json" ]] || fail "Missing metadata.json: $source_dir"

        local uuid shell_support
        uuid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["uuid"])' \
            "$source_dir/metadata.json")"

        shell_support="$(python3 -c '
import json,sys
print(" ".join(json.load(open(sys.argv[1])).get("shell-version", [])))
' "$source_dir/metadata.json")"

        [[ " $shell_support " == *" 50 "* ]] ||
            fail "$uuid does not declare GNOME 50 support."
    done
}

install_extension() {
    local source="$1"
    local uuid
    local source_dir="$PROJECT_ROOT/$source"
    local destination="$HOME/.local/share/gnome-shell/extensions/$(
        python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["uuid"])' \
            "$source_dir/metadata.json"
    )"
    local relative_path="${destination#"$HOME/"}"

    uuid="$(basename "$destination")"

    if [[ -e "$destination" || -L "$destination" ]]; then
        log "Existing extension found: $uuid"

        if (( DRY_RUN )); then
            log "DRY RUN: would back up and replace $relative_path"
            return 0
        fi

        "$BACKUP_HELPER" backup "$relative_path" ||
            fail "Could not back up $uuid"
    else
        if (( DRY_RUN )); then
            log "DRY RUN: would install and track $relative_path"
            return 0
        fi
    fi

    if (( DRY_RUN )); then
        return 0
    fi

    mkdir -p "$(dirname "$destination")"

    local staging="${destination}.macstyle-staging"
    [[ ! -e "$staging" && ! -L "$staging" ]] ||
        fail "Staging path already exists: $staging"

    if ! cp -a -- "$source_dir" "$staging"; then
        rm -rf -- "$staging"
        fail "Could not stage extension files for $uuid"
    fi

    if [[ -d "$staging/schemas" ]]; then
        if ! glib-compile-schemas --strict "$staging/schemas"; then
            rm -rf -- "$staging"
            fail "Schema compilation failed for $uuid"
        fi
    fi

    if [[ -e "$destination" || -L "$destination" ]]; then
        local previous="${destination}.macstyle-previous"

        [[ ! -e "$previous" && ! -L "$previous" ]] ||
            fail "Previous-version path already exists: $previous"

        mv -- "$destination" "$previous" ||
            fail "Could not move existing extension aside: $uuid"

        if ! mv -- "$staging" "$destination"; then
            rm -rf -- "$staging"
            mv -- "$previous" "$destination" ||
                fail "CRITICAL: Could not restore previous extension: $uuid"
            fail "Could not install staged extension: $uuid"
        fi

        rm -rf -- "$previous"
    else
        if ! mv -- "$staging" "$destination"; then
            rm -rf -- "$staging"
            fail "Could not move staged extension into place: $uuid"
        fi

        if ! "$BACKUP_HELPER" track "$relative_path"; then
            rm -rf -- "$destination"
            fail "Could not track newly installed extension: $uuid"
        fi
    fi

    log "Installed: $uuid"
}

main() {
    case "${1:-}" in
        --dry-run)
            DRY_RUN=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        "")
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac

    validate_environment

    log "GNOME 50 environment validated."

    for source in "${EXTENSIONS[@]}"; do
        install_extension "$source"
    done

    if (( DRY_RUN )); then
        log "Dry run complete. No files or desktop settings changed."
    else
        log "Extension files installed."
        log "No extensions were enabled, disabled, or removed."
        log "A GNOME session restart may be required before newly installed extensions appear."
    fi
}

main "$@"
