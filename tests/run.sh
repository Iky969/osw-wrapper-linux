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
# Versi yang sedang diuji; jangan hardcode di assert supaya naik VERSION tidak
# mematahkan tes.
TEST_VERSION="$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")"

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
        PATH="${OSW_TEST_PATH:-$TEST_PATH}" \
        "$@"
}

# Jalankan osw dengan stub curl (tidak menyentuh network); setiap pemanggilan
# curl dicatat ke $SB/curl.log lalu gagal dengan exit 22 seperti curl -f.
osw_run_stub_curl() {
    local stub_dir="$SB/curl-bin"
    mkdir -p "$stub_dir"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'printf "%%s\\n" "$*" >>"$CURL_LOG"\n'
        printf 'exit 22\n'
    } >"$stub_dir/curl"
    chmod +x "$stub_dir/curl"
    CURL_LOG="$SB/curl.log"
    : >"$CURL_LOG"
    OSW_TEST_PATH="$stub_dir:$TEST_PATH" \
        _sandbox_env CURL_LOG="$CURL_LOG" bash "$OSW" "$@" >"$OUT" 2>"$ERR"
    RC=$?
    return 0
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
    printf 'OS=debian\nINSTALLED_AT=2026-01-01T00:00:00Z\nVERSION=%s\n' "$TEST_VERSION" \
        >"$SB/cfg/osw/os.conf"
    cp "$ROOT_DIR/os/debian.sh" "$SB/data/osw/os/debian.sh"
}

