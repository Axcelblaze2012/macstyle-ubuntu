#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

for cmd in dbus-run-session dconf gnome-shell gnome-extensions glib-compile-schemas; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "MISSING TEST DEPENDENCY: $cmd" >&2
        exit 1
    }
done

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/macstyle-roundtrip.XXXXXX")"

cleanup() {
    local rc=$?
    if (( rc == 0 )); then
        rm -rf -- "$TEST_ROOT"
        echo "Temporary test workspace removed."
    else
        echo "TEST FAILED. Temporary workspace retained: $TEST_ROOT" >&2
    fi
}
trap cleanup EXIT

TEST_HOME="$TEST_ROOT/home"
mkdir -p "$TEST_HOME" "$TEST_ROOT/bin" "$TEST_ROOT/state"

printf 'user-db:user\n' > "$TEST_ROOT/dconf.profile"

cat > "$TEST_ROOT/bin/systemctl" <<'STUB'
#!/usr/bin/env bash
echo "[isolated test stub] systemctl $*"
exit 0
STUB
chmod +x "$TEST_ROOT/bin/systemctl"

echo "========== ISOLATED INSTALL / UNINSTALL TEST =========="

env \
    HOME="$TEST_HOME" \
    XDG_CONFIG_HOME="$TEST_HOME/.config" \
    XDG_DATA_HOME="$TEST_HOME/.local/share" \
    XDG_STATE_HOME="$TEST_ROOT/state" \
    DCONF_PROFILE="$TEST_ROOT/dconf.profile" \
    PATH="$TEST_ROOT/bin:$PATH" \
    PROJECT_ROOT="$PROJECT_ROOT" \
    TEST_HOME="$TEST_HOME" \
    dbus-run-session -- bash -Eeuo pipefail -c '
cd "$PROJECT_ROOT"

echo
echo "========== INSTALL IN TEMPORARY HOME =========="
./ubuntu/install.sh --install

echo
echo "========== VERIFY INSTALLED FILES =========="
for uuid in \
    dash2dock-motion@unmade.space \
    blur-my-shell@aunetx \
    compiz-alike-magic-lamp-effect@hermes83.github.com \
    user-theme@gnome-shell-extensions.gcampax.github.com
do
    file="$HOME/.local/share/gnome-shell/extensions/$uuid/metadata.json"
    [[ -s "$file" ]] || {
        echo "FAIL: $uuid not installed"
        exit 1
    }
    echo "PASS: $uuid"
done

grep -Fq "MacStyle Ubuntu Zsh Integration" "$HOME/.zshrc"
echo "PASS: Zsh integration"

theme="$(dconf read /org/gnome/shell/extensions/user-theme/name)"
[[ "$theme" == "'\''WhiteSur-Dark'\''" ]] || {
    echo "FAIL: unexpected isolated User Theme setting: $theme"
    exit 1
}
echo "PASS: isolated DConf configuration"

echo
echo "========== UNINSTALL IN TEMPORARY HOME =========="
printf "UNINSTALL\n" | ./ubuntu/uninstall.sh --uninstall

echo
echo "========== VERIFY RESTORATION =========="
for uuid in \
    dash2dock-motion@unmade.space \
    blur-my-shell@aunetx \
    compiz-alike-magic-lamp-effect@hermes83.github.com \
    user-theme@gnome-shell-extensions.gcampax.github.com
do
    path="$HOME/.local/share/gnome-shell/extensions/$uuid"
    [[ ! -e "$path" && ! -L "$path" ]] || {
        echo "FAIL: $uuid still exists"
        exit 1
    }
    echo "PASS: $uuid removed"
done

[[ ! -e "$HOME/.zshrc" ]] || {
    echo "FAIL: test-created .zshrc remains"
    exit 1
}
echo "PASS: test-created .zshrc removed"

remaining="$(dconf dump /)"
[[ -z "$remaining" ]] || {
    echo "FAIL: isolated DConf database is not empty after rollback"
    printf "%s\n" "$remaining"
    exit 1
}
echo "PASS: isolated DConf database restored to original empty state"

echo
echo "ISOLATED INSTALL / UNINSTALL ROUND-TRIP: PASS"
'
