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
| 3 | `install.sh` | **belum** (masih stub 2 baris) | belum ada |
| 4 | `os/void.sh` | belum | — |
| 5 | `os/alpine.sh` | belum | — |
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

## Item terbuka

### 1. BUG (Fase 1): `osw self-update` selalu gagal — TERVERIFIKASI, belum diperbaiki

- Verifikasi statis:
  `grep -n expected_sha bin/osw` →
  `372:    if [[ -z "$expected_sha" ]]; then` (pemakaian) dan
  `399:    local expected_sha=""` (deklarasi, jauh setelahnya).
- Verifikasi runtime: dengan `os.conf` valid, `osw self-update` keluar `rc=1`
  dengan `bin/osw: line 372: expected_sha: unbound variable`.
- Dampak: `self-update` berhenti sebelum mengunduh apa pun; verifikasi SHA-256 di
  blok sesudahnya juga tidak pernah menjadi wajib.
- Status: **belum diperbaiki**. Dijadwalkan sebagai commit `fix(...)` terpisah,
  bukan dicampur ke commit fase.

### 2. Cakupan uji belum lengkap

- Fase 8 (`tests/smoke.sh`, `tests/contract.sh`, 4 container) belum dikerjakan.
  `tests/run.sh` saat ini memuat tes Fase 0-2 (+ Fase 3 nanti) dan dirancang agar
  bisa ditambah.
- Belum ada uji nyata `apt-get` dan belum ada uji di OS selain Debian/Ubuntu
  (lingkungan kerja ini Ubuntu 22.04, dijalankan sebagai root di container).

## Riwayat langkah

- `chore: tambahkan AGENTS.md, TODOS.md, tests/run.sh` — harness hermetik + 19
  tes Fase 0-2 (19 lulus).
- Fase 3 (`install.sh`) — belum dikerjakan.
