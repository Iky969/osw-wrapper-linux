#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Iky969
#
# Installer osw.
#   bash install.sh                     # dijalankan dari clone repo
#   curl -fsSL <url>/install.sh | bash  # mode pipe (unduh snapshot repo)
set -euo pipefail

PROJECT="osw"
UPSTREAM_REPO="${OSW_UPSTREAM_REPO:-Iky969/osw-wrapper-linux}"
DEFAULT_VERSION="0.1.5"
# Ref sumber untuk mode pipe. Default-nya tag rilis yang cocok dengan
# DEFAULT_VERSION, supaya modul yang dipasang sama persis dengan installer
# yang dipiping. Set OSW_UPSTREAM_REF=main untuk mencoba kode pengembangan.
UPSTREAM_REF="${OSW_UPSTREAM_REF:-v$DEFAULT_VERSION}"

# -----------------------------------------------------------------------------
# 1. Lokasi sumber
# BASH_SOURCE kosong kalau skrip dibaca dari stdin (curl | bash); mode itu
# mengunduh snapshot repo ke direktori sementara.
# -----------------------------------------------------------------------------
SRC=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
    SRC="$(cd -- "$(dirname -- "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
fi

# -----------------------------------------------------------------------------
# 2. Path — harus identik dengan bin/osw
# -----------------------------------------------------------------------------
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/$PROJECT"
DATA_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/$PROJECT"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
CONF="$CONF_DIR/os.conf"

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
_info() {
    printf '%s\n' "$*"
}

_err() {
    printf 'install.sh: error: %s\n' "$*" >&2
}

die() {
    _err "$*"
    exit 1
}

usage() {
    cat <<EOF
Usage: install.sh [OPTIONS]

Pasang $PROJECT (wrapper package manager Linux) untuk pengguna saat ini.

Options:
  --os <name>        Paksa modul OS: debian, void, alpine, gentoo, arch, fedora
  --redetect         Deteksi ulang OS dan perbarui INSTALLED_AT
  --prefix <dir>     Prefix binary (default: ~/.local, binary ke <dir>/bin/osw).
                     Data dan config tetap mengikuti XDG agar sama dengan yang
                     dibaca oleh bin/osw.
  --no-path-hint     Jangan cetak saran penambahan PATH
  --uninstall        Hapus instalasi (delegasi ke "osw uninstall")
  -y, --yes          Tanpa konfirmasi (dipakai bersama --uninstall)
  -h, --help         Tampilkan bantuan ini

Contoh:
  bash install.sh
  bash install.sh --os debian --no-path-hint
  bash install.sh --uninstall -y
  curl -fsSL https://github.com/$UPSTREAM_REPO/releases/latest/download/install.sh | bash
EOF
}

# -----------------------------------------------------------------------------
# 3. Deteksi OS — pemetaan harus sama dengan bin/osw
# OSW_OS_RELEASE hanya untuk pengujian; default /etc/os-release.
# -----------------------------------------------------------------------------
OS_RELEASE_FILE="${OSW_OS_RELEASE:-/etc/os-release}"

# >>> blok-deteksi-os — salinan identik di bin/osw dan install.sh (diuji tests/run.sh) >>>
_os_release_value() {
    local key="$1"
    local value=""
    if [[ -r "$OS_RELEASE_FILE" ]]; then
        # shellcheck disable=SC1090
        value="$(. "$OS_RELEASE_FILE" >/dev/null 2>&1 && printf '%s' "${!key:-}")"
    fi
    printf '%s\n' "$value"
}

# Urutan pencocokan: ID dulu, lalu setiap token ID_LIKE. Hanya token di tabel
# ini yang dipetakan; turunan lain bisa memakai package manager/repo berbeda.
OSW_FAMILY_TABLE='debian:debian ubuntu:debian void:void alpine:alpine gentoo:gentoo arch:arch archarm:arch'

# Family yang HANYA boleh dipetakan dari ID, tidak pernah dari ID_LIKE.
# Fedora ada di sini karena turunan RHEL (rocky, almalinux, centos) memakai
# repo dan perilaku paket yang berbeda walau ID_LIKE-nya menyebut fedora.
OSW_ID_ONLY_TABLE='fedora:fedora'

# token -> family dari tabel ID_LIKE; rc 1 kalau token tidak ada di tabel.
_osw_family_for() {
    local token="$1"
    local pair=""
    local -a pairs=()
    [[ -n "$token" ]] || return 1
    read -r -a pairs <<<"$OSW_FAMILY_TABLE"
    for pair in "${pairs[@]}"; do
        if [[ "${pair%%:*}" == "$token" ]]; then
            printf '%s\n' "${pair#*:}"
            return 0
        fi
    done
    return 1
}

# ID -> family: tabel ID_LIKE dulu, lalu token yang hanya valid dari ID.
# Token ID_LIKE tidak pernah memakai OSW_ID_ONLY_TABLE.
_osw_family_for_id() {
    local family=""
    local pair=""
    local -a pairs=()
    if family="$(_osw_family_for "$1")"; then
        printf '%s\n' "$family"
        return 0
    fi
    read -r -a pairs <<<"$OSW_ID_ONLY_TABLE"
    for pair in "${pairs[@]}"; do
        if [[ "${pair%%:*}" == "$1" ]]; then
            printf '%s\n' "${pair#*:}"
            return 0
        fi
    done
    return 1
}

detect_os() {
    local family=""
    local token=""
    local -a likes=()
    if family="$(_osw_family_for_id "$(_os_release_value ID)")"; then
        printf '%s\n' "$family"
        return 0
    fi
    read -r -a likes <<<"$(_os_release_value ID_LIKE)"
    for token in "${likes[@]}"; do
        if family="$(_osw_family_for "$token")"; then
            printf '%s\n' "$family"
            return 0
        fi
    done
    printf 'unknown\n'
}

# Nama tampilan saja; tidak pernah dipakai memilih modul.
detect_os_name() {
    local name=""
    name="$(_os_release_value PRETTY_NAME)"
    if [[ -z "$name" ]]; then
        name="$(_os_release_value NAME)"
    fi
    if [[ -z "$name" ]]; then
        name="unknown"
    fi
    printf '%s\n' "$name"
}

# Pesan seragam saat family tidak dikenali; menyebut nilai yang terbaca.
detect_os_unrecognized() {
    printf 'OS tidak dikenali (ID=%s, ID_LIKE=%s)' \
        "$(_os_release_value ID)" "$(_os_release_value ID_LIKE)"
}
# <<< blok-deteksi-os <<<

# -----------------------------------------------------------------------------
# 4. Parser argumen
# -----------------------------------------------------------------------------
OS_OVERRIDE=""
REDETECT=0
PREFIX=""
NO_PATH_HINT=0
DO_UNINSTALL=0
ASSUME_YES=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --os)
            if [[ $# -lt 2 ]]; then
                die "opsi --os membutuhkan nilai"
            fi
            OS_OVERRIDE="$2"
            shift 2
            ;;
        --os=*)
            OS_OVERRIDE="${1#*=}"
            shift
            ;;
        --redetect)
            REDETECT=1
            shift
            ;;
        --prefix)
            if [[ $# -lt 2 ]]; then
                die "opsi --prefix membutuhkan nilai"
            fi
            PREFIX="$2"
            shift 2
            ;;
        --prefix=*)
            PREFIX="${1#*=}"
            shift
            ;;
        --no-path-hint)
            NO_PATH_HINT=1
            shift
            ;;
        --uninstall)
            DO_UNINSTALL=1
            shift
            ;;
        -y | --yes)
            ASSUME_YES=1
            shift
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            die "argumen tidak dikenal: $1 (lihat --help)"
            ;;
    esac
