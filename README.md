# platform-infra

Infrastruktur bersama di VPS Dev: backing services (Compose), bootstrap k3s,
konfigurasi tunnel, dan skrip jatah tenant. Platform ini bukan milik satu
project. WorkLog hanya penghuni pertamanya.

Manifest yang dijalankan di cluster tinggal di repo terpisah,
[platform-gitops](https://github.com/nurulhidayyah/platform-gitops).

## Prinsip

- **Hanya environment Dev yang tinggal di mesin ini.** Prod nanti di mesin lain.
- **Datastore dan tampilan operasional hanya mendengar di `127.0.0.1`.** Dari
  PC, keduanya dijangkau lewat SSH port forwarding. Tidak ada yang dibuka ke
  internet selain hostname aplikasi dan webhook, lewat Cloudflare Tunnel.
- **Service tidak pernah tahu di mana dirinya jalan.** Alamat dan kredensial
  selalu masuk lewat environment, jadi pindah mesin tidak menyentuh kode.
- **Platform membagikan jatah, bukan kunci induk.** Setiap service mendapat
  database, role, bucket, dan kredensialnya sendiri. Superuser hanya dipakai
  skrip jatah tenant.
- **Repo ini publik.** Tidak ada rahasia dan tidak ada alamat IP server di sini.
  Semuanya lewat `.env` yang di-gitignore.

## Aturan penamaan

Nama milik platform tidak pernah memuat nama project. Mengganti nama volume
atau namespace belakangan bukan rename, melainkan migrasi data.

Placeholder: `<project>` (misalnya `worklog`), `<service>` (misalnya
`identity`), `<env>` (`dev` atau `prod`), `<komponen>` (misalnya `postgres`).

| Hal | Pola | Contoh |
|---|---|---|
| Compose project dan network | `platform` | `platform` |
| Container | `platform-<komponen>` | `platform-postgres` |
| Volume | `platform_<komponen>_data` | `platform_postgres_data` |
| Database dan role (Postgres, MySQL) | `<project>_<service>_<env>` | `worklog_identity_dev` |
| Bucket MinIO | `<project>-<service>-<env>` | `worklog-template-dev` |
| User ACL Redis | `<project>-<service>-<env>` | `worklog-identity-dev` |
| Prefix key Redis | `<project>:<service>:` | `worklog:identity:` |
| Topic Kafka | `<env>.<project>.<domain>.<event>` | `dev.worklog.document.requested` |
| Namespace k3s | `<project>-<env>` | `worklog-dev` |
| Secret kredensial platform | `<service>-platform` | `identity-platform` |
| Repository image | `<project>/<service>` | `worklog/identity` |
| Tag image | SHA commit, 7 karakter | `a1b2c3d` |
| Hostname aplikasi | `<project>-<env>.hostingskuy.cloud` | `worklog-dev.hostingskuy.cloud` |
| Hostname milik platform | `platform-<fungsi>.hostingskuy.cloud` | `platform-webhook.hostingskuy.cloud` |

Database dan role memakai garis bawah karena tanda hubung harus dikutip di
SQL. Bucket dan hostname memakai tanda hubung karena garis bawah tidak sah di
keduanya.

**Hostname hanya satu tingkat di bawah domain.** Universal SSL Cloudflare
paket gratis hanya menutup `*.hostingskuy.cloud`, jadi nama seperti
`identity.worklog-dev.hostingskuy.cloud` tidak punya sertifikat. Service
dalam satu project dibedakan lewat path, bukan subdomain.

## Port di host

Semua komponen platform mendengar di `127.0.0.1`, kecuali disebut lain.
Datastore juga mendengar di `172.30.0.1`, gateway network Docker `platform`,
supaya pod di k3s bisa menjangkaunya. Alamat itu selalu ada selama Docker
hidup, tanpa menunggu k3s, dan tidak bisa dijangkau dari internet.

| Port | Pemakai | Catatan |
|---|---|---|
| 22 | sshd | publik, hanya menerima kunci |
| 80, 443 | nginx penghuni lama | jangan dipakai platform |
| 3306, 33060 | MySQL milik absensi | jangan dipakai platform |
| 8000 | timesheet-app | jangan dipakai platform |
| 5432 | Postgres platform | |
| 3307 | MySQL platform | 3306 sudah terpakai |
| 6379 | Redis | |
| 3900 | Garage, API S3 | RPC 3901 dan admin 3903 tidak dibuka ke host |
| 3909 | garage-webui | wajib login; kata sandi di baris pertama `env/garage-webui.env` |
| 5000 | registry image | hanya 127.0.0.1; k3s menariknya dari sini tanpa `registries.yaml` |

Port Jenkins, Prometheus, Grafana, Jaeger, dan Argo CD ditetapkan saat
komponennya dipasang, dan ditambahkan ke tabel ini.

## Susunan

```
compose.yaml                   backing services: Postgres, MySQL, Redis, Garage
env/<komponen>.env.example     contoh konfigurasi; `make env` membuat versi aslinya
postgres/init/                 SQL yang jalan sekali, saat volume Postgres masih baru
redis/entrypoint.sh            menyiapkan aclfile sebelum Redis start
garage/garage.toml             konfigurasi Garage tanpa rahasia
scripts/garage-init.sh         layout satu node dan kunci platform-admin
scripts/webui-env.sh           login dan admin token untuk garage-webui
registry/config.yml            registry image; penghapusan diaktifkan untuk garbage collection
scripts/registry-gc.sh         membuang blob yang tidak dirujuk tag mana pun
pc/ssh-config.example          contoh ~/.ssh/config untuk PC
k3s/config.yaml                konfigurasi k3s: servicelb mati, Secret terenkripsi
k3s/traefik-config.yaml        Traefik di ClusterIP 10.43.0.80, tanpa port host
scripts/tenant.sh              jatah tenant
scripts/test-isolation.sh      bukti bahwa dua tenant tidak bisa saling membaca
tenants/                       kredensial hasil jatah tenant; di-gitignore
```

## Memakai

```
make up
make tenant-create PROJECT=worklog SERVICE=identity ENV=dev WITH="postgres redis"
make test-isolation
```

`make up` menjalankan `make env` lebih dulu. `make env` tidak pernah menimpa
berkas yang sudah ada, karena kata sandi superuser tertanam di volume data
sejak start pertama.

Kredensial tenant ditulis ke `tenants/<project>-<service>-<env>.env`. Host
sengaja tidak ditulis: dari PC lewat `ssh -L` alamatnya `localhost`, dari pod
alamatnya `172.30.0.1`.

`make tenant-delete` menghapus database, user, dan seluruh datanya, jadi harus
disertai `CONFIRM=yes`.

## Memasang k3s

Kedua berkas di `k3s/` harus sudah terpasang **sebelum** k3s pertama kali start.
Kalau terlambat, Traefik sempat berdiri dengan setelan bawaan dan mengambil port
80 dan 443 di alamat publik.

```
sudo mkdir -p /etc/rancher/k3s /var/lib/rancher/k3s/server/manifests
sudo cp k3s/config.yaml /etc/rancher/k3s/config.yaml
sudo cp k3s/traefik-config.yaml /var/lib/rancher/k3s/server/manifests/traefik-config.yaml
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION=v1.36.4+k3s1 sh -
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown "$USER:$USER" ~/.kube/config && chmod 600 ~/.kube/config
```

## Object storage

Object storage memakai [Garage](https://garagehq.deuxfleurs.fr/), bukan
MinIO: image resmi MinIO sudah tidak diterbitkan lagi, dan tag yang dulu
dipakai tidak bisa ditarik dari Docker Hub maupun quay.io. Service tetap
berbicara lewat API S3, jadi kodenya tidak bergantung pada Garage.

Untuk melihat isi bucket, buka garage-webui di `http://localhost:3909` lewat
SSH port forwarding. Klien S3 harus memakai path-style dan region `garage`. Setiap bucket tenant
dibatasi kuota 5 GiB supaya satu tenant tidak bisa mengisi disk bersama.

## Branch

Pekerjaan dilakukan di `dev`. `main` hanya menerima `git merge --ff-only dev`.

## Perintah

```
make help
```
