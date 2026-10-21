# TODOS.md

Status kerja repo `osw`. Diperbarui 2026-10-21.

## Catatan sumber acuan

- `docs/archive/` **tidak ada** di repo ini (diperiksa 2026-10-21). Rencana fase
  diambil dari `blueprint.md`.
- `tests/run.sh` baru dibuat di langkah persiapan ini; sebelumnya belum ada tes
  otomatis sama sekali.

## Ringkasan status fase

| Fase | Isi | Implementasi | Status uji |
| ---- | --- | ------------ | ---------- |
| 0 | Kerangka repo | selesai | manual: `bin/`, `os/`, `install.sh`, `README.md`, `.shellcheckrc`, `VERSION`=0.1.0 |
| 1 | `bin/osw` dispatcher | selesai | otomatis: help, flag, version, status, detect, fallback 3 (lihat `tests/run.sh`) |
| 2 | `os/debian.sh` | selesai (14 fungsi) | otomatis: hanya mode `-n` (dry-run); **eksekusi apt nyata belum diuji** |
| 3 | `install.sh` | selesai (11 poin blueprint + config 4 baris) | otomatis: 21 tes Fase 3; mode pipe lewat network belum diuji |
| 4 | `os/void.sh` | selesai (13 fungsi) | otomatis: mode `-n` untuk semua aksi + `autoclean` -> 3; **XBPS nyata belum diuji** |
| 5 | `os/alpine.sh` | selesai (12 fungsi) | otomatis: mode `-n`, `autoremove` no-op, `orphans`/`autoclean`/`list --user` -> 3; **apk nyata belum diuji** |
| 6 | `os/gentoo.sh` | selesai (13 fungsi) | otomatis: mode `-n` (`--ask` default), autoremove pretend, tool opsional -> 3; **emerge nyata belum diuji** |
| 7 | `os/arch.sh` | selesai (13 fungsi) | otomatis: mode `-n` (`--noconfirm`, bukan `-y`), autoremove; **pacman nyata belum diuji** |
| 8 | Tes lintas OS (`smoke.sh`, `contract.sh`) | selesai | otomatis: kontrak 5 modul + smoke 75 perintah (stub) + smoke debian dry-run nyata; **4 container nyata belum dijalankan** |
| 9 | README, docs, rilis | selesai (+ CI rilis otomatis) | otomatis: tes checksum/VERSION/tag/workflow (4 tes); **workflow belum pernah berjalan di GitHub** — tag `v0.1.0` akan dibuat CI pada push pertama |

## Detail Fase 0-2

### Fase 0 — kerangka repo

- Ada: `bin/osw`, `os/debian.sh`, `install.sh`, `README.md`, `.shellcheckrc`,
  `VERSION`, `LICENSE`, `blueprint.md`.
- `.shellcheckrc` berisi `disable=SC1090,SC1091` (source file dinamis). Tidak ada
  disable baru yang ditambahkan.
- `tests/` belum ada di Fase 0; dibuat di langkah persiapan.

### Fase 1 — dispatcher

Sudah ada: header + `VERSION` relatif `$0`, path XDG, parser flag global
(`-y/-n/-q/--no-color/--debug/-h/-v`), `_run`, `_priv`, `_need_args`, cek config
(exit 4), source config + modul, fallback `pkg_*` (`return 3`), `usage`,
`usage_cmd`, `do_version`, `do_status`, `do_detect`, `do_uninstall`,
`do_self_update`, dispatcher dengan exit code 0/1/2/3/4.

Uji otomatis yang sekarang ada (hermetik): lihat daftar tes di `tests/run.sh`
bagian "Fase 0-2".

Perilaku yang ditemukan saat menulis tes dan **bukan** bug (sesuai blueprint
poin 7 → 17): subcommand tidak dikenal tanpa `os.conf` keluar **4** (cek config
lebih dulu), bukan 2. Dengan config ada, keluar 2.

### Fase 2 — modul debian

14 fungsi ada (update, upgrade, full-upgrade, install, remove, search, info, list,
files, owner, autoremove, orphans, clean, autoclean; reinstall lewat fallback
dispatcher). Pola `local -a yes=()` dihormati.

Belum diuji: eksekusi `apt-get` sungguhan (butuh container/VM sekali pakai),
`pkg_orphans` (`apt-get -s autoremove`), `pkg_owner` pada path yang tidak ada.

## Detail Fase 3 — `install.sh`

Selesai. Implementasi mengikuti blueprint poin 1-11:

1. Header `set -euo pipefail`; lokasi sumber lewat `BASH_SOURCE` + `readlink -f`.
2. `CONF_DIR`, `DATA_DIR`, `BIN_DIR`, `CONF` identik dengan `bin/osw`.
3. `detect_os` sama dengan dispatcher: alpine, void, gentoo/funtoo,
   debian/ubuntu/mint/linuxmint/pop/kali, arch/manjaro/endeavouros, else unknown.
4. Parser: `--os`, `--os=`, `--redetect`, `--prefix`, `--no-path-hint`,
   `--uninstall`, `-h/--help`. Tambahan `-y/--yes` khusus `--uninstall` supaya
   bisa dipakai non-interaktif.
5. Preflight: OS tidak didukung → exit 1 + daftar OS; modul tidak ada → exit 1;
   `bin/osw` tidak ada → exit 1.
6. Deploy modul: `cp -f "$SRC"/os/*.sh "$DATA_DIR/os/"`.
7. Deploy dispatcher: `install -m 755 "$SRC/bin/osw" "$BIN_DIR/osw"`.
8. Config 4 baris (`OS`, `OS_NAME`, `INSTALLED_AT`, `VERSION`). `INSTALLED_AT`
   dipertahankan kalau config sudah ada, dan hanya diperbarui dengan
   `--redetect`.
9. PATH hint dicetak saja; rc file tidak pernah diubah otomatis.
10. Self-test `osw version` + `osw status` setelah deploy; gagal → exit 1.
11. `--uninstall` delegasi ke `osw uninstall`; kalau binary tidak ada, sisa
    direktori dibersihkan sendiri.

Semantik deteksi (penting):

- `OS` = **family** yang dipakai memilih modul `os/$OS.sh`. Nilainya dideteksi
  dari `/etc/os-release` `ID` **hanya** kalau `os.conf` belum ada atau
  `--redetect` diberikan. Kalau config sudah ada, `OS` tersimpan dipakai apa
  adanya dan tidak ada deteksi ulang (kecuali `--os`/`--redetect` eksplisit).
- Tidak ada pencarian modul satu per satu. Kalau `os/$OS.sh` tidak ada → exit 1
  dengan pesan "modul ... belum tersedia" (sudah diuji dengan OS=alpine).
- `OS_NAME` = nama tampilan dari `PRETTY_NAME`, fallback `NAME`, lalu `unknown`.
  Disimpan dengan `printf '%q'` sehingga aman di-`source` kembali (diuji dengan
  spasi, tanda kutip, dan tanda kurung). `OS_NAME` **tidak pernah** dipakai
  memilih modul (diuji dengan `OS=debian` + `OS_NAME=Alpine Linux`).
- `OSW_OS_RELEASE` (default `/etc/os-release`) adalah hook pengujian; tes
  memakainya untuk mengganti isi os-release tanpa menyentuh `/etc`.
- Config lama 3 baris tetap terbaca: `OS` dipakai, `OS_NAME` dilengkapi sekali
  dari os-release untuk tampilan.
- `osw detect` di `bin/osw` ikut menulis 4 baris + `OS_NAME` (perubahan di luar
  `install.sh`, disebut eksplisit di pesan commit) agar format config konsisten.

Keputusan desain yang perlu diketahui:

- **Semantik `--prefix`**: hanya memindahkan binary (`<prefix>/bin/osw`). Data dan
  config tetap mengikuti XDG, karena `bin/osw` menghitung `DATA_DIR`/`CONF_DIR`
  dari XDG; memindahkannya akan membuat dispatcher tidak menemukan modul.
  `install.sh --uninstall --prefix <dir>` menghapus binary prefix itu secara
  eksplisit karena dispatcher hanya tahu `BIN_DIR` versi XDG.
- **Mode pipe** (`curl ... | bash`): `BASH_SOURCE` kosong, jadi installer
  mengunduh snapshot `codeload.github.com/<repo>/tar.gz/refs/heads/<ref>` ke
  direktori sementara (butuh `curl`, `tar`, network). Repo/ref bisa di-override
  lewat `OSW_UPSTREAM_REPO`/`OSW_UPSTREAM_REF`.
- `--os <nama>` menerima nama modul (`debian`, `void`, ...), bukan `ID` mentah
  dari `/etc/os-release`.
- Installer tidak memanggil `apt` sama sekali.

Belum diuji: unduhan mode pipe yang sukses (butuh network + repo publik) dan
instalasi di OS selain container Ubuntu ini.

