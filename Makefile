SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help doctor test test-foundation test-proof-demo lint-logos audit-actions configure prepare compose-config build up verify status logs down db-shell

help:
	@bash scripts/dev.sh help

doctor:
	@bash scripts/dev.sh doctor

test:
	@bash scripts/dev.sh test

test-foundation:
	@bash scripts/dev.sh test-foundation

test-proof-demo:
	@python3 -m unittest host_adapters.tests.proof_demo_contract host_adapters.tests.proof_worker_contract -v

lint-logos:
	@bash scripts/dev.sh lint-logos

audit-actions:
	@bash scripts/dev.sh audit-actions --expect-firebat2=disabled

configure:
	@bash scripts/dev.sh configure

prepare:
	@bash scripts/dev.sh prepare

compose-config:
	@bash scripts/dev.sh compose-config

build:
	@bash scripts/dev.sh build

up:
	@bash scripts/dev.sh up

verify:
	@bash scripts/dev.sh verify

status:
	@bash scripts/dev.sh status

logs:
	@bash scripts/dev.sh logs

down:
	@bash scripts/dev.sh down

db-shell:
	@bash scripts/dev.sh db-shell
