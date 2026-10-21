#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Iky969
#
# Harness tes osw.
# Hermetik: setiap tes mendapat HOME + XDG_* sendiri di direktori sementara,
# tanpa root, tanpa apt, tanpa network. Perintah paket hanya diuji dengan -n;
# installer hanya diuji pada path lokal (mode pipe diuji tanpa network).
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

# Installer dengan file os-release palsu (OSW_OS_RELEASE).
installer_run_osrel() {
    local rel="$1"
    shift
    _sandbox_env OSW_OS_RELEASE="$rel" bash "$INSTALLER" "$@" >"$OUT" 2>"$ERR"
    RC=$?
    return 0
}

# Tulis file os-release palsu: ID (penentu family) + PRETTY_NAME (tampilan).
write_os_release() {
    local path="$1"
    local id="$2"
    local pretty="$3"
    {
        printf 'ID=%s\n' "$id"
        printf "PRETTY_NAME='%s'\n" "$pretty"
    } >"$path"
}

# Baca kembali OS_NAME dari config seperti yang dilakukan bin/osw (source).
conf_os_name() {
    _sandbox_env bash -c '. "$1" >/dev/null 2>&1; printf "%s" "${OS_NAME:-}"' _ "$1"
}

# Jalankan osw dengan proxy yang tidak bisa dihubungi: memastikan jalur network
# gagal dengan pesan jelas, tanpa benar-benar menyentuh internet.
osw_run_blocked_network() {
    _sandbox_env \
        https_proxy="http://127.0.0.1:9" \
        http_proxy="http://127.0.0.1:9" \
        bash "$OSW" "$@" >"$OUT" 2>"$ERR"
    RC=$?
    return 0
}

