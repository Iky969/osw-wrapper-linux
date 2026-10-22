#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Iky969
#
# Smoke test per modul: pasang osw ke sandbox (HOME/XDG sementara), lalu
# jalankan setiap subcommand dengan OSW_DRY=1 OSW_YES=1. Exit code harus 0;
# fitur opsional yang memang tidak didukung boleh 3. Output tidak dibandingkan
# karena berbeda tiap package manager.
#
# Pemakaian:
#   bash tests/smoke.sh --stub             # semua modul, binari paket palsu
#   bash tests/smoke.sh --os void --stub   # satu modul
#   bash tests/smoke.sh                    # OS terdeteksi, binari asli (dry-run saja)
#
# Mode tanpa --stub hanya menjalankan perintah yang dijamin tidak mengeksekusi
# package manager (semua lewat OSW_DRY=1), jadi aman di host mana pun. Perintah
# read-only (search/info/list/files/owner/orphans) hanya dijalankan dengan
# --stub, karena di container pun paket contoh belum tentu terpasang.
#
# Exit: 0 kalau semua modul lulus, 1 kalau ada yang gagal.

set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
INSTALLER="$ROOT_DIR/install.sh"
TEST_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

OS_CHOICE=""
USE_STUB=0

usage() {
    cat <<'EOF'
Usage: bash tests/smoke.sh [--os <name>] [--stub]

  --os <name>   Hanya uji modul itu (debian, void, alpine, gentoo, arch, fedora)
  --stub        Pakai binari package manager palsu di PATH (hermetik, semua
                subcommand termasuk search/files/owner/orphans)
  -h, --help    Tampilkan bantuan ini

Tanpa --stub, OS dideteksi dari /etc/os-release dan hanya perintah dry-run
yang dijalankan.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --os)
            if [[ $# -lt 2 ]]; then
                printf 'smoke.sh: error: opsi --os membutuhkan nilai\n' >&2
                exit 1
            fi
            OS_CHOICE="$2"
            shift 2
            ;;
        --os=*)
            OS_CHOICE="${1#*=}"
            shift
            ;;
        --stub)
            USE_STUB=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'smoke.sh: error: argumen tidak dikenal: %s\n' "$1" >&2
            exit 1
            ;;
    esac
done

detect_family() {
    local id=""
    if [[ -r /etc/os-release ]]; then
        id="$(. /etc/os-release >/dev/null 2>&1 && printf '%s' "${ID:-}")"
    fi
    case "$id" in
        alpine) printf 'alpine\n' ;;
        void) printf 'void\n' ;;
        gentoo | funtoo) printf 'gentoo\n' ;;
        fedora) printf 'fedora\n' ;;
        debian | ubuntu | mint | linuxmint | pop | kali) printf 'debian\n' ;;
        arch | manjaro | endeavouros) printf 'arch\n' ;;
        *) printf 'unknown\n' ;;
    esac
}

FAMILY="$OS_CHOICE"
if [[ -z "$FAMILY" ]]; then
    FAMILY="$(detect_family)"
fi

if [[ "$FAMILY" == "unknown" ]]; then
    printf 'smoke.sh: error: OS tidak dikenali; gunakan --os <name> atau --stub\n' >&2
    exit 1
fi

