package protocol

import (
	"testing"
)

func TestParseRequestTCP(t *testing.T) {
	data := []byte{
		TypeRequest,
		NetworkTCP,
		AddrIPv4,
		8, 8, 8, 8,
		0x00, 0x50,
		'H', 'e', 'l', 'l', 'o',
	}

	req, err := ParseRequest(data)
	if err != nil {
		t.Fatalf("解析失败: %v", err)
	}

	if req.Network != "tcp" {
		t.Errorf("Network 错误: %s", req.Network)
	}
	if req.Address != "8.8.8.8" {
		t.Errorf("Address 错误: %s", req.Address)
	}
	if req.Port != 80 {
		t.Errorf("Port 错误: %d", req.Port)
	}
}

func TestParseRequestDomain(t *testing.T) {
	domain := "example.com"
	data := []byte{
		TypeRequest,
		NetworkTCP,
		AddrDomain,
		byte(len(domain)),
	}
	data = append(data, []byte(domain)...)
	data = append(data, 0x01, 0xBB)

	req, err := ParseRequest(data)
	if err != nil {
		t.Fatalf("解析失败: %v", err)
	}

	if req.Address != domain {
		t.Errorf("Address 错误: %s", req.Address)
	}
	if req.Port != 443 {
		t.Errorf("Port 错误: %d", req.Port)
	}
}

func TestBuildResponse(t *testing.T) {
	data := []byte("response data")
	resp := BuildResponse(data)

	if resp[0] != TypeResponse {
		t.Errorf("Type 错误: %d", resp[0])
	}
	if resp[1] != 0x00 {
		t.Errorf("Status 错误: %d", resp[1])
	}
}