done

# -----------------------------------------------------------------------------
# 5. Prefix binary (opsional)
# -----------------------------------------------------------------------------
if [[ -n "$PREFIX" ]]; then
    if ! mkdir -p "$PREFIX" 2>/dev/null; then
        die "tidak bisa membuat direktori prefix: $PREFIX"
    fi
    PREFIX="$(cd -- "$PREFIX" && pwd)"
    if [[ "$PREFIX" == "/" ]]; then
        die "--prefix tidak boleh /"
    fi
    BIN_DIR="$PREFIX/bin"
fi

# -----------------------------------------------------------------------------
# 6. Mode --uninstall (sebelum preflight: tidak butuh modul OS)
# -----------------------------------------------------------------------------
if [[ "$DO_UNINSTALL" == "1" ]]; then
    if [[ -x "$BIN_DIR/osw" ]]; then
        _info "Menghapus instalasi osw lewat $BIN_DIR/osw..."
        if [[ "$ASSUME_YES" == "1" ]]; then
            "$BIN_DIR/osw" -y uninstall
        else
            "$BIN_DIR/osw" uninstall
        fi
        # Dispatcher hanya tahu BIN_DIR versi XDG, jadi binary di --prefix
        # kustom harus dihapus di sini.
        rm -f "$BIN_DIR/osw"
        exit 0
    fi

    _info "Binary osw tidak ditemukan di $BIN_DIR; membersihkan sisa direktori."
    rm -rf "$DATA_DIR"
    rm -f "$BIN_DIR/osw"
    rm -rf "$CONF_DIR"
    _info "Selesai."
    exit 0
