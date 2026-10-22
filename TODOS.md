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
| 9 | README, docs, rilis | selesai (+ CI rilis otomatis) | otomatis: tes checksum/VERSION/tag/workflow + regresi installer file tunggal; **terverifikasi di GitHub**: CI membuat tag + Release `v0.1.0`, `v0.1.1`, `v0.1.2` (aset + checksum diperiksa) |

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

- `.github/workflows/ci.yml` (2026-10-22, dipisah dari workflow rilis):
  - pemicu `push` ke `main` dan `pull_request`.
  - job `lint`: `bash -n bin/osw install.sh os/*.sh tests/*.sh`, lalu
    shellcheck **v0.10.0** dari binary statis GitHub release (bukan apt)
    dengan `-S warning` untuk `bin/osw install.sh os/*.sh tests/run.sh
    tests/smoke.sh tests/contract.sh`.
  - job `test`: `needs: lint`, matriks container `ubuntu:22.04`,
    `ubuntu:24.04`, `debian:bookworm`, `fail-fast: false`; tiap container
    memasang `ca-certificates coreutils curl git tar xz-utils` (git wajib
    untuk `actions/checkout`) lalu menjalankan `bash tests/run.sh`.
  - Tidak ada container Void/Alpine/Gentoo di job ini (fase terpisah).
- `.github/workflows/release.yml` (job rilis dipindah dari `ci.yml`):
  - pemicu `push` branch `main`, `push` tag `v*`, dan `workflow_dispatch`.
  - job `test` (matriks sama dengan `ci.yml`) lalu job `release` dengan
    `needs: test` — rilis hanya terbit kalau tes hijau, termasuk saat dipicu
    push tag. Konsekuensi pilihan gate (b): pada push ke `main` matriks tes
    berjalan dua kali (`ci.yml` dan `release.yml`).
  - validasi `VERSION` (`X.Y.Z`) + `DEFAULT_VERSION`; pada push tag, nama tag
    harus sama dengan `v$VERSION`.
  - tag belum ada: tulis `install.sh.sha256`, commit `[skip ci]` bila berubah,
    lalu `gh release create --target <sha>` dengan aset `install.sh` +
    `install.sh.sha256`.
  - tag sudah ada: verifikasi checksum terhadap isi tag, dan buat Release
    untuk tag itu kalau belum ada (`--verify-tag`, tag tidak dipindah).
  - Perlu `permissions: contents: write` pada job rilis; branch protection
    harus mengizinkan bot Actions push commit checksum, atau jalankan manual
    lewat `workflow_dispatch`.
- **Verifikasi checksum shellcheck** (2026-10-22): langkah `ShellCheck 0.10.0`
  di `ci.yml` menjalankan `printf '%s  %s\n' "$SHELLCHECK_SHA256" /tmp/shellcheck.tar.xz | sha256sum -c -`
  sebelum ekstraksi, jadi hash yang tidak cocok menggagalkan job. Nilai yang
  dipakai: `6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87`
  (2.404.716 byte). Rilis v0.10.0 **tidak menerbitkan file checksum/digest**
  (7 aset tanpa `SHA256SUMS`, API aset tanpa field `digest`), jadi nilai ini
  dihitung dari aset resmi
  `https://github.com/koalaman/shellcheck/releases/download/v0.10.0/shellcheck-v0.10.0.linux.x86_64.tar.xz`
  dan dicocokkan dengan dua pin independen: Pants 2.32
  (`known_versions`: `v0.10.0|linux_x86_64|6c881ab…|2404716`,
  `https://www.pantsbuild.org/2.32/reference/subsystems/shellcheck`) dan
  `multitool.lock.json` Selenium 4.40.0
  (`https://chromium.googlesource.com/external/github.com/SeleniumHQ/selenium/+/refs/tags/selenium-4.40.0/multitool.lock.json`).
  `release.yml` tidak punya job lint, jadi hanya satu pekerjaan yang berubah.
  Terverifikasi di GitHub: run CI `deb80f9`
  (`https://github.com/Iky969/osw-wrapper-linux/actions/runs/39853639585`)
  job `Lint (bash -n & shellcheck)` hijau dan langkah
  `ShellCheck 0.10.0 (binary statis)` berstatus success.
- `install.sh.sha256` di-commit di root repo supaya tag pertama langsung
  punya checksum dan `osw self-update` tidak pernah melihat tag tanpa
  `.sha256`.
