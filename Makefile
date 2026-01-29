# Phantom Server v2.0 Makefile

BINARY_NAME := phantom-server
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BUILD_TIME := $(shell date -u '+%Y-%m-%d %H:%M:%S')

LDFLAGS := -s -w \
	-X 'main.Version=$(VERSION)' \
	-X 'main.BuildTime=$(BUILD_TIME)' \
	-X 'main.GitCommit=$(COMMIT)'

GO := go
GOFLAGS := -trimpath

.PHONY: all build clean test lint run help

# 默认目标
all: build

# 构建
build:
	@echo "🔨 构建 $(BINARY_NAME) $(VERSION)..."
	$(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $(BINARY_NAME) ./cmd/phantom-server
	@echo "✅ 构建完成: $(BINARY_NAME)"

# 多平台构建
release:
	@echo "🚀 构建所有平台..."
	@mkdir -p dist
	
	@echo "  → linux/amd64"
	@GOOS=linux GOARCH=amd64 CGO_ENABLED=0 $(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o dist/$(BINARY_NAME)-linux-amd64 ./cmd/phantom-server
	
	@echo "  → linux/arm64"
	@GOOS=linux GOARCH=arm64 CGO_ENABLED=0 $(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o dist/$(BINARY_NAME)-linux-arm64 ./cmd/phantom-server
	
	@echo "  → linux/armv7"
	@GOOS=linux GOARCH=arm GOARM=7 CGO_ENABLED=0 $(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o dist/$(BINARY_NAME)-linux-armv7 ./cmd/phantom-server
	
	@echo "  → darwin/amd64"
	@GOOS=darwin GOARCH=amd64 CGO_ENABLED=0 $(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o dist/$(BINARY_NAME)-darwin-amd64 ./cmd/phantom-server
	
	@echo "  → darwin/arm64"
	@GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 $(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o dist/$(BINARY_NAME)-darwin-arm64 ./cmd/phantom-server
	
	@echo "  → windows/amd64"
	@GOOS=windows GOARCH=amd64 CGO_ENABLED=0 $(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o dist/$(BINARY_NAME)-windows-amd64.exe ./cmd/phantom-server
	
	@echo "  → freebsd/amd64"
	@GOOS=freebsd GOARCH=amd64 CGO_ENABLED=0 $(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o dist/$(BINARY_NAME)-freebsd-amd64 ./cmd/phantom-server
	
	@echo "✅ 所有平台构建完成"
	@ls -lh dist/

# 清理
clean:
	@echo "🧹 清理..."
	@rm -f $(BINARY_NAME)
	@rm -rf dist/
	@rm -f coverage.out
	@echo "✅ 清理完成"

# 测试
test:
	@echo "🧪 运行测试..."
	$(GO) test -v -race -coverprofile=coverage.out ./...
	@echo "✅ 测试完成"

# 代码检查
lint:
	@echo "🔍 代码检查..."
	@which golangci-lint > /dev/null || (echo "请安装 golangci-lint" && exit 1)
	golangci-lint run
	@echo "✅ 检查通过"

# 运行
run: build
	@echo "🚀 运行..."
	./$(BINARY_NAME) -c configs/config.example.yaml

# 生成 PSK
gen-psk:
	@openssl rand -base64 32

# 安装到系统
install: build
	@echo "📦 安装到 /usr/local/bin..."
	@sudo cp $(BINARY_NAME) /usr/local/bin/
	@echo "✅ 安装完成"

# 帮助
help:
	@echo ""
	@echo "Phantom Server v2.0 构建系统"
	@echo ""
	@echo "用法: make [目标]"
	@echo ""
	@echo "目标:"
	@echo "  build     构建当前平台"
	@echo "  release   构建所有平台"
	@echo "  clean     清理构建文件"
	@echo "  test      运行测试"
	@echo "  lint      代码检查"
	@echo "  run       构建并运行"
	@echo "  gen-psk   生成 PSK"
	@echo "  install   安装到系统"
	@echo "  help      显示帮助"
	@echo ""