## Detail Fase 4 — `os/void.sh`

Selesai. Pemetaan XBPS sesuai blueprint: update `xbps-install -S`, upgrade
`xbps-install -u`, full-upgrade `xbps-install -Su` (Void tidak memisahkan
keduanya), install/remove, search/info `xbps-query -Rs`/`-R`, list `-l`
(`--user` -> `-m`), files `-f`, owner `-o`, autoremove `xbps-remove -o`,
orphans `xbps-query -O` (read-only), clean `xbps-remove -O`.

`pkg_autoclean` sengaja tidak didefinisikan (tidak ada padanan di XBPS), jadi
fallback dispatcher mengembalikan 3 — diuji.

Belum diuji: eksekusi XBPS sungguhan (butuh container Void); semua uji memakai
`OSW_DRY=1`.

## Detail Fase 5 — `os/alpine.sh`

Selesai. Flag non-interaktif memakai `--no-interactive` (apk tidak punya `-y`).
update `apk update`, upgrade & full-upgrade `apk upgrade` (Alpine tidak
memisahkannya), install `apk add`, remove `apk del`, search `apk search`,
info `apk info -a`, list `apk info` (`--repo` -> `apk list --installed`),
files `apk info -L`, owner `apk info --who-owns`, autoremove no-op dengan pesan
(apk sudah membersihkan dependensi saat `apk del`), clean `apk cache clean`.

Sengaja tidak didukung (fallback dispatcher, exit 3): `orphans`, `autoclean`,
dan `list --user` (apk tidak mencatat instalasi manual; mengembalikan daftar
semua paket akan menyesatkan).

Belum diuji: eksekusi apk sungguhan (butuh container Alpine).

## Detail Fase 6 — `os/gentoo.sh`

Selesai. emerge tidak punya `-y`, jadi pola flag-nya menambahkan `--ask`
kecuali `OSW_YES=1`. update `emerge --sync`, upgrade & full-upgrade
`emerge -uDN @world`, install `emerge`, remove `emerge --unmerge`,
search `emerge --search`, info `qlist -Iv` (fallback `emerge -pv`, karena
`emerge --info <pkg>` bukan info paket), list `qlist -I` dengan fallback isi
`/var/db/pkg` (`--user` membaca `/var/lib/portage/world`), files `qlist`,
owner `qfile`, autoremove `emerge -p --depclean` lalu `--depclean` hanya bila
`OSW_YES=1`, orphans `emerge -p --depclean` (read-only), clean
`eclean-dist --deep`.

Mengembalikan 3 bila `qlist`/`qfile`/`eclean-dist` tidak ada (paket
`app-portage/portage-utils` dan `app-portage/gentoolkit` belum terpasang).
`autoclean` tidak didefinisikan.

Belum diuji: eksekusi emerge sungguhan dan keluaran `qlist`/`qfile` (butuh
container/stage3 Gentoo).

## Detail Fase 7 — `os/arch.sh`

Selesai. update `pacman -Sy`, upgrade `pacman -Su`, full-upgrade
`pacman -Syu`, install `pacman -S`, remove `pacman -Rns`, search `pacman -Ss`,
info `pacman -Si`, list `pacman -Q` (`--user` -> `pacman -Qe`), files
`pacman -Ql`, owner `pacman -Qo`, autoremove `pacman -Qtdq` lalu
`pacman -Rns`, orphans `pacman -Qtdq` (read-only, keluar 0 walau kosong),
clean `pacman -Sc`.

Penting: di pacman `-y` berarti refresh database, **bukan** "jawab ya". Pola
non-interaktif modul ini memakai `--noconfirm`, sehingga `osw -y install x`
tidak pernah diperlakukan sebagai refresh. `autoclean` tidak didefinisikan.

Belum diuji: eksekusi pacman sungguhan dan kasus ada orphan (butuh container
Arch).

## Detail Fase 8 — kontrak & smoke

`tests/contract.sh` men-source tiap modul dengan stub helper dispatcher, lalu
memeriksa:

- shebang `#!/usr/bin/env bash`;
- 10 fungsi wajib (`pkg_install pkg_remove pkg_update pkg_upgrade
  pkg_full_upgrade pkg_search pkg_info pkg_list pkg_autoremove pkg_clean`);
- modul tidak memakai `set -e` dan tidak mem-parse argumen sendiri;
- fungsi opsional (`files owner orphans autoclean`) dilaporkan, bukan diwajibkan.

