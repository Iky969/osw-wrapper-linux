# Menambah modul OS baru

Satu modul = satu family package manager. Satu modul = satu commit
(`feat(faseN): modul <os>`). Baca `docs/CONTRACT.md` dulu.

## 1. Tentukan family dan pemetaannya

Pilih nama family yang sama dengan nama file: `os/<family>.sh`. Petakan token
dari `/etc/os-release` (`ID` dulu, lalu setiap token `ID_LIKE`) ke family itu.
Contoh: `ID=archarm` dengan `ID_LIKE=arch` masuk family `arch`.

Tambahkan token ke `OSW_FAMILY_TABLE` di blok `# >>> blok-deteksi-os` pada
**dua file**, dan salin blok itu utuh supaya tetap identik:

- `bin/osw`
- `install.sh`

Blok itu memuat tabel, `detect_os()`, dan pesan `OS tidak dikenali`; `tests/run.sh`
membandingkan kedua salinan byte-per-byte, jadi jangan mengubah salah satunya
saja. Token di luar tabel tidak pernah dipetakan secara otomatis.

Tambahkan juga family baru ke daftar yang diterima di `install.sh`:

```sh
case "$OS" in
    debian | void | alpine | gentoo | arch | <family>) ;;
    ...
```

## 2. Tulis modul

Mulai dari `os/debian.sh`, lalu ganti command-nya. Kerangka minimal:

```sh
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Iky969
# Modul ini di-source oleh bin/osw, bukan dieksekusi langsung.

pkg_update() {
    _priv <cmd> update
}

pkg_upgrade() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(<flag-noninteraktif>) || true
    _priv <cmd> upgrade "${yes[@]}"
}

pkg_full_upgrade() {
    pkg_upgrade "$@"
}

pkg_install() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(<flag-noninteraktif>) || true
    _priv <cmd> install "${yes[@]}" "$@"
}

pkg_remove() {
    local -a yes=()
    [[ "${OSW_YES:-0}" == "1" ]] && yes=(<flag-noninteraktif>) || true
    _priv <cmd> remove "${yes[@]}" "$@"
}

pkg_search() { <cmd> search "$@"; }
pkg_info()   { <cmd> info "$@"; }

pkg_list() {
    case "${1:-}" in
        --user) <cmd> list-manual ;;
        --repo | "") <cmd> list-installed ;;
        *) _err "opsi tidak dikenal untuk list: $1 (gunakan --user atau --repo)"; return 2 ;;
    esac
}

pkg_autoremove() { _priv <cmd> autoremove; }
pkg_clean()      { _priv <cmd> clean; }

# Opsional: hanya kalau OS benar-benar mendukung.
# pkg_files()     { <cmd> files "$@"; }
# pkg_owner()     { <cmd> owner "$@"; }
# pkg_orphans()   { <cmd> orphans; }        # WAJIB read-only
# pkg_autoclean() { _priv <cmd> autoclean; }
```

Jangan definisikan fungsi opsional yang tidak punya padanan — biarkan fallback
dispatcher mengembalikan 3. Jangan tulis `return 3` palsu untuk fungsi yang
sebenarnya bisa diimplementasikan.

## Checklist

- [ ] 10 fungsi wajib ada; tidak ada `set -e`; tidak ada parser argumen sendiri.
- [ ] Aksi yang mengubah sistem lewat `_priv`; perintah read-only tanpa `_priv`.
- [ ] Pola `-y` sesuai package manager (jangan asumsikan `-y`; lihat pacman).
- [ ] `pkg_orphans` read-only (pretend/`-s`/`-p`), tidak pernah menghapus.
- [ ] `pkg_autoremove` yang destruktif hanya pretend kecuali `OSW_YES=1`
      (contoh: Gentoo `--depclean`).
- [ ] Pemetaan `ID` ditambahkan di `bin/osw` **dan** `install.sh`.
- [ ] Family ditambahkan ke daftar `install.sh`.
- [ ] `bash tests/contract.sh os/<family>.sh` lulus.
- [ ] `bash tests/smoke.sh --os <family> --stub` lulus.
- [ ] Tes dry-run khusus modul ditambahkan ke `tests/run.sh` (lihat blok
      Fase 4-7) dan `bash tests/run.sh` hijau.
- [ ] README (tabel OS + pemetaan) dan `docs/CONTRACT.md` (tabel ketersediaan)
      diperbarui.
- [ ] `TODOS.md` diperbarui.

## Verifikasi

```sh
bash -n bin/osw install.sh os/*.sh tests/*.sh
shellcheck -S warning bin/osw install.sh os/*.sh tests/*.sh
bash tests/run.sh
bash tests/smoke.sh --os <family> --stub
```

Uji di OS aslinya memakai container sekali pakai. Perintah destruktif hanya
boleh dengan `-n`/`OSW_DRY=1`:

```sh
docker run --rm -it -v "$PWD:/src:ro" debian:stable bash -c '
  cp -r /src /tmp/osw && cd /tmp/osw && bash tests/smoke.sh'
```

