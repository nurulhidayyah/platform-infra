#!/usr/bin/env bash
# Membuktikan isolasi jaringan satu namespace project: pod di dalamnya saling
# menjangkau, bisa memakai DNS cluster dan datastore di 172.30.0.1, tapi tidak
# bisa dijangkau dari namespace lain dan tidak bisa menjangkau pod di namespace
# lain. Pod uji dihapus di akhir, lulus atau gagal.
set -euo pipefail
ns=${1:?pemakaian: test-namespace.sh <namespace>}
image=busybox:1.37
k() { kubectl "$@"; }

cleanup() {  # cleanup [true|false]: tunggu pod benar-benar hilang atau tidak
  k -n "$ns" delete pod uji-dalam uji-klien --ignore-not-found --wait="${1:-false}" >/dev/null 2>&1 || true
  k -n default delete pod uji-luar uji-klien --ignore-not-found --wait="${1:-false}" >/dev/null 2>&1 || true
}
trap cleanup EXIT
# Sisa run sebelumnya harus benar-benar hilang, kalau tidak pembuatan pod
# berikutnya ditolak AlreadyExists.
cleanup true

k -n "$ns" run uji-dalam --image=$image --restart=Never -- httpd -f -p 8080 -h /tmp >/dev/null
k -n default run uji-luar --image=$image --restart=Never -- httpd -f -p 8080 -h /tmp >/dev/null
k -n "$ns" wait --for=condition=Ready pod/uji-dalam --timeout=90s >/dev/null
k -n default wait --for=condition=Ready pod/uji-luar --timeout=90s >/dev/null
ip_dalam=$(k -n "$ns" get pod uji-dalam -o jsonpath='{.status.podIP}')
ip_luar=$(k -n default get pod uji-luar -o jsonpath='{.status.podIP}')

# Pod klien menunggu 5 detik sebelum mencoba. Aturan NetworkPolicy per pod baru
# dipasang controller setelah pod itu terdeteksi; klien yang langsung mencoba
# lolos lewat jeda itu, sehingga egress yang seharusnya ditolak tampak "BISA".
dari() {  # dari <namespace> <perintah shell>; mencetak BISA atau TIDAK
  k -n "$1" run uji-klien --rm -i --restart=Never --image=$image --command -- \
    sh -c "sleep 5; if $2; then echo BISA; else echo TIDAK; fi" 2>/dev/null | grep -E '^(BISA|TIDAK)$' || echo TIDAK
}

passed=0 failed=0
check() {  # check <label> <harapan BISA|TIDAK> <hasil>
  if [[ $3 == "$2" ]]; then printf '  lulus  %-5s %s\n' "$2" "$1"; passed=$((passed + 1))
  else printf '  GAGAL  %-5s %s (hasil: %s)\n' "$2" "$1" "$3"; failed=$((failed + 1)); fi
}

echo "Namespace $ns"
check "sesama pod di $ns"                      BISA  "$(dari "$ns" "nc -w 3 $ip_dalam 8080 </dev/null")"
check "DNS cluster dari $ns"                   BISA  "$(dari "$ns" "nslookup -timeout=3 kubernetes.default.svc.cluster.local >/dev/null")"
check "datastore 172.30.0.1:5432 dari $ns"     BISA  "$(dari "$ns" "nc -w 3 172.30.0.1 5432 </dev/null")"
check "namespace default masuk ke $ns"         TIDAK "$(dari default "nc -w 3 $ip_dalam 8080 </dev/null")"
check "$ns keluar ke pod namespace default"    TIDAK "$(dari "$ns" "nc -w 3 $ip_luar 8080 </dev/null")"

echo
echo "$passed lulus, $failed gagal"
(( failed == 0 ))
