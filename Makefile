.DEFAULT_GOAL := help
COMPOSE := docker compose

# `env` juga nama direktori; tanpa .PHONY make menganggapnya sudah dibuat.
.PHONY: help env up down ps logs tenant-create tenant-delete tenant-secret test-isolation test-namespace registry-gc k8s-token test-alerts reset

help: ## Tampilkan daftar perintah
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-16s %s\n", $$1, $$2}'

env: ## Buat env/*.env dari contohnya, dengan kata sandi acak; tidak menimpa
	@scripts/init-env.sh
	@scripts/webui-env.sh
	@scripts/jenkins-key.sh

up: env k8s-token ## Nyalakan backing services, tunggu sampai sehat, siapkan Garage
	$(COMPOSE) up -d --wait --build
	@scripts/garage-init.sh

down: ## Matikan backing services; data di volume tetap
	$(COMPOSE) down

ps: ## Status container
	$(COMPOSE) ps

logs: ## Ikuti log (Ctrl-C untuk keluar)
	$(COMPOSE) logs -f

tenant-create: ## Buat jatah: PROJECT= SERVICE= ENV= WITH="postgres mysql redis s3"
	@scripts/tenant.sh create $(PROJECT) $(SERVICE) $(ENV) $(WITH)

tenant-delete: ## Hapus jatah beserta datanya: PROJECT= SERVICE= ENV= CONFIRM=yes
	@CONFIRM=$(CONFIRM) scripts/tenant.sh delete $(PROJECT) $(SERVICE) $(ENV)

tenant-secret: ## Salin kredensial ke Secret <service>-platform: PROJECT= SERVICE= ENV=
	@scripts/tenant.sh secret $(PROJECT) $(SERVICE) $(ENV)

test-isolation: ## Buktikan dua tenant tidak bisa saling membaca
	@scripts/test-isolation.sh

test-namespace: ## Buktikan isolasi jaringan namespace k3s: NS=worklog-dev
	@scripts/test-namespace.sh $(NS)

registry-gc: ## Buang blob registry yang tidak dirujuk tag mana pun
	@scripts/registry-gc.sh

k8s-token: ## Salin token Prometheus dari cluster ke secrets/k8s/
	@scripts/k8s-prometheus-token.sh

test-alerts: ## Uji aturan alert Prometheus dengan deret buatan
	@docker run --rm -v $(CURDIR)/prometheus:/p:ro -w /p/tests --entrypoint promtool prom/prometheus:v3.15.0 test rules platform.test.yml

reset: ## Ulang semua volume dan kata sandi dari nol (menghapus data!): CONFIRM=yes
	@CONFIRM=$(CONFIRM) scripts/reset.sh
