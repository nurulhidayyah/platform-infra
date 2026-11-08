#!/usr/bin/env bash
# Menyiapkan SonarQube yang sudah jalan; aman diulang (dipanggil `make up`):
#   1. kata sandi admin bawaan (admin) diganti SONARQUBE_ADMIN_PASSWORD
#   2. quality gate "Platform" dibuat dan dijadikan bawaan
#   3. token analisis untuk Jenkins dibuat kalau SONAR_TOKEN di env/jenkins.env
#      kosong atau tidak berlaku lagi, lalu container Jenkins dibuat ulang
#      supaya JCasC membacanya
# Token dan kata sandi tidak pernah dicetak.
set -euo pipefail
cd "$(dirname "$0")/.."
url=http://127.0.0.1:9000

admin_pw=$(grep '^SONARQUBE_ADMIN_PASSWORD=' env/sonarqube.env | cut -d= -f2-)
[[ -n $admin_pw ]] || { echo "SONARQUBE_ADMIN_PASSWORD kosong di env/sonarqube.env" >&2; exit 1; }

until curl -fsS "$url/api/system/status" | grep -q '"status":"UP"'; do sleep 5; done

valid() { curl -fsS -u "$1" "$url/api/authentication/validate" | grep -q '"valid":true'; }
if valid admin:admin; then
  curl -fsS -o /dev/null -u admin:admin -X POST "$url/api/users/change_password" \
    --data-urlencode login=admin --data-urlencode previousPassword=admin \
    --data-urlencode "password=$admin_pw"
  echo "kata sandi admin SonarQube dipasang"
fi
valid "admin:$admin_pw" || { echo "login admin SonarQube gagal; cek env/sonarqube.env" >&2; exit 1; }
api() { curl -fsS -u "admin:$admin_pw" -X POST "$url/api/$1" "${@:2}"; }

# Gate Platform, hanya menilai kode baru (kode lama tidak): tanpa issue baru,
# setiap security hotspot baru sudah ditinjau, duplikasi maksimal 3%, dan
# coverage minimal 80%. Coverage butuh laporan dari repo service (JaCoCo,
# pytest-cov, lcov); tanpa laporan coverage dianggap 0%. SonarQube melewatkan
# syarat coverage dan duplikasi kalau kode barunya kurang dari 20 baris.
show() { curl -fsS -u "admin:$admin_pw" "$url/api/qualitygates/show?name=Platform"; }
if ! show >/dev/null 2>&1; then
  api qualitygates/create --data-urlencode name=Platform >/dev/null
  echo "quality gate Platform dibuat"
fi
gate=$(show)
ensure() {
  jq -e --arg m "$1" '.conditions[] | select(.metric == $m)' <<< "$gate" >/dev/null ||
    api qualitygates/create_condition --data-urlencode gateName=Platform \
      -d "metric=$1" -d "op=$2" -d "error=$3" >/dev/null
}
ensure new_violations GT 0
ensure new_security_hotspots_reviewed LT 100
ensure new_duplicated_lines_density GT 3
ensure new_coverage LT 80
api qualitygates/set_as_default --data-urlencode name=Platform

token=$(grep '^SONAR_TOKEN=' env/jenkins.env | cut -d= -f2- || true)
if [[ -n $token ]] && curl -fsS -H "Authorization: Bearer $token" "$url/api/authentication/validate" | grep -q '"valid":true'; then
  echo "token SonarQube Jenkins masih berlaku"
  exit 0
fi
api user_tokens/revoke -d login=admin -d name=jenkins >/dev/null || true
token=$(api user_tokens/generate -d login=admin -d name=jenkins -d type=GLOBAL_ANALYSIS_TOKEN | jq -r .token)
if grep -q '^SONAR_TOKEN=' env/jenkins.env; then
  sed -i "s|^SONAR_TOKEN=.*|SONAR_TOKEN=$token|" env/jenkins.env
else
  printf '%s\n' "SONAR_TOKEN=$token" >> env/jenkins.env
fi
echo "token SonarQube Jenkins dibuat; Jenkins dibuat ulang"
# Bukan `docker restart`: itu memakai env lama, env_file hanya dibaca saat
# container dibuat. Compose membuat ulang container karena isi env berubah.
docker compose up -d --wait jenkins