- `install.sh` mode pipe sekarang mengunduh snapshot **tag** `v$DEFAULT_VERSION`
  (fallback ke `main` dengan peringatan kalau tag belum terbit);
  `bin/osw self-update` memakai URL tag, bukan `main`.
- `README.md` ditulis ulang: instalasi (latest release, checksum, clone),
  tabel perintah, contoh alur pemakaian, update/uninstall, config, tabel OS,
  tes, cara kerja CI + cara merilis versi baru, dan troubleshooting.

Hasil run pertama workflow terpisah (push `5a426d1`, 2026-10-22) — **hijau**:

- `CI` — https://github.com/Iky969/osw-wrapper-linux/actions/runs/39851572157
  - `Lint (bash -n & shellcheck)`: sukses.
  - `Tes (ubuntu:22.04)`, `Tes (ubuntu:24.04)`, `Tes (debian:bookworm)`:
    sukses ketiganya.
- `Release` — https://github.com/Iky969/osw-wrapper-linux/actions/runs/39851571901
  - `Tes sebelum rilis (ubuntu:22.04)`, `(ubuntu:24.04)`, `(debian:bookworm)`:
    sukses ketiganya.
  - `Tag & rilis otomatis`: sukses. Langkah `Cek apakah tag sudah ada`
    menemukan `v0.1.2` yang sudah terbit, checksum tag diverifikasi, Release
    lama tidak dibuat ulang, dan langkah `Buat tag dan GitHub Release`
    di-skip sesuai desain.
- Biaya pilihan gate (b): pada push ke `main` matriks tes berjalan dua kali
  (`CI` + `Release`); terlihat pada dua run di atas.

Hasil rilis 0.1.3 (push `868f21d`, 2026-10-22) — **hijau**:

- `CI` — https://github.com/Iky969/osw-wrapper-linux/actions/runs/39853897169
  - `Lint (bash -n & shellcheck)`: sukses (termasuk langkah checksum
    shellcheck).
  - `Tes (ubuntu:22.04)`, `Tes (ubuntu:24.04)`, `Tes (debian:bookworm)`:
    sukses ketiganya.
- `Release` — https://github.com/Iky969/osw-wrapper-linux/actions/runs/39853897286
  - `Tes sebelum rilis (ubuntu:22.04)`, `(ubuntu:24.04)`, `(debian:bookworm)`:
    sukses ketiganya.
  - `Tag & rilis otomatis`: sukses. Langkah: `Baca dan validasi VERSION`
    sukses; `Cek apakah tag sudah ada` sukses (belum ada); `Pastikan checksum
    tag lama masih cocok` skipped; `Pastikan Release untuk tag yang sudah ada`
    skipped; `Buat tag dan GitHub Release` sukses.
- Tag `v0.1.3` = `868f21dc493eda5ed1f7d8a28f74ec058c855268`, dibuat oleh job
  rilis (`gh release create --target`). Release:
  https://github.com/Iky969/osw-wrapper-linux/releases/tag/v0.1.3 — aset
  `install.sh` (13.045 byte) dan `install.sh.sha256` (77 byte); unduhan aset
  lolos `sha256sum -c` dan `DEFAULT_VERSION` di aset = 0.1.3.
- Jalur **push tag** tidak dapat diuji: tag sudah dibuat otomatis oleh run
  push `main`, dan aturan melarang memindahkan/menimpa tag. Percobaan
  `workflow_dispatch` pada ref `v0.1.3` ditolak token (HTTP 403, butuh
  `actions: write`), jadi tidak ada run ber-event tag.

Hasil run CI pertama (push `764b545`, 2026-10-21):

- `bash -n` + `shellcheck -S warning` + `bash tests/run.sh` di runner lolos,
  tetapi 5 tes modul gagal: runner berjalan sebagai non-root, sehingga `_priv`
  menambahkan prefix `sudo ` pada baris `DRY:` (sesuai blueprint) dan string
  yang di-assert tidak cocok.
- **Diperbaiki**: `expect_dry`/`expect_dry_not` di `tests/run.sh` mengabaikan
  prefix `sudo`/`doas`, jadi hasil tes sama untuk root maupun non-root.
- Efek samping: run pertama tersebut menyisakan job berstatus `in_progress`
  padahal run sudah `completed`, dan push berikutnya tidak memunculkan run
  baru. Concurrency tingkat workflow dihapus agar tiap push berdiri sendiri.

