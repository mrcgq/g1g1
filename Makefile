BINARY_NAME := phantom-server
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME := $(shell date -u '+%Y-%m-%d %H:%M:%S')

LDFLAGS := -s -w \
	-X 'main.Version=$(VERSION)' \
	-X 'main.BuildTime=$(BUILD_TIME)' \
	-X 'main.GitCommit=$(COMMIT)'

.PHONY: all build clean test lint run release gen-psk install

all: build

build:
	@echo "🔨 构建 $(BINARY_NAME)..."
	@go build -trimpath -ldflags "$(LDFLAGS)" -o $(BINARY_NAME) ./cmd/phantom-server
	@echo "✅ 完成: $(BINARY_NAME)"

release:
	@echo "🚀 构建所有平台..."
	@mkdir -p dist
	@GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -o dist/$(BINARY_NAME)-linux-amd64 ./cmd/phantom-server
	@GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -o dist/$(BINARY_NAME)-linux-arm64 ./cmd/phantom-server
	@GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -o dist/$(BINARY_NAME)-darwin-amd64 ./cmd/phantom-server
	@GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -o dist/$(BINARY_NAME)-darwin-arm64 ./cmd/phantom-server
	@GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -trimpath -ldflags "$(LDFLAGS)" -o dist/$(BINARY_NAME)-windows-amd64.exe ./cmd/phantom-server
	@echo "✅ 完成"
	@ls -lh dist/

clean:
	@rm -f $(BINARY_NAME)
	@rm -rf dist/
	@rm -f coverage.out

test:
	@go test -v -race -coverprofile=coverage.out ./...

lint:
	@go vet ./...

run: build
	@./$(BINARY_NAME) -c configs/config.example.yaml

gen-psk:
	@openssl rand -base64 32

install: build
	@sudo cp $(BINARY_NAME) /usr/local/bin/
	@echo "✅ 安装完成"