`tests/smoke.sh` memasang osw ke sandbox (HOME/XDG sementara), lalu menjalankan
perintah dengan `OSW_DRY=1 OSW_YES=1`. Dua mode:

- `--stub` — semua modul, PATH berisi binari package manager palsu, sehingga 15
  perintah (termasuk search/info/list/files/owner/orphans) bisa diuji hermetik:
  **75 perintah, 75 lulus**.
- tanpa `--stub` — OS dideteksi dari `/etc/os-release`, hanya perintah dry-run
  yang dijalankan (tidak ada package manager yang dieksekusi): debian **9
  perintah, 9 lulus** di host ini.

Exit 3 diterima hanya untuk fitur opsional (`files`, `owner`, `orphans`,
`autoclean`, `clean`); perintah inti yang keluar 3 dianggap gagal.

Belum dijalankan: smoke di 4 container nyata (`debian:stable`,
`voidlinux/voidlinux`, `alpine:latest`, `gentoo/stage3`). Lingkungan kerja ini
tidak punya docker dan tidak boleh menjalankan package manager sungguhan.

## Detail Fase 9 — dokumentasi & rilis

Selesai untuk bagian yang bisa dikerjakan tanpa push:

- `README.md`: instalasi (tag + checksum, mode pipe, clone), opsi installer,
  format config, daftar perintah + flag global + exit code, tabel OS yang
  didukung, tabel pemetaan perintah per OS, cara menjalankan tes, cara lapor
  bug, dan langkah rilis.
- `docs/CONTRACT.md`: aturan arsitektur, 10 fungsi wajib + 5 opsional, tabel
  ketersediaan per modul, pola flag non-interaktif, exit code, path/config,
  hook pengujian.
- `docs/ADDING-OS.md`: checklist modul baru, kerangka kode, verifikasi, uji
  container, dan jebakan yang sudah ditemukan (`pacman -y`, `emerge --info`,
  `apk` tanpa `-y`, `pacman -Qtdq` exit 1).

### Rilis otomatis (lanjutan Fase 9)

- `.github/workflows/ci.yml`:
  - job `test` pada setiap push ke `main` + pull request: `bash -n`,
    `shellcheck -S warning`, `tests/run.sh`, `tests/smoke.sh --stub`,
    `tests/contract.sh`.
  - job `release` (butuh `test` hijau, hanya push `main` atau
    `workflow_dispatch`): validasi `VERSION` (`X.Y.Z`) dan
    `DEFAULT_VERSION` di `install.sh`, lewati kalau tag `v<VERSION>` sudah ada
    (tapi verifikasi checksum-nya), kalau belum: tulis
    `install.sh.sha256`, commit `[skip ci]`, buat annotated tag, push tag,
    lalu `gh release create` dengan aset `install.sh` + `install.sh.sha256`.
  - Perlu `permissions: contents: write`; branch protection harus mengizinkan
    bot Actions push commit checksum + tag, atau jalankan manual lewat
    `workflow_dispatch`.
- `install.sh.sha256` di-commit di root repo supaya tag pertama langsung
  punya checksum dan `osw self-update` tidak pernah melihat tag tanpa
  `.sha256`.
- `install.sh` mode pipe sekarang mengunduh snapshot **tag** `v$DEFAULT_VERSION`
  (fallback ke `main` dengan peringatan kalau tag belum terbit);
  `bin/osw self-update` memakai URL tag, bukan `main`.
- `README.md` ditulis ulang: instalasi (latest release, checksum, clone),
  tabel perintah, contoh alur pemakaian, update/uninstall, config, tabel OS,
  tes, cara kerja CI + cara merilis versi baru, dan troubleshooting.

Belum diverifikasi (butuh GitHub, di luar lingkungan ini):

- job `release` benar-benar membuat tag/Release pada push pertama;
- izin `contents: write` pada repo asli (branch protection, Actions token).

## Item terbuka

### 1. BUG (Fase 1): `osw self-update` selalu gagal — TERVERIFIKASI & SUDAH DIPERBAIKI

- Verifikasi statis:
  `grep -n expected_sha bin/osw` →
  `372:    if [[ -z "$expected_sha" ]]; then` (pemakaian) dan
  `399:    local expected_sha=""` (deklarasi, jauh setelahnya).
- Verifikasi runtime: dengan `os.conf` valid, `osw self-update` keluar `rc=1`
  dengan `bin/osw: line 372: expected_sha: unbound variable`.
