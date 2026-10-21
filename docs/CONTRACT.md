# Kontrak modul `os/*.sh`

Dokumen ini adalah kesepakatan antara dispatcher `bin/osw` dan modul OS. Modul
baru harus memenuhi kontrak ini; `tests/contract.sh` memeriksa bagian yang bisa
diperiksa otomatis.

## Aturan arsitektur

1. `os/*.sh` **di-source** oleh dispatcher, tidak pernah dieksekusi langsung.
   Shebang tetap `#!/usr/bin/env bash` supaya konsisten dan bisa di-shellcheck.
2. Modul **tidak** boleh memakai `set -e`/`set -u`/`set -o pipefail`; mode
   shell diurus dispatcher.
3. Modul **tidak** boleh mem-parse argumen global (`-y`, `-n`, `--debug`, ...)
   atau memakai `getopts`/loop `while [[ $# -gt 0 ]]`. Dispatcher sudah
   membuang flag global dan meneruskan sisanya.
4. Semua aksi yang mengubah sistem lewat `_priv` (root) atau `_run` (tanpa
   root) supaya `--dry-run`, `--yes`, dan `--debug` konsisten.
5. Perintah read-only (`search`, `info`, `list`, `files`, `owner`, `orphans`)
   boleh memanggil binary langsung; jangan lewat `_priv`.
6. Modul tidak boleh memanggil `exit`; kembalikan exit code dari fungsi.
   Pesan error lewat `_err`, info lewat `_info`, peringatan lewat `_warn`.
7. Modul tidak boleh mengetahui nama perintah `osw`; dispatcher yang memetakan
   subcommand ke `pkg_*`.
8. `bin/osw` tidak boleh tahu command package manager per OS. Kalau butuh
   cabang per OS di dispatcher, kontraknya belum bersih.

## Fungsi wajib

Semua modul harus mendefinisikan fungsi berikut. Dispatcher memanggilnya tanpa
fallback, jadi kalau hilang hasilnya `command not found`.

| Fungsi | Argumen | Perilaku |
| --- | --- | --- |
| `pkg_update` | — | Sinkronisasi indeks repo |
| `pkg_upgrade` | — | Upgrade paket terpasang |
| `pkg_full_upgrade` | — | Upgrade penuh (boleh sama dengan `pkg_upgrade` bila OS tidak memisahkan) |
| `pkg_install` | ≥1 nama paket | Pasang paket |
| `pkg_remove` | ≥1 nama paket | Hapus paket |
| `pkg_search` | ≥1 kata kunci | Cari di repo |
| `pkg_info` | ≥1 nama paket | Detail paket |
| `pkg_list` | `""`, `--user`, atau `--repo` | Daftar paket; opsi lain → `_err` + `return 2` |
| `pkg_autoremove` | — | Hapus dependensi tak terpakai; boleh no-op `return 0` bila OS sudah otomatis |
| `pkg_clean` | — | Bersihkan cache paket |

## Fungsi opsional

Boleh tidak didefinisikan. Dispatcher memasang fallback yang mencetak
`fitur <nama> belum didukung untuk OS=<family>` dan `return 3`.

| Fungsi | Argumen | Catatan |
| --- | --- | --- |
| `pkg_files` | ≥1 nama paket | Daftar file milik paket |
| `pkg_owner` | ≥1 path | Paket pemilik path |
| `pkg_orphans` | — | **Wajib read-only**, hanya menampilkan |
| `pkg_autoclean` | — | Bersihkan cache usang |
| `pkg_reinstall` | ≥1 nama paket | Fallback dispatcher: `pkg_remove` lalu `pkg_install` |

Ketersediaan per modul saat ini:

