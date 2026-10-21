#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Iky969
# Modul ini di-source oleh bin/osw, bukan dieksekusi langsung.
#
# Arch memakai pacman. PENTING: di pacman `-y` berarti "refresh database",
# bukan "jawab ya". Karena itu pola non-interaktif di sini memakai
# --noconfirm, bukan -y, agar tidak mengubah arti perintah.
# `pkg_autoclean` sengaja tidak didefinisikan (tidak ada padanannya).

pkg_update() {
    _priv pacman -Sy
}

pkg_upgrade() {
    local -a noconfirm=()
    [[ "${OSW_YES:-0}" == "1" ]] && noconfirm=(--noconfirm) || true
    _priv pacman -Su "${noconfirm[@]}"
}

pkg_full_upgrade() {
    local -a noconfirm=()
    [[ "${OSW_YES:-0}" == "1" ]] && noconfirm=(--noconfirm) || true
    _priv pacman -Syu "${noconfirm[@]}"
}

pkg_install() {
    local -a noconfirm=()
    [[ "${OSW_YES:-0}" == "1" ]] && noconfirm=(--noconfirm) || true
    _priv pacman -S "${noconfirm[@]}" "$@"
}

pkg_remove() {
    local -a noconfirm=()
    [[ "${OSW_YES:-0}" == "1" ]] && noconfirm=(--noconfirm) || true
    _priv pacman -Rns "${noconfirm[@]}" "$@"
}

pkg_search() {
    pacman -Ss "$@"
}

pkg_info() {
    pacman -Si "$@"
}

pkg_list() {
    case "${1:-}" in
        --user)
            # -Qe: paket yang dipasang eksplisit (bukan dependensi).
            pacman -Qe
            ;;
        --repo)
            pacman -Q
            ;;
        "")
            pacman -Q
            ;;
        *)
            _err "opsi tidak dikenal untuk list: $1 (gunakan --user atau --repo)"
            return 2
            ;;
    esac
}

pkg_files() {
    pacman -Ql "$@"
}

pkg_owner() {
    pacman -Qo "$@"
}

pkg_autoremove() {
    local -a orphans=()
    mapfile -t orphans < <(pacman -Qtdq 2>/dev/null || true)
    if [[ ${#orphans[@]} -eq 0 ]]; then
        _info "Tidak ada paket yatim untuk dihapus."
        return 0
    fi
    local -a noconfirm=()
    [[ "${OSW_YES:-0}" == "1" ]] && noconfirm=(--noconfirm) || true
    _priv pacman -Rns "${noconfirm[@]}" "${orphans[@]}"
}

# Read-only: -Qtdq hanya mendaftar, tidak menghapus.
pkg_orphans() {
    if ! command -v pacman >/dev/null 2>&1; then
        _err "pacman tidak ditemukan"
        return 1
    fi
    local out=""
    # pacman -Qtdq keluar 1 kalau tidak ada orphan; itu bukan error.
    out="$(pacman -Qtdq 2>/dev/null || true)"
    if [[ -n "$out" ]]; then
        printf '%s\n' "$out"
    fi
}

pkg_clean() {
    local -a noconfirm=()
    [[ "${OSW_YES:-0}" == "1" ]] && noconfirm=(--noconfirm) || true
    _priv pacman -Sc "${noconfirm[@]}"
}
