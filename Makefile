SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help doctor test test-foundation configure prepare compose-config build up verify status logs down db-shell

help:
	@bash scripts/dev.sh help

doctor:
	@bash scripts/dev.sh doctor

test:
	@bash scripts/dev.sh test

test-foundation:
	@bash scripts/dev.sh test-foundation

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