Hasil run sukses (push `74e2ed8`):

- seluruh job hijau; job rilis membuat tag `v0.1.0` + Release berisi aset
  `install.sh` dan `install.sh.sha256` (diverifikasi lewat API dan unduhan:
  `sha256sum -c` cocok, mode pipe `releases/latest/download/install.sh`
  memasang 0.1.0 dengan sumber dari tag `v0.1.0`).
- Catatan: daftar run di API GitHub terlambat tampil beberapa menit; tag tetap
  bisa dicek langsung dengan `git ls-remote --tags`.

Hasil run kedua (push `997b086`, `fd48258`):

- job tes hijau di runner non-root setelah `expect_dry`/`expect_dry_not`.
- job rilis berjalan sampai membuat checksum, lalu gagal di `git push` tag:
  `refusing to allow a GitHub App to create or update workflow
  .github/workflows/ci.yml without workflows permission`. `GITHUB_TOKEN`
  memang tidak punya izin `workflows`, dan push ref baru yang memuat file
  workflow ditolak.
- **Diperbaiki**: tag sekarang dibuat lewat GitHub Release API
  (`gh release create --target <sha>`), bukan `git push refs/tags`. Commit-nya
  sudah ada di `main`, jadi pembuatan ref lewat API tidak terkena batasan itu.

### 3. BUG (Fase 1): `osw self-update` 0.1.0 gagal saat menjalankan installer — TERVERIFIKASI & DIPERBAIKI (0.1.1)

- Reproduksi: pasang 0.1.0 dari Release ke direktori sementara, lalu
  `osw -y self-update` → `install.sh: error: dispatcher tidak ditemukan:
  /tmp/bin/osw` (exit 1). Checksum lolos; yang gagal adalah installer.
- Penyebab: `self-update` menjalankan installer dari file sementara
  (`bash "$tmp_installer"`), sehingga `BASH_SOURCE` menunjuk `/tmp` yang tidak
  punya `bin/osw` maupun `os/`. Installer mengira sedang di clone repo, lalu
  preflight menolak.
- Status: **diperbaiki** di `install.sh` — sumber diunduh kalau direktori
  installer tidak memuat `bin/osw` atau `os/`. Regresi dijaga tes
  "installer file tunggal unduh sumber" (network diblokir, harus sampai ke
  "gagal mengunduh", bukan "dispatcher tidak ditemukan").
- Karena `install.sh` berubah, `VERSION` dinaikkan ke **0.1.1** (tag `v0.1.0`
  sudah terbit; memperbarui tag lama akan memutus checksum yang sudah
  diumumkan). Pengguna 0.1.0 perlu sekali menjalankan ulang installer rilis
  0.1.1 karena `self-update` di versi lama tidak bisa memperbaiki dirinya.
- Terverifikasi: CI membuat tag + Release `v0.1.1` (aset checksum cocok), dan
  `osw self-update` dari instalasi 0.1.0 berhasil memasang 0.1.1 (installer
  diunduh dari tag, checksum diverifikasi, sumber diunduh dari tag).

### 4. BUG tampilan (Fase 1): status setelah self-update mencetak versi lama — DIPERBAIKI (0.1.2)

- Reproduksi: setelah `self-update` 0.1.0 → 0.1.1 berhasil, baris
  `osw version : 0.1.0` masih tercetak karena proses yang berjalan memuat
  config lama di awal; config di disk sudah `VERSION=0.1.1`.
- Status: **diperbaiki** di `bin/osw` — config di-`source` ulang setelah
  installer dijalankan, baru `do_status` dipanggil. `VERSION` dinaikkan ke
  **0.1.2** agar perbaikan ini ikut terpasang lewat rilis.
- Terverifikasi: pasang 0.1.2, ubah `VERSION` config sandbox menjadi 0.1.1,
  jalankan `self-update` → installer 0.1.2 terpasang dan status langsung
  mencetak `osw version : 0.1.2` (bukan 0.1.1).
- Rilis `v0.1.2` dibuat otomatis oleh CI (tag di `ef3ed3f`, aset
  `install.sh` + `.sha256` cocok).

Catatan proses: pembuatan run/job Actions di repo ini kadang tertunda
belasan menit (run tetap muncul dan sukses); tag bisa diperiksa langsung
dengan `git ls-remote --tags` tanpa menunggu API.

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

### 2. Bug `_run`, RETURN trap, dan dry-run `self-update` — TERVERIFIKASI & DIPERBAIKI

