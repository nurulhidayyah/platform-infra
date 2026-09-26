#!/usr/bin/env bash
# Mengulang backing services dari nol dengan kata sandi baru: semua volume
# Compose dihapus, env/*.env dibuat ulang, jatah tenant yang ada dibuat ulang
# dengan kredensial baru (termasuk Secret-nya di cluster), lalu Jenkins
# memindai GitHub supaya image service dibangun ulang ke registry yang kosong.
#
# Yang dipertahankan: GITHUB_WEBHOOK_SECRET (juga tersimpan di pengaturan
# GitHub App), isi secrets/ (kunci GitHub App dan deploy key), dan semua yang
# ada di k3s, termasuk volume data aplikasi.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if [[ ${CONFIRM:-} != yes ]]; then
  cat >&2 <<'MSG'
Menghapus PERMANEN semua volume platform: database dan jatah tenant, bucket
Garage, image di registry, riwayat Jenkins, metrik, dan Grafana.
Jalankan lagi dengan: make reset CONFIRM=yes
MSG
  exit 2
fi

export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# Webhook secret dan daftar jatah dicatat sebelum berkasnya dihapus.
webhook=$(grep '^GITHUB_WEBHOOK_SECRET=' env/jenkins.env | cut -d= -f2-)
[[ -n $webhook ]] || { echo "GITHUB_WEBHOOK_SECRET tidak ditemukan di env/jenkins.env" >&2; exit 1; }
declare -a jatah=()
for f in tenants/*.env; do
  [[ -e $f ]] || continue
  name=$(basename "$f" .env)
  parts=""
  grep -q '^PG_DATABASE=' "$f" && parts+=" postgres"
  grep -q '^MYSQL_DATABASE=' "$f" && parts+=" mysql"
  grep -q '^REDIS_USER=' "$f" && parts+=" redis"
  grep -q '^S3_BUCKET=' "$f" && parts+=" s3"
  jatah+=("${name//-/ }|${parts# }")
done

echo "== hapus container dan volume"
docker compose down -v
rm -f env/*.env tenants/*.env

echo "== env baru"
make --no-print-directory env
sed -i "s/^GITHUB_WEBHOOK_SECRET=.*/GITHUB_WEBHOOK_SECRET=$webhook/" env/jenkins.env

echo "== nyalakan"
make --no-print-directory up
# Job yang dibuat JCasC saat start pertama baru dimuat Jenkins setelah restart.
docker restart platform-jenkins >/dev/null
until curl -sf -o /dev/null http://127.0.0.1:8090/login; do sleep 3; done

for j in "${jatah[@]}"; do
  read -r project service env <<< "${j%%|*}"
  echo "== jatah $project-$service-$env: ${j#*|}"
  # shellcheck disable=SC2086
  scripts/tenant.sh create "$project" "$service" "$env" ${j#*|}
  if kubectl get namespace "$project-$env" >/dev/null 2>&1; then
    scripts/tenant.sh secret "$project" "$service" "$env"
    echo "Secret $service-platform di $project-$env diperbarui; restart pod-nya kalau sedang jalan"
  fi
done

echo "== pindai GitHub"
pass=$(grep '^JENKINS_ADMIN_PASSWORD=' env/jenkins.env | cut -d= -f2-)
jar=$(mktemp)
trap 'rm -f "$jar"' EXIT
crumb=$(curl -sf -c "$jar" -u "admin:$pass" http://127.0.0.1:8090/crumbIssuer/api/json \
  | jq -r '.crumbRequestField + ":" + .crumb')
curl -sf -b "$jar" -o /dev/null -u "admin:$pass" -H "$crumb" -X POST \
  "http://127.0.0.1:8090/job/github/build?delay=0"
echo "Jenkins memindai akun GitHub dan membangun ulang branch main setiap service."
echo "Kata sandi baru ada di env/*.env."