| Fungsi | debian | void | alpine | gentoo | arch |
| --- | --- | --- | --- | --- | --- |
| wajib (10) | ya | ya | ya | ya | ya |
| `pkg_files` | ya | ya | ya | ya (butuh `qlist`) | ya |
| `pkg_owner` | ya | ya | ya | ya (butuh `qfile`) | ya |
| `pkg_orphans` | ya | ya | tidak (3) | ya | ya |
| `pkg_autoclean` | ya | tidak (3) | tidak (3) | tidak (3) | tidak (3) |

`pkg_clean` di Gentoo membutuhkan `eclean-dist`; tanpa itu `return 3`.

## Flag non-interaktif

`OSW_YES=1` (dari `-y`) harus diterjemahkan ke flag aman milik package manager
masing-masing. **Jangan** hardcode `-y` di semua modul: arti `-y` berbeda.

| Modul | Pola |
| --- | --- |
| debian | `local -a yes=(); [[ $OSW_YES == 1 ]] && yes=(-y)` |
| void | sama, `xbps-*` menerima `-y` |
| alpine | `yes=(--no-interactive)` |
| gentoo | `ask=(--ask)` **kecuali** `OSW_YES=1` |
| arch | `noconfirm=(--noconfirm)`, karena `pacman -y` berarti refresh database |

## Exit code

| Kode | Arti |
| --- | --- |
| 0 | Sukses |
| 1 | Argumen salah (mis. `osw install` tanpa paket; `install.sh` gagal preflight) |
| 2 | Subcommand/flag tidak dikenal, atau opsi `pkg_list` tidak valid |
| 3 | Fitur belum didukung untuk OS ini (fallback dispatcher) |
| 4 | Config belum ada (`osw status` dan perintah paket) |

`osw help`, `osw version`, `osw detect` tetap jalan tanpa config.

## Config & path

`bin/osw` dan `install.sh` wajib memakai path yang identik:

```
CONF_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/osw
DATA_DIR=${XDG_DATA_HOME:-$HOME/.local/share}/osw
BIN_DIR=${XDG_BIN_HOME:-$HOME/.local/bin}
CONF=$CONF_DIR/os.conf
```

`os.conf` berisi 4 baris: `OS`, `OS_NAME`, `INSTALLED_AT`, `VERSION`.
`OS` adalah family yang memilih `os/$OS.sh`; `OS_NAME` hanya tampilan dan
ditulis dengan `printf '%q'`. Modul dibaca dari `$DATA_DIR/os/$OS.sh`.

`install.sh --prefix <dir>` hanya memindahkan binary ke `<dir>/bin/osw`; data
dan config tetap XDG karena dispatcher menghitungnya dari XDG.

## Hook pengujian

- `OSW_OS_RELEASE` (default `/etc/os-release`) mengganti file os-release yang
  dibaca `bin/osw` dan `install.sh`, supaya deteksi bisa diuji tanpa menyentuh
  `/etc`.
- `OSW_UPSTREAM_REPO` / `OSW_UPSTREAM_REF` mengganti repo/ref unduhan installer
  mode pipe (default ref: tag `v<DEFAULT_VERSION>`, fallback `main`).
  `self-update` hanya memakai `OSW_UPSTREAM_REPO`; installernya selalu diambil
  dari tag `v<VERSION>`.
- Variabel `OSW_*` lain (`OSW_YES`, `OSW_DRY`, `OSW_QUIET`, `OSW_NO_COLOR`,
  `OSW_DEBUG`) diurus dispatcher dan diwariskan ke modul.

## Tes

```sh
bash tests/contract.sh              # semua modul
bash tests/contract.sh os/void.sh   # satu modul
bash tests/smoke.sh --stub          # semua modul, binari palsu
```

`tests/contract.sh` memeriksa shebang, 10 fungsi wajib, larangan `set -e`, dan
larangan parser argumen di modul. `tests/smoke.sh` memasang ke sandbox lalu
menjalankan setiap subcommand dengan `OSW_DRY=1 OSW_YES=1`; exit 3 hanya
diterima untuk fitur opsional.