# Modul yang diuji.
MODULES=()
if [[ "$USE_STUB" == "1" && -z "$OS_CHOICE" ]]; then
    for file in "$ROOT_DIR"/os/*.sh; do
        MODULES+=("$(basename "$file" .sh)")
    done
else
    MODULES=("$FAMILY")
fi

# -----------------------------------------------------------------------------
# Stub package manager (hanya untuk --stub)
# -----------------------------------------------------------------------------
SHIM=""
_make_stub() {
    SHIM="$(mktemp -d "${TMPDIR:-/tmp}/osw-smoke-shim.XXXXXX")"
    cat >"$SHIM/_stub" <<'STUB'
#!/bin/sh
name=$(basename "$0")
case "$name $*" in
    "pacman -Qtdq") exit 0 ;;
esac
printf '%s %s\n' "$name" "$*"
STUB
    chmod +x "$SHIM/_stub"
    local name=""
    for name in apt-get apt-cache apt-mark dpkg xbps-install xbps-remove \
        xbps-query apk emerge qlist qfile eclean-dist pacman \
        dnf dnf5 rpm sudo doas; do
        ln -s "$SHIM/_stub" "$SHIM/$name"
    done
}

if [[ "$USE_STUB" == "1" ]]; then
    _make_stub
    RUN_PATH="$SHIM:$TEST_PATH"
else
    RUN_PATH="$TEST_PATH"
fi

# -----------------------------------------------------------------------------
# Daftar perintah
# -----------------------------------------------------------------------------
DRY_COMMANDS=(
    "update"
    "upgrade"
    "full-upgrade"
    "install neovim"
    "remove neovim"
    "reinstall neovim"
    "autoremove"
    "clean"
    "autoclean"
)

READ_COMMANDS=(
    "list"
    "search neovim"
    "info neovim"
    "files neovim"
    "owner /usr/bin/true"
    "orphans"
)

# Fitur opsional yang boleh mengembalikan 3 tanpa menggagalkan smoke.
_allow_unsupported() {
    case "$1" in
        files | owner | orphans | autoclean | clean) return 0 ;;
        *) return 1 ;;
    esac
}

TOTAL=0
PASSED=0
FAILED=0
FAILED_DETAIL=()

_run_case() {
    local sb="$1"
    local label="$2"
    shift 2

    local out="$sb/.out"
    local err="$sb/.err"
    local rc=0

    env \
        -u OSW_QUIET -u OSW_NO_COLOR -u OSW_DEBUG \
        HOME="$sb/home" \
        XDG_CONFIG_HOME="$sb/cfg" \
        XDG_DATA_HOME="$sb/data" \
        XDG_BIN_HOME="$sb/bin" \
        PATH="$RUN_PATH" \
        OSW_DRY=1 \
        OSW_YES=1 \
        "$sb/bin/osw" "$@" >"$out" 2>"$err"
    rc=$?

    TOTAL=$((TOTAL + 1))
    if [[ "$rc" -eq 0 ]]; then
        PASSED=$((PASSED + 1))
        return 0
    fi
    if [[ "$rc" -eq 3 ]] && _allow_unsupported "$label"; then
        PASSED=$((PASSED + 1))
        return 0
    fi

    FAILED=$((FAILED + 1))
    FAILED_DETAIL+=("$label: exit $rc")
    printf '  gagal: %s -> exit %d\n' "$label" "$rc" >&2
    sed 's/^/      | /' "$err" | tail -n 5 >&2
    return 0
}

run_module() {
    local os="$1"
    local sb=""
    sb="$(mktemp -d "${TMPDIR:-/tmp}/osw-smoke.XXXXXX")"
    mkdir -p "$sb/home" "$sb/cfg" "$sb/data" "$sb/bin"

    local rc=0
    env \
        -u OSW_YES -u OSW_DRY -u OSW_QUIET -u OSW_DEBUG -u OSW_NO_COLOR \
        HOME="$sb/home" \
        XDG_CONFIG_HOME="$sb/cfg" \
        XDG_DATA_HOME="$sb/data" \
        XDG_BIN_HOME="$sb/bin" \
        PATH="$RUN_PATH" \
        bash "$INSTALLER" --os "$os" --no-path-hint >"$sb/.install.out" 2>"$sb/.install.err"
    rc=$?

    if [[ "$rc" -ne 0 ]]; then
        printf 'FAIL  %s: installer exit %d\n' "$os" "$rc"
        sed 's/^/      | /' "$sb/.install.err" | tail -n 5
        FAILED=$((FAILED + 1))
        FAILED_DETAIL+=("$os: installer exit $rc")
        rm -rf "$sb"
        return 1
    fi

    local before="$FAILED"
    local entry=""
    for entry in "${DRY_COMMANDS[@]}"; do
        # shellcheck disable=SC2086
        _run_case "$sb" "${entry%% *}" $entry
    done
    if [[ "$USE_STUB" == "1" ]]; then
        for entry in "${READ_COMMANDS[@]}"; do
            # shellcheck disable=SC2086
            _run_case "$sb" "${entry%% *}" $entry
        done
    fi

    if [[ "$FAILED" == "$before" ]]; then
        printf 'PASS  %s\n' "$os"
    else
        printf 'FAIL  %s\n' "$os"
    fi

    rm -rf "$sb"
}

printf 'smoke test osw (%s)\n' "$ROOT_DIR"
if [[ "$USE_STUB" == "1" ]]; then
    printf 'mode: stub (binari paket palsu)\n\n'
else
    printf 'mode: dry-run dengan binari asli (tanpa perintah read-only)\n\n'
fi

for module in "${MODULES[@]}"; do
    run_module "$module" || true
done

printf '\n%d perintah: %d lulus, %d gagal\n' "$TOTAL" "$PASSED" "$FAILED"

if [[ "$FAILED" -gt 0 ]]; then
    printf 'Gagal:\n'
    printf '  - %s\n' "${FAILED_DETAIL[@]}"
    [[ -n "$SHIM" ]] && rm -rf "$SHIM"
    exit 1
fi

[[ -n "$SHIM" ]] && rm -rf "$SHIM"
exit 0
