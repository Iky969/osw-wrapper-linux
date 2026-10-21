#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Iky969
#
# Harness tes osw.
# Hermetik: setiap tes mendapat HOME + XDG_* sendiri di direktori sementara,
# tanpa root, tanpa apt, tanpa network. Perintah paket hanya diuji dengan -n.
#
# Pemakaian: bash tests/run.sh
# Exit: 0 kalau semua tes lulus, 1 kalau ada yang gagal.

set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
OSW="$ROOT_DIR/bin/osw"
INSTALLER="$ROOT_DIR/install.sh"

# PATH tetap supaya hasil tidak bergantung PATH pemanggil.
TEST_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

TOTAL=0
PASSED=0
FAILED=0
FAILED_NAMES=()

# State per tes (diisi oleh run_test).
SB=""
OUT=""
ERR=""
RC=0

# -----------------------------------------------------------------------------
# Sandbox & eksekusi
# -----------------------------------------------------------------------------
_mk_sandbox() {
    mktemp -d "${TMPDIR:-/tmp}/osw-test.XXXXXX"
}

# Jalankan perintah di dalam sandbox: HOME/XDG terisolasi, OSW_* dibersihkan.
_sandbox_env() {
    env \
        -u OSW_YES -u OSW_DRY -u OSW_QUIET -u OSW_DEBUG -u OSW_NO_COLOR \
        HOME="$SB/home" \
        XDG_CONFIG_HOME="$SB/cfg" \
        XDG_DATA_HOME="$SB/data" \
        XDG_BIN_HOME="$SB/bin" \
        PATH="$TEST_PATH" \
        "$@"
}

osw_run() {
    _sandbox_env bash "$OSW" "$@" >"$OUT" 2>"$ERR"
    RC=$?
    return 0
}

bin_run() {
    local bin="$1"
    shift
    _sandbox_env "$bin" "$@" >"$OUT" 2>"$ERR"
    RC=$?
    return 0
}

installer_run() {
    _sandbox_env bash "$INSTALLER" "$@" >"$OUT" 2>"$ERR"
    RC=$?
    return 0
}

# Siapkan ~/.config/osw/os.conf + modul debian di data dir sandbox.
prepare_debian_config() {
    mkdir -p "$SB/cfg/osw" "$SB/data/osw/os"
    printf 'OS=debian\nINSTALLED_AT=2026-01-01T00:00:00Z\nVERSION=0.1.0\n' \
        >"$SB/cfg/osw/os.conf"
    cp "$ROOT_DIR/os/debian.sh" "$SB/data/osw/os/debian.sh"
}

# -----------------------------------------------------------------------------
# Assertion
# -----------------------------------------------------------------------------
_fail() {
    printf '  gagal: %s\n' "$*" >&2
    return 1
}

expect_rc() {
    local want="$1"
    [[ "$RC" -eq "$want" ]] || _fail "exit code $RC, seharusnya $want"
}

expect_out() {
    grep -qF -- "$1" "$OUT" || _fail "stdout tidak memuat: $1"
}

expect_out_not() {
    if grep -qF -- "$1" "$OUT"; then
        _fail "stdout seharusnya tidak memuat: $1"
    fi
}

expect_out_re() {
    grep -qE -- "$1" "$OUT" || _fail "stdout tidak cocok pola: $1"
}

expect_err() {
    grep -qF -- "$1" "$ERR" || _fail "stderr tidak memuat: $1"
}

expect_err_re() {
    grep -qE -- "$1" "$ERR" || _fail "stderr tidak cocok pola: $1"
}

expect_file() {
    [[ -f "$1" ]] || _fail "file tidak ada: $1"
}

expect_exec() {
    [[ -x "$1" ]] || _fail "file tidak executable: $1"
}

expect_absent() {
    [[ ! -e "$1" ]] || _fail "path seharusnya tidak ada: $1"
}

expect_file_contains() {
    grep -qF -- "$2" "$1" || _fail "$1 tidak memuat: $2"
}

expect_file_matches() {
    grep -qE -- "$2" "$1" || _fail "$1 tidak cocok pola: $2"
}

# -----------------------------------------------------------------------------
# Fase 0-2: dispatcher & modul debian
# -----------------------------------------------------------------------------
test_help_without_config() {
    osw_run help
    expect_rc 0 || return 1
    expect_out "Usage: osw" || return 1
    expect_out "osw install neovim git curl" || return 1
}

test_help_per_command() {
    osw_run help install
    expect_rc 0 || return 1
    expect_out "Usage: osw [FLAGS] install" || return 1
}

test_help_unknown_command() {
    osw_run help bogus
    expect_rc 2 || return 1
    expect_err "subcommand tidak dikenal untuk help: bogus" || return 1
}

test_unknown_global_flag() {
    osw_run --bogus
    expect_rc 2 || return 1
    expect_err "flag tidak dikenal: --bogus" || return 1
}

test_unknown_subcommand() {
    # Tanpa config, cek config (exit 4) sengaja mendahului dispatcher (blueprint poin 7-17).
    prepare_debian_config
    osw_run bogus
    expect_rc 2 || return 1
    expect_err "subcommand tidak dikenal: bogus" || return 1
}

test_version_without_config() {
    osw_run version
    expect_rc 0 || return 1
    expect_out "osw 0.1.0" || return 1
}

test_status_without_config() {
    osw_run status
    expect_rc 4 || return 1
    expect_err "konfigurasi tidak ditemukan" || return 1
}