# Ambil definisi fungsi dari bin/osw (sebelum blok dispatch) supaya _run dan
# do_self_update bisa dipanggil langsung dalam satu shell tes.
make_osw_functions_fixture() {
    local dest="$1"
    awk '/^# Early exit untuk subcommand/{exit} {print}' "$OSW" >"$dest"
    # bin/osw memakai set -euo pipefail; matikan lagi untuk sisa skrip pemanggil.
    printf 'set +eu\n' >>"$dest"
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

# Baris "DRY: ..." berawalan "sudo "/"doas " kalau tes dijalankan sebagai
# non-root (perilaku _priv sesuai blueprint). Prefix itu diabaikan supaya tes
# tidak bergantung pada apakah proses berjalan sebagai root.
expect_dry() {
    local want="$1"
    sed -E 's/^DRY: (sudo|doas) /DRY: /' "$OUT" | grep -qxF -- "DRY: $want" \
        || _fail "stdout tidak memuat baris: DRY: $want"
}

expect_dry_not() {
    local want="$1"
    if sed -E 's/^DRY: (sudo|doas) /DRY: /' "$OUT" | grep -qxF -- "DRY: $want"; then
        _fail "stdout seharusnya tidak memuat baris: DRY: $want"
    fi
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
    expect_out "osw $TEST_VERSION" || return 1
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
    expect_file_contains "$SB/cfg/osw/os.conf" "VERSION=$TEST_VERSION" || return 1
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

# _run tidak boleh bergantung pada set -e: perintah yang gagal harus
# mengembalikan rc-nya sendiri dan dry-run tidak boleh mengeksekusi apa pun.
test_run_returns_status() {
    local fixture="$SB/osw-funcs.sh"
    local marker="$SB/run-marker"
    make_osw_functions_fixture "$fixture"

    _sandbox_env FIXTURE="$fixture" MARKER="$marker" bash -c '
set -euo pipefail
. "$FIXTURE" >/dev/null 2>&1
set +eu
rc=0
_run false || rc=$?
printf "false-rc=%s\n" "$rc"
rc=0
_run bash -c "exit 7" || rc=$?
printf "exit7-rc=%s\n" "$rc"
OSW_DRY=1
_run touch "$MARKER"
if [[ -e "$MARKER" ]]; then printf "marker=ada\n"; else printf "marker=tidak-ada\n"; fi
' >"$OUT" 2>"$ERR"
    RC=$?

    expect_rc 0 || return 1
    expect_out "false-rc=1" || return 1
    expect_out "exit7-rc=7" || return 1
    expect_out "DRY: touch $marker" || return 1
    expect_out "marker=tidak-ada" || return 1
}

# Dry-run self-update saat upstream tidak terjangkau: OSW_VERSION_URL diarahkan
# ke alamat yang ditolak, jadi curl sungguhan yang gagal (bukan stub). Pesan
# harus memakai versi lokal dengan label "lokal, upstream tidak terjangkau".
test_self_update_dry_run_offline_label() {
    prepare_debian_config
    mkdir -p "$SB/tmp"

    _sandbox_env \
        TMPDIR="$SB/tmp" \
        OSW_VERSION_URL="http://127.0.0.1:9/VERSION" \
        https_proxy="http://127.0.0.1:9" \
        http_proxy="http://127.0.0.1:9" \
        bash "$OSW" -n self-update >"$OUT" 2>"$ERR"
    RC=$?

    expect_rc 0 || return 1
    expect_out "DRY: self-update dari https://raw.githubusercontent.com/Iky969/osw-wrapper-linux/v${TEST_VERSION}/install.sh (lokal, upstream tidak terjangkau)" || return 1
    expect_out_not "Mengunduh installer" || return 1
    if [[ -n "$(ls -A "$SB/tmp")" ]]; then
        _fail "dry-run meninggalkan file sementara: $(ls -A "$SB/tmp")"
        return 1
    fi
}

# Dry-run saat VERSION upstream terbaca: pesan memakai versi upstream dan
# diberi label "(upstream)". VERSION disajikan lewat file:// supaya hermetik.
test_self_update_dry_run_upstream_label() {
    prepare_debian_config
    mkdir -p "$SB/tmp"
    printf '9.9.9\n' >"$SB/upstream-version"

    _sandbox_env \
        TMPDIR="$SB/tmp" \
        OSW_VERSION_URL="file://$SB/upstream-version" \
        https_proxy="http://127.0.0.1:9" \
        http_proxy="http://127.0.0.1:9" \
        bash "$OSW" -n self-update >"$OUT" 2>"$ERR"
    RC=$?

    expect_rc 0 || return 1
    expect_out "DRY: self-update dari https://raw.githubusercontent.com/Iky969/osw-wrapper-linux/v9.9.9/install.sh (upstream)" || return 1
    expect_out_not "lokal, upstream tidak terjangkau" || return 1
    expect_out_not "Mengunduh installer" || return 1
    if [[ -n "$(ls -A "$SB/tmp")" ]]; then
        _fail "dry-run meninggalkan file sementara: $(ls -A "$SB/tmp")"
        return 1
    fi
}

# Dry-run tidak boleh mengunduh installer: hanya URL VERSION yang boleh
# disentuh, dan tidak boleh ada permintaan dengan -o (tulis file).
test_self_update_dry_run_never_downloads_installer() {
    prepare_debian_config
    mkdir -p "$SB/tmp" "$SB/curl-bin"
    {
        printf '#!/usr/bin/env bash\n'
        printf 'printf "%%s\\n" "$*" >>"%s"\n' "$SB/curl.log"
        printf 'exit 22\n'
    } >"$SB/curl-bin/curl"
    chmod +x "$SB/curl-bin/curl"
    : >"$SB/curl.log"

    OSW_TEST_PATH="$SB/curl-bin:$TEST_PATH" \
        _sandbox_env \
        TMPDIR="$SB/tmp" \
        https_proxy="http://127.0.0.1:9" \
        http_proxy="http://127.0.0.1:9" \
        bash "$OSW" -n self-update >"$OUT" 2>"$ERR"
    RC=$?

    expect_rc 0 || return 1
    expect_out "(lokal, upstream tidak terjangkau)" || return 1
    expect_file_contains "$SB/curl.log" "/main/VERSION" || return 1
    if grep -qF "/install.sh" "$SB/curl.log"; then
        _fail "dry-run mengunduh installer: $(cat "$SB/curl.log")"
        return 1
    fi
    if grep -qF -- " -o " "$SB/curl.log"; then
        _fail "dry-run menulis file: $(cat "$SB/curl.log")"
        return 1
    fi
    if [[ -n "$(ls -A "$SB/tmp")" ]]; then
        _fail "dry-run meninggalkan file sementara: $(ls -A "$SB/tmp")"
        return 1
    fi
}

# RETURN trap di do_self_update harus dicabut: kalau tertinggal, source atau
# fungsi berikutnya memicu rm -f pada variabel yang sudah hilang, dan set -u
# mematikan shell.
test_self_update_clears_return_trap() {
    local fixture="$SB/osw-funcs.sh"
    make_osw_functions_fixture "$fixture"
    prepare_debian_config
    mkdir -p "$SB/tmp"

    _sandbox_env \
        TMPDIR="$SB/tmp" \
        https_proxy="http://127.0.0.1:9" \
        http_proxy="http://127.0.0.1:9" \
        FIXTURE="$fixture" \
        bash -c '
set -euo pipefail
. "$FIXTURE" >/dev/null 2>&1
set +e
set -u
. "$XDG_CONFIG_HOME/osw/os.conf"
rc=0
do_self_update >/dev/null 2>&1 || rc=$?
printf "rc=%s\n" "$rc"
printf "trap=%s\n" "$(trap -p RETURN)"
. "$XDG_CONFIG_HOME/osw/os.conf"
printf "masih-hidup\n"
' >"$OUT" 2>"$ERR"
    RC=$?

    expect_rc 0 || return 1
    expect_out "rc=1" || return 1
    expect_out_re "^trap=$" || return 1
    expect_out "masih-hidup" || return 1
    if [[ -n "$(ls -A "$SB/tmp")" ]]; then
        _fail "file sementara tertinggal: $(ls -A "$SB/tmp")"
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
    expect_file_contains "$SB/cfg/osw/os.conf" "VERSION=$TEST_VERSION" || return 1
    expect_exec "$SB/bin/osw" || return 1
    expect_file "$SB/data/osw/os/debian.sh" || return 1

    bin_run "$SB/bin/osw" version
    expect_rc 0 || return 1
    expect_out "osw $TEST_VERSION (OS=debian)" || return 1

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
    expect_dry "xbps-install neovim" || return 1

    bin_run "$SB/bin/osw" -n -y install neovim
    expect_rc 0 || return 1
    expect_dry "xbps-install -y neovim" || return 1

    bin_run "$SB/bin/osw" -n remove neovim
    expect_rc 0 || return 1
    expect_dry "xbps-remove neovim" || return 1

    bin_run "$SB/bin/osw" -n update
    expect_rc 0 || return 1
    expect_dry "xbps-install -S" || return 1

    bin_run "$SB/bin/osw" -n upgrade
    expect_rc 0 || return 1
    expect_dry "xbps-install -u" || return 1

    bin_run "$SB/bin/osw" -n -y full-upgrade
    expect_rc 0 || return 1
    expect_dry "xbps-install -Su -y" || return 1

    bin_run "$SB/bin/osw" -n autoremove
    expect_rc 0 || return 1
    expect_dry "xbps-remove -o" || return 1

    bin_run "$SB/bin/osw" -n clean
    expect_rc 0 || return 1
    expect_dry "xbps-remove -O" || return 1
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
    expect_dry "apk add neovim" || return 1

    bin_run "$SB/bin/osw" -n -y install neovim
    expect_rc 0 || return 1
    expect_dry "apk add --no-interactive neovim" || return 1

    bin_run "$SB/bin/osw" -n remove neovim
    expect_rc 0 || return 1
    expect_dry "apk del neovim" || return 1

    bin_run "$SB/bin/osw" -n update
    expect_rc 0 || return 1
    expect_dry "apk update" || return 1

    bin_run "$SB/bin/osw" -n upgrade
    expect_rc 0 || return 1
    expect_dry "apk upgrade" || return 1

    bin_run "$SB/bin/osw" -n full-upgrade
    expect_rc 0 || return 1
    expect_dry "apk upgrade" || return 1

    bin_run "$SB/bin/osw" -n clean
    expect_rc 0 || return 1
    expect_dry "apk cache clean" || return 1
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
    expect_dry "emerge --sync" || return 1

    # Tanpa -y emerge harus tetap bertanya (--ask).
    bin_run "$SB/bin/osw" -n install neovim
    expect_rc 0 || return 1
    expect_dry "emerge --ask neovim" || return 1

    bin_run "$SB/bin/osw" -n -y install neovim
    expect_rc 0 || return 1
    expect_dry "emerge neovim" || return 1
    expect_dry_not "emerge --ask neovim" || return 1

    bin_run "$SB/bin/osw" -n upgrade
    expect_rc 0 || return 1
    expect_dry "emerge -uDN @world --ask" || return 1

    bin_run "$SB/bin/osw" -n -y full-upgrade
    expect_rc 0 || return 1
    expect_dry "emerge -uDN @world" || return 1
    expect_out_not "--ask" || return 1

    bin_run "$SB/bin/osw" -n remove neovim
    expect_rc 0 || return 1
    expect_dry "emerge --unmerge --ask neovim" || return 1
}

test_gentoo_autoremove_pretend() {
    installer_run --os gentoo --no-path-hint
    expect_rc 0 || return 1

    # Tanpa -y: hanya pretend, tidak ada yang dihapus.
    bin_run "$SB/bin/osw" -n autoremove
    expect_rc 0 || return 1
    expect_dry "emerge -p --depclean" || return 1

    bin_run "$SB/bin/osw" -n -y autoremove
    expect_rc 0 || return 1
    expect_dry "emerge --depclean" || return 1
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
    expect_dry "pacman -S neovim" || return 1

    # -y di pacman berarti refresh database, jadi non-interaktif memakai
    # --noconfirm.
    bin_run "$SB/bin/osw" -n -y install neovim
    expect_rc 0 || return 1
    expect_dry "pacman -S --noconfirm neovim" || return 1

    bin_run "$SB/bin/osw" -n remove neovim
    expect_rc 0 || return 1
    expect_dry "pacman -Rns neovim" || return 1

    bin_run "$SB/bin/osw" -n update
    expect_rc 0 || return 1
    expect_dry "pacman -Sy" || return 1

    bin_run "$SB/bin/osw" -n -y upgrade
    expect_rc 0 || return 1
    expect_dry "pacman -Su --noconfirm" || return 1

    bin_run "$SB/bin/osw" -n full-upgrade
    expect_rc 0 || return 1
    expect_dry "pacman -Syu" || return 1

    bin_run "$SB/bin/osw" -n -y clean
    expect_rc 0 || return 1
    expect_dry "pacman -Sc --noconfirm" || return 1
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
# Fase 8: kontrak modul & smoke lintas modul
# -----------------------------------------------------------------------------
test_contract_all_modules() {
    _sandbox_env bash "$ROOT_DIR/tests/contract.sh" >"$OUT" 2>"$ERR"
    RC=$?
    expect_rc 0 || return 1
    expect_out "PASS  os/debian.sh" || return 1
    expect_out "PASS  os/void.sh" || return 1
    expect_out "PASS  os/alpine.sh" || return 1
    expect_out "PASS  os/gentoo.sh" || return 1
    expect_out "PASS  os/arch.sh" || return 1
    expect_out "5 modul: 0 gagal" || return 1
}

test_contract_rejects_missing_funcs() {
    # Modul yang tidak lengkap harus ditolak: memastikan tes kontrak tidak
    # selalu hijau.
    local mod="$SB/os/broken.sh"
    mkdir -p "$SB/os"
    printf '#!/usr/bin/env bash\npkg_update() { :; }\n' >"$mod"
    _sandbox_env bash "$ROOT_DIR/tests/contract.sh" "$mod" >"$OUT" 2>"$ERR"
    RC=$?
    expect_rc 1 || return 1
    expect_err "fungsi wajib tidak ada" || return 1
}

test_contract_rejects_own_parser() {
    local mod="$SB/os/parser.sh"
    mkdir -p "$SB/os"
    printf '#!/usr/bin/env bash\nset -euo pipefail\n' >"$mod"
    _sandbox_env bash "$ROOT_DIR/tests/contract.sh" "$mod" >"$OUT" 2>"$ERR"
    RC=$?
    expect_rc 1 || return 1
    expect_err "modul memakai set -e" || return 1
}

test_smoke_stub_all_modules() {
    _sandbox_env bash "$ROOT_DIR/tests/smoke.sh" --stub >"$OUT" 2>"$ERR"
    RC=$?
    expect_rc 0 || return 1
    expect_out "PASS  debian" || return 1
    expect_out "PASS  void" || return 1
    expect_out "PASS  alpine" || return 1
    expect_out "PASS  gentoo" || return 1
    expect_out "PASS  arch" || return 1
    expect_out ", 0 gagal" || return 1
}

test_smoke_real_debian() {
    # Tanpa --stub: hanya perintah dry-run, memakai binari asli host.
    _sandbox_env bash "$ROOT_DIR/tests/smoke.sh" --os debian >"$OUT" 2>"$ERR"
    RC=$?
    expect_rc 0 || return 1
    expect_out "PASS  debian" || return 1
    expect_out "9 perintah" || return 1
}

# -----------------------------------------------------------------------------
# Rilis: checksum, tag, CI
# -----------------------------------------------------------------------------
# checksum yang di-commit harus selalu cocok dengan install.sh; kalau tidak,
# instalasi dari tag akan gagal di "sha256sum -c" dan self-update ditolak.
test_installer_checksum_matches() {
    local sha_file="$ROOT_DIR/install.sh.sha256"
    if [[ ! -f "$sha_file" ]]; then
        _fail "install.sh.sha256 tidak ada"
        return 1
    fi
    local expected actual
    expected="$(awk 'NR==1 {print $1}' "$sha_file")"
    actual="$(sha256sum "$ROOT_DIR/install.sh" | awk '{print $1}')"
    if [[ "$actual" != "$expected" ]]; then
        _fail "checksum kedaluwarsa (install.sh=$actual, file=$expected); jalankan: sha256sum install.sh > install.sh.sha256"
        return 1
    fi
    expect_file_contains "$sha_file" "install.sh" || return 1
}

# CI menolak rilis kalau VERSION dan DEFAULT_VERSION di installer berbeda,
# jadi tes ini menjaga keduanya tetap sinkron sebelum di-push.
test_version_matches_installer_default() {
    local version default
    version="$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")"
    default="$(sed -n 's/^DEFAULT_VERSION="\([^"]*\)"$/\1/p' "$ROOT_DIR/install.sh" | head -n1)"
    if [[ "$version" != "$default" ]]; then
        _fail "VERSION ($version) != DEFAULT_VERSION ($default)"
        return 1
    fi
}

# self-update harus mengambil installer dari tag v<VERSION>, bukan dari main.
test_self_update_uses_release_tag() {
    local version
    version="$(tr -d '[:space:]' <"$ROOT_DIR/VERSION")"

    prepare_debian_config
    osw_run_stub_curl self-update
    expect_rc 1 || return 1
    expect_err "gagal mengunduh installer" || return 1
    expect_file_contains "$SB/curl.log" "/v$version/install.sh" || return 1
    if grep -qF "/main/install.sh" "$SB/curl.log"; then
        _fail "self-update masih mengunduh installer dari main"
        return 1
    fi
}

# Workflow rilis harus memuat semua langkah yang dibutuhkan agar tag yang
# terbit selalu punya checksum dan Release.
# Regresi: `osw self-update` menjalankan installer dari file sementara tanpa
# repo di sebelahnya. Dulu preflight menolak dengan "dispatcher tidak
# ditemukan"; sekarang installer harus mengunduh snapshot repo.
test_installer_lone_file_downloads_sources() {
    local lone="$SB/lone"
    mkdir -p "$lone"
    cp "$INSTALLER" "$lone/install.sh"
    _sandbox_env \
        https_proxy="http://127.0.0.1:9" \
        http_proxy="http://127.0.0.1:9" \
        bash "$lone/install.sh" --no-path-hint >"$OUT" 2>"$ERR"
    RC=$?
    expect_rc 1 || return 1
    expect_err "gagal mengunduh" || return 1
    if grep -qF "dispatcher tidak ditemukan" "$ERR"; then
        _fail "installer file tunggal tidak mengunduh sumber repo"
        return 1
    fi
}

test_release_workflow_present() {
    local wf="$ROOT_DIR/.github/workflows/release.yml"
    local ci="$ROOT_DIR/.github/workflows/ci.yml"
    if [[ ! -f "$wf" ]]; then
        _fail "workflow .github/workflows/release.yml tidak ada"
        return 1
    fi
    expect_file_contains "$wf" "sha256sum install.sh > install.sh.sha256" || return 1
    expect_file_contains "$wf" "gh release create" || return 1
    expect_file_contains "$wf" "--target" || return 1
    expect_file_contains "$wf" "bash tests/run.sh" || return 1
    # Gate rilis: job rilis harus butuh job test, dan push tag harus tetap
    # memicu workflow ini.
    expect_file_contains "$wf" "needs: test" || return 1
    expect_file_contains "$wf" "tags: ['v*']" || return 1
    expect_file_contains "$ci" "bash tests/run.sh" || return 1
    expect_file_contains "$ci" "shellcheck" || return 1
    expect_file_contains "$ROOT_DIR/install.sh" 'ref_path="tags/' || return 1
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
run_test "_run mengembalikan rc & dry-run"   test_run_returns_status
run_test "self-update dry-run label offline"    test_self_update_dry_run_offline_label
run_test "self-update dry-run label upstream"   test_self_update_dry_run_upstream_label
run_test "self-update dry-run tanpa unduhan"    test_self_update_dry_run_never_downloads_installer
run_test "self-update mencabut RETURN trap"   test_self_update_clears_return_trap

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

printf -- '\n--- Fase 8: kontrak & smoke modul ---\n'
run_test "contract semua modul"               test_contract_all_modules
run_test "contract menolak modul tidak lengkap" test_contract_rejects_missing_funcs
run_test "contract menolak set -e di modul"   test_contract_rejects_own_parser
run_test "smoke --stub semua modul"           test_smoke_stub_all_modules
run_test "smoke debian (dry-run asli)"        test_smoke_real_debian

printf -- '\n--- Rilis: checksum, tag, CI ---\n'
run_test "checksum install.sh cocok"          test_installer_checksum_matches
run_test "VERSION == DEFAULT_VERSION"         test_version_matches_installer_default
run_test "self-update ambil installer tag"    test_self_update_uses_release_tag
run_test "installer file tunggal unduh sumber" test_installer_lone_file_downloads_sources
run_test "workflow rilis otomatis lengkap"    test_release_workflow_present

printf '\n%d tes: %d lulus, %d gagal\n' "$TOTAL" "$PASSED" "$FAILED"

if [[ "$FAILED" -gt 0 ]]; then
    printf 'Gagal:\n'
    printf '  - %s\n' "${FAILED_NAMES[@]}"
    exit 1
fi

exit 0
