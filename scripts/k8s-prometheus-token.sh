#!/usr/bin/env bash
# Menyalin token ServiceAccount platform/prometheus dan CA cluster ke
# secrets/k8s/, tempat Prometheus membacanya. ServiceAccount dan izinnya
# dikelola di platform-gitops (folder platform/).
#
# Berkasnya dibuat bisa dibaca semua user (644), karena Prometheus di dalam
# container berjalan sebagai uid 65534, bukan pemilik berkas. Yang tetap
# menjaganya adalah direktori home (750): user lain di VPS tidak bisa masuk.
set -euo pipefail
cd "$(dirname "$0")/.."
export KUBECONFIG=${KUBECONFIG:-$HOME/.kube/config}
mkdir -p secrets/k8s
kubectl -n platform get secret prometheus-token -o jsonpath='{.data.token}' | base64 -d > secrets/k8s/token
kubectl -n platform get secret prometheus-token -o jsonpath='{.data.ca\.crt}' | base64 -d > secrets/k8s/ca.crt
chmod 644 secrets/k8s/token secrets/k8s/ca.crt
echo "token Prometheus disalin ke secrets/k8s/"