- Dampak: `self-update` berhenti sebelum mengunduh apa pun; verifikasi SHA-256 di
  blok sesudahnya juga tidak pernah menjadi wajib.
- Status: **diperbaiki** di commit `fix(self-update): ...` (commit terpisah, di
  luar fase, sesuai aturan). Perbaikan: pemakaian `$expected_sha` sebelum
  deklarasi dihapus; checksum sekarang **wajib** diunduh dan dicocokkan sebelum
  `bash "$tmp_installer"` dijalankan.
- Konsekuensi yang perlu diketahui: `self-update` hanya akan berjalan kalau file
  `<url install.sh>.sha256` tersedia di upstream. Fase 9 perlu menerbitkan file
  tersebut bersama installer bertag.
- Regresi dijaga oleh tes "self-update gagal tanpa network" di `tests/run.sh`
  (memastikan tidak ada lagi `unbound variable` dan kegagalan network dilaporkan
  dengan pesan jelas).

### 2. Cakupan uji belum lengkap

- `tests/run.sh` berisi 61 tes hermetik: 19 tes Fase 0-2, 1 tes regresi
  self-update, 21 tes Fase 3, 11 tes modul Fase 4-7, 5 tes kontrak/smoke Fase 8,
  dan 4 tes rilis (checksum, `VERSION` == `DEFAULT_VERSION`, `self-update`
  memakai tag, kelengkapan workflow).
- Smoke di 4 container nyata belum dijalankan; lihat `tests/smoke.sh` dan
  `docs/ADDING-OS.md`.
- Belum ada uji nyata `apt-get` dan belum ada uji di OS selain Debian/Ubuntu
  (lingkungan kerja ini Ubuntu 22.04, dijalankan sebagai root di container).
- Mode pipe baru diuji pada jalur gagal (network diblokir via stub/ proxy);
  jalur unduh + install sukses belum diuji.
- Workflow CI baru divalidasi secara lokal (YAML di-parse, langkah
  baca-`VERSION` dijalankan, `shellcheck` 0 warning); belum ada run sungguhan.

## Riwayat langkah

- `chore: tambahkan AGENTS.md, TODOS.md, tests/run.sh` — harness hermetik + 19
  tes Fase 0-2 (19 lulus).
- `feat(fase3): install.sh` — installer + 17 tes Fase 3 (36 tes total, 36 lulus).
- `fix(self-update): perbaiki unbound variable & wajibkan checksum SHA-256` —
  perbaikan bug Fase 1 di commit terpisah (37 tes total, 37 lulus).
- `feat(fase3): OS_NAME di config & deteksi OS hanya saat perlu` — config 4
  baris, `OS_NAME` ter-escape, deteksi family hanya tanpa config/`--redetect`,
  `bin/osw do_detect` disamakan (41 tes total, 41 lulus).
- `feat(fase4): modul void (XBPS)` — `os/void.sh`, tes dry-run + fallback
  `autoclean`, tes preflight "modul belum tersedia" dibuat independen dari
  modul yang ada (43 tes total, 43 lulus).
- `feat(fase5): modul alpine (apk)` — `os/alpine.sh`, tes dry-run + no-op
  `autoremove` + fitur tidak didukung; tes `--redetect` memakai repo tanpa
  modul alpine agar tidak bergantung pada modul yang sudah ada (46 lulus).
- `feat(fase6): modul gentoo (portage)` — `os/gentoo.sh`, tes `--ask` default,
  autoremove pretend vs `-y`, dan tool opsional yang tidak tersedia
  (49 tes total, 49 lulus).
- `feat(fase7): modul arch (pacman)` — `os/arch.sh`, tes dry-run dengan
  `--noconfirm` (bukan `-y`), autoremove tanpa pacman, fallback `autoclean`
  (52 tes total, 52 lulus).
- `test(fase8): kontrak & smoke lintas modul` — `tests/contract.sh`,
  `tests/smoke.sh`, integrasi ke `tests/run.sh` (57 tes total, 57 lulus).
- `docs(fase9): README, kontrak modul, panduan modul baru` — `README.md`,
  `docs/CONTRACT.md`, `docs/ADDING-OS.md` (57 tes tetap hijau).
- `ci: rilis otomatis (tag + checksum + Release)` — `.github/workflows/ci.yml`,
  `install.sh.sha256`, mode pipe `install.sh` dipin ke tag, `self-update`
  memakai URL tag, README ditulis ulang (61 tes lulus).
