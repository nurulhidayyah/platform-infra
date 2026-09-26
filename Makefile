.DEFAULT_GOAL := help
COMPOSE := docker compose

# `env` juga nama direktori; tanpa .PHONY make menganggapnya sudah dibuat.
.PHONY: help env up down ps logs tenant-create tenant-delete test-isolation

help: ## Tampilkan daftar perintah
	@grep -E '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-16s %s\n", $$1, $$2}'

env: ## Buat env/*.env dari contohnya, dengan kata sandi acak; tidak menimpa
	@scripts/init-env.sh

up: env ## Nyalakan backing services dan tunggu sampai sehat
	$(COMPOSE) up -d --wait

down: ## Matikan backing services; data di volume tetap
	$(COMPOSE) down

ps: ## Status container
	$(COMPOSE) ps

logs: ## Ikuti log (Ctrl-C untuk keluar)
	$(COMPOSE) logs -f

tenant-create: ## Buat jatah: PROJECT= SERVICE= ENV= WITH="postgres mysql redis"
	@scripts/tenant.sh create $(PROJECT) $(SERVICE) $(ENV) $(WITH)

tenant-delete: ## Hapus jatah beserta datanya: PROJECT= SERVICE= ENV= CONFIRM=yes
	@CONFIRM=$(CONFIRM) scripts/tenant.sh delete $(PROJECT) $(SERVICE) $(ENV)

test-isolation: ## Buktikan dua tenant tidak bisa saling membaca
	@scripts/test-isolation.sh
