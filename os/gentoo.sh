#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Iky969
# Modul ini di-source oleh bin/osw, bukan dieksekusi langsung.
#
# Gentoo memakai Portage/emerge. emerge tidak memakai -y: perilaku amannya
# adalah bertanya, jadi pola flag di sini menambahkan --ask kecuali OSW_YES=1.
# `pkg_autoclean` sengaja tidak didefinisikan (tidak ada padanannya).

pkg_update() {
    _priv emerge --sync
}

pkg_upgrade() {
    local -a ask=()
    [[ "${OSW_YES:-0}" == "0" ]] && ask=(--ask) || true
    _priv emerge -uDN @world "${ask[@]}"
}

# Di Gentoo, upgrade dan full-upgrade identik dalam praktik: keduanya
# menyinkronkan seluruh @world.
pkg_full_upgrade() {
    pkg_upgrade "$@"
}

pkg_install() {
    local -a ask=()
    [[ "${OSW_YES:-0}" == "0" ]] && ask=(--ask) || true
    _priv emerge "${ask[@]}" "$@"
}

# --unmerge hanya menghapus paket yang disebut; --depclean ditangani
# pkg_autoremove/pkg_orphans supaya tidak menghapus dependensi diam-diam.
pkg_remove() {
    local -a ask=()
    [[ "${OSW_YES:-0}" == "0" ]] && ask=(--ask) || true
    _priv emerge --unmerge "${ask[@]}" "$@"
}

pkg_search() {
    emerge --search "$@"
}

# `emerge --info <pkg>` hanya mencetak info sistem, bukan info paket.
# qlist -Iv menampilkan versi terpasang; kalau portage-utils tidak ada,
# emerge -pv menampilkan detail paket tanpa memasangnya.
pkg_info() {
    if command -v qlist >/dev/null 2>&1; then
        qlist -Iv "$@"
    else
        emerge -pv "$@"
    fi
}

pkg_list() {
    case "${1:-}" in
        --user)
            # Set world berisi paket yang dipasang eksplisit oleh user;
            # itulah padanan terdekat "manual install" di Gentoo.
            if [[ -r /var/lib/portage/world ]]; then
                cat /var/lib/portage/world
            else
                _err "fitur list --user membutuhkan /var/lib/portage/world"
                return 3
            fi
            ;;
        --repo | "")
            if command -v qlist >/dev/null 2>&1; then
                qlist -I
            elif [[ -d /var/db/pkg ]]; then
                local pkgdir=""
                for pkgdir in /var/db/pkg/*/*; do
                    [[ -d "$pkgdir" ]] || continue
                    printf '%s\n' "${pkgdir#/var/db/pkg/}"
                done
            else
                _err "portage tidak ditemukan (qlist maupun /var/db/pkg)"
                return 1
            fi
            ;;
        *)
            _err "opsi tidak dikenal untuk list: $1 (gunakan --user atau --repo)"
            return 2
            ;;
    esac
}

pkg_files() {
    if ! command -v qlist >/dev/null 2>&1; then
        _err "fitur files membutuhkan qlist (app-portage/portage-utils)"
        return 3
    fi
    qlist "$@"
}

pkg_owner() {
    if ! command -v qfile >/dev/null 2>&1; then
        _err "fitur owner membutuhkan qfile (app-portage/portage-utils)"
        return 3
    fi
    qfile "$@"
}

# --depclean bisa menghapus paket, jadi tanpa OSW_YES=1 hanya pretend (-p).
pkg_autoremove() {
    if [[ "${OSW_YES:-0}" == "1" ]]; then
        _priv emerge --depclean
    else
        _priv emerge -p --depclean
    fi
}

# Read-only: -p berarti pretend, tidak ada yang dihapus.
pkg_orphans() {
    emerge -p --depclean
}

pkg_clean() {
    if ! command -v eclean-dist >/dev/null 2>&1; then
        _err "fitur clean membutuhkan eclean-dist (app-portage/gentoolkit)"
        return 3
    fi
    _priv eclean-dist --deep
}
