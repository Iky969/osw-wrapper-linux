# osw — One Simple Wrapper

**Different distros. Same commands.**

Satu perintah package manager untuk Debian/Ubuntu, Void, Alpine, Gentoo, dan
Arch. `osw` mendeteksi *family* OS sekali saat instalasi, lalu memilih modul
`os/<family>.sh`; perintah yang tidak didukung di suatu OS ditolak dengan exit
code 3, bukan ditebak.

```sh
osw update && osw -y upgrade
osw install neovim git curl
osw search ripgrep
```

## Instalasi

### Cara tercepat (rilis terbaru)

```sh
curl -fsSL https://github.com/Iky969/osw-wrapper-linux/releases/latest/download/install.sh | bash
```

Installer dijalankan lewat pipe: ia mengunduh snapshot repo **dari tag rilis**
(lihat `DEFAULT_VERSION` di `install.sh`) ke direktori sementara, menyalin
dispatcher + modul, menulis config, lalu melakukan self-test. Override sumber
dengan `OSW_UPSTREAM_REPO` / `OSW_UPSTREAM_REF` (mis. `OSW_UPSTREAM_REF=main`
untuk kode pengembangan).

### Dengan verifikasi checksum (disarankan)

```sh
V=$(curl -fsSL https://raw.githubusercontent.com/Iky969/osw-wrapper-linux/main/VERSION)
curl -fsSLO "https://github.com/Iky969/osw-wrapper-linux/releases/download/v$V/install.sh"
curl -fsSLO "https://github.com/Iky969/osw-wrapper-linux/releases/download/v$V/install.sh.sha256"
sha256sum -c install.sh.sha256
bash install.sh
```

Setiap tag rilis berisi `install.sh` + `install.sh.sha256` yang dibuat oleh CI,
jadi keduanya selalu sinkron. `osw self-update` juga menolak installer yang
checksum-nya tidak tersedia atau tidak cocok.

### Dari clone repo

```sh
git clone https://github.com/Iky969/osw-wrapper-linux.git
cd osw-wrapper-linux
bash install.sh
```

### Yang dipasang

Installer tidak pernah memanggil package manager dan tidak mengubah rc file.

| Isi | Lokasi |
| --- | --- |
| Dispatcher | `${XDG_BIN_HOME:-~/.local/bin}/osw` |
| Modul `os/*.sh` | `${XDG_DATA_HOME:-~/.local/share}/osw/os/` |
| Config | `${XDG_CONFIG_HOME:-~/.config}/osw/os.conf` |

Opsi installer:

```
--os <name>      Paksa modul (debian, void, alpine, gentoo, arch)
--redetect       Deteksi ulang family OS dan perbarui INSTALLED_AT
--prefix <dir>   Binary ke <dir>/bin/osw (data & config tetap XDG)
--no-path-hint   Jangan cetak saran PATH
--uninstall      Hapus instalasi
-y, --yes        Tanpa konfirmasi (untuk --uninstall)
-h, --help       Bantuan
```

Kalau `~/.local/bin` belum ada di `PATH`, installer hanya mencetak saran
`export PATH=...`; tambahkan sendiri ke `~/.bashrc`/`~/.zshrc`.

## Cara menggunakan

Bentuk umum: `osw [FLAGS] <command> [args...]`.

```sh
osw install neovim git   # pasang paket
osw -y upgrade           # upgrade tanpa prompt
osw search ripgrep       # cari paket
osw info neovim          # detail paket
osw list --user          # paket yang dipasang manual
```