Commit: `fix: _run, RETURN trap, dan dry-run self-update` (2026-10-22).

- **`_run` (`bin/osw`)** — `local rc=$?` berada setelah `"$@"` yang berada di
  bawah `set -e`, jadi baris itu tidak pernah dieksekusi saat perintah gagal:
  shell mati di dalam `_run` dan `_run` tidak pernah bisa mengembalikan rc
  non-nol. Diganti pola `"$@" || rc=$?` (rc ditangkap eksplisit, `set +x` untuk
  `--debug` selalu dijalankan). Catatan: exit code proses di jalur dispatch
  tetap sama seperti sebelumnya, jadi ini perbaikan struktural/kontrak, bukan
  perubahan hasil yang terlihat dari luar.
- **`trap ... RETURN` (`do_self_update`)** — terbukti: setelah fungsi gagal,
  `trap -p RETURN` masih menampilkan trap, sedangkan `tmp_installer` (variabel
  lokal) sudah hilang. `source`/fungsi berikutnya yang selesai memicu
  `rm -f "$tmp_installer"` dan `set -u` mematikan shell
  (`bash: tmp_installer: unbound variable`, exit 127). Diperbaiki: `trap -
  RETURN` dicabut sebelum setiap `return` (jalur error, kegagalan installer,
  dan jalur normal), `rm -f` tetap dijalankan di semua jalur, rc installer
  tetap diteruskan.
- **`self-update` mengabaikan dry-run** — `bin/osw -n self-update` tetap
  mengunduh dan menjalankan installer. Diperbaiki: `OSW_DRY=1` berhenti sebelum
  `mktemp`/unduhan apa pun. Perilaku pesan (putusan review 2026-10-22):
  `VERSION` upstream dibaca lebih dulu dengan `curl --max-time 5` (read-only)
  supaya URL target yang dicetak benar. Kalau berhasil, pesan berlabel
  `DRY: self-update dari <URL v<VERSION> upstream> (upstream)`; kalau gagal,
  versi lokal dipakai dengan label `(lokal, upstream tidak terjangkau)`.
  Installer tidak pernah diunduh, `mktemp` tidak dipanggil, tidak ada eksekusi.
  Hook pengujian: `OSW_VERSION_URL` menimpa URL `VERSION` (dipakai tes untuk
  arahkan ke `http://127.0.0.1:9` dan ke `file://...`).
- Regresi dijaga 5 tes di `tests/run.sh`: `_run mengembalikan rc & dry-run`,
  `self-update dry-run label offline` (curl asli + `OSW_VERSION_URL` ke alamat
  ditolak: label lokal, tanpa unduhan), `self-update dry-run label upstream`
  (`OSW_VERSION_URL=file://...` berisi `9.9.9`: URL `v9.9.9` + label
  `(upstream)`), `self-update dry-run tanpa unduhan` (curl stub mencatat semua
  pemanggilan: hanya `/main/VERSION`, tidak ada `/install.sh` maupun `-o`),
  dan `self-update mencabut RETURN trap` (`trap -p RETURN` kosong dan `source`
  berikutnya tidak mematikan shell). Empat tes **gagal** kalau dijalankan pada
  `bin/osw` sebelumnya (diverifikasi dengan salinan repo berisi `bin/osw` dari
  `HEAD`); `_run` hanya berbeda secara struktural.
- Belum dirilis: `VERSION` sengaja tidak diubah di commit ini, jadi rilis
  berikutnya perlu menaikkan `VERSION` + `DEFAULT_VERSION` di `install.sh`.

### 3. `VERSION` fallback masih hardcoded (terbuka)

- `bin/osw` memakai `VERSION="0.1.0"` kalau `VERSION` di repo tidak ditemukan
  (instalasi binary tunggal tanpa direktori repo). Nilai itu tidak ikut naik
  saat rilis, sehingga `osw version`/`osw status` bisa melaporkan versi yang
  salah. Belum diperbaiki; perlu sumber versi yang ditanam saat rilis atau
  dibaca dari `os.conf`.
- Per rilis 0.1.3: fallback ini **bukan** sumber mismatch kontrak
  `VERSION` == `DEFAULT_VERSION`. Kontrak itu dibaca dari file `VERSION` di
  root repo (0.1.3) dan `DEFAULT_VERSION` di `install.sh` (0.1.3); fallback
  hanya aktif kalau file `VERSION` tidak ada di sebelah binary (instalasi file
  tunggal), dan itu tetap item terbuka, bukan diubah di commit rilis.

