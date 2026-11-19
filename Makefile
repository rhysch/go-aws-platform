.PHONY: test vet run smoke build compose-up compose-down tf-check
VERSION ?= dev
URL ?= http://localhost:8080

test:
	go test -race -cover ./...
vet:
	go vet ./...
run:
	go run ./cmd/api
smoke:
	go run ./cmd/smoke -url $(URL)
build:
	mkdir -p bin
	CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.version=$(VERSION)" -o bin/api ./cmd/api
compose-up:
	docker compose up -d --build --wait
compose-down:
	docker compose down
tf-check:
	terraform fmt -check -recursive infra
	terraform -chdir=infra/bootstrap init -backend=false
	terraform -chdir=infra/bootstrap validate
	terraform -chdir=infra/app init -backend=false
	terraform -chdir=infra/app validate
	terraform -chdir=infra/app test
