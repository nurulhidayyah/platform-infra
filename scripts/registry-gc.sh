#!/usr/bin/env bash
# Membuang blob yang tidak lagi dirujuk tag mana pun. Tanpa ini, setiap build
# Jenkins menambah isi volume registry selamanya dan akhirnya mengisi disk yang
# juga dipakai Postgres. Menghapus tag dilakukan lewat API registry; perintah
# ini hanya membersihkan sisanya.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
compose=(docker compose --project-directory "$root" -f "$root/compose.yaml")
before=$("${compose[@]}" exec -T registry du -sh /var/lib/registry | cut -f1)
"${compose[@]}" exec -T registry registry garbage-collect --delete-untagged /etc/distribution/config.yml >/dev/null 2>&1
after=$("${compose[@]}" exec -T registry du -sh /var/lib/registry | cut -f1)
echo "registry: $before sebelum, $after sesudah garbage collection"