test_detect_writes_config() {
    osw_run detect
    expect_rc 0 || return 1
    expect_file "$SB/cfg/osw/os.conf" || return 1
    expect_file_matches "$SB/cfg/osw/os.conf" '^OS=(debian|void|alpine|gentoo|arch|unknown)$' || return 1
    expect_file_matches "$SB/cfg/osw/os.conf" '^INSTALLED_AT=.+$' || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "VERSION=0.1.0" || return 1
}

test_dry_run_install_without_config() {
    osw_run -n install neovim
    expect_rc 4 || return 1
    expect_err "install.sh" || return 1
}

test_dry_run_install() {
    prepare_debian_config
    osw_run -n install neovim
    expect_rc 0 || return 1
    expect_out "DRY: " || return 1
    expect_out "apt-get install neovim" || return 1
    expect_out_not "apt-get install -y" || return 1
}

test_dry_run_install_yes() {
    prepare_debian_config
    osw_run -n -y install neovim
    expect_rc 0 || return 1
    expect_out "apt-get install -y neovim" || return 1
}

test_dry_run_remove() {
    prepare_debian_config
    osw_run -n remove neovim
    expect_rc 0 || return 1
    expect_out "apt-get remove neovim" || return 1
}

test_dry_run_reinstall() {
    prepare_debian_config
    osw_run -n reinstall neovim
    expect_rc 0 || return 1
    expect_out "apt-get remove neovim" || return 1
    expect_out "apt-get install neovim" || return 1
}

test_dry_run_upgrade() {
    prepare_debian_config
    osw_run -n -y upgrade
    expect_rc 0 || return 1
    expect_out "apt-get upgrade -y" || return 1
}

test_dry_run_full_upgrade() {
    prepare_debian_config
    osw_run -n full-upgrade
    expect_rc 0 || return 1
    expect_out "apt-get full-upgrade" || return 1
}

test_missing_module_returns_3() {
    mkdir -p "$SB/cfg/osw"
    printf 'OS=void\nINSTALLED_AT=2026-01-01T00:00:00Z\nVERSION=0.1.0\n' \
        >"$SB/cfg/osw/os.conf"
    osw_run files foo
    expect_rc 3 || return 1
    expect_err "belum didukung" || return 1
}

test_install_without_args() {
    prepare_debian_config
    osw_run install
    expect_rc 1 || return 1
    expect_err "membutuhkan minimal 1 argumen" || return 1
}

test_files_without_args() {
    prepare_debian_config
    osw_run files
    expect_rc 1 || return 1
    expect_err "membutuhkan minimal 1 argumen" || return 1
}

test_list_invalid_option() {
    prepare_debian_config
    osw_run list -- --bogus
    expect_rc 2 || return 1
    expect_err "opsi tidak dikenal untuk list: --bogus" || return 1
}

# -----------------------------------------------------------------------------
# Runner
# -----------------------------------------------------------------------------
run_test() {
    local name="$1"
    local fn="$2"

    TOTAL=$((TOTAL + 1))
    SB="$(_mk_sandbox)"
    OUT="$SB/.stdout"
    ERR="$SB/.stderr"
    RC=0
    : >"$OUT"
    : >"$ERR"

    if ( set +e; "$fn" ) >"$SB/.log" 2>&1; then
        PASSED=$((PASSED + 1))
        printf 'PASS  %s\n' "$name"
    else
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$name")
        printf 'FAIL  %s\n' "$name"
        sed 's/^/      /' "$SB/.log"
        printf '      stdout:\n'
        sed 's/^/      | /' "$OUT" | tail -n 10
        printf '      stderr:\n'
        sed 's/^/      | /' "$ERR" | tail -n 10
    fi

    rm -rf "$SB"
    SB=""
    OUT=""
    ERR=""
}

printf 'osw test suite (%s)\n\n' "$ROOT_DIR"
printf -- '--- Fase 0-2: dispatcher & modul debian ---\n'
run_test "help tanpa config"                 test_help_without_config
run_test "help per subcommand"               test_help_per_command
run_test "help subcommand tidak dikenal"     test_help_unknown_command
run_test "flag global tidak dikenal"         test_unknown_global_flag
run_test "subcommand tidak dikenal"          test_unknown_subcommand
run_test "version tanpa config"              test_version_without_config
run_test "status tanpa config"               test_status_without_config
run_test "detect menulis config"             test_detect_writes_config
run_test "dry-run install tanpa config"      test_dry_run_install_without_config
run_test "dry-run install"                   test_dry_run_install
run_test "dry-run install -y"                test_dry_run_install_yes
run_test "dry-run remove"                    test_dry_run_remove
run_test "dry-run reinstall"                 test_dry_run_reinstall
run_test "dry-run upgrade"                   test_dry_run_upgrade
run_test "dry-run full-upgrade"              test_dry_run_full_upgrade
run_test "modul tidak ada -> exit 3"         test_missing_module_returns_3
run_test "install tanpa argumen"             test_install_without_args
run_test "files tanpa argumen"               test_files_without_args
run_test "list opsi tidak dikenal"           test_list_invalid_option

printf '\n%d tes: %d lulus, %d gagal\n' "$TOTAL" "$PASSED" "$FAILED"

if [[ "$FAILED" -gt 0 ]]; then
    printf 'Gagal:\n'
    printf '  - %s\n' "${FAILED_NAMES[@]}"
    exit 1
fi

exit 0
