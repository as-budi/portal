#!/bin/bash
# Memasang / memperbarui file portal di server (jalankan sebagai root atau dengan sudo):
#   sudo /srv/portal/repo/deploy/scripts/publish.sh
# Menyalin folder site/ ke /srv/portal/site: pemilik root, folder 755, file 644
# (Nginx hanya bisa MEMBACA). Isi lama diganti utuh, jadi file yang dihapus dari site/
# juga hilang dari server.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$REPO/site"
DEST=/srv/portal/site

[ "$(id -u)" = 0 ] || { echo "Run as root: sudo $0" >&2; exit 1; }
[ -f "$SRC/index.html" ] || { echo "Missing $SRC/index.html" >&2; exit 1; }

# security.txt: alamat kontak wajib diganti, tanggal Expires belum lewat.
SEC="$SRC/.well-known/security.txt"
if grep -qE "^Contact:.*(GANTI|contoh\.com)" "$SEC"; then
  echo "Edit $SEC first: replace the Contact line with the maintainer's email." >&2
  exit 1
fi
# RFC 9116: Contact berupa URI, mis. "mailto:nama@contoh.ac.id" atau "https://…".
if ! grep -qE "^Contact: (mailto:|https://|tel:)" "$SEC"; then
  echo "In $SEC the Contact line must be a URI, e.g. 'Contact: mailto:name@example.ac.id'." >&2
  exit 1
fi
expires=$(grep -E '^Expires:' "$SEC" | cut -d' ' -f2)
if [ "$(date -u -d "$expires" +%s)" -le "$(date -u +%s)" ]; then
  echo "The Expires date in $SEC has passed ($expires). Set a date at most 1 year ahead." >&2
  exit 1
fi

# Disalin ke folder baru dulu, lalu ditukar: pengunjung tidak pernah melihat situs setengah jadi.
install -d -o root -g root -m 755 /srv/portal
NEW=$(mktemp -d /srv/portal/.site-new.XXXXXX)
cp -R "$SRC/." "$NEW/"
find "$NEW" -name ".DS_Store" -delete
chown -R root:root "$NEW"
find "$NEW" -type d -exec chmod 755 {} +
find "$NEW" -type f -exec chmod 644 {} +
rm -rf "$DEST.old"
[ -d "$DEST" ] && mv "$DEST" "$DEST.old"
mv "$NEW" "$DEST"
rm -rf "$DEST.old"
echo "Published $(find "$DEST" -type f | wc -l) files to $DEST"