Ganti image sesuai family (`voidlinux/voidlinux`, `alpine:latest`,
`gentoo/stage3`, `archlinux:latest`, `fedora:latest`). Mode tanpa `--stub`
hanya menjalankan perintah dry-run, jadi tidak ada paket yang berubah.

Untuk memeriksa perintah read-only dengan paket nyata, jalankan manual di
container, misalnya `osw search bash`, `osw files bash`, `osw owner /bin/bash`.
Jangan jalankan `autoremove`, `remove`, atau `clean` tanpa `-n` di mesin yang
masih dipakai.

## Fedora (dnf/dnf5)

Modul `os/fedora.sh` memilih binary sendiri: `dnf5` kalau ada (Fedora 41+),
lalu `dnf` (Python). Keduanya menerima opsi global di belakang subcommand,
jadi daftar flag sama. Pemetaan `ID=fedora` ada di `OSW_ID_ONLY_TABLE`, bukan
`OSW_FAMILY_TABLE`, supaya `ID_LIKE=fedora` (rocky/almalinux/centos) tidak ikut
terpetakan.

Flag per aksi:

| Aksi `osw` | Perintah | Catatan |
| --- | --- | --- |
| `update` | `dnf makecache` | Unduh metadata repo |
| `upgrade` | `dnf upgrade` | `full-upgrade` sama: Fedora tidak memisahkan |
| `install` | `dnf install` | |
| `remove` | `dnf remove` | |
| `search` | `dnf search` | |
| `info` | `dnf info` | |
| `list` | `dnf list --installed` | |
| `list --user` | `dnf repoquery --userinstalled` | Butuh `dnf repoquery` |
| `files` / `owner` | `rpm -ql` / `rpm -qf` | Read-only, dari rpm |
| `autoremove` | `dnf autoremove` | |
| `orphans` | `dnf repoquery --unneeded` | Read-only, hanya mendaftar |
| `clean` | `dnf clean all` | dnf5 butuh tipe cache (`all`) |
| `autoclean` | — | Tidak ada padanan → fallback `return 3` |

Flag konfirmasi:

- **Dry-run (`OSW_DRY=1`) → `--assumeno`**, bukan `-y`. dnf menghitung
transaksi lalu menjawab "tidak", jadi pratinjau `DRY:` tidak pernah berarti
"setujui".
- **Nyata + `OSW_YES=1` → `-y`**. Ini satu-satunya cara non-interaktif dnf;
tanpa `-y` (dan tanpa `--assumeno`) dnf bertanya ke pengguna.
- **Nyata tanpa `-y` → tanpa flag**, sama seperti package manager lain.

Sumber verifikasi: dokumentasi resmi DNF4
(<https://dnf.readthedocs.io/en/latest/command_ref.html>) dan DNF5
(<https://dnf5.readthedocs.io/en/latest/dnf5.8.html>,
<https://dnf5.readthedocs.io/en/latest/commands/repoquery.8.html>,
<https://dnf5.readthedocs.io/en/latest/commands/clean.8.html>).
Lingkungan pengembangan modul ini (Ubuntu 22.04) tidak punya `dnf`, `dnf5`,
maupun runtime container Fedora, jadi flag **belum** dicocokkan dengan
`dnf --help`/`dnf5 --help` di binary nyata; verifikasi perilaku sebenarnya
harus dilakukan di container `fedora:latest` (lihat perintah di atas).

Efek samping yang jujur harus disebut:

- `search`, `info`, `list`, `orphans`, dan juga `--assumeno` **tidak**
  mengubah paket terpasang, tetapi dnf dapat menyegarkan cache metadata
  (mengunduh metadata repo) saat cache kedaluwarsa. Jangan klaim "tanpa efek
  samping".
- `repoquery` di dnf4 berasal dari `dnf-plugins-core`; modul mengecek
  `dnf repoquery --help` dan mengembalikan 3 dengan pesan yang menyebut
  paketnya kalau tidak tersedia.

## Jebakan yang sudah pernah kena

- **`pacman -y` bukan "ya"**, melainkan refresh database. Gunakan
  `--noconfirm` (lihat `os/arch.sh`).
- **`emerge --info <pkg>` bukan info paket**, melainkan info sistem. Gunakan
  `qlist -Iv` atau `emerge -pv` (lihat `os/gentoo.sh`).
- **`apk` tidak punya `-y`**; gunakan `--no-interactive`.
- **`pacman -Qtdq` keluar 1 saat tidak ada orphan**; itu bukan error.
- **Modul yang mendefinisikan `pkg_autoclean` palsu** akan lolos kontrak tetapi
  menyesatkan pengguna; lebih baik biarkan fallback 3.
- **`dnf -y` ≠ pratinjau.** `-y` menyetujui transaksi; untuk dry-run gunakan
  `--assumeno` supaya dnf menghitung transaksi lalu menolaknya.
- **`dnf clean` di dnf5 butuh tipe cache.** `dnf5 clean` tanpa argumen gagal;
  `clean all` valid di dnf4 dan dnf5.
- **`dnf repoquery` bukan inti dnf4.** Di dnf4 butuh `dnf-plugins-core`; di dnf5
  sudah menyatu. Cek dulu, jangan asumsikan ada.
