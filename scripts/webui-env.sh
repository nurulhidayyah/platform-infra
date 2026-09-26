#!/usr/bin/env bash
# Membuat env/garage-webui.env: admin token Garage untuk UI, dan login UI
# dengan kata sandi acak. Tidak pernah menimpa berkas yang sudah ada.
#
# UI ini memegang admin token Garage, jadi siapa pun yang membukanya berkuasa
# penuh atas semua bucket. Login mencegah proses lain di VPS yang bisa
# menjangkau 127.0.0.1:3909 ikut menjadi admin storage.
set -euo pipefail
cd "$(dirname "$0")/../env"
target=garage-webui.env
if [[ -e $target ]]; then
  echo "lewati  env/$target (sudah ada)"
  exit 0
fi
# shellcheck disable=SC1091
source garage.env
password=$(openssl rand -hex 16)
hash=$(python3 -c 'import bcrypt, sys; print(bcrypt.hashpw(sys.argv[1].encode(), bcrypt.gensalt()).decode())' "$password")
umask 077
{
  echo "# Login garage-webui: admin / $password"
  echo "API_ADMIN_KEY=$GARAGE_ADMIN_TOKEN"
  # Compose menafsirkan \$ di env_file, jadi setiap \$ di hash bcrypt ditulis \$\$.
  echo "AUTH_USER_PASS=admin:${hash//\$/\$\$}"
} > "$target"
echo "dibuat  env/$target (kata sandi login ada di baris pertamanya)"
