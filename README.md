# Phantom Server v2.0

[![Build](https://github.com/mrcgq/g1g1/actions/workflows/build.yml/badge.svg)](https://github.com/mrcgq/g1g1/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/mrcgq/g1g1)](https://github.com/mrcgq/g1g1/releases)

## 极简 · 无状态 · 抗探测

Phantom 是一个极简的加密 UDP 代理协议。

## 🚀 快速开始

### 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/mrcgq/g1g1/main/scripts/install.sh)

手动安装
# 下载
wget https://github.com/mrcgq/g1g1/releases/latest/download/phantom-server-linux-amd64.tar.gz
tar -xzf phantom-server-linux-amd64.tar.gz

# 生成 PSK
./phantom-server -gen-psk

# 创建配置
cat > config.yaml << EOF
listen: ":54321"
psk: "你的PSK"
time_window: 30
log_level: "info"
EOF

# 运行
./phantom-server -c config.yaml

⚙️ 配置
参数	默认值	说明
listen	:54321	监听地址
psk	必填	Base64 编码的 32 字节密钥
time_window	30	时间窗口（秒）
log_level	info	日志级别

🔧 管理
# 使用管理脚本
bash install.sh          # 菜单
bash install.sh status   # 状态
bash install.sh link     # 分享链接

# 使用 systemctl
systemctl start phantom
systemctl stop phantom
systemctl status phantom
journalctl -u phantom -f


📄 许可证
MIT License

---

### 16. scripts/install.sh

由于这个文件很长（约 900 行），我只修改关键部分。你需要把之前给的完整 `install.sh` 中的以下内容替换：

**找到并替换这些变量：**

```bash
# 在文件开头找到这些变量，修改为：
VERSION="2.0.0"
GITHUB_REPO="mrcgq/g1g1"

目录结构确认
g1g1/
├── .github/
│   └── workflows/
│       ├── build.yml
│       └── release.yml
├── .gitignore
├── .golangci.yml
├── cmd/
│   └── phantom-server/
│       └── main.go
├── configs/
│   └── config.example.yaml
├── internal/
│   ├── crypto/
│   │   ├── crypto.go
│   │   └── crypto_test.go
│   ├── protocol/
│   │   ├── protocol.go
│   │   └── protocol_test.go
│   └── server/
│       └── server.go
├── scripts/
│   └── install.sh
├── go.mod
├── go.sum
├── LICENSE
├── Makefile
└── README.md

