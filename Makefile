# Load .env so every target sees the same config.
ifneq (,$(wildcard .env))
include .env
export
endif

DATE ?= $(shell date -u -d 'yesterday' +%F 2>/dev/null || date -u -v-1d +%F)
DBT   = cd dbt && dbt

.PHONY: help keys tf-apply up connectors seed traffic settle settle-backfill snowflake-setup dbt-build airflow test down destroy

help:            ## list targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-16s %s\n", $$1, $$2}'

keys:            ## generate key pairs for your Snowflake admin user and the service user
	@mkdir -p keys
	@for k in admin svc; do \
	  [ -f keys/$${k}_key.p8 ] || openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -out keys/$${k}_key.p8; \
	  openssl rsa -in keys/$${k}_key.p8 -pubout -out keys/$${k}_key.pub 2>/dev/null; \
	  echo "$$k public key: $$(grep -v 'PUBLIC KEY' keys/$${k}_key.pub | tr -d '\n')"; echo; \
	done

tf-apply:        ## provision AWS + Snowflake
	cd terraform && terraform init -upgrade && terraform apply

up:              ## start Postgres, Kafka, Kafka Connect, Kafka UI
	docker compose up -d --build postgres kafka connect kafka-ui

connectors:      ## register Debezium source + S3 sink
	./scripts/register_connectors.sh

seed:            ## backfill 7 days of ledger history
	python generator/traffic.py --backfill-days 7

traffic:         ## live OLTP traffic (Ctrl-C to stop)
	python generator/traffic.py --rate 5

settle:          ## write processor settlement file for DATE (default: yesterday)
	python generator/settlements.py --date $(DATE)

settle-backfill: ## settlement files for the 7 seeded days
	@for i in 7 6 5 4 3 2 1; do \
	  d=$$(date -u -d "$$i days ago" +%F 2>/dev/null || date -u -v-$${i}d +%F); \
	  python generator/settlements.py --date $$d; \
	done

snowflake-setup: ## create RAW stages, tables, pipes (needs Snowflake CLI `snow`)
	@mkdir -p build
	envsubst '$$S3_BUCKET' < snowflake/setup.sql > build/setup.sql
	snow sql -f build/setup.sql

dbt-build:       ## build + test all dbt models (dev target)
	$(DBT) build --profiles-dir .

airflow:         ## start Airflow at http://localhost:8080
	docker compose --profile airflow up -d --build airflow

test:            ## unit tests + lint
	pytest -q generator/tests && ruff check generator airflow

down:            ## stop containers and delete local volumes
	docker compose --profile airflow down -v

destroy:         ## tear down all cloud resources
	cd terraform && terraform destroy
