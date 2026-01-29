package protocol

import (
	"encoding/binary"
	"fmt"
	"net"
)

const (
	TypeRequest  = 0x01
	TypeResponse = 0x02
)

const (
	AddrIPv4   = 0x01
	AddrIPv6   = 0x04
	AddrDomain = 0x03
)

const (
	NetworkTCP = 0x01
	NetworkUDP = 0x02
)

// Request 解析后的请求
type Request struct {
	Type    byte
	Network string
	Address string
	Port    uint16
	Data    []byte
}

// ParseRequest 解析请求
func ParseRequest(data []byte) (*Request, error) {
	if len(data) < 5 {
		return nil, fmt.Errorf("数据太短: %d", len(data))
	}

	req := &Request{
		Type: data[0],
	}

	switch data[1] {
	case NetworkTCP:
		req.Network = "tcp"
	case NetworkUDP:
		req.Network = "udp"
	default:
		return nil, fmt.Errorf("未知网络类型: %d", data[1])
	}

	addrType := data[2]
	offset := 3

	switch addrType {
	case AddrIPv4:
		if len(data) < offset+4+2 {
			return nil, fmt.Errorf("IPv4 地址不完整")
		}
		req.Address = net.IP(data[offset : offset+4]).String()
		offset += 4

	case AddrIPv6:
		if len(data) < offset+16+2 {
			return nil, fmt.Errorf("IPv6 地址不完整")
		}
		req.Address = net.IP(data[offset : offset+16]).String()
		offset += 16

	case AddrDomain:
		if len(data) < offset+1 {
			return nil, fmt.Errorf("域名长度缺失")
		}
		domainLen := int(data[offset])
		offset++
		if len(data) < offset+domainLen+2 {
			return nil, fmt.Errorf("域名不完整")
		}
		req.Address = string(data[offset : offset+domainLen])
		offset += domainLen

	default:
		return nil, fmt.Errorf("未知地址类型: %d", addrType)
	}

	if len(data) < offset+2 {
		return nil, fmt.Errorf("端口缺失")
	}
	req.Port = binary.BigEndian.Uint16(data[offset : offset+2])
	offset += 2

	if len(data) > offset {
		req.Data = data[offset:]
	}

	return req, nil
}

// BuildResponse 构建响应
func BuildResponse(data []byte) []byte {
	resp := make([]byte, 2+len(data))
	resp[0] = TypeResponse
	resp[1] = 0x00
	copy(resp[2:], data)
	return resp
}

// BuildErrorResponse 构建错误响应
func BuildErrorResponse(code byte) []byte {
	return []byte{TypeResponse, code}
}

// TargetAddr 返回目标地址
func (r *Request) TargetAddr() string {
	return fmt.Sprintf("%s:%d", r.Address, r.Port)
}