### 4. Deteksi OS terduplikasi (terbuka)

- `detect_os`/`detect_os_name` ada di `bin/osw` dan `install.sh` dengan daftar
  family yang sama. Risikonya bisa berbeda tanpa ketahuan; `tests/run.sh` baru
  membandingkan perilaku lewat beberapa ID, belum seluruh daftar. Belum
  diperbaiki karena butuh keputusan arsitektur (installer harus tetap bisa
  berdiri sendiri tanpa `bin/osw`).

### 5. Cakupan uji belum lengkap

- `tests/run.sh` berisi 67 tes hermetik: 19 tes Fase 0-2, 1 tes regresi
  self-update, 5 tes regresi `_run`/`RETURN` trap/dry-run, 21 tes Fase 3,
  11 tes modul Fase 4-7, 5 tes kontrak/smoke Fase 8, dan 5 tes rilis (checksum,
  `VERSION` == `DEFAULT_VERSION`, `self-update` memakai tag, installer file
  tunggal mengunduh sumber, kelengkapan workflow).
- `tests/run.sh` sudah berjalan di container `ubuntu:22.04`, `ubuntu:24.04`,
  dan `debian:bookworm` lewat CI (run `5a426d1`). Smoke di container
  Void/Alpine/Gentoo belum dijalankan; lihat `tests/smoke.sh` dan
  `docs/ADDING-OS.md`.
- Belum ada uji nyata `apt-get` dan belum ada uji di OS selain Debian/Ubuntu
  (lingkungan kerja ini Ubuntu 22.04, dijalankan sebagai root di container).
- Mode pipe baru diuji pada jalur gagal (network diblokir via stub/ proxy);
  jalur unduh + install sukses belum diuji.
- Workflow divalidasi lokal (YAML di-parse dengan PyYAML + actionlint 1.7.7
  bersih, `shellcheck` 0 warning) dan run pertama di GitHub hijau: `CI`
  (lint + 3 container) dan `Release` (3 container + job rilis) untuk push
  `5a426d1`, lihat tautan di bagian rilis otomatis.

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
- `fix: _run, RETURN trap, dan dry-run self-update` — `bin/osw` (`_run`,
  `do_self_update`), 3 tes regresi baru di `tests/run.sh` (65 tes total,
  65 lulus; shellcheck 0 warning).
- `fix(self-update): dry-run memakai versi upstream, fallback lokal berlabel` —
  pembacaan `VERSION` upstream dipindah ke awal `do_self_update` dan dipakai
  bersama oleh dry-run dan jalur unduh; pesan `DRY:` tidak lagi menampilkan
  versi lokal tanpa keterangan (66 tes total, 66 lulus; shellcheck 0 warning).
- `chore: catat hasil run CI hijau` — `TODOS.md`: status "hijau di GitHub"
  ditandai setelah run `5a426d1` benar-benar selesai (CI + Release), termasuk
  dua tautan run dan catatan job rilis yang di-skip karena tag sudah ada.
- `ci: verifikasi SHA-256 tarball shellcheck v0.10.0` — langkah shellcheck di
  `ci.yml` memverifikasi hash sebelum ekstraksi; sumber checksum dicatat di
  TODOS (upstream v0.10.0 tidak menerbitkan file checksum). Run `deb80f9`
  hijau: Lint + 3 container.
- `chore(release): v0.1.3` — `VERSION` dan `DEFAULT_VERSION` menjadi 0.1.3,
  `install.sh.sha256` dihitung ulang, item fallback `bin/osw` dicatat sebagai
  terbuka (bukan sumber mismatch). Tes 67 lulus, 0 gagal.
- `ci: tambahkan workflow test dan gate rilis` — `ci.yml` dipecah: job `lint`
  (shellcheck v0.10.0 statis) + job `test` matriks `ubuntu:22.04`,
  `ubuntu:24.04`, `debian:bookworm`; rilis pindah ke `release.yml` dengan job
  `test` sebagai gate (`needs: test`) dan pemicu push tag `v*`. Sekaligus:
  label dry-run `(upstream)` / `(lokal, upstream tidak terjangkau)`,
  `--max-time 5`, hook `OSW_VERSION_URL`, dan 3 tes dry-run baru (67 tes,
  67 lulus; shellcheck 0 warning; actionlint bersih).