| Perintah | Arti |
| --- | --- |
| `update` | Sinkronkan indeks paket |
| `upgrade` | Upgrade paket yang sudah terpasang |
| `full-upgrade` | Upgrade penuh (termasuk perubahan dependensi) |
| `install <pkg>...` | Pasang paket |
| `remove <pkg>...` | Hapus paket (beserta dependensi tak terpakai di Arch) |
| `reinstall <pkg>...` | `remove` lalu `install` (fallback dispatcher) |
| `search <query>...` | Cari paket |
| `info <pkg>...` | Info paket |
| `list [--user\|--repo]` | Daftar paket terpasang / manual / repo |
| `files <pkg>...` | File milik paket |
| `owner <path>...` | Paket pemilik path |
| `autoremove` | Hapus dependensi tak terpakai |
| `orphans` | Daftar paket yatim (read-only) |
| `clean` | Bersihkan cache paket |
| `autoclean` | Bersihkan cache usang |
| `status` | Status instalasi, config, dan PATH |
| `detect` | Deteksi ulang family OS dan simpan ke config |
| `self-update` | Perbarui osw dari tag rilis upstream |
| `uninstall` | Hapus instalasi osw |
| `version` | Versi osw + OS aktif |
| `help [command]` | Bantuan umum / per subcommand |

Flag global:

| Flag | Arti |
| --- | --- |
| `-y`, `--yes` | Tanpa prompt (diterjemahkan ke flag non-interaktif tiap package manager) |
| `-n`, `--dry-run` | Cetak `DRY: ...` tanpa eksekusi |
| `-q`, `--quiet` | Kurangi output informasi |
| `--no-color` | Nonaktifkan warna |
| `--debug` | `set -x` saat menjalankan perintah |
| `-h`, `--help`, `-v`, `--version` | Bantuan / versi |

Exit code: `0` sukses, `1` argumen salah, `2` subcommand/flag tidak dikenal,
`3` fitur tidak didukung untuk OS ini, `4` config belum ada (jalankan
`install.sh`).

Contoh alur pemakaian:

```sh
# 1. Periksa dulu apa yang akan dijalankan
osw -n install neovim

# 2. Kalau cocok, jalankan sungguhan
osw -y install neovim

# 3. Cari tahu paket apa yang memiliki sebuah file
osw owner /usr/bin/curl

# 4. Bersih-bersih setelah upgrade
osw -y autoremove && osw clean
```

### Update osw

```sh
osw self-update
```

`self-update` membaca `VERSION` di branch `main`, lalu mengunduh `install.sh`
dan `install.sh.sha256` dari tag `v<VERSION>`, mencocokkan SHA-256, baru
menjalankannya. Tidak ada jalur "paksa tanpa checksum": kalau file `.sha256`
tidak ada atau tidak cocok, pembaruan dibatalkan dengan exit code 1.

> Versi 0.1.0 rusak di langkah ini (`dispatcher tidak ditemukan: /tmp/bin/osw`).
> Kalau Anda masih di 0.1.0, jalankan sekali installer rilis terbaru
> (perintah "Cara tercepat" di atas) — setelah itu `self-update` berfungsi.

### Uninstall

```sh
osw uninstall      # tanya konfirmasi, lalu tanya soal config
osw -y uninstall   # tanpa konfirmasi
```

Atau lewat installer (juga menghapus binary kalau dipasang dengan `--prefix`
kustom):

```sh
bash install.sh --uninstall -y
```

### Config

`os.conf` berisi 4 baris dan aman di-`source`:

```
OS=debian
OS_NAME=Debian\ GNU/Linux\ 12\ \(bookworm\)
INSTALLED_AT=2026-10-21T06:01:13Z
VERSION=0.1.2
```

- `OS` adalah *family* yang dipakai memilih `os/$OS.sh`. Nilainya hanya
  dideteksi dari `ID` di `/etc/os-release` saat config belum ada atau dengan
  `--redetect`/`osw detect`; selama config ada, nilai tersimpan dipakai.
- `OS_NAME` hanya untuk tampilan (`PRETTY_NAME`, fallback `NAME`, lalu
  `unknown`), di-escape dengan `printf '%q'`, dan tidak pernah dipakai memilih
  modul.

## OS yang didukung

| Family | `ID` di os-release | Package manager | Modul |
| --- | --- | --- | --- |
| debian | debian, ubuntu, mint, linuxmint, pop, kali | apt/dpkg | `os/debian.sh` |
| void | void | XBPS | `os/void.sh` |
| alpine | alpine | apk | `os/alpine.sh` |
| gentoo | gentoo, funtoo | Portage | `os/gentoo.sh` |
| arch | arch, manjaro, endeavouros | pacman | `os/arch.sh` |

Pemetaan perintah:

| Perintah `osw` | debian | void | alpine | gentoo | arch |
| --- | --- | --- | --- | --- | --- |
| `update` | `apt-get update` | `xbps-install -S` | `apk update` | `emerge --sync` | `pacman -Sy` |
| `upgrade` | `apt-get upgrade` | `xbps-install -u` | `apk upgrade` | `emerge -uDN @world` | `pacman -Su` |
| `full-upgrade` | `apt-get full-upgrade` | `xbps-install -Su` | `apk upgrade` | `emerge -uDN @world` | `pacman -Syu` |
| `install` | `apt-get install` | `xbps-install` | `apk add` | `emerge` | `pacman -S` |
| `remove` | `apt-get remove` | `xbps-remove` | `apk del` | `emerge --unmerge` | `pacman -Rns` |
| `search` | `apt-cache search` | `xbps-query -Rs` | `apk search` | `emerge --search` | `pacman -Ss` |
| `info` | `apt-cache show` | `xbps-query -R` | `apk info -a` | `qlist -Iv` / `emerge -pv` | `pacman -Si` |
| `list` | `dpkg -l` | `xbps-query -l` | `apk info` | `qlist -I` / isi `/var/db/pkg` | `pacman -Q` |
| `list --user` | `apt-mark showmanual` | `xbps-query -m` | tidak didukung (3) | `/var/lib/portage/world` | `pacman -Qe` |
| `files` | `dpkg -L` | `xbps-query -f` | `apk info -L` | `qlist` | `pacman -Ql` |
| `owner` | `dpkg -S` | `xbps-query -o` | `apk info --who-owns` | `qfile` | `pacman -Qo` |
| `autoremove` | `apt-get autoremove` | `xbps-remove -o` | no-op (apk sudah bersih) | `emerge -p/--depclean` | `pacman -Qtdq` + `-Rns` |
| `orphans` | `apt-get -s autoremove` | `xbps-query -O` | tidak didukung (3) | `emerge -p --depclean` | `pacman -Qtdq` |
| `clean` | `apt-get clean` | `xbps-remove -O` | `apk cache clean` | `eclean-dist --deep` | `pacman -Sc` |
| `autoclean` | `apt-get autoclean` | tidak didukung (3) | tidak didukung (3) | tidak didukung (3) | tidak didukung (3) |

Flag non-interaktif berbeda per package manager dan **tidak** selalu `-y`:
Debian/Void memakai `-y`; Alpine `--no-interactive`; Gentoo menambahkan
`--ask` kecuali `OSW_YES=1`; Arch memakai `--noconfirm` karena `-y` di pacman
berarti refresh database.

Butuh `qlist`, `qfile`, `eclean-dist` (Gentoo: `app-portage/portage-utils`,
`app-portage/gentoolkit`) untuk `files`, `owner`, dan `clean`; tanpa itu
perintah mengembalikan 3.

## Tes

```sh
bash -n bin/osw install.sh os/*.sh tests/*.sh
shellcheck -S warning bin/osw install.sh os/*.sh tests/*.sh
bash tests/run.sh            # semua tes hermetik
bash tests/contract.sh       # kontrak fungsi tiap modul
bash tests/smoke.sh --stub   # semua modul, binari package manager palsu
bash tests/smoke.sh --os debian  # dry-run dengan binari asli host
```

Tes hermetik: `HOME` dan semua `XDG_*` diarahkan ke direktori sementara, tanpa
root, tanpa apt, tanpa network. `tests/run.sh` juga menjaga `VERSION` ==
`DEFAULT_VERSION` dan `install.sh.sha256` tetap cocok dengan `install.sh`.
Smoke di container nyata (Debian, Void, Alpine, Gentoo) belum dijalankan
otomatis; lihat `docs/ADDING-OS.md`.

## Rilis otomatis (CI)

Model rilis: **tag-driven (model B)**. Rilis hanya dipicu push tag
`v<VERSION>`; workflow rilis tidak berjalan pada push ke `main`, tidak membuat
tag, dan tidak mendorong commit apa pun.

`.github/workflows/ci.yml` — pada setiap push ke `main` dan pull request:

1. **Lint** — `bash -n` dan shellcheck v0.10.0; tarball shellcheck diverifikasi
   SHA-256 sebelum ekstraksi.
2. **Tes** — matriks container `ubuntu:22.04`, `ubuntu:24.04`,
   `debian:bookworm`, menjalankan `tests/run.sh` (hermetik).

`.github/workflows/release.yml` — hanya pada push tag `v*`, dengan job `test`
(matrisk sama) sebagai gate `needs: test`:

- menolak ref selain tag, dan menolak kalau nama tag ≠ `v$VERSION`;
- menolak kalau `VERSION` bukan `X.Y.Z` atau `DEFAULT_VERSION` di `install.sh`
  ≠ `VERSION`;
- memverifikasi `install.sh.sha256` terhadap `install.sh` di commit tag, dan
  gagal kalau tidak cocok;
- menerbitkan GitHub Release untuk tag tersebut dengan `--verify-tag` (aset:
  `install.sh` + `install.sh.sha256`), atau melewatinya kalau Release sudah
  ada.

Cara merilis versi baru:

```sh
# 1. Naikkan versi di dua tempat (harus sama) dan hitung checksum
printf '0.2.0\n' > VERSION
# ubah DEFAULT_VERSION="0.1.4" -> "0.2.0" di install.sh
sha256sum install.sh > install.sh.sha256

# 2. Commit dan push ke main
git add VERSION install.sh install.sh.sha256 TODOS.md
git commit -m "chore(release): v0.2.0"
git push origin main

# 3. Tunggu CI hijau pada commit itu, baru buat dan push tag
git tag v0.2.0 <commit-yang-hijau>
git push origin v0.2.0
```

Aturan penting: **tag tidak boleh menunjuk commit yang belum lulus CI**.
Push tag memicu `release.yml`; kalau gate tes atau validasi gagal, Release
tidak terbit. Selama tag belum terbit, `install.sh` versi baru tetap bisa
dipakai lewat clone repo; mode pipe akan memberi tahu bahwa tag `v<versi>`
belum ada lalu memakai `main`.

Catatan:

- Tag dibuat manusia (`git tag`/`git push`), bukan CI. Job rilis hanya memakai
  tag yang sudah ada (`gh release create --verify-tag`), jadi tidak ada izin
  `workflows` yang dibutuhkan dan tag tidak pernah dipindahkan.
- `install.sh.sha256` harus sudah benar di commit yang diberi tag; kalau tidak,
  job rilis berhenti sebelum menerbitkan Release.
- Kalau Release perlu dibuat ulang, jalankan ulang job dari tab Actions pada run
  tag yang sama; tidak perlu membuat tag baru.

## Pemecahan masalah

- **`osw: command not found`** — `~/.local/bin` belum ada di `PATH`. Tambahkan
  `export PATH="$HOME/.local/bin:$PATH"` ke rc file Anda (installer tidak
  mengubahnya otomatis), lalu buka shell baru.
- **Exit code 4** — config belum ada; jalankan `install.sh`.
- **Exit code 3** — perintah itu memang tidak didukung modul OS Anda (lihat
  tabel di atas).
- **`self-update` menolak dengan "checksum SHA-256 tidak tersedia"** — tag
  rilis belum punya `install.sh.sha256`, atau `VERSION` di `main` menunjuk
  versi yang belum dirilis. Tunggu CI selesai atau pasang ulang lewat
  installer.
- **OS terdeteksi salah** — jalankan `osw detect` (atau `install.sh --redetect`),
  atau paksa dengan `install.sh --os <family>`.

## Lapor bug

Buka issue di <https://github.com/Iky969/osw-wrapper-linux/issues> dan
sertakan:

- keluaran `osw version` dan `osw status`;
- isi `/etc/os-release`;
- perintah persisnya, misal `osw -n install foo`, plus keluaran `--debug`;
- yang diharapkan vs yang terjadi.

Jangan menyertakan perintah destruktif tanpa `-n`/`--dry-run` di laporan.
Untuk bug modul, sebutkan nama file `os/<family>.sh` dan fungsi `pkg_*` yang
bermasalah.

## Lisensi

MIT — lihat [LICENSE](LICENSE).
