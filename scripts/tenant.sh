#!/usr/bin/env bash
# Jatah tenant: satu perintah membuat database dan role, user Redis, bucket S3,
# dan berkas kredensial untuk satu service di satu environment. Aturan nama:
# README.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
compose=(docker compose --project-directory "$root" -f "$root/compose.yaml")
tenants="$root/tenants"

usage() {
  cat >&2 <<'USAGE'
Pemakaian:
  tenant.sh create <project> <service> <env> <jatah>...
  CONFIRM=yes tenant.sh delete <project> <service> <env>
  tenant.sh secret <project> <service> <env>

secret menyalin kredensial ke Secret <service>-platform di namespace
<project>-<env>, supaya pod menerimanya lewat envFrom.

Jatah: postgres, mysql, redis, s3
Contoh: tenant.sh create worklog identity dev postgres redis
USAGE
  exit 2
}

[[ $# -ge 4 ]] || usage
action=$1 project=$2 service=$3 env=$4
shift 4

for part in "$project" "$service"; do
  [[ $part =~ ^[a-z][a-z0-9]*$ ]] || { echo "nama '$part' hanya boleh huruf kecil dan angka, diawali huruf" >&2; exit 2; }
done
[[ $env == dev || $env == prod ]] || { echo "env harus dev atau prod, bukan '$env'" >&2; exit 2; }

sql_name="${project}_${service}_${env}"   # database dan role
dash_name="${project}-${service}-${env}"  # user Redis, bucket dan kunci S3, nama berkas
key_prefix="${project}:${service}:"
cred_file="$tenants/$dash_name.env"
(( ${#sql_name} <= 32 )) || { echo "'$sql_name' lebih dari 32 karakter, batas nama user MySQL" >&2; exit 2; }

password() { openssl rand -hex 24; }

psql_admin() {
  "${compose[@]}" exec -T postgres sh -c 'psql -v ON_ERROR_STOP=1 -qAt -U "$POSTGRES_USER" -d postgres'
}
mysql_admin() {
  "${compose[@]}" exec -T mysql sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot -N -B'
}
redis_admin() {
  "${compose[@]}" exec -T redis sh -c 'redis-cli --no-auth-warning --user default --pass "$REDIS_PASSWORD" "$@"' redis-cli "$@"
}
garage() {
  "${compose[@]}" exec -T -e RUST_LOG=warn garage /garage "$@"
}
key_field() {  # key_field <nama kunci> <"Key ID"|"Secret key">
  garage key info "$1" --show-secret | awk -F': *' -v f="$2" '$1 == f {print $2}'
}
# Klien S3 untuk mengosongkan bucket; versinya dipin seperti image lain.
rclone_image=rclone/rclone:1.71.2

create_postgres() {
  local pw; pw=$(password)
  psql_admin <<SQL
CREATE ROLE "$sql_name" LOGIN PASSWORD '$pw' CONNECTION LIMIT 20;
CREATE DATABASE "$sql_name" OWNER "$sql_name";
REVOKE CONNECT, TEMPORARY ON DATABASE "$sql_name" FROM PUBLIC;
SQL
  printf 'PG_DATABASE=%s\nPG_USER=%s\nPG_PASSWORD=%s\nPG_PORT=5432\n' "$sql_name" "$sql_name" "$pw" >> "$cred_file"
}

create_mysql() {
  local pw; pw=$(password)
  mysql_admin <<SQL
CREATE DATABASE \`$sql_name\`;
CREATE USER '$sql_name'@'%' IDENTIFIED BY '$pw';
GRANT ALL PRIVILEGES ON \`$sql_name\`.* TO '$sql_name'@'%';
SQL
  printf 'MYSQL_DATABASE=%s\nMYSQL_USER=%s\nMYSQL_PASSWORD=%s\nMYSQL_PORT=3307\n' "$sql_name" "$sql_name" "$pw" >> "$cred_file"
}

create_redis() {
  local pw; pw=$(password)
  # -@dangerous menutup FLUSHALL, KEYS, CONFIG, dan sejenisnya.
  redis_admin ACL SETUSER "$dash_name" on ">$pw" "~${key_prefix}*" "&${key_prefix}*" +@all -@dangerous >/dev/null
  redis_admin ACL SAVE >/dev/null
  printf 'REDIS_USER=%s\nREDIS_PASSWORD=%s\nREDIS_KEY_PREFIX=%s\nREDIS_PORT=6379\n' "$dash_name" "$pw" "$key_prefix" >> "$cred_file"
}

create_s3() {
  garage bucket create "$dash_name" >/dev/null
  garage key create "$dash_name" >/dev/null
  garage bucket allow --read --write --owner "$dash_name" --key "$dash_name" >/dev/null
  garage bucket allow --read --write --owner "$dash_name" --key platform-admin >/dev/null
  # Kuota melindungi disk bersama dari satu tenant yang kebablasan.
  garage bucket set-quotas --max-size 5GiB "$dash_name" >/dev/null
  printf 'S3_BUCKET=%s\nS3_ACCESS_KEY=%s\nS3_SECRET_KEY=%s\nS3_REGION=garage\nS3_PORT=3900\nS3_PATH_STYLE=true\n' \
    "$dash_name" "$(key_field "$dash_name" 'Key ID')" "$(key_field "$dash_name" 'Secret key')" >> "$cred_file"
}

delete_s3() {
  if garage bucket info "$dash_name" >/dev/null 2>&1; then
    docker run --rm --network platform "$rclone_image" --retries 1 --low-level-retries 1 \
      --s3-provider Other --s3-endpoint http://platform-garage:3900 --s3-region garage --s3-force-path-style \
      --s3-access-key-id "$(key_field platform-admin 'Key ID')" \
      --s3-secret-access-key "$(key_field platform-admin 'Secret key')" \
      delete ":s3:$dash_name" >/dev/null 2>&1
    garage bucket delete --yes "$dash_name" >/dev/null
  fi
  if garage key info "$dash_name" >/dev/null 2>&1; then
    garage key delete --yes "$dash_name" >/dev/null
  fi
}

create() {
  [[ $# -ge 1 ]] || usage
  for r in "$@"; do
    [[ $r == postgres || $r == mysql || $r == redis || $r == s3 ]] || { echo "jatah '$r' tidak dikenal" >&2; exit 2; }
  done
  [[ ! -e $cred_file ]] || { echo "tenant $dash_name sudah ada: $cred_file" >&2; exit 1; }
  mkdir -p "$tenants"
  umask 077
  {
    echo "# Kredensial tenant $dash_name, dibuat $(date -u +%Y-%m-%dT%H:%MZ). Jangan di-commit."
    echo "# Host sengaja tidak ditulis: dari PC lewat ssh -L memakai localhost,"
    echo "# dari pod di k3s memakai 172.30.0.1."
  } > "$cred_file"
  for r in "$@"; do
    "create_$r"
    echo "dibuat  $r untuk $dash_name"
  done
  echo "kredensial: ${cred_file#$root/}"
}

delete() {
  [[ ${CONFIRM:-} == yes ]] || { echo "menghapus $dash_name beserta seluruh datanya; ulangi dengan CONFIRM=yes" >&2; exit 1; }
  psql_admin <<SQL
SET client_min_messages = warning;
DROP DATABASE IF EXISTS "$sql_name" WITH (FORCE);
DROP ROLE IF EXISTS "$sql_name";
SQL
  mysql_admin <<SQL
DROP DATABASE IF EXISTS \`$sql_name\`;
DROP USER IF EXISTS '$sql_name'@'%';
SQL
  "${compose[@]}" exec -T redis sh -c '
    auth="--no-auth-warning --user default --pass $REDIS_PASSWORD"
    redis-cli $auth --scan --pattern "$1*" | xargs -r redis-cli $auth del >/dev/null
    redis-cli $auth ACL DELUSER "$2" >/dev/null
    redis-cli $auth ACL SAVE >/dev/null
  ' sh "$key_prefix" "$dash_name"
  delete_s3
  rm -f "$cred_file"
  echo "dihapus $dash_name"
}

secret() {
  [[ -e $cred_file ]] || { echo "tenant $dash_name belum ada: jalankan create dulu" >&2; exit 1; }
  local namespace="${project}-${env}"
  kubectl get namespace "$namespace" >/dev/null 2>&1 || { echo "namespace $namespace belum ada" >&2; exit 1; }
  # Baris komentar di berkas kredensial diabaikan --from-env-file.
  kubectl -n "$namespace" create secret generic "${service}-platform" \
    --from-env-file="$cred_file" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  echo "Secret ${service}-platform di namespace $namespace diperbarui"
}

case $action in
  create) create "$@" ;;
  delete) delete ;;
  secret) secret ;;
  *) usage ;;
esac
