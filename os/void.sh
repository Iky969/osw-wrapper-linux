#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Iky969
# Modul ini di-source oleh bin/osw, bukan dieksekusi langsung.
#
# Void Linux memakai XBPS. Tidak ada pembeda manual/otomatis seperti
# apt-mark; `xbps-query -m` menampilkan paket yang dipasang manual.
# `pkg_autoclean` sengaja tidak didefinisikan: XBPS tidak punya padanannya,
# jadi dispatcher memakai fallback `return 3`.

pkg_update() {
    _priv xbps-install -S
}

pkg_upgrade() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(-y) || true
    _priv xbps-install -u "${yes[@]}"
}

# Void tidak memisahkan upgrade dan full-upgrade: -S menyinkronkan indeks
# sekaligus mengupgrade seluruh sistem.
pkg_full_upgrade() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(-y) || true
    _priv xbps-install -Su "${yes[@]}"
}

pkg_install() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(-y) || true
    _priv xbps-install "${yes[@]}" "$@"
}

pkg_remove() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(-y) || true
    _priv xbps-remove "${yes[@]}" "$@"
}

pkg_search() {
    xbps-query -Rs "$@"
}

pkg_info() {
    xbps-query -R "$@"
}

pkg_list() {
    case "${1:-}" in
        --user)
            xbps-query -m
            ;;
        --repo)
            xbps-query -l
            ;;
        "")
            xbps-query -l
            ;;
        *)
            _err "opsi tidak dikenal untuk list: $1 (gunakan --user atau --repo)"
            return 2
            ;;
    esac
}

pkg_files() {
    xbps-query -f "$@"
}

pkg_owner() {
    xbps-query -o "$@"
}

pkg_autoremove() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(-y) || true
    _priv xbps-remove -o "${yes[@]}"
}

# Read-only, tidak pernah memodifikasi sistem.
pkg_orphans() {
    xbps-query -O
}

pkg_clean() {
    _priv xbps-remove -O
}
