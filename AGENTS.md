# AGENTS.md

Aturan tetap untuk siapa pun (manusia atau agen) yang mengubah repo ini.

## Sumber kebenaran

- `blueprint.md` — rencana fase, tujuan, fungsi yang harus ada, dan tabel uji.
- `TODOS.md` — status fase saat ini (implementasi dan uji). **Wajib diperbarui**
  setiap kali satu langkah selesai.
- `docs/archive/` — disebut di beberapa instruksi kerja, tetapi **tidak ada** di
  repo ini per 2026-10-21. Jangan menganggapnya ada; kalau nanti ditambahkan,
  baca isinya dulu dan samakan dengan `blueprint.md`.
- `VERSION` — satu baris, sumber versi untuk dispatcher dan `install.sh`.

## Alur kerja

1. Satu fase atau satu perbaikan = satu commit.
2. Format pesan commit: `feat(faseN): ringkasan singkat`, perbaikan:
   `fix(area): ringkasan singkat`, persiapan: `chore: ringkasan singkat`.
3. Jangan mengerjakan fase lain di commit yang sama.
4. Jangan mengubah perilaku fase yang sudah selesai, kecuali untuk memperbaiki
   bug. Bug yang diperbaiki di luar fase harus disebut eksplisit di pesan commit.
5. Jangan memperbaiki bug yang belum terbukti: verifikasi dulu (tes atau reproduksi
   minimal), baru ubah kode.
6. Setiap commit `fix` atau `feat` **wajib** menambahkan satu baris
   `[NOTICE] update <versi> <ringkasan>` ke `CHANGELOG.md` (entri terbaru di
   paling atas). Versi yang dipakai adalah versi tujuan rilis berikutnya. Commit
   tanpa entri changelog dianggap belum selesai.

## Rilis: pemasangan tag

Tag rilis `v<versi>` hanya boleh dibuat pada commit yang memenuhi **ketiganya**:

1. Membawa `VERSION` **dan** `DEFAULT_VERSION` di `install.sh` yang sama dengan
   tag (mis. tag `v0.1.5` → `VERSION` 0.1.5 dan `DEFAULT_VERSION="0.1.5"`).
2. CI-nya hijau **pada commit itu** (run `CI` untuk SHA tersebut, bukan commit
   lain di sekitarnya). Kalau gagal karena infrastruktur, jalankan ulang CI di
   commit yang sama sampai hijau.
3. Pohon commit itu memuat **semua** baris `[NOTICE] update <versi>` yang
   berkaitan dengan versi tersebut di `CHANGELOG.md` — tidak boleh ada
   perbaikan versi itu yang baru masuk di commit setelahnya.

Larangan:

- **Jangan** memasang tag di commit yang versinya sudah naik tetapi perbaikannya
  belum masuk (commit versi mendahului commit perbaikan). Kalau urutan commit
  terbalik, perbaiki urutannya dulu — tag bukan alat untuk menambal urutan yang
  salah.
- **Jangan** memindahkan atau menimpa tag yang sudah ada (`git tag -f`,
  `git push --force` tag, menghapus lalu membuat ulang tag yang sama). Tag yang
  sudah terbit bersifat tetap; kalau isinya salah, terbitkan versi baru.

## Verifikasi wajib setelah mengubah kode

```sh
bash -n bin/osw install.sh os/*.sh tests/run.sh
shellcheck -S warning bin/osw install.sh os/*.sh tests/run.sh
bash tests/run.sh
```

- Laporkan hasil apa adanya. Jangan klaim sebuah fase lulus kalau tes belum
  dijalankan dan hijau.
- Jangan menambah `disable=` baru di `.shellcheckrc` tanpa alasan tertulis di
  pesan commit.
- Tes harus hermetik: `HOME` dan semua `XDG_*` diarahkan ke direktori sementara,
  tanpa root, tanpa `apt`, tanpa network. Perintah paket hanya boleh diuji dengan
  `-n`/`OSW_DRY=1`.

## Perintah berbahaya

- `apt-get install/remove/autoremove/upgrade` **tanpa** `-n` hanya boleh
  dijalankan di VM atau container sekali pakai.
- Di lingkungan lain selalu gunakan `--dry-run` atau `osw -n`.
- Jangan pernah mengedit rc file (`~/.bashrc`, `~/.zshrc`) secara otomatis;
  cetak saran saja.

## Arsitektur yang harus dijaga

- `bin/osw` adalah dispatcher. Ia **tidak boleh** tahu command paket per OS;
  semua aksi lewat fungsi `pkg_*`.
- `os/*.sh` adalah modul yang di-`source`, bukan dieksekusi. Modul tidak mem-parse
  flag global; `OSW_YES`/`OSW_DRY`/`OSW_DEBUG` diurus dispatcher.
- Semua aksi paket lewat `_priv`/`_run` supaya mode `--dry-run`, `--yes`, dan
  `--debug` konsisten.
- Variabel path (`CONF_DIR`, `DATA_DIR`, `BIN_DIR`, `CONF`) harus identik antara
  `bin/osw` dan `install.sh`.
