FASE 0 — Kerangka repo

Tujuan: folder kosong + file kosong, belum ada isi.

1. Buat folder osw/
2. Di dalam: bin/, os/, tests/ (opsional), install.sh, README.md, .shellcheckrc, VERSION
3. VERSION isi 1 baris: 0.1.0
4. .shellcheckrc isi disable=SC1090,SC1091 (karena kita source file dinamis)
5. Semua file .sh dan bin/osw → chmod +x, pakai shebang #!/usr/bin/env bash
6. Tentukan nama final dulu (osw sudah dikonfirmasi) dan prefix config: ~/.config/osw/, ~/.local/share/osw/

Output fase ini: tree repo kosong, tanpa kode. Selesai kalau find osw -type f menampilkan struktur.

---

FASE 1 — bin/osw (dispatcher, inti)

Tujuan: satu file yang bisa dijalankan, help/version hidup, tapi semua subcommand masih stub. Jangan sentuh install.sh dan os/*.sh dulu.

Kerjakan per poin, tes di poin tertentu:

1. Header — shebang, set -euo pipefail, PROJECT=osw, baca VERSION dari file relatif ke $0 (pakai readlink -f)
   → tes: ./bin/osw version cetak 0.1.0
2. Resolusi path — definisikan CONF_DIR, DATA_DIR, BIN_DIR pakai ${XDG_*:-default}; CONF="$CONF_DIR/os.conf"
3. Flag global parser — while [[ $# -gt 0 ]]; kenali -y|--yes, -n|--dry-run, -q|--quiet, --no-color, --debug; sisanya push ke array POSITIONAL_ARGS. Setelah loop, set -- "${POSITIONAL_ARGS[@]}" dan cmd="${1:-help}"; shift || true
   → tes: ./bin/osw --debug install foo → OSW_DEBUG=1, cmd=install, $@=foo
4. Helper _run — kalau OSW_DRY=1 print DRY: ..., kalau OSW_DEBUG=1 set -x sebelum eksekusi, lalu "$@"
5. Helper _priv — EUID 0 → _run "$@"; else sudo ada → _run sudo "$@"; else doas ada → _run doas "$@"; else error return 1
   → tes: ./bin/osw --dry-run install x di non-root → print DRY: sudo apt-get ... (nanti setelah modul ada)
6. Helper _need_args — kalau $# -lt 1 → error + saran osw help $cmd, exit 1
7. Cek config — kalau $CONF gak ada → pesan "jalankan install.sh dulu", exit 4
8. Source config → source modul OS — source "$CONF" dapat OS=; OSFILE="$DATA_DIR/os/$OS.sh"; cek ada → source
   → tes: buat manual ~/.config/osw/os.conf berisi OS=debian, buat stub ~/.local/share/osw/os/debian.sh kosong → ./bin/osw help jalan
9. Fallback fungsi (SETELAH source) —
   · pkg_reinstall → definisikan kalau belum ada, isi: pkg_remove "$@" && pkg_install "$@"
   · loop pkg_files pkg_owner pkg_orphans pkg_autoclean → kalau belum ada, definisikan stub return 3 dengan pesan OS=$OS
     → tes: modul kosong, ./bin/osw files foo → exit 3 dengan pesan jelas
10. usage() — heredoc cat <<'EOF' berisi daftar perintah + flag + 4-5 contoh. Jangan cetak OS di sini, biar statis. (Ambil dari blueprint FASE sebelumnya.)
11. usage_cmd() — case "${1:-}" in — cabang pertama "") usage ;;, lalu per subcommand satu baris, *) → error + return 2
12. do_version — cetak osw $VERSION + OS=$OS kalau config ada
13. do_status — cetak: versi osw, OS dari config, INSTALLED_AT dari config, path config, path data, cek $BIN_DIR di $PATH (⚠ kalau tidak ada)
14. do_detect — salin logika detect_os (nanti di fase install.sh) ke sini juga, tapi jangan duplikat — pakai source dari file bersama lib/detect.sh (opsi A) atau tulis inline (opsi B, lebih simpel untuk 1 file). Untuk awal: inline. Tulis ulang OS= ke $CONF, cetak hasil
15. do_self_update — curl -fsSL <URL install.sh> | bash (URL hardcode di konstanta UPSTREAM_URL di header). Setelah itu panggil do_status
16. do_uninstall — konfirmasi kecuali -y; hapus $DATA_DIR, $BIN_DIR/osw; tanya dulu mau hapus $CONF_DIR atau simpan
17. case "$cmd" dispatcher — semua cabang, exit code konsisten: sukses 0, arg salah 1, tidak dikenal 2, fitur belum didukung 3, config hilang 4. *) → pesan + usage >&2 + exit 2

Output fase ini: osw help, osw version, osw status, osw detect fungsional. Semua subcommand paket masih "belum didukung" (karena modul belum ada). Ini titik commit pertama.

---

FASE 2 — os/debian.sh (modul pertama, paling gampang dites)

Tujuan: modul lengkap untuk apt (Ubuntu/Debian/Mint/Pop/Kali). Kerjakan per fungsi, tes tiap fungsi di VM/container Debian.

1. Header — shebang, komentar "modul ini di-source, bukan dieksekusi", gak ada set -e (ikut dispatcher)
2. Pola flag -y — tiap fungsi pakai local -a yes=(); [[ ${OSW_YES:-0} == 1 ]] && yes=(-y). Jangan hardcode -y
3. pkg_update — _priv apt-get update
4. pkg_upgrade — _priv apt-get upgrade "${yes[@]}"
5. pkg_full_upgrade — _priv apt-get full-upgrade "${yes[@]}"
6. pkg_install — _priv apt-get install "${yes[@]}" "$@"
7. pkg_remove — _priv apt-get remove "${yes[@]}" "$@"
8. pkg_search — apt-cache search "$@" (gak perlu priv)
9. pkg_info — apt-cache show "$@" (gak perlu priv)
10. pkg_list — default dpkg -l; kalau $1 == --user → apt-mark showmanual; kalau --repo → apt list --installed
11. pkg_files — dpkg -L "$@"
12. pkg_owner — dpkg -S "$@" (tangkap error "no path found")
13. pkg_autoremove — _priv apt-get autoremove "${yes[@]}"
14. pkg_orphans (read-only) — apt-mark showauto lalu filter yang gak dipakai; simpelnya: comm -23 <(apt-mark showauto|sort) <(apt-mark showmanual|sort) — verifikasi manual di Debian
15. pkg_clean — _priv apt-get clean
16. pkg_autoclean — _priv apt-get autoclean

Tes modul (di Debian container/VM):

· OSW_DRY=1 osw install neovim → print DRY: sudo apt-get install neovim (tanpa -y)
· OSW_DRY=1 OSW_YES=1 osw install neovim → print dengan -y
· osw search neovim, osw info neovim, osw files neovim, osw owner /usr/bin/vim → output benar
· osw orphans → daftar (tidak menghapus apa pun)
· osw autoremove tanpa -y → apt minta konfirmasi (bukan auto)

Output fase ini: debian.sh lolos semua tes. Commit kedua.

---

FASE 3 — install.sh (final, deploy)

Tujuan: file bootstrap yang dipanggil via curl | bash. Sekarang modul sudah ada, jadi bisa dites end-to-end.

1. Header — shebang, set -euo pipefail, PROJECT=osw, SRC=readlink -f
2. Vars — CONF_DIR, DATA_DIR, BIN_DIR, CONF (sama seperti dispatcher — samakan persis)
3. detect_os — source /etc/os-release, case mapping: alpine→alpine, void→void, gentoo/funtoo→gentoo, debian/ubuntu/mint/pop/kali→debian, arch→arch (opsional), else unknown
4. Parser argumen install.sh — --os <name> (override detect), --redetect (paksa detect ulang meski sudah ada config), --prefix <dir> (default ~/.local), --no-path-hint (jangan cetak saran PATH), --uninstall, -h|--help
5. Preflight — OS unknown → exit 1 dengan daftar OS didukung; file os/$OS.sh gak ada → exit 1 dengan "modul belum tersedia"; $SRC/os/$OS.sh wajib ada
6. Deploy modul — mkdir -p "$DATA_DIR/os"; cp -f "$SRC"/os/*.sh "$DATA_DIR/os/"; jangan copy yang gak perlu
7. Deploy dispatcher — install -m 755 "$SRC/bin/osw" "$BIN_DIR/osw"
8. Tulis config — printf 'OS=%s\nINSTALLED_AT=%s\nVERSION=%s\n' ke $CONF (3 baris, biar do_status bisa baca VERSION)
9. PATH hint — cek $BIN_DIR di $PATH; kalau tidak, cetak saran export PATH="$HOME/.local/bin:$PATH" + baris untuk ~/.bashrc / ~/.zshrc — jangan edit rc file otomatis (surprise bagi user)
10. Self-test post-install — panggil "$BIN_DIR/osw" version dan "$BIN_DIR/osw" status sekali untuk verifikasi; kalau gagal → exit 1
11. Mode --uninstall — delegate ke osw uninstall kalau $BIN_DIR/osw ada

Tes fase ini:

· Di Debian container: bash install.sh → config tertulis OS=debian, ~/.local/bin/osw ada, osw version jalan
· bash install.sh --uninstall → bersih
· Di Arch (kalau nanti modulnya ada): bash install.sh --os debian → paksa deploy modul debian (untuk tes)
· Di OS unknown (misal macOS) → exit 1 dengan pesan jelas

Output fase ini: instalasi end-to-end jalan di 1 OS. Commit ketiga.

---

FASE 4 — os/void.sh

Kerjakan sama persis urutannya dengan FASE 2, ganti command:

1. Header (sama)
2. Pola flag -y: void pakai xbps-install -y, xbps-remove -y → tetap local -a yes dengan -y
3. pkg_update → _priv xbps-install -S
4. pkg_upgrade → _priv xbps-install -u "${yes[@]}"
5. pkg_full_upgrade → _priv xbps-install -Su "${yes[@]}" (sync + upgrade, Void gak punya full terpisah; beri komentar jelas)
6. pkg_install → _priv xbps-install "${yes[@]}" "$@"
7. pkg_remove → _priv xbps-remove "${yes[@]}" "$@"
8. pkg_search → xbps-query -Rs "$@"
9. pkg_info → xbps-query -R "$@"
10. pkg_list → xbps-query -l; --user → filter manual (Void gak punya konsep manual-install yang sama; beri komentar)
11. pkg_files → xbps-query -f "$@"
12. pkg_owner → xbps-query -o "$@"
13. pkg_autoremove → _priv xbps-remove -o "${yes[@]}"
14. pkg_orphans → xbps-query -O (read-only)
15. pkg_clean → _priv xbps-remove -O
16. pkg_autoclean → tidak ada padanan → jangan definisikan, biar fallback return 3 di dispatcher yang tangani

Tes di Void: sama dengan FASE 2, sesuaikan command. Titik commit keempat.

---

FASE 5 — os/alpine.sh

1. Header (sama)
2. Pola flag -y: apk pakai --no-interactive atau -y? → Alpine pakai apk add -y sebenarnya tidak ada; yang ada --no-interactive. Jadi local -a yes=(); [[ $OSW_YES == 1 ]] && yes=(--no-interactive)
3. pkg_update → _priv apk update
4. pkg_upgrade → _priv apk upgrade "${yes[@]}"
5. pkg_full_upgrade → tidak ada padanan terpisah → alias pkg_upgrade (beri komentar)
6. pkg_install → _priv apk add "${yes[@]}" "$@"
7. pkg_remove → _priv apk del "${yes[@]}" "$@"
8. pkg_search → apk search "$@"
9. pkg_info → apk info -a "$@" (atau apk show di versi baru)
10. pkg_list → apk info / apk list --installed (beda Alpine version — pilih yang stabil)
11. pkg_files → apk info -L "$@"
12. pkg_owner → apk info --who-owns "$@"
13. pkg_autoremove → return 0 no-op + echo "apk otomatis bersih saat apk del" (sesuai catatan audit)
14. pkg_orphans → jangan definisikan → fallback return 3 dari dispatcher (tepat: Alpine gak punya konsep orphan eksplisit)
15. pkg_clean → _priv apk cache clean
16. pkg_autoclean → tidak ada → jangan definisikan

Tes di Alpine container (docker run -it alpine). Titik commit kelima.

---

FASE 6 — os/gentoo.sh

Perhatian khusus: emerge banyak yang destruktif → selalu -p (pretend) dulu kecuali OSW_YES=1.

1. Header (sama)
2. Pola flag: Gentoo gak butuh -y; yang relevan --ask atau langsung. Pakai local -a yes=(); [[ $OSW_YES == 0 ]] && yes=(--ask) → default ask, -y menghilangkan ask
3. pkg_update → _priv emerge --sync
4. pkg_upgrade → _priv emerge -uDN @world "${yes[@]}" (sesuai audit)
5. pkg_full_upgrade → _priv emerge -uDN @world "${yes[@]}" (sama; beri komentar "di Gentoo upgrade & full identik di praktik")
6. pkg_install → _priv emerge "${yes[@]}" "$@"
7. pkg_remove → _priv emerge --unmerge "${yes[@]}" "$@" (jangan --depclean di sini)
8. pkg_search → emerge --search "$@"
9. pkg_info → emerge --info "$@" (atau qlist -Iv)
10. pkg_list → qlist -I kalau app-portage/portage-utils terpasang; kalau tidak, ls /var/db/pkg/*/* fallback
11. pkg_files → qlist "$@" (butuh portage-utils)
12. pkg_owner → qfile "$@" (butuh portage-utils) — kalau tidak ada, return 3
13. pkg_autoremove → WAJIB pretend dulu: _priv emerge -p --depclean; kalau OSW_YES=1 baru _priv emerge --depclean
14. pkg_orphans → emerge -p --depclean (read-only, sesuai audit)
15. pkg_clean → _priv eclean-dist --deep — cek dulu command -v eclean-dist, kalau tidak ada return 3
16. pkg_autoclean → tidak ada → jangan definisikan