# Mode pipe: skrip dibaca dari stdin (BASH_SOURCE kosong), proxy diblokir supaya
# tes tidak menyentuh network.
installer_pipe_run() {
    _sandbox_env \
        https_proxy="http://127.0.0.1:9" \
        http_proxy="http://127.0.0.1:9" \
        bash <"$INSTALLER" >"$OUT" 2>"$ERR"
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

# Salin repo ke sandbox tanpa satu modul: menguji preflight "modul belum
# tersedia" tanpa bergantung pada modul mana yang sudah ada di repo.
repo_without_module() {
    local drop="$1"
    local dest="$SB/repo"
    local file
    mkdir -p "$dest/os" "$dest/bin"
    cp "$INSTALLER" "$dest/install.sh"
    cp "$ROOT_DIR/VERSION" "$dest/VERSION"
    cp "$ROOT_DIR/bin/osw" "$dest/bin/osw"
    for file in "$ROOT_DIR"/os/*.sh; do
        if [[ "$(basename "$file" .sh)" == "$drop" ]]; then
            continue
        fi
        cp "$file" "$dest/os/"
    done
    printf '%s\n' "$dest"
}

installer_run_alt() {
    local script="$1"
    shift
    _sandbox_env bash "$script" "$@" >"$OUT" 2>"$ERR"
    RC=$?
    return 0
}

installer_run_alt_osrel() {
    local script="$1"
    local rel="$2"
    shift 2
    _sandbox_env OSW_OS_RELEASE="$rel" bash "$script" "$@" >"$OUT" 2>"$ERR"
    RC=$?
    return 0
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

expect_file_lines() {
    local file="$1"
    local want="$2"
    local got
    got="$(wc -l <"$file")"
    got="${got//[[:space:]]/}"
    [[ "$got" == "$want" ]] || _fail "$file punya $got baris, seharusnya $want"
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
    expect_file_lines "$SB/cfg/osw/os.conf" 4 || return 1
    expect_file_matches "$SB/cfg/osw/os.conf" '^OS=(debian|void|alpine|gentoo|arch|unknown)$' || return 1
    expect_file_matches "$SB/cfg/osw/os.conf" '^OS_NAME=.+$' || return 1
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

test_self_update_fails_cleanly_without_network() {
    # Regresi: baris 372 lama memakai $expected_sha sebelum dideklarasikan,
    # sehingga self-update mati dengan "unbound variable".
    prepare_debian_config
    osw_run_blocked_network self-update
    expect_rc 1 || return 1
    expect_err "gagal mengunduh" || return 1
    if grep -qF "unbound variable" "$ERR"; then
        _fail "self-update gagal karena unbound variable"
        return 1
    fi
}

test_list_invalid_option() {
    prepare_debian_config
    osw_run list -- --bogus
    expect_rc 2 || return 1
    expect_err "opsi tidak dikenal untuk list: --bogus" || return 1
}

# -----------------------------------------------------------------------------
# Fase 3: install.sh
# -----------------------------------------------------------------------------
test_installer_help() {
    installer_run --help
    expect_rc 0 || return 1
    expect_out "Usage: install.sh" || return 1
    expect_out "--no-path-hint" || return 1
}

test_installer_unknown_arg() {
    installer_run --bogus
    expect_rc 1 || return 1
    expect_err "argumen tidak dikenal: --bogus" || return 1
}

test_installer_missing_option_value() {
    installer_run --prefix
    expect_rc 1 || return 1
    expect_err "opsi --prefix membutuhkan nilai" || return 1
}

test_installer_unknown_os() {
    installer_run --os unknown
    expect_rc 1 || return 1
    expect_err "OS tidak didukung: unknown" || return 1
    expect_err "debian, void, alpine, gentoo, arch" || return 1
    expect_absent "$SB/cfg/osw/os.conf" || return 1
}

test_installer_missing_module() {
    local repo=""
    repo="$(repo_without_module void)"
    installer_run_alt "$repo/install.sh" --os void
    expect_rc 1 || return 1
    expect_err "modul untuk OS=void belum tersedia" || return 1
    expect_absent "$SB/cfg/osw/os.conf" || return 1
    expect_absent "$SB/bin/osw" || return 1
}

test_installer_debian() {
    installer_run --os debian
    expect_rc 0 || return 1
    expect_file "$SB/cfg/osw/os.conf" || return 1
    expect_file_lines "$SB/cfg/osw/os.conf" 4 || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS=debian" || return 1
    expect_file_matches "$SB/cfg/osw/os.conf" '^OS_NAME=.+$' || return 1
    expect_file_matches "$SB/cfg/osw/os.conf" '^INSTALLED_AT=20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T' || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "VERSION=0.1.0" || return 1
    expect_exec "$SB/bin/osw" || return 1
    expect_file "$SB/data/osw/os/debian.sh" || return 1

    bin_run "$SB/bin/osw" version
    expect_rc 0 || return 1
    expect_out "osw 0.1.0 (OS=debian)" || return 1

    bin_run "$SB/bin/osw" status
    expect_rc 0 || return 1
    expect_out "OS           : debian" || return 1
}

test_installer_os_equals_form() {
    installer_run --os=debian --no-path-hint
    expect_rc 0 || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS=debian" || return 1
}

test_installer_path_hint() {
    installer_run --os debian
    expect_rc 0 || return 1
    expect_out "belum ada di PATH" || return 1
    expect_out "export PATH=" || return 1
    expect_out ".bashrc" || return 1
}

test_installer_no_path_hint() {
    installer_run --os debian --no-path-hint
    expect_rc 0 || return 1
    expect_out_not "export PATH=" || return 1
}

test_installer_idempotent() {
    installer_run --os debian --no-path-hint
    expect_rc 0 || return 1
    installer_run --os debian --no-path-hint
    expect_rc 0 || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS=debian" || return 1
    bin_run "$SB/bin/osw" version
    expect_rc 0 || return 1
}

test_installer_prefix() {
    installer_run --os debian --prefix "$SB/prefix" --no-path-hint
    expect_rc 0 || return 1
    expect_exec "$SB/prefix/bin/osw" || return 1
    expect_absent "$SB/bin/osw" || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS=debian" || return 1

    bin_run "$SB/prefix/bin/osw" version
    expect_rc 0 || return 1
    expect_out "OS=debian" || return 1
}

test_installer_keeps_installed_at() {
    mkdir -p "$SB/cfg/osw"
    printf 'OS=debian\nINSTALLED_AT=2000-01-01T00:00:00Z\nVERSION=0.1.0\n' \
        >"$SB/cfg/osw/os.conf"
    installer_run --no-path-hint
    expect_rc 0 || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "INSTALLED_AT=2000-01-01T00:00:00Z" || return 1
}

test_installer_redetect_refreshes_installed_at() {
    mkdir -p "$SB/cfg/osw"
    printf 'OS=debian\nINSTALLED_AT=2000-01-01T00:00:00Z\nVERSION=0.1.0\n' \
        >"$SB/cfg/osw/os.conf"
    installer_run --redetect --os debian --no-path-hint
    expect_rc 0 || return 1
    expect_file_matches "$SB/cfg/osw/os.conf" '^INSTALLED_AT=20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]T' || return 1
    if grep -qF "INSTALLED_AT=2000-01-01T00:00:00Z" "$SB/cfg/osw/os.conf"; then
        _fail "--redetect tidak memperbarui INSTALLED_AT"
        return 1
    fi
}

test_installer_keeps_config_os_without_redetect() {
    mkdir -p "$SB/cfg/osw"
    printf 'OS=debian\nOS_NAME=Debian\nINSTALLED_AT=2026-01-01T00:00:00Z\nVERSION=0.1.0\n' \
        >"$SB/cfg/osw/os.conf"
    write_os_release "$SB/os-release" "alpine" "Alpine Linux"

    installer_run_osrel "$SB/os-release" --no-path-hint
    expect_rc 0 || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS=debian" || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS_NAME=Debian" || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "INSTALLED_AT=2026-01-01T00:00:00Z" || return 1
    expect_file_lines "$SB/cfg/osw/os.conf" 4 || return 1
    expect_file "$SB/data/osw/os/debian.sh" || return 1
}

test_installer_redetect_reevaluates_os() {
    mkdir -p "$SB/cfg/osw"
    printf 'OS=debian\nOS_NAME=Debian\nINSTALLED_AT=2026-01-01T00:00:00Z\nVERSION=0.1.0\n' \
        >"$SB/cfg/osw/os.conf"
    write_os_release "$SB/os-release" "alpine" "Alpine Linux"

    # Family jadi alpine; repo uji sengaja tidak punya modul alpine -> harus
    # gagal, bukan mencoba modul lain. Config lama tidak boleh rusak.
    local repo=""
    repo="$(repo_without_module alpine)"
    installer_run_alt_osrel "$repo/install.sh" "$SB/os-release" --redetect --no-path-hint
    expect_rc 1 || return 1
    expect_err "modul untuk OS=alpine belum tersedia" || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS=debian" || return 1

    write_os_release "$SB/os-release" "ubuntu" "Ubuntu Test 99"
    installer_run_osrel "$SB/os-release" --redetect --no-path-hint
    expect_rc 0 || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS=debian" || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" 'OS_NAME=Ubuntu\ Test\ 99' || return 1
}

test_installer_os_name_escaped() {
    local expected='Debian "Bookworm" Test Edition (stable)'
    write_os_release "$SB/os-release" "debian" "$expected"

    installer_run_osrel "$SB/os-release" --no-path-hint
    expect_rc 0 || return 1
    expect_file_lines "$SB/cfg/osw/os.conf" 4 || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" 'OS_NAME=Debian\ \"Bookworm\"\ Test\ Edition\ \(stable\)' || return 1

    local got=""
    got="$(conf_os_name "$SB/cfg/osw/os.conf")"
    if [[ "$got" != "$expected" ]]; then
        _fail "OS_NAME terbaca '$got', seharusnya '$expected'"
        return 1
    fi
    expect_file "$SB/data/osw/os/debian.sh" || return 1
}

test_installer_os_name_not_used_for_module() {
    write_os_release "$SB/os-release" "debian" "Alpine Linux 3.20"

    installer_run_osrel "$SB/os-release" --no-path-hint
    expect_rc 0 || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS=debian" || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" 'OS_NAME=Alpine\ Linux\ 3.20' || return 1
    expect_file "$SB/data/osw/os/debian.sh" || return 1
}

test_installer_uninstall_delegates() {
    installer_run --os debian --no-path-hint
    expect_rc 0 || return 1
    expect_exec "$SB/bin/osw" || return 1

    installer_run --uninstall -y
    expect_rc 0 || return 1
    expect_absent "$SB/bin/osw" || return 1
    expect_absent "$SB/data/osw" || return 1
    expect_absent "$SB/cfg/osw" || return 1
}

test_installer_uninstall_with_prefix() {
    installer_run --os debian --prefix "$SB/prefix" --no-path-hint
    expect_rc 0 || return 1
    expect_exec "$SB/prefix/bin/osw" || return 1

    installer_run --uninstall -y --prefix "$SB/prefix"
    expect_rc 0 || return 1
    expect_absent "$SB/prefix/bin/osw" || return 1
    expect_absent "$SB/data/osw" || return 1
    expect_absent "$SB/cfg/osw" || return 1
}

test_installer_uninstall_without_binary() {
    mkdir -p "$SB/data/osw/os" "$SB/cfg/osw"
    printf 'OS=debian\nINSTALLED_AT=2026-01-01T00:00:00Z\nVERSION=0.1.0\n' \
        >"$SB/cfg/osw/os.conf"
    installer_run --uninstall -y
    expect_rc 0 || return 1
    expect_absent "$SB/data/osw" || return 1
    expect_absent "$SB/cfg/osw" || return 1
    expect_out "membersihkan sisa direktori" || return 1
}

test_installer_pipe_mode_without_network() {
    installer_pipe_run
    expect_rc 1 || return 1
    expect_err "gagal mengunduh" || return 1
    expect_err "git clone" || return 1
    if grep -qF "unbound variable" "$ERR"; then
        _fail "installer gagal karena unbound variable"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Fase 4: modul void (XBPS)
# -----------------------------------------------------------------------------
test_void_dry_run() {
    installer_run --os void --no-path-hint
    expect_rc 0 || return 1
    expect_file "$SB/data/osw/os/void.sh" || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS=void" || return 1

    bin_run "$SB/bin/osw" -n install neovim
    expect_rc 0 || return 1
    expect_out "DRY: xbps-install neovim" || return 1

    bin_run "$SB/bin/osw" -n -y install neovim
    expect_rc 0 || return 1
    expect_out "DRY: xbps-install -y neovim" || return 1

    bin_run "$SB/bin/osw" -n remove neovim
    expect_rc 0 || return 1
    expect_out "DRY: xbps-remove neovim" || return 1

    bin_run "$SB/bin/osw" -n update
    expect_rc 0 || return 1
    expect_out "DRY: xbps-install -S" || return 1

    bin_run "$SB/bin/osw" -n upgrade
    expect_rc 0 || return 1
    expect_out "DRY: xbps-install -u" || return 1

    bin_run "$SB/bin/osw" -n -y full-upgrade
    expect_rc 0 || return 1
    expect_out "DRY: xbps-install -Su -y" || return 1

    bin_run "$SB/bin/osw" -n autoremove
    expect_rc 0 || return 1
    expect_out "DRY: xbps-remove -o" || return 1

    bin_run "$SB/bin/osw" -n clean
    expect_rc 0 || return 1
    expect_out "DRY: xbps-remove -O" || return 1
}

test_void_autoclean_unsupported() {
    installer_run --os void --no-path-hint
    expect_rc 0 || return 1
    bin_run "$SB/bin/osw" autoclean
    expect_rc 3 || return 1
    expect_err "fitur autoclean belum didukung untuk OS=void" || return 1
}

# -----------------------------------------------------------------------------
# Fase 5: modul alpine (apk)
# -----------------------------------------------------------------------------
test_alpine_dry_run() {
    installer_run --os alpine --no-path-hint
    expect_rc 0 || return 1
    expect_file "$SB/data/osw/os/alpine.sh" || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS=alpine" || return 1

    bin_run "$SB/bin/osw" -n install neovim
    expect_rc 0 || return 1
    expect_out "DRY: apk add neovim" || return 1

    bin_run "$SB/bin/osw" -n -y install neovim
    expect_rc 0 || return 1
    expect_out "DRY: apk add --no-interactive neovim" || return 1

    bin_run "$SB/bin/osw" -n remove neovim
    expect_rc 0 || return 1
    expect_out "DRY: apk del neovim" || return 1

    bin_run "$SB/bin/osw" -n update
    expect_rc 0 || return 1
    expect_out "DRY: apk update" || return 1

    bin_run "$SB/bin/osw" -n upgrade
    expect_rc 0 || return 1
    expect_out "DRY: apk upgrade" || return 1

    bin_run "$SB/bin/osw" -n full-upgrade
    expect_rc 0 || return 1
    expect_out "DRY: apk upgrade" || return 1

    bin_run "$SB/bin/osw" -n clean
    expect_rc 0 || return 1
    expect_out "DRY: apk cache clean" || return 1
}

test_alpine_autoremove_noop() {
    installer_run --os alpine --no-path-hint
    expect_rc 0 || return 1
    bin_run "$SB/bin/osw" autoremove
    expect_rc 0 || return 1
    expect_out "apk otomatis membersihkan dependensi" || return 1
}

test_alpine_unsupported_features() {
    installer_run --os alpine --no-path-hint
    expect_rc 0 || return 1

    bin_run "$SB/bin/osw" orphans
    expect_rc 3 || return 1
    expect_err "fitur orphans belum didukung untuk OS=alpine" || return 1

    bin_run "$SB/bin/osw" autoclean
    expect_rc 3 || return 1
    expect_err "fitur autoclean belum didukung untuk OS=alpine" || return 1

    bin_run "$SB/bin/osw" list --user
    expect_rc 3 || return 1
    expect_err "list --user belum didukung untuk OS=alpine" || return 1
}

# -----------------------------------------------------------------------------
# Fase 6: modul gentoo (portage/emerge)
# -----------------------------------------------------------------------------
test_gentoo_dry_run() {
    installer_run --os gentoo --no-path-hint
    expect_rc 0 || return 1
    expect_file "$SB/data/osw/os/gentoo.sh" || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS=gentoo" || return 1

    bin_run "$SB/bin/osw" -n update
    expect_rc 0 || return 1
    expect_out "DRY: emerge --sync" || return 1

    # Tanpa -y emerge harus tetap bertanya (--ask).
    bin_run "$SB/bin/osw" -n install neovim
    expect_rc 0 || return 1
    expect_out "DRY: emerge --ask neovim" || return 1

    bin_run "$SB/bin/osw" -n -y install neovim
    expect_rc 0 || return 1
    expect_out "DRY: emerge neovim" || return 1
    expect_out_not "DRY: emerge --ask neovim" || return 1

    bin_run "$SB/bin/osw" -n upgrade
    expect_rc 0 || return 1
    expect_out "DRY: emerge -uDN @world --ask" || return 1

    bin_run "$SB/bin/osw" -n -y full-upgrade
    expect_rc 0 || return 1
    expect_out "DRY: emerge -uDN @world" || return 1
    expect_out_not "--ask" || return 1

    bin_run "$SB/bin/osw" -n remove neovim
    expect_rc 0 || return 1
    expect_out "DRY: emerge --unmerge --ask neovim" || return 1
}

test_gentoo_autoremove_pretend() {
    installer_run --os gentoo --no-path-hint
    expect_rc 0 || return 1

    # Tanpa -y: hanya pretend, tidak ada yang dihapus.
    bin_run "$SB/bin/osw" -n autoremove
    expect_rc 0 || return 1
    expect_out "DRY: emerge -p --depclean" || return 1

    bin_run "$SB/bin/osw" -n -y autoremove
    expect_rc 0 || return 1
    expect_out "DRY: emerge --depclean" || return 1
    expect_out_not "emerge -p --depclean" || return 1
}

test_gentoo_optional_tools_missing() {
    installer_run --os gentoo --no-path-hint
    expect_rc 0 || return 1

    # Lingkungan tes tidak punya eclean-dist/qlist/qfile.
    bin_run "$SB/bin/osw" clean
    expect_rc 3 || return 1
    expect_err "eclean-dist" || return 1

    bin_run "$SB/bin/osw" files foo
    expect_rc 3 || return 1
    expect_err "qlist" || return 1

    bin_run "$SB/bin/osw" owner /usr/bin/foo
    expect_rc 3 || return 1
    expect_err "qfile" || return 1

    bin_run "$SB/bin/osw" autoclean
    expect_rc 3 || return 1
    expect_err "fitur autoclean belum didukung untuk OS=gentoo" || return 1
}

# -----------------------------------------------------------------------------
# Fase 7: modul arch (pacman)
# -----------------------------------------------------------------------------
test_arch_dry_run() {
    installer_run --os arch --no-path-hint
    expect_rc 0 || return 1
    expect_file "$SB/data/osw/os/arch.sh" || return 1
    expect_file_contains "$SB/cfg/osw/os.conf" "OS=arch" || return 1

    bin_run "$SB/bin/osw" -n install neovim
    expect_rc 0 || return 1
    expect_out "DRY: pacman -S neovim" || return 1

    # -y di pacman berarti refresh database, jadi non-interaktif memakai
    # --noconfirm.
    bin_run "$SB/bin/osw" -n -y install neovim
    expect_rc 0 || return 1
    expect_out "DRY: pacman -S --noconfirm neovim" || return 1

    bin_run "$SB/bin/osw" -n remove neovim
    expect_rc 0 || return 1
    expect_out "DRY: pacman -Rns neovim" || return 1

    bin_run "$SB/bin/osw" -n update
    expect_rc 0 || return 1
    expect_out "DRY: pacman -Sy" || return 1

    bin_run "$SB/bin/osw" -n -y upgrade
    expect_rc 0 || return 1
    expect_out "DRY: pacman -Su --noconfirm" || return 1

    bin_run "$SB/bin/osw" -n full-upgrade
    expect_rc 0 || return 1
    expect_out "DRY: pacman -Syu" || return 1

    bin_run "$SB/bin/osw" -n -y clean
    expect_rc 0 || return 1
    expect_out "DRY: pacman -Sc --noconfirm" || return 1
}

test_arch_autoremove() {
    installer_run --os arch --no-path-hint
    expect_rc 0 || return 1

    # Lingkungan tes tidak punya pacman: tidak ada orphan, jadi no-op yang bersih.
    bin_run "$SB/bin/osw" -n autoremove
    expect_rc 0 || return 1
    expect_out "Tidak ada paket yatim" || return 1
}

test_arch_autoclean_unsupported() {
    installer_run --os arch --no-path-hint
    expect_rc 0 || return 1
    bin_run "$SB/bin/osw" autoclean
    expect_rc 3 || return 1
    expect_err "fitur autoclean belum didukung untuk OS=arch" || return 1
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
run_test "self-update gagal tanpa network"   test_self_update_fails_cleanly_without_network

printf -- '\n--- Fase 3: install.sh ---\n'
run_test "installer --help"                     test_installer_help
run_test "installer argumen tidak dikenal"      test_installer_unknown_arg
run_test "installer opsi tanpa nilai"           test_installer_missing_option_value
run_test "installer OS unknown"                 test_installer_unknown_os
run_test "installer modul belum tersedia"       test_installer_missing_module
run_test "installer deploy debian"              test_installer_debian
run_test "installer --os=debian"                test_installer_os_equals_form
run_test "installer PATH hint"                  test_installer_path_hint
run_test "installer --no-path-hint"             test_installer_no_path_hint
run_test "installer idempotent"                 test_installer_idempotent
run_test "installer --prefix"                   test_installer_prefix
run_test "installer pertahankan INSTALLED_AT"   test_installer_keeps_installed_at
run_test "installer --redetect"                 test_installer_redetect_refreshes_installed_at
run_test "installer pakai OS dari config"       test_installer_keeps_config_os_without_redetect
run_test "installer --redetect deteksi ulang"   test_installer_redetect_reevaluates_os
run_test "installer OS_NAME di-escape"          test_installer_os_name_escaped
run_test "installer OS_NAME bukan pemilih modul" test_installer_os_name_not_used_for_module
run_test "installer --uninstall delegasi"       test_installer_uninstall_delegates
run_test "installer --uninstall dengan prefix"  test_installer_uninstall_with_prefix
run_test "installer --uninstall tanpa binary"   test_installer_uninstall_without_binary
run_test "installer mode pipe tanpa network"    test_installer_pipe_mode_without_network

printf -- '\n--- Fase 4: modul void ---\n'
run_test "void dry-run"                        test_void_dry_run
run_test "void autoclean -> exit 3"             test_void_autoclean_unsupported

printf -- '\n--- Fase 5: modul alpine ---\n'
run_test "alpine dry-run"                      test_alpine_dry_run
run_test "alpine autoremove no-op"             test_alpine_autoremove_noop
run_test "alpine fitur tidak didukung"         test_alpine_unsupported_features

printf -- '\n--- Fase 6: modul gentoo ---\n'
run_test "gentoo dry-run (--ask default)"      test_gentoo_dry_run
run_test "gentoo autoremove pretend"           test_gentoo_autoremove_pretend
run_test "gentoo tool opsional tidak ada"      test_gentoo_optional_tools_missing

printf -- '\n--- Fase 7: modul arch ---\n'
run_test "arch dry-run (--noconfirm)"          test_arch_dry_run
run_test "arch autoremove"                     test_arch_autoremove
run_test "arch autoclean -> exit 3"            test_arch_autoclean_unsupported

printf '\n%d tes: %d lulus, %d gagal\n' "$TOTAL" "$PASSED" "$FAILED"

if [[ "$FAILED" -gt 0 ]]; then
    printf 'Gagal:\n'
    printf '  - %s\n' "${FAILED_NAMES[@]}"
    exit 1
fi

exit 0
