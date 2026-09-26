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

| Port | Pemakai | Catatan |
|---|---|---|
| 22 | sshd | publik, hanya menerima kunci |
| 80, 443 | nginx penghuni lama | jangan dipakai platform |
| 3306, 33060 | MySQL milik absensi | jangan dipakai platform |
| 8000 | timesheet-app | jangan dipakai platform |
| 5432 | Postgres platform | |
| 3307 | MySQL platform | 3306 sudah terpakai |
| 6379 | Redis | |
| 9000, 9001 | MinIO API dan konsol | |
| 5000 | registry image | |

Port Jenkins, Prometheus, Grafana, Jaeger, dan Argo CD ditetapkan saat
komponennya dipasang, dan ditambahkan ke tabel ini.

## Branch

Pekerjaan dilakukan di `dev`. `main` hanya menerima `git merge --ff-only dev`.

## Perintah

```
make help
```
