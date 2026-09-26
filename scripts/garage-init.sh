#!/usr/bin/env bash
# Menyiapkan Garage satu node. Aman dijalankan berulang kali.
#
# Node baru belum punya peran di layout, dan tanpa peran Garage menolak
# menyimpan objek. Kapasitas di layout hanya bobot pembagian data antar-node,
# bukan batas pakai; batas pakai diatur lewat kuota per bucket.
#
# Kunci platform-admin diberi hak atas setiap bucket tenant, supaya skrip
# jatah tenant bisa mengosongkan bucket sebelum menghapusnya. Garage menolak
# menghapus bucket yang masih berisi objek.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
garage() {
  docker compose --project-directory "$root" -f "$root/compose.yaml" \
    exec -T -e RUST_LOG=warn garage /garage "$@"
}

if garage status | grep -q 'NO ROLE ASSIGNED'; then
  node=$(garage status | awk '/^[0-9a-f]{16} /{print $1; exit}')
  current=$(garage layout show | awk '/Current cluster layout version:/{print $NF}')
  garage layout assign -z vps -c 100G "$node" >/dev/null
  garage layout apply --version $((current + 1)) >/dev/null
  echo "garage: node $node diberi peran di layout"
fi

if ! garage key info platform-admin >/dev/null 2>&1; then
  garage key create platform-admin >/dev/null
  echo "garage: kunci platform-admin dibuat"
fi
