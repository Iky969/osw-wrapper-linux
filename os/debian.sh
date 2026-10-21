#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Iky969
# Modul ini di-source oleh bin/osw, bukan dieksekusi langsung.

pkg_update() {
    _priv apt-get update
}

pkg_upgrade() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(-y) || true
    _priv apt-get upgrade "${yes[@]}"
}

pkg_full_upgrade() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(-y) || true
    _priv apt-get full-upgrade "${yes[@]}"
}

pkg_install() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(-y) || true
    _priv apt-get install "${yes[@]}" "$@"
}

pkg_remove() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(-y) || true
    _priv apt-get remove "${yes[@]}" "$@"
}

pkg_search() {
    apt-cache search "$@"
}

pkg_info() {
    apt-cache show "$@"
}

pkg_list() {
    case "${1:-}" in
        --user)
            apt-mark showmanual
            ;;
        --repo)
            apt list --installed
            ;;
        "")
            dpkg -l
            ;;
        *)
            _err "opsi tidak dikenal untuk list: $1 (gunakan --user atau --repo)"
            return 2
            ;;
    esac
}

pkg_files() {
    dpkg -L "$@"
}

pkg_owner() {
    local out=""
    if ! out="$(dpkg -S "$@" 2>&1)"; then
        if [[ "$out" == *"no path found matching pattern"* ]]; then
            _err "tidak ditemukan paket pemilik untuk path: $*"
        else
            printf '%s\n' "$out" >&2
        fi
        return 1
    fi
    printf '%s\n' "$out"
}

pkg_autoremove() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(-y) || true
    _priv apt-get autoremove "${yes[@]}"
}

pkg_orphans() {
    apt-get -s autoremove 2>/dev/null | awk '/^Remv /{print $2}' | sort -u

}
pkg_clean() {
    _priv apt-get clean
}

pkg_autoclean() {
    _priv apt-get autoclean
}
