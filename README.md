# Portal reslab-csub.cloud

Halaman statis di domain utama `https://reslab-csub.cloud`, pintu masuk ke dua aplikasi lab yang
berjalan di VPS yang sama:

| Alamat | Aplikasi | Repo |
|---|---|---|
| `https://reslab-csub.cloud` | portal ini | `portal` |
| `https://iot.reslab-csub.cloud` | IoT Platform | `IoT_platform` |
| `https://mqtt.reslab-csub.cloud` | MQTT Client | `mqtt_client` |

Sengaja **tanpa** JavaScript, cookie, form, backend, dan sumber dari luar (CDN, Google Fonts),
sehingga Content-Security-Policy bisa `default-src 'none'`. Tema gelap mengikuti pengaturan
sistem (`prefers-color-scheme`).

- Isi halaman: `site/index.html`, tampilan: `site/assets/portal.css`.
- Memasang di server: [docs/pasang-di-server.md](docs/pasang-di-server.md).

## Melihat di laptop

```bash
python3 -m http.server 8080 -d site
# buka http://127.0.0.1:8080
```

Server sederhana ini tidak mengirim header keamanan (CSP dan lainnya); header itu diatur di
`deploy/nginx/portal.conf` di server.

## Aturan saat mengubah halaman

- Jangan menambah `<script>`, atribut `style="…"`, `<form>`, atau gambar/font dari situs lain:
  CSP memblokirnya. Taruh CSS dan gambar di `site/assets/`.
- Jangan menaruh apa pun yang diisi pengguna di domain utama (lihat alasan di panduan pasang).
- Setahun sekali perbarui `Expires` di `site/.well-known/security.txt`.