Tes di Gentoo container/stage3. Titik commit keenam.

---

FASE 7 — os/arch.sh (opsional, terakhir)

Kalau mau ditambah, minimal kontrak sama. Pemetaan: pacman -Sy (update), pacman -Su (upgrade), pacman -Syu (full), pacman -S (install), pacman -Rns (remove), pacman -Ss (search), pacman -Si (info), pacman -Q (list), pacman -Ql (files), pacman -Qo (owner), pacman -Sc (clean), pacman -Qtdq | pacman -Rns - (autoremove), pacman -Qtdq (orphans). Titik commit ketujuh, hanya kalau perlu.

---

FASE 8 — Testing lintas OS

Tujuan: verifikasi kontrak dipenuhi 4 modul.

1. Buat tests/smoke.sh — untuk tiap cmd di daftar blueprint, jalankan OSW_DRY=1 OSW_YES=1 osw <cmd> → assert exit 0 atau 3 (fitur belum didukung), jangan assert output spesifik (beda OS)
2. Buat tests/contract.sh — verifikasi tiap modul mendefinisikan semua fungsi wajib: pkg_install pkg_remove pkg_update pkg_upgrade pkg_full_upgrade pkg_search pkg_info pkg_list pkg_autoremove pkg_clean. Untuk pkg_files pkg_owner pkg_orphans pkg_autoclean boleh tidak ada
3. Jalankan shellcheck bin/osw install.sh os/*.sh → 0 warning (kecuali SC1090/SC1091 yang disabled)
4. Jalankan di 4 container: debian:stable, voidlinux/voidlinux, alpine:latest, gentoo/stage3 — satu skrip, 4 target
5. Jangan jalankan perintah destruktif (autoremove, remove) tanpa OSW_DRY=1 di container tes

Titik commit kedelapan.

---

FASE 9 — Dokumentasi & rilis

1. README.md — 4 bagian: install via curl, osw help, daftar OS didukung + tabel pemetaan (dari audit), cara lapor bug
2. docs/CONTRACT.md — kontrak fungsi per OS (wajib vs opsional), exit code, flag global, supaya orang lain bisa kontribusi modul baru tanpa baca kode
3. docs/ADDING-OS.md — checklist untuk tambah modul baru (copy os/debian.sh, ganti command, tes dengan OSW_DRY=1)
4. Tag v0.1.0 di GitHub; siapkan install.sh di URL raw.githubusercontent.com/<user>/osw/v0.1.0/install.sh (pin ke tag, bukan main, biar install reproducible)
5. do_self_update di dispatcher pakai URL tag terbaru, bukan main

Titik commit kesembilan.

---

Ringkasan urutan & titik commit

Fase Modul Prasyarat Titik commit
0 Skeleton — —
1 bin/osw (stub modul) 0 feat: dispatcher skeleton
2 os/debian.sh 1 feat: debian module
3 install.sh final 1, 2 feat: installer
4 os/void.sh 3 feat: void module
5 os/alpine.sh 4 feat: alpine module
6 os/gentoo.sh 5 feat: gentoo module
7 os/arch.sh (opsional) 6 feat: arch module
8 tests/ + shellcheck 2–7 test: smoke + contract
9 README + docs + rilis 8 v0.1.0

Aturan main saat mengerjakan:

· Satu modul OS = satu sesi kerja, jangan campur
· Tiap modul dites dulu dengan OSW_DRY=1 sebelum eksekusi nyata
· bin/osw tidak boleh tahu command paket — semua lewat pkg_*. Kalau kamu tergoda nambah case khusus OS di dispatcher, berhenti, itu tanda kontraknya belum bersih
· os/*.sh tidak boleh parse flag sendiri; flag global diurus dispatcher, sisanya diteruskan utuh
