package server

import (
	"context"
	"fmt"
	"io"
	"net"
	"sync"
	"time"

	"github.com/mrcgq/g1g1/internal/crypto"
	"github.com/mrcgq/g1g1/internal/protocol"
)

const (
	logError = 0
	logInfo  = 1
	logDebug = 2
)

// Server UDP 代理服务器
type Server struct {
	listenAddr  string
	crypto      *crypto.Crypto
	conn        *net.UDPConn
	logLevel    int
	replayCache sync.Map
}

// New 创建服务器
func New(listenAddr, psk string, timeWindow int, logLevel string) (*Server, error) {
	c, err := crypto.New(psk, timeWindow)
	if err != nil {
		return nil, fmt.Errorf("初始化加密模块失败: %w", err)
	}

	level := logInfo
	switch logLevel {
	case "debug":
		level = logDebug
	case "error":
		level = logError
	}

	return &Server{
		listenAddr: listenAddr,
		crypto:     c,
		logLevel:   level,
	}, nil
}

// Run 启动服务器
func (s *Server) Run(ctx context.Context) error {
	addr, err := net.ResolveUDPAddr("udp", s.listenAddr)
	if err != nil {
		return fmt.Errorf("解析地址失败: %w", err)
	}

	s.conn, err = net.ListenUDP("udp", addr)
	if err != nil {
		return fmt.Errorf("监听失败: %w", err)
	}
	defer s.conn.Close()

	_ = s.conn.SetReadBuffer(4 * 1024 * 1024)
	_ = s.conn.SetWriteBuffer(4 * 1024 * 1024)

	s.log(logInfo, "服务器已启动，监听 %s", s.listenAddr)
	s.log(logInfo, "UserID: %x", s.crypto.GetUserID())

	go s.cleanupReplayCache(ctx)

	buf := make([]byte, 65535)
	for {
		select {
		case <-ctx.Done():
			s.log(logInfo, "服务器正在关闭...")
			return nil
		default:
		}

		_ = s.conn.SetReadDeadline(time.Now().Add(1 * time.Second))
		n, remoteAddr, err := s.conn.ReadFromUDP(buf)
		if err != nil {
			if netErr, ok := err.(net.Error); ok && netErr.Timeout() {
				continue
			}
			s.log(logError, "读取错误: %v", err)
			continue
		}

		if n == 0 {
			continue
		}

		packet := make([]byte, n)
		copy(packet, buf[:n])

		go s.handlePacket(packet, remoteAddr)
	}
}

func (s *Server) handlePacket(data []byte, from *net.UDPAddr) {
	if len(data) < crypto.HeaderSize+crypto.NonceSize+crypto.TagSize {
		return
	}

	var userID [crypto.UserIDSize]byte
	copy(userID[:], data[:crypto.UserIDSize])
	if userID != s.crypto.GetUserID() {
		s.log(logDebug, "UserID 不匹配，丢弃")
		return
	}

	nonceKey := string(data[crypto.HeaderSize : crypto.HeaderSize+crypto.NonceSize])
	if _, exists := s.replayCache.LoadOrStore(nonceKey, time.Now()); exists {
		s.log(logDebug, "检测到重放，丢弃")
		return
	}

	plaintext, err := s.crypto.Decrypt(data)
	if err != nil {
		s.log(logDebug, "解密失败: %v", err)
		return
	}

	req, err := protocol.ParseRequest(plaintext)
	if err != nil {
		s.log(logDebug, "解析请求失败: %v", err)
		return
	}

	s.log(logDebug, "请求: %s %s", req.Network, req.TargetAddr())

	response, err := s.forward(req)
	if err != nil {
		s.log(logDebug, "转发失败: %v", err)
		errResp := protocol.BuildErrorResponse(0x01)
		if encrypted, encErr := s.crypto.Encrypt(errResp); encErr == nil {
			_, _ = s.conn.WriteToUDP(encrypted, from)
		}
		return
	}

	respData := protocol.BuildResponse(response)
	encrypted, err := s.crypto.Encrypt(respData)
	if err != nil {
		s.log(logError, "加密响应失败: %v", err)
		return
	}

	_, _ = s.conn.WriteToUDP(encrypted, from)
	s.log(logDebug, "响应已发送: %d bytes", len(encrypted))
}

func (s *Server) forward(req *protocol.Request) ([]byte, error) {
	switch req.Network {
	case "tcp":
		return s.forwardTCP(req)
	case "udp":
		return s.forwardUDP(req)
	default:
		return nil, fmt.Errorf("不支持的网络类型: %s", req.Network)
	}
}

func (s *Server) forwardTCP(req *protocol.Request) ([]byte, error) {
	conn, err := net.DialTimeout("tcp", req.TargetAddr(), 10*time.Second)
	if err != nil {
		return nil, fmt.Errorf("连接目标失败: %w", err)
	}
	defer conn.Close()

	_ = conn.SetDeadline(time.Now().Add(30 * time.Second))

	if len(req.Data) > 0 {
		if _, err := conn.Write(req.Data); err != nil {
			return nil, fmt.Errorf("发送数据失败: %w", err)
		}
	}

	response := make([]byte, 4096)
	n, err := conn.Read(response)
	if err != nil && err != io.EOF {
		return nil, fmt.Errorf("读取响应失败: %w", err)
	}

	return response[:n], nil
}

func (s *Server) forwardUDP(req *protocol.Request) ([]byte, error) {
	addr, err := net.ResolveUDPAddr("udp", req.TargetAddr())
	if err != nil {
		return nil, fmt.Errorf("解析地址失败: %w", err)
	}

	conn, err := net.DialUDP("udp", nil, addr)
	if err != nil {
		return nil, fmt.Errorf("连接目标失败: %w", err)
	}
	defer conn.Close()

	_ = conn.SetDeadline(time.Now().Add(10 * time.Second))

	if _, err := conn.Write(req.Data); err != nil {
		return nil, fmt.Errorf("发送数据失败: %w", err)
	}

	response := make([]byte, 4096)
	n, err := conn.Read(response)
	if err != nil {
		return nil, fmt.Errorf("读取响应失败: %w", err)
	}

	return response[:n], nil
}

func (s *Server) cleanupReplayCache(ctx context.Context) {
	ticker := time.NewTicker(1 * time.Minute)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			now := time.Now()
			s.replayCache.Range(func(key, value interface{}) bool {
				if t, ok := value.(time.Time); ok {
					if now.Sub(t) > 2*time.Minute {
						s.replayCache.Delete(key)
					}
				}
				return true
			})
		}
	}
}

func (s *Server) log(level int, format string, args ...interface{}) {
	if level > s.logLevel {
		return
	}

	prefix := ""
	switch level {
	case logError:
		prefix = "[ERROR] "
	case logInfo:
		prefix = "[INFO]  "
	case logDebug:
		prefix = "[DEBUG] "
	}

	fmt.Printf("%s%s %s\n", prefix, time.Now().Format("15:04:05"), fmt.Sprintf(format, args...))
}
