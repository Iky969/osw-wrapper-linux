# osw

Wrapper package manager Linux dengan satu perintah untuk Debian/Ubuntu, Void,
Alpine, Gentoo, dan Arch. `osw` mendeteksi *family* OS sekali saat instalasi,
lalu memilih modul `os/<family>.sh`; perintah yang tidak didukung di suatu OS
ditolak dengan exit code 3, bukan ditebak.

```
osw update && osw -y upgrade
osw install neovim git curl
osw search ripgrep
```

## Instalasi

### Dari rilis (URL dipin ke tag)

```sh
curl -fsSLO https://raw.githubusercontent.com/Iky969/osw-wrapper-linux/v0.1.0/install.sh
curl -fsSLO https://raw.githubusercontent.com/Iky969/osw-wrapper-linux/v0.1.0/install.sh.sha256
sha256sum -c install.sh.sha256
bash install.sh
```

Atau langsung tanpa menyimpan file (mode pipe; installer mengunduh snapshot
repo ke direktori sementara):

```sh
curl -fsSL https://raw.githubusercontent.com/Iky969/osw-wrapper-linux/v0.1.0/install.sh | bash
```

> Selama fase pengembangan belum ada tag rilis, jadi gunakan cara di bawah.
> Mode pipe membutuhkan `curl`, `tar`, dan network.

### Dari clone repo

```sh
git clone https://github.com/Iky969/osw-wrapper-linux.git
cd osw-wrapper-linux
bash install.sh
```

Installer tidak pernah memanggil package manager dan tidak mengubah rc file.
Yang dipasang:

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

## Penggunaan

```
osw [FLAGS] <command> [args...]

install <pkg>...      remove <pkg>...       reinstall <pkg>...
update                upgrade               full-upgrade
search <query>...     info <pkg>...         list [--user|--repo]
files <pkg>...        owner <path>...       autoremove
orphans               clean                 autoclean
status                detect                self-update
uninstall             version               help [command]
```

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

Contoh:

```sh
osw --dry-run install neovim     # lihat perintah yang akan dijalankan
osw -y autoremove                # tanpa konfirmasi
osw list --user                  # paket yang dipasang manual
osw orphans                      # read-only
osw detect                       # deteksi ulang family OS
osw self-update                  # unduh installer bertag + verifikasi SHA-256
```

`self-update` mengambil `VERSION` dari `main`, lalu mengunduh
`install.sh` dan `install.sh.sha256` dari tag `v<VERSION>`. Checksum **wajib**
ada dan cocok; kalau tidak, pembaruan dibatalkan.

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

`reinstall` selalu memakai fallback dispatcher: `remove` lalu `install`.

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
root, tanpa apt, tanpa network. Smoke di container nyata (Debian, Void, Alpine,
Gentoo) belum dijalankan otomatis; lihat `docs/ADDING-OS.md`.

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

## Rilis

Rilis dipin ke tag supaya instalasi reproducible:

```sh
# pastikan VERSION = versi yang akan dirilis
sha256sum install.sh > install.sh.sha256
git add install.sh.sha256
git commit -m "chore: checksum installer v$(cat VERSION)"
git tag -a "v$(cat VERSION)" -m "osw v$(cat VERSION)"
git push origin "v$(cat VERSION)"
```

`install.sh.sha256` wajib ikut tag: `osw self-update` menolak menjalankan
installer yang checksum-nya tidak tersedia atau tidak cocok.

## Lisensi

MIT — lihat [LICENSE](LICENSE).
