package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/anthropics/phantom-server/internal/server"
	"gopkg.in/yaml.v3"
)

var Version = "2.0.0"

// Config 配置结构
type Config struct {
	Listen     string `yaml:"listen"`      // 监听地址，如 ":54321"
	PSK        string `yaml:"psk"`         // Base64 编码的预共享密钥
	TimeWindow int    `yaml:"time_window"` // 时间窗口（秒）
	LogLevel   string `yaml:"log_level"`   // debug/info/error
}

func main() {
	configPath := flag.String("c", "config.yaml", "配置文件路径")
	showVersion := flag.Bool("v", false, "显示版本")
	flag.Parse()

	if *showVersion {
		fmt.Printf("Phantom Server v%s\n", Version)
		return
	}

	// 加载配置
	cfg, err := loadConfig(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "加载配置失败: %v\n", err)
		os.Exit(1)
	}

	// 创建服务器
	srv, err := server.New(cfg.Listen, cfg.PSK, cfg.TimeWindow, cfg.LogLevel)
	if err != nil {
		fmt.Fprintf(os.Stderr, "创建服务器失败: %v\n", err)
		os.Exit(1)
	}

	// 启动服务器
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		sigCh := make(chan os.Signal, 1)
		signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
		<-sigCh
		fmt.Println("\n收到退出信号，正在关闭...")
		cancel()
	}()

	fmt.Printf("Phantom Server v%s 已启动\n", Version)
	fmt.Printf("监听: %s\n", cfg.Listen)

	if err := srv.Run(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "服务器错误: %v\n", err)
		os.Exit(1)
	}
}

func loadConfig(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	cfg := &Config{
		Listen:     ":54321",
		TimeWindow: 30,
		LogLevel:   "info",
	}

	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, err
	}

	if cfg.PSK == "" {
		return nil, fmt.Errorf("PSK 不能为空")
	}

	return cfg, nil
}
