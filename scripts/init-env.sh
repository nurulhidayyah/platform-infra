#!/usr/bin/env bash
# Membuat env/<komponen>.env dari contohnya, mengganti setiap __GENERATE__
# dengan kata sandi acak. Berkas yang sudah ada tidak pernah ditimpa: kata
# sandi superuser tertanam di volume data sejak start pertama, jadi mengganti
# berkasnya saja hanya membuat keduanya tidak cocok.
set -euo pipefail
cd "$(dirname "$0")/../env"
umask 077
for example in *.env.example; do
  target="${example%.example}"
  if [[ -e "$target" ]]; then
    echo "lewati  env/$target (sudah ada)"
    continue
  fi
  while IFS= read -r line; do
    while [[ "$line" == *__GENERATE__* ]]; do
      line="${line/__GENERATE__/$(openssl rand -hex 24)}"
    done
    printf '%s\n' "$line"
  done < "$example" > "$target"
  echo "dibuat  env/$target"
done
