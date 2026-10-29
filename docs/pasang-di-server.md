# Memasang portal reslab-csub.cloud di server

Portal adalah halaman statis di domain utama `https://reslab-csub.cloud` yang menjadi pintu
masuk ke dua aplikasi yang sudah berjalan di VPS yang sama:

```
reslab-csub.cloud        → portal (file statis, /srv/portal/site)      ← panduan ini
www.reslab-csub.cloud    → 301 ke reslab-csub.cloud
iot.reslab-csub.cloud    → IoT Platform  (IoT_platform/docs/deploy-vps.md)
mqtt.reslab-csub.cloud   → MQTT Client   (mqtt_client/docs/deploy.md)
```

Tidak ada proses, database, atau port baru. Nginx yang sudah ada cukup diberi satu
konfigurasi tambahan, dan certbot satu sertifikat baru.

Perkiraan waktu: 20–30 menit, ditambah menunggu DNS.

## Prinsip keamanan

| Keputusan | Alasan |
|---|---|
| Halaman statis tanpa JavaScript, cookie, form, atau CDN | tidak ada kode yang berjalan di server maupun browser yang bisa diserang. CSP bisa dibuat sangat ketat (`default-src 'none'`) |
| File milik `root`, Nginx hanya bisa membaca | celah di Nginx pun tidak bisa mengubah isi situs |
| Hanya `GET`/`HEAD`; berkas tersembunyi (`.git`, `.env`) selalu 404 | |
| HSTS tanpa `includeSubDomains` dulu | header ini di domain utama berlaku untuk SEMUA subdomain; aktifkan setelah yakin (bagian 8) |
| Tidak ada konten dari pengguna di domain utama | domain utama dan subdomain dianggap *same-site* oleh browser. Halaman di domain utama yang bisa disisipi skrip bisa ikut menyerang `iot.` dan `mqtt.` |
| Record DNS CAA, SPF dan DMARC | hanya Let's Encrypt yang boleh menerbitkan sertifikat; domain tidak bisa dipakai memalsukan email |

## Isi folder

```
portal/
├── site/                        yang dipasang ke /srv/portal/site
│   ├── index.html               halaman utama
│   ├── 404.html                 halaman "tidak ditemukan"
│   ├── favicon.svg, robots.txt
│   ├── assets/portal.css, assets/logo.svg
│   └── .well-known/security.txt kontak pelaporan celah keamanan (RFC 9116)
├── deploy/
│   ├── nginx/portal-http.conf   tahap awal (sebelum sertifikat)
│   ├── nginx/portal.conf        konfigurasi akhir (HTTPS + header keamanan)
│   ├── scripts/publish.sh       menyalin site/ ke /srv/portal/site dengan izin yang benar
│   └── scripts/update.sh        git pull lalu publish.sh (pembaruan rutin, bagian 9)
└── docs/pasang-di-server.md     panduan ini
```

Mengubah teks halaman: edit `site/index.html` (dan `site/assets/portal.css` untuk tampilan),
lalu jalankan ulang `publish.sh` (bagian 9). Jangan menambahkan `<script>`, atribut
`style="…"`, atau gambar/font dari situs lain: CSP akan memblokirnya.

---

## 1. DNS

Di pengelola DNS domain `reslab-csub.cloud`, buat:

| Type | Name | Value | Keterangan |
|---|---|---|---|
| A | `@` | IP VPS (sama dengan `iot.`) | domain utama |
| A | `www` | IP VPS | atau `CNAME www → reslab-csub.cloud` |
| CAA | `@` | `0 issue "letsencrypt.org"` | hanya Let's Encrypt yang boleh menerbitkan sertifikat (berlaku juga untuk `iot.` dan `mqtt.`) |
| CAA | `@` | `0 issuewild ";"` | sertifikat wildcard `*.reslab-csub.cloud` dilarang |

Bila **tidak ada** email yang dikirim dengan alamat `@reslab-csub.cloud` (platform mengirim
email lewat akun Gmail/Brevo dengan alamat lain), tambahkan juga:

| Type | Name | Value |
|---|---|---|
| TXT | `@` | `v=spf1 -all` |
| TXT | `_dmarc` | `v=DMARC1; p=reject;` |

Artinya: tidak ada server yang berhak mengirim email atas nama domain ini, jadi email palsu
`…@reslab-csub.cloud` ditolak penerima. Bila suatu saat platform mengirim email **dari**
`@reslab-csub.cloud` (mis. lewat Brevo/SES dengan domain terverifikasi), ganti SPF sesuai
petunjuk layanan itu sebelum mulai mengirim.

