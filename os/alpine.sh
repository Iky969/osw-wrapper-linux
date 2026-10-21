#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Iky969
# Modul ini di-source oleh bin/osw, bukan dieksekusi langsung.
#
# Alpine memakai apk. `apk` tidak punya flag -y; yang tersedia adalah
# --no-interactive, jadi pola flag di sini memakai itu.
# `pkg_orphans` dan `pkg_autoclean` sengaja tidak didefinisikan: apk tidak
# punya konsep orphan/cache usang terpisah, jadi dispatcher memakai fallback
# `return 3`.

pkg_update() {
    _priv apk update
}

pkg_upgrade() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(--no-interactive) || true
    _priv apk upgrade "${yes[@]}"
}

# Alpine tidak memisahkan upgrade dan full-upgrade; `apk upgrade` mengupgrade
# seluruh sistem.
pkg_full_upgrade() {
    pkg_upgrade "$@"
}

pkg_install() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(--no-interactive) || true
    _priv apk add "${yes[@]}" "$@"
}

pkg_remove() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(--no-interactive) || true
    _priv apk del "${yes[@]}" "$@"
}

pkg_search() {
    apk search "$@"
}

pkg_info() {
    apk info -a "$@"
}

pkg_list() {
    case "${1:-}" in
        --user)
            # apk tidak mencatat apakah paket dipasang manual atau sebagai
            # dependensi, jadi daftar "manual" tidak bisa diberikan dengan jujur.
            _err "fitur list --user belum didukung untuk OS=alpine (apk tidak mencatat instalasi manual)"
            return 3
            ;;
        --repo)
            apk list --installed
            ;;
        "")
            apk info
            ;;
        *)
            _err "opsi tidak dikenal untuk list: $1 (gunakan --user atau --repo)"
            return 2
            ;;
    esac
}

pkg_files() {
    apk info -L "$@"
}

pkg_owner() {
    apk info --who-owns "$@"
}

# apk sudah menghapus dependensi yang tidak terpakai saat `apk del`, jadi tidak
# ada aksi tambahan yang aman dijalankan di sini.
pkg_autoremove() {
    _info "apk otomatis membersihkan dependensi saat apk del; tidak ada yang perlu dijalankan."
}

pkg_clean() {
    _priv apk cache clean
}
