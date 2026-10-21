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
| 2 | `os/debian.sh` | selesai (16 fungsi) | otomatis: hanya mode `-n` (dry-run); **eksekusi apt nyata belum diuji** |
| 3 | `install.sh` | selesai (11 poin blueprint + config 4 baris) | otomatis: 21 tes Fase 3; mode pipe lewat network belum diuji |
| 4 | `os/void.sh` | selesai (14 fungsi) | otomatis: mode `-n` untuk semua aksi + `autoclean` -> 3; **XBPS nyata belum diuji** |
| 5 | `os/alpine.sh` | selesai (13 fungsi) | otomatis: mode `-n`, `autoremove` no-op, `orphans`/`autoclean`/`list --user` -> 3; **apk nyata belum diuji** |
| 6 | `os/gentoo.sh` | belum | — |
| 7 | `os/arch.sh` (opsional) | belum | — |
| 8 | Tes lintas OS (`smoke.sh`, `contract.sh`) | belum | — |
| 9 | README, docs, rilis | belum (`README.md` baru 1 baris) | — |

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

16 fungsi ada (update, upgrade, full-upgrade, install, remove, search, info, list,
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

- `tests/run.sh` berisi 41 tes hermetik: 19 tes Fase 0-2, 1 tes regresi
  self-update, dan 21 tes Fase 3.
- Fase 8 (`tests/smoke.sh`, `tests/contract.sh`, 4 container) belum dikerjakan.
  `tests/run.sh` dirancang agar bisa ditambah.
- Belum ada uji nyata `apt-get` dan belum ada uji di OS selain Debian/Ubuntu
  (lingkungan kerja ini Ubuntu 22.04, dijalankan sebagai root di container).
- Mode pipe baru diuji pada jalur gagal (network diblokir via proxy); jalur
  unduh + install sukses belum diuji.

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
- Berikutnya: Fase 6 (`os/gentoo.sh`).