Periksa dari laptop (perubahan DNS bisa butuh beberapa menit sampai beberapa jam):

```bash
dig +short reslab-csub.cloud          # ✔ IP VPS
dig +short www.reslab-csub.cloud      # ✔ IP VPS (atau nama CNAME lalu IP)
dig +short iot.reslab-csub.cloud      # ✔ IP yang sama
dig +short CAA reslab-csub.cloud      # ✔ 0 issue "letsencrypt.org" ...
```

Port 80 dan 443 sudah terbuka untuk IoT Platform; tidak ada perubahan firewall.

## 2. Mengambil kode ke server

Semua perintah dijalankan di server sebagai user admin dengan `sudo` (atau sebagai `root`,
tanpa `sudo`).

**Cara 1 — git** (disarankan bila folder `portal` sudah menjadi repository di GitHub):

```bash
sudo install -d -o root -g root -m 755 /srv/portal
sudo git clone https://github.com/NAMA/portal.git /srv/portal/repo
# repository privat: pakai deploy key read-only seperti di panduan platform (7.2),
# dengan kunci milik root, lalu git@github.com:NAMA/portal.git
```

**Cara 2 — salin dari Mac** (tanpa repository online):

```bash
# di Mac, dari folder iot_platform_project:
rsync -av --exclude .git --exclude .DS_Store --exclude .claude-tmp \
      -e "ssh -i ~/.ssh/iot-server" portal/ ubuntu@IP-VPS:/tmp/portal/
# di server:
sudo install -d -o root -g root -m 755 /srv/portal
sudo rm -rf /srv/portal/repo && sudo mv /tmp/portal /srv/portal/repo && sudo chown -R root:root /srv/portal/repo
```

`/srv/portal/repo` hanya sumber. Yang dilayani Nginx adalah `/srv/portal/site` (langkah 3);
folder repo tidak pernah bisa dibuka dari web.

## 3. Mengisi kontak keamanan dan memasang halaman

`security.txt` memberi tahu orang yang menemukan celah keamanan ke mana harus melapor. Ganti
baris `Contact` dengan email pengelola (atau tautan formulir):

```bash
sudo nano /srv/portal/repo/site/.well-known/security.txt
#   Contact: mailto:alamat-pengelola@contoh.ac.id
#   Expires: paling lama 1 tahun ke depan
```

Lalu pasang:

```bash
sudo /srv/portal/repo/deploy/scripts/publish.sh
# ✔ Published 7 files to /srv/portal/site
sudo ls -lR /srv/portal/site | head -20     # ✔ milik root, -rw-r--r--
```

`publish.sh` menolak berjalan bila `Contact` masih contoh atau `Expires` sudah lewat. Ia
menyalin `site/` ke folder baru lalu menukarnya dengan `/srv/portal/site`, jadi pengunjung tidak
pernah melihat situs setengah jadi.

Bila folder repo berasal dari git (cara 1), perubahan `security.txt` ini adalah perubahan
lokal. Agar `git pull` berikutnya tidak bentrok, lebih baik ubah file itu di Mac, commit, lalu
`git pull` di server.

## 4. Nginx tahap HTTP

```bash
sudo cp /srv/portal/repo/deploy/nginx/portal-http.conf /etc/nginx/sites-available/portal
sudo ln -s /etc/nginx/sites-available/portal /etc/nginx/sites-enabled/portal
sudo nginx -t && sudo systemctl reload nginx
curl -s http://reslab-csub.cloud/ ; echo        # ✔ reslab-csub.cloud: HTTPS is not set up yet.
```

Folder `/var/www/certbot` sudah dibuat di panduan platform. Bila belum ada:
`sudo mkdir -p /var/www/certbot`.

## 5. Sertifikat HTTPS

Satu sertifikat untuk dua nama (domain utama dan `www`). Uji dulu dengan `--dry-run`:

```bash
sudo certbot certonly --webroot -w /var/www/certbot \
     -d reslab-csub.cloud -d www.reslab-csub.cloud \
     --email email-anda@contoh.com --agree-tos --no-eff-email --dry-run
# berhasil? jalankan lagi TANPA --dry-run
sudo certbot certonly --webroot -w /var/www/certbot \
     -d reslab-csub.cloud -d www.reslab-csub.cloud \
     --email email-anda@contoh.com --agree-tos --no-eff-email
sudo ls /etc/letsencrypt/live/reslab-csub.cloud/    # ✔ fullchain.pem, privkey.pem
```

