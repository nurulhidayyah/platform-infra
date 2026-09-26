#!/usr/bin/env bash
# Membuat kunci SSH yang dipakai Jenkins untuk menulis tag image ke
# platform-gitops. Kunci publiknya didaftarkan sebagai deploy key dengan akses
# tulis di repo itu, dan hanya di repo itu: bocornya kunci ini tidak membuka
# repo lain. Tidak pernah menimpa kunci yang sudah ada.
set -euo pipefail
cd "$(dirname "$0")/.."
key=secrets/gitops-deploy-key
if [[ -e $key ]]; then
  echo "lewati  $key (sudah ada)"
  exit 0
fi
mkdir -p secrets
ssh-keygen -q -t ed25519 -N '' -C platform-jenkins -f "$key"
# Container Jenkins berjalan sebagai uid 1000, sama dengan pemilik berkas ini.
chmod 600 "$key"
echo "dibuat  $key; daftarkan $key.pub sebagai deploy key (write) di platform-gitops"
