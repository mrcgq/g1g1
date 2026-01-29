package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/anthropics/phantom-server/internal/crypto" // 注意：这里需要引入 crypto 包
	"github.com/anthropics/phantom-server/internal/server"
	"gopkg.in/yaml.v3"
)

var Version = "2.0.0"

// Config 配置结构
type Config struct {
	Listen     string `yaml:"listen"`      // 监听地址
	PSK        string `yaml:"psk"`         // Base64 密钥
	TimeWindow int    `yaml:"time_window"` // 时间窗口
	LogLevel   string `yaml:"log_level"`   // 日志级别
}

func main() {
	// 1. 定义命令行参数
	configPath := flag.String("c", "config.yaml", "配置文件路径")
	showVersion := flag.Bool("v", false, "显示版本")
	genPSK := flag.Bool("gen-psk", false, "生成新的随机 PSK 并退出")
	flag.Parse()

	// 2. 处理版本显示
	if *showVersion {
		fmt.Printf("Phantom Server v%s\n", Version)
		return
	}

	// 3. 处理 PSK 生成 (这是你问的部分)
	if *genPSK {
		psk, err := crypto.GeneratePSK()
		if err != nil {
			fmt.Fprintf(os.Stderr, "生成 PSK 失败: %v\n", err)
			os.Exit(1)
		}
		fmt.Printf("生成的随机 PSK (Base64):\n%s\n", psk)
		fmt.Println("\n请将此 PSK 复制到你的 config.yaml 文件的 psk 字段中。")
		return
	}

	// 4. 加载配置并启动服务器
	cfg, err := loadConfig(*configPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "加载配置失败: %v\n", err)
		os.Exit(1)
	}

	srv, err := server.New(cfg.Listen, cfg.PSK, cfg.TimeWindow, cfg.LogLevel)
	if err != nil {
		fmt.Fprintf(os.Stderr, "创建服务器失败: %v\n", err)
		os.Exit(1)
	}

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