fi

# -----------------------------------------------------------------------------
# 7. Baca config lama (kalau ada)
# -----------------------------------------------------------------------------
CONF_OS=""
CONF_OS_NAME=""
CONF_INSTALLED_AT=""
CONF_VERSION=""
if [[ -f "$CONF" ]]; then
    # shellcheck disable=SC1090
    . "$CONF"
    CONF_OS="${OS:-}"
    CONF_OS_NAME="${OS_NAME:-}"
    CONF_INSTALLED_AT="${INSTALLED_AT:-}"
    CONF_VERSION="${VERSION:-}"
fi

# -----------------------------------------------------------------------------
# 8. Tentukan OS & OS_NAME
# OS (family) hanya dideteksi kalau config belum ada atau --redetect diberikan.
# Kalau config sudah ada, nilai tersimpan dipakai apa adanya.
# -----------------------------------------------------------------------------
if [[ "$REDETECT" == "1" || -z "$CONF_OS" ]]; then
    DETECTED_OS="$(detect_os)"
    DETECTED_NAME="$(detect_os_name)"
else
    DETECTED_OS="$CONF_OS"
    if [[ -n "$CONF_OS_NAME" ]]; then
        DETECTED_NAME="$CONF_OS_NAME"
    else
        # Config lama (3 baris) belum punya OS_NAME; lengkapi untuk tampilan.
        DETECTED_NAME="$(detect_os_name)"
    fi
fi

if [[ -n "$OS_OVERRIDE" ]]; then
    OS="$OS_OVERRIDE"
else
    OS="$DETECTED_OS"
fi
OS_NAME="$DETECTED_NAME"

case "$OS" in
    debian | void | alpine | gentoo | arch | fedora) ;;
    *)
        if [[ "$OS" == "unknown" && -z "$OS_OVERRIDE" ]]; then
            die "$(detect_os_unrecognized). OS yang didukung: debian, void, alpine, gentoo, arch, fedora."
        fi
        die "OS tidak didukung: $OS. OS yang didukung: debian, void, alpine, gentoo, arch, fedora."
        ;;
esac

if [[ "$REDETECT" == "1" ]]; then
    INSTALLED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
elif [[ -n "$CONF_INSTALLED_AT" ]]; then
    INSTALLED_AT="$CONF_INSTALLED_AT"
else
    INSTALLED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
fi

# -----------------------------------------------------------------------------
# 9. Siapkan sumber (unduh snapshot hanya untuk mode pipe)
# -----------------------------------------------------------------------------
TMP_SRC=""
TMP_BASE=""
_cleanup() {
    if [[ -n "$TMP_SRC" && -d "$TMP_SRC" ]]; then
        rm -rf "$TMP_SRC"
    fi
    TMP_SRC=""
}
trap _cleanup EXIT

