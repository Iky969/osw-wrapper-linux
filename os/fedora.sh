#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Iky969
# Modul ini di-source oleh bin/osw, bukan dieksekusi langsung.
#
# Fedora memakai dnf. dnf5 dipakai kalau tersedia (Fedora 41+), lalu dnf
# (Python). Keduanya menerima opsi global di belakang subcommand, jadi daftar
# flag di modul ini sama untuk keduanya.
#
# Pola flag:
# - Dry-run OSW_DRY=1: `--assumeno`. dnf tetap menghitung transaksi, lalu
#   menjawab "tidak" untuk setiap pertanyaan, sehingga pratinjau DRY tidak
#   pernah menyetujui apa pun dan tidak memakai `-y`.
# - Nyata + OSW_YES=1: `-y` (--assumeyes), satu-satunya cara non-interaktif.
# - Nyata tanpa OSW_YES: tanpa flag; dnf bertanya seperti biasa.
#
# `pkg_autoclean` sengaja tidak didefinisikan: `dnf clean` hanya punya tipe
# cache all/packages/metadata/dbcache/expire-cache, tidak ada padanan
# "cache usang saja". Dispatcher memakai fallback return 3.

# Prefer dnf5 (C++), lalu dnf (Python). Jangan menebak: kalau tidak ada
# keduanya, kembalikan pesan yang jelas.
_dnf_bin() {
    if command -v dnf5 >/dev/null 2>&1; then
        printf 'dnf5\n'
        return 0
    fi
    if command -v dnf >/dev/null 2>&1; then
        printf 'dnf\n'
        return 0
    fi
    _err "dnf/dnf5 tidak ditemukan"
    return 1
}

# `repoquery` bukan bagian inti dnf4 (butuh dnf-plugins-core), sedangkan di
# dnf5 sudah menyatu. --help dipakai sebagai cek murah dan read-only.
_dnf_has_repoquery() {
    local dnf="$1"
    "$dnf" repoquery --help >/dev/null 2>&1
}

pkg_update() {
    local dnf
    dnf="$(_dnf_bin)" || return 1
    _priv "$dnf" makecache
}

pkg_upgrade() {
    local dnf
    dnf="$(_dnf_bin)" || return 1
    local -a mode=()
    if [[ "${OSW_DRY:-0}" == "1" ]]; then
        mode=(--assumeno)
    elif [[ "${OSW_YES:-0}" == "1" ]]; then
        mode=(-y)
    fi
    _priv "$dnf" upgrade "${mode[@]}"
}

# Fedora tidak memisahkan upgrade dan full-upgrade: `dnf upgrade` mengupgrade
# seluruh sistem. Upgrade antar-rilis memakai `dnf system-upgrade` (plugin
# terpisah), jadi bukan padanan perintah ini.
pkg_full_upgrade() {
    pkg_upgrade "$@"
}

pkg_install() {
    local dnf
    dnf="$(_dnf_bin)" || return 1
    local -a mode=()
    if [[ "${OSW_DRY:-0}" == "1" ]]; then
        mode=(--assumeno)
    elif [[ "${OSW_YES:-0}" == "1" ]]; then
        mode=(-y)
    fi
    _priv "$dnf" install "${mode[@]}" "$@"
}

pkg_remove() {
    local dnf
    dnf="$(_dnf_bin)" || return 1
    local -a mode=()
    if [[ "${OSW_DRY:-0}" == "1" ]]; then
        mode=(--assumeno)
    elif [[ "${OSW_YES:-0}" == "1" ]]; then
        mode=(-y)
    fi
    _priv "$dnf" remove "${mode[@]}" "$@"
}

pkg_search() {
    local dnf
    dnf="$(_dnf_bin)" || return 1
    "$dnf" search "$@"
}

pkg_info() {
    local dnf
    dnf="$(_dnf_bin)" || return 1
    "$dnf" info "$@"
}

pkg_list() {
    local dnf
    dnf="$(_dnf_bin)" || return 1
    case "${1:-}" in
        --user)
            # repoquery --userinstalled: paket yang dipasang user, bukan
            # sebagai dependensi.
            if ! _dnf_has_repoquery "$dnf"; then
                _err "fitur list --user membutuhkan 'dnf repoquery' (di dnf4: pasang dnf-plugins-core)"
                return 3
            fi
            "$dnf" repoquery --userinstalled
            ;;
        --repo)
            "$dnf" list --installed
            ;;
        "")
            "$dnf" list --installed
            ;;
        *)
            _err "opsi tidak dikenal untuk list: $1 (gunakan --user atau --repo)"
            return 2
            ;;
    esac
}

pkg_files() {
    if ! command -v rpm >/dev/null 2>&1; then
        _err "fitur files membutuhkan rpm"
        return 3
    fi
    rpm -ql "$@"
}

pkg_owner() {
    if ! command -v rpm >/dev/null 2>&1; then
        _err "fitur owner membutuhkan rpm"
        return 3
    fi
    rpm -qf "$@"
}

pkg_autoremove() {
    local dnf
    dnf="$(_dnf_bin)" || return 1
    local -a mode=()
    if [[ "${OSW_DRY:-0}" == "1" ]]; then
        mode=(--assumeno)
    elif [[ "${OSW_YES:-0}" == "1" ]]; then
        mode=(-y)
    fi
    _priv "$dnf" autoremove "${mode[@]}"
}

# Read-only: repoquery --unneeded hanya mendaftar paket yang akan dihapus
# autoremove (paket dependensi yang tidak lagi dibutuhkan); tidak ada
# transaksi yang dijalankan.
pkg_orphans() {
    local dnf
    dnf="$(_dnf_bin)" || return 1
    if ! _dnf_has_repoquery "$dnf"; then
        _err "fitur orphans membutuhkan 'dnf repoquery' (di dnf4: pasang dnf-plugins-core)"
        return 3
    fi
    "$dnf" repoquery --unneeded
}

pkg_clean() {
    local dnf
    dnf="$(_dnf_bin)" || return 1
    _priv "$dnf" clean all
}
