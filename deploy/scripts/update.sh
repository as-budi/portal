#!/bin/bash
# Memperbarui portal di server dari GitHub (jalankan sebagai root atau dengan sudo):
#   sudo /srv/portal/repo/deploy/scripts/update.sh            # pull + pasang halaman
#   sudo /srv/portal/repo/deploy/scripts/update.sh --nginx    # juga pasang ulang konfigurasi Nginx
#
# Urutan: git pull (hanya fast-forward) -> publish.sh (salin site/ ke /srv/portal/site)
#         -> [--nginx] salin portal.conf, nginx -t, reload (dikembalikan bila tes gagal).
# Bila satu langkah gagal, skrip berhenti dan situs lama tetap tampil.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
NGINX_SITE=/etc/nginx/sites-available/portal
WITH_NGINX=0
[ "${1:-}" = "--nginx" ] && WITH_NGINX=1

[ "$(id -u)" = 0 ] || { echo "Run as root: sudo $0 $*" >&2; exit 1; }
[ -d "$REPO/.git" ] || { echo "$REPO is not a git clone. Copy the files again (docs/pasang-di-server.md, step 2)." >&2; exit 1; }

echo "==> git pull"
before=$(git -C "$REPO" rev-parse --short HEAD)
git -C "$REPO" pull --ff-only
after=$(git -C "$REPO" rev-parse --short HEAD)
if [ "$before" = "$after" ]; then
  echo "    already up to date ($after)"
else
  git -C "$REPO" log --oneline "$before..$after" | sed 's/^/    /'
fi

echo "==> publish"
# Dijalankan dari repo yang BARU ditarik, jadi perubahan publish.sh ikut terpakai.
"$REPO/deploy/scripts/publish.sh"

if [ "$WITH_NGINX" = 1 ]; then
  echo "==> nginx"
  cp "$NGINX_SITE" "$NGINX_SITE.bak"
  cp "$REPO/deploy/nginx/portal.conf" "$NGINX_SITE"
  if nginx -t; then
    systemctl reload nginx
    echo "    nginx reloaded (previous config: $NGINX_SITE.bak)"
  else
    cp "$NGINX_SITE.bak" "$NGINX_SITE"
    echo "nginx -t failed: the previous config was restored, nginx was NOT reloaded." >&2
    exit 1
  fi
elif [ -f "$NGINX_SITE" ] && ! cmp -s "$REPO/deploy/nginx/portal.conf" "$NGINX_SITE"; then
  echo "NOTE: deploy/nginx/portal.conf differs from $NGINX_SITE."
  echo "      Run again with --nginx to install it (only after the certificate exists, step 5)."
fi
echo "Done ($after)."