# Direktori dasar untuk mktemp. TMPDIR dihormati: kalau belum ada, dicoba dibuat
# dengan mkdir -p. Kalau TMPDIR tidak bisa dipakai, installer tidak buntu:
# peringatan dicetak dan /tmp dipakai sebagai gantinya.
_tmp_base() {
    local base="${TMPDIR:-/tmp}"
    if [[ -d "$base" ]]; then
        printf '%s\n' "$base"
        return 0
    fi
    if mkdir -p -- "$base" 2>/dev/null; then
        printf '%s\n' "$base"
        return 0
    fi
    printf 'install.sh: peringatan: direktori sementara %s tidak bisa dibuat; memakai /tmp\n' "$base" >&2
    mkdir -p -- /tmp 2>/dev/null || true
    printf '%s\n' /tmp
}

# Unduh snapshot repo untuk satu ref (tags/<tag> atau heads/<branch>) ke TMP_SRC.
# Status: 0 = sukses, 2 = HTTP 404 (ref tidak ada), 1 = kegagalan lain.
_fetch_ref() {
    local ref_path="$1"
    local url="https://codeload.github.com/${UPSTREAM_REPO}/tar.gz/refs/${ref_path}"
    local code=""
    local tarball=""

    _cleanup
    # Jangan lanjut tanpa direktori kerja: tanpa ini tar menulis ke "-C " kosong
    # dan installer tetap mencoba network walau mktemp gagal.
    if ! TMP_SRC="$(mktemp -d "$TMP_BASE/osw-install.XXXXXX" 2>/dev/null)"; then
        TMP_SRC=""
        _err "gagal membuat direktori sementara dengan mktemp di $TMP_BASE${TMPDIR:+ (TMPDIR=$TMPDIR)}; periksa direktori itu atau set TMPDIR ke direktori yang bisa ditulis"
        return 1
    fi

    tarball="$TMP_SRC/sumber.tar.gz"
    if ! code="$(curl -sS -L -o "$tarball" -w '%{http_code}' "$url")"; then
        _err "curl gagal mengunduh $url"
        return 1
    fi
    case "$code" in
        200) ;;
        404) return 2 ;;
        *)
            _err "gagal mengunduh $url: HTTP $code"
            return 1
            ;;
    esac

    if ! tar -xzf "$tarball" -C "$TMP_SRC" --strip-components=1; then
        _err "arsip sumber $url tidak bisa diekstrak"
        return 1
    fi
    rm -f -- "$tarball"
    return 0
}

fetch_sources() {
    if ! command -v curl >/dev/null 2>&1; then
        die "curl tidak ditemukan; jalankan installer dari clone repo: bash install.sh"
    fi
    if ! command -v tar >/dev/null 2>&1; then
        die "tar tidak ditemukan; jalankan installer dari clone repo: bash install.sh"
    fi

    local ref_path
    case "$UPSTREAM_REF" in
        v[0-9]*) ref_path="tags/$UPSTREAM_REF" ;;
        *) ref_path="heads/$UPSTREAM_REF" ;;
    esac

    TMP_BASE="$(_tmp_base)"

    _info "Installer dijalankan lewat pipe; mengunduh sumber ${UPSTREAM_REPO}@${UPSTREAM_REF}..."
    local rc=0
    _fetch_ref "$ref_path" || rc=$?
    if [[ "$rc" -eq 0 ]]; then
        SRC="$TMP_SRC"
        return 0
    fi

    # Hanya 404 yang berarti tag rilis belum terbit (mis. VERSION baru
    # dinaikkan tapi tag belum di-push). Error lain (network mati, 5xx) bukan
    # alasan memakai main: itu justru menyembunyikan masalah sesungguhnya.
    if [[ "$rc" -eq 2 && "$ref_path" == "tags/v$DEFAULT_VERSION" ]]; then
        _info "Tag v$DEFAULT_VERSION belum terbit; memakai main (HTTP 404, tidak dipin ke rilis)."
        rc=0
        _fetch_ref "heads/main" || rc=$?
        if [[ "$rc" -eq 0 ]]; then
            SRC="$TMP_SRC"
            return 0
        fi
    fi

    die "gagal mengunduh sumber ${UPSTREAM_REPO}@${UPSTREAM_REF} (butuh network; alternatif: git clone lalu bash install.sh)"
}