Perpanjangan otomatis (`certbot.timer`) dan hook reload Nginx sudah dipasang di panduan
platform; keduanya berlaku untuk sertifikat ini juga.

## 6. Nginx akhir (HTTPS dan header keamanan)

```bash
sudo cp /srv/portal/repo/deploy/nginx/portal.conf /etc/nginx/sites-available/portal
sudo nginx -t && sudo systemctl reload nginx
```

Konfigurasi ini:

- mengalihkan `http://` dan `https://www.` ke `https://reslab-csub.cloud`;
- melayani file dari `/srv/portal/site`, hanya `GET`/`HEAD`;
- mengirim header keamanan (tabel di bagian 7);
- menyimpan CSS/gambar di cache browser 1 hari, HTML selalu diperiksa ulang.

## 7. Pemeriksaan

Dari laptop:

```bash
# pengalihan
curl -sI http://reslab-csub.cloud/        | grep -iE "^HTTP|^location"   # ✔ 301 → https://reslab-csub.cloud/
curl -sI https://www.reslab-csub.cloud/x  | grep -iE "^HTTP|^location"   # ✔ 301 → https://reslab-csub.cloud/x

# halaman dan header
curl -sI https://reslab-csub.cloud/ | grep -iE "^HTTP|strict-transport|content-security|x-content-type|referrer|permissions|cross-origin"

# yang harus DITOLAK
curl -s -o /dev/null -w "%{http_code}\n" https://reslab-csub.cloud/.git/config       # ✔ 404
curl -s -o /dev/null -w "%{http_code}\n" https://reslab-csub.cloud/tidak-ada          # ✔ 404 (halaman 404 portal)
curl -s -o /dev/null -w "%{http_code}\n" -X POST https://reslab-csub.cloud/            # ✔ 405

# security.txt
curl -s https://reslab-csub.cloud/.well-known/security.txt                            # ✔ Contact: … email asli

# aplikasi lain tetap normal
curl -s -o /dev/null -w "%{http_code}\n" https://iot.reslab-csub.cloud/accounts/login/  # ✔ 200
curl -s -o /dev/null -w "%{http_code}\n" https://mqtt.reslab-csub.cloud/                # ✔ 200
```

Header yang harus muncul pada `https://reslab-csub.cloud/`:

| Header | Nilai |
|---|---|
| `Strict-Transport-Security` | `max-age=31536000` |
| `Content-Security-Policy` | `default-src 'none'; style-src 'self'; img-src 'self'; font-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'` |
| `X-Content-Type-Options` | `nosniff` |
| `Referrer-Policy` | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | `camera=(), microphone=(), …` |
| `Cross-Origin-Opener-Policy` / `Cross-Origin-Resource-Policy` | `same-origin` |

Penilaian dari luar:

- [securityheaders.com](https://securityheaders.com/?q=reslab-csub.cloud) → target **A** atau
  **A+**;
- [SSL Labs](https://www.ssllabs.com/ssltest/analyze.html?d=reslab-csub.cloud) → target **A**.

Di browser: buka `https://reslab-csub.cloud`, tekan F12 → tab **Console**. Tidak boleh ada
pesan *Content Security Policy* atau berkas yang gagal dimuat. Coba juga tema gelap
(pengaturan tampilan sistem) dan layar ponsel.

## 8. HSTS untuk semua subdomain (nanti, opsional)

Sekarang HSTS dikirim:

- oleh portal untuk `reslab-csub.cloud` saja (tanpa `includeSubDomains`);
- oleh IoT Platform dan MQTT Client untuk subdomain masing-masing (`DJANGO_HSTS_SECONDS`).

`includeSubDomains` di domain utama membuat browser memaksa HTTPS di **setiap**
`*.reslab-csub.cloud` selama `max-age`, termasuk subdomain yang dibuat nanti. Aktifkan hanya bila
semua subdomain pasti HTTPS:

```nginx
set $portal_hsts "max-age=31536000; includeSubDomains";
```

Tambahan `; preload` lalu mendaftar di hstspreload.org memasukkan domain ke daftar bawaan
browser. Langkah ini **sulit dibatalkan** (keluar dari daftar butuh berbulan-bulan), jadi
lewati kecuali benar-benar diperlukan.

## 9. Memperbarui halaman

**Cara 1 (git):** commit dan push dari Mac, lalu di server cukup satu perintah:

```bash
sudo /srv/portal/repo/deploy/scripts/update.sh
# ==> git pull     (hanya fast-forward; menampilkan commit yang baru masuk)
# ==> publish      (publish.sh dari versi yang baru ditarik)
# Done (1c34d7e).
```

Bila `deploy/nginx/portal.conf` ikut berubah, `update.sh` menulis *NOTE: … differs …*.
Pasang dengan:

```bash
sudo /srv/portal/repo/deploy/scripts/update.sh --nginx
```

`--nginx` menyalin konfigurasi, menjalankan `nginx -t`, lalu reload. Bila tes gagal,
konfigurasi lama dikembalikan dan Nginx tidak di-reload, jadi situs tetap jalan.

Bila `git pull` gagal dengan *Not possible to fast-forward*, ada file yang diubah langsung di
server (mis. `security.txt`). Lihat dengan `sudo git -C /srv/portal/repo status`, kembalikan
dengan `sudo git -C /srv/portal/repo checkout -- <file>`, lalu ubah file itu di Mac saja.

**Cara 2 (rsync):** ulangi rsync di langkah 2, lalu `publish.sh` (`update.sh` hanya untuk
folder hasil `git clone`).

Perubahan langsung terlihat (HTML tidak di-cache). Perubahan CSS bisa butuh hingga 1 hari di
browser yang sudah pernah membuka halaman; tekan **Cmd+Shift+R** / **Ctrl+F5** untuk melihatnya
segera.

Setahun sekali, sebelum tanggal `Expires` di `security.txt` lewat, perbarui tanggal itu (di Mac,
commit, push), lalu jalankan `update.sh`.

## 10. Pemecahan masalah

| Gejala | Penyebab / perbaikan |
|---|---|
| `certbot`: *Timeout* / *Invalid response* | DNS `@` atau `www` belum mengarah ke VPS (`dig +short`), atau langkah 4 belum dikerjakan |
| `certbot`: *CAA record … prevents issuance* | record CAA salah ketik; harus `0 issue "letsencrypt.org"` |
| `nginx -t`: *cannot load certificate … reslab-csub.cloud* | `portal.conf` dipasang sebelum sertifikat terbit; kembali ke `portal-http.conf`, kerjakan langkah 5 |
| Browser: *connection reset* / sertifikat salah nama | `server_name` tidak cocok sehingga tertangkap server *default* milik platform (yang menolak host tak dikenal); cek `sudo nginx -T \| grep -n "server_name reslab-csub.cloud"` |
| Halaman tanpa tampilan (tanpa CSS) | file belum dipasang atau izinnya salah: jalankan ulang `publish.sh`; cek `curl -sI https://reslab-csub.cloud/assets/portal.css` → 200 |
| `403 Forbidden` | Nginx tidak bisa membaca `/srv/portal/site`: `sudo chmod 755 /srv/portal /srv/portal/site` (publish.sh mengatur ini) |
| `publish.sh`: *Edit … security.txt first* | baris `Contact` masih contoh (langkah 3) |
| `publish.sh`: *the Contact line must be a URI* | tulis `Contact: mailto:nama@contoh.ac.id`, bukan alamat email saja |
| `update.sh`: *is not a git clone* | folder repo disalin dengan rsync; pakai cara 2 di bagian 9, atau clone ulang (langkah 2, cara 1) |
| `update.sh`: *Not possible to fast-forward* | ada perubahan lokal di server (bagian 9) |
| Console browser: *Refused to … Content Security Policy* | ada skrip/gaya inline atau sumber dari luar di HTML; pindahkan ke `assets/` |

Log: `sudo tail -f /var/log/nginx/access.log /var/log/nginx/error.log`.

## 11. Daftar periksa

- [ ] DNS: `@` dan `www` ke IP VPS; CAA `letsencrypt.org`; SPF/DMARC bila tidak mengirim email.
- [ ] `security.txt` berisi kontak asli dan `Expires` di masa depan.
- [ ] `https://reslab-csub.cloud` tampil; `http://` dan `www` dialihkan.
- [ ] securityheaders.com A/A+, SSL Labs A.
- [ ] `/.git/config` → 404, `POST /` → 405.
- [ ] `iot.` dan `mqtt.` tetap berjalan normal.
