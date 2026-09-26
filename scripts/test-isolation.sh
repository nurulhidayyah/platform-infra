#!/usr/bin/env bash
# Membuktikan dua tenant tidak bisa saling membaca. Membuat dua tenant
# sementara, isotest-alpha-dev dan isotest-beta-dev, lalu menguji dari sisi
# alpha. Keduanya dihapus lagi di akhir, lulus atau gagal.
#
# Klien menyambung lewat nama container, bukan 127.0.0.1, supaya lewat jalur
# autentikasi yang sama dengan klien dari luar container.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
compose=(docker compose --project-directory "$root" -f "$root/compose.yaml")
tenant="$root/scripts/tenant.sh"

cleanup() {
  CONFIRM=yes "$tenant" delete isotest alpha dev >/dev/null 2>&1 || true
  CONFIRM=yes "$tenant" delete isotest beta dev >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup
"$tenant" create isotest alpha dev postgres mysql redis s3 >/dev/null
"$tenant" create isotest beta dev postgres mysql redis s3 >/dev/null

# shellcheck disable=SC1091
source "$root/tenants/isotest-alpha-dev.env"

pg()    { "${compose[@]}" exec -T -e PGPASSWORD="$2" postgres psql -h platform-postgres -U "$PG_USER" -d "$1" -v ON_ERROR_STOP=1 -qAtc "$3" 2>&1; }
my()    { "${compose[@]}" exec -T -e MYSQL_PWD="$MYSQL_PASSWORD" mysql mysql -h platform-mysql -u "$MYSQL_USER" -N -B -e "$1" 2>&1; }
rd()    { "${compose[@]}" exec -T redis redis-cli -h platform-redis --no-auth-warning --user "$REDIS_USER" --pass "$REDIS_PASSWORD" "$@" 2>&1; }
s3()    { docker run --rm -i --network platform rclone/rclone:1.71.2 --retries 1 --low-level-retries 1 \
            --s3-provider Other --s3-endpoint http://platform-garage:3900 --s3-region garage --s3-force-path-style \
            --s3-access-key-id "$S3_ACCESS_KEY" --s3-secret-access-key "$S3_SECRET_KEY" "$@" 2>&1; }

passed=0 failed=0
check() {  # check <label> <harapan: ok|tolak> <pola-output-yang-diharapkan> <output>
  local label=$1 want=$2 pattern=$3 out=$4
  if grep -qiE "$pattern" <<<"$out"; then
    printf '  lulus  %-5s %s\n' "$want" "$label"; passed=$((passed + 1))
  else
    printf '  GAGAL  %-5s %s\n         keluaran: %s\n' "$want" "$label" "$(head -1 <<<"$out")"; failed=$((failed + 1))
  fi
}

echo "Postgres"
check "alpha menulis ke database-nya sendiri" ok '^1$' \
  "$(pg "$PG_DATABASE" "$PG_PASSWORD" 'CREATE TABLE t (x int); INSERT INTO t VALUES (1); SELECT x FROM t;' || true)"
check "alpha masuk ke database beta" tolak 'permission denied for database' \
  "$(pg isotest_beta_dev "$PG_PASSWORD" 'SELECT 1' || true)"
check "alpha masuk ke database postgres" tolak 'permission denied for database' \
  "$(pg postgres "$PG_PASSWORD" 'SELECT 1' || true)"
check "alpha dengan kata sandi salah" tolak 'password authentication failed' \
  "$(pg "$PG_DATABASE" salah 'SELECT 1' || true)"

echo "MySQL"
check "alpha menulis ke database-nya sendiri" ok '^1$' \
  "$(my "CREATE TABLE $MYSQL_DATABASE.t (x int); INSERT INTO $MYSQL_DATABASE.t VALUES (1); SELECT x FROM $MYSQL_DATABASE.t;" || true)"
check "alpha membaca database beta" tolak 'access denied' \
  "$(my 'USE isotest_beta_dev' || true)"

echo "Redis"
check "alpha menulis ke prefix-nya sendiri" ok '^OK$' "$(rd SET "${REDIS_KEY_PREFIX}k" 1 || true)"
check "alpha menulis ke prefix beta" tolak 'NOPERM' "$(rd SET isotest:beta:k 1 || true)"
check "alpha menjalankan FLUSHALL" tolak 'NOPERM' "$(rd FLUSHALL || true)"

echo "S3 (Garage)"
check "alpha menulis ke bucket-nya sendiri" ok '^obj\.txt$' "$(echo halo | s3 rcat ":s3:$S3_BUCKET/obj.txt" >/dev/null; s3 lsf ":s3:$S3_BUCKET" || true)"
check "alpha membaca bucket beta" tolak 'AccessDenied' "$(s3 lsf :s3:isotest-beta-dev || true)"
check "alpha menulis ke bucket beta" tolak 'AccessDenied' "$(echo x | s3 rcat :s3:isotest-beta-dev/x.txt || true)"

echo
echo "$passed lulus, $failed gagal"
(( failed == 0 ))
