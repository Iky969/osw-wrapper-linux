# osw

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
VERSION=0.1.0
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

`.github/workflows/ci.yml` punya dua job:

1. **Tes hermetik** — `bash -n`, `shellcheck -S warning`, `tests/run.sh`,
   `tests/smoke.sh --stub`, `tests/contract.sh` pada setiap push ke `main` dan
   setiap pull request.
2. **Tag & rilis otomatis** — hanya pada push ke `main` (atau
   `workflow_dispatch`), setelah job tes hijau. Langkahnya:
   - memvalidasi `VERSION` berbentuk `X.Y.Z`;
   - menolak rilis kalau `DEFAULT_VERSION` di `install.sh` ≠ `VERSION`;
   - kalau tag `v<VERSION>` belum ada: menulis `install.sh.sha256`,
     meng-commit-nya (`chore: checksum installer v<VERSION> [skip ci]`), lalu
     menerbitkan GitHub Release yang sekaligus membuat tag `v<VERSION>`
     (aset: `install.sh` + `install.sh.sha256`);
   - kalau tag sudah ada: memastikan checksum yang di-commit masih cocok, dan
     gagal dengan pesan "naikkan VERSION" kalau `install.sh` berubah tanpa
     kenaikan versi.

Jadi cara merilis versi baru cukup:

```sh
# 1. Naikkan versi di DUA tempat (harus sama)
printf '0.2.0\n' > VERSION
# ubah DEFAULT_VERSION="0.1.0" -> "0.2.0" di install.sh

# 2. Perbarui TODOS.md, commit, lalu push ke main
git add -A
git commit -m "chore: rilis v0.2.0"
git push origin main
```

CI yang membuat tag, checksum, dan Release. Selama tag belum terbit,
`install.sh` versi baru tetap bisa dipakai lewat clone repo; mode pipe akan
memberi tahu bahwa tag `v<versi>` belum ada lalu memakai `main`.

Catatan:

- Job rilis butuh `permissions: contents: write`. Kalau branch `main` diproteksi,
  izinkan GitHub Actions (atau bot) untuk push commit checksum, atau jalankan
  workflow secara manual dari tab Actions (`workflow_dispatch`).
- Tag dibuat lewat GitHub Release API, bukan `git push refs/tags`. Alasannya:
  `GITHUB_TOKEN` adalah GitHub App tanpa izin `workflows`, sehingga push tag
  yang commit-nya memuat `.github/workflows/` ditolak dengan pesan
  `refusing to allow a GitHub App to create or update workflow`. Membuat ref
  lewat API tidak terkena batasan itu karena commit-nya sudah ada di `main`.
- Rilis manual (tanpa CI) tetap mungkin, tetapi urutannya wajib: checksum
  di-commit **sebelum** tag dibuat.

  ```sh
  sha256sum install.sh > install.sh.sha256
  git add install.sh.sha256
  git commit -m "chore: checksum installer v$(cat VERSION)"
  git tag -a "v$(cat VERSION)" -m "osw v$(cat VERSION)"
  git push origin main "v$(cat VERSION)"
  ```

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