# Installer yang dijalankan dari file tunggal (mis. hasil unduhan
# `osw self-update` di direktori sementara) tidak punya bin/ dan os/ di
# sebelahnya; dalam kasus itu sumber harus diunduh seperti mode pipe.
if [[ -z "$SRC" || ! -f "$SRC/bin/osw" || ! -d "$SRC/os" ]]; then
    fetch_sources
fi

# -----------------------------------------------------------------------------
# 10. Preflight
# -----------------------------------------------------------------------------
if [[ ! -f "$SRC/bin/osw" ]]; then
    die "dispatcher tidak ditemukan: $SRC/bin/osw"
fi
if [[ ! -f "$SRC/os/$OS.sh" ]]; then
    die "modul untuk OS=$OS belum tersedia: $SRC/os/$OS.sh"
fi

VERSION="$DEFAULT_VERSION"
if [[ -f "$SRC/VERSION" ]]; then
    IFS= read -r VERSION <"$SRC/VERSION" || true
    VERSION="${VERSION//$'\r'/}"
    VERSION="${VERSION//[[:space:]]/}"
fi
if [[ -z "$VERSION" ]]; then
    VERSION="${CONF_VERSION:-$DEFAULT_VERSION}"
fi

# -----------------------------------------------------------------------------
# 11. Deploy modul + dispatcher
# -----------------------------------------------------------------------------
mkdir -p "$DATA_DIR/os"
cp -f "$SRC"/os/*.sh "$DATA_DIR/os/"

mkdir -p "$BIN_DIR"
install -m 755 "$SRC/bin/osw" "$BIN_DIR/osw"

# -----------------------------------------------------------------------------
# 12. Tulis config (4 baris, dibaca bin/osw)
# OS_NAME hanya untuk tampilan dan di-escape supaya aman di-source kembali.
# -----------------------------------------------------------------------------
mkdir -p "$CONF_DIR"
printf 'OS=%s\nOS_NAME=%s\nINSTALLED_AT=%s\nVERSION=%s\n' \
    "$OS" "$(printf '%q' "$OS_NAME")" "$INSTALLED_AT" "$VERSION" >"$CONF"

# -----------------------------------------------------------------------------
# 13. PATH hint — cetak saja, jangan edit rc file
# -----------------------------------------------------------------------------
if [[ "$NO_PATH_HINT" == "0" && ":$PATH:" != *":$BIN_DIR:"* ]]; then
    _info ""
    _info "⚠ $BIN_DIR belum ada di PATH."
    _info "  Tambahkan baris ini ke ~/.bashrc atau ~/.zshrc (tidak diubah otomatis):"
    _info "      export PATH=\"$BIN_DIR:\$PATH\""
    _info "  Untuk sesi ini saja:"
    _info "      export PATH=\"$BIN_DIR:\$PATH\""
fi

# -----------------------------------------------------------------------------
# 14. Self-test post-install
# -----------------------------------------------------------------------------
if ! "$BIN_DIR/osw" version; then
    die "self-test gagal: \"$BIN_DIR/osw version\" tidak berhasil"
fi
if ! "$BIN_DIR/osw" status >/dev/null; then
    die "self-test gagal: \"$BIN_DIR/osw status\" tidak berhasil"
fi

_info ""
_info "osw $VERSION terpasang untuk OS=$OS."
_info "  Binary : $BIN_DIR/osw"
_info "  Modul  : $DATA_DIR/os"
_info "  Config : $CONF"
