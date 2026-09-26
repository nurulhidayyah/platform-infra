#!/bin/sh
# User `default` ditulis ke aclfile, bukan lewat requirepass, supaya semua user
# (termasuk user tenant dari skrip jatah tenant) hidup di satu berkas yang
# disimpan `ACL SAVE` dan bertahan setelah restart. Setelah itu entrypoint
# resmi image yang menjalankan Redis sebagai user `redis`, bukan root.
set -eu
acl=/data/users.acl
if [ ! -s "$acl" ]; then
  : "${REDIS_PASSWORD:?REDIS_PASSWORD kosong}"
  printf 'user default on >%s ~* &* +@all\n' "$REDIS_PASSWORD" > "$acl"
fi
exec docker-entrypoint.sh redis-server \
  --aclfile "$acl" \
  --appendonly yes \
  --maxmemory 96mb \
  --maxmemory-policy noeviction
