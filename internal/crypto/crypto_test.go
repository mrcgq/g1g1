package crypto

import (
	"testing"
)

func TestGeneratePSK(t *testing.T) {
	psk, err := GeneratePSK()
	if err != nil {
		t.Fatalf("生成 PSK 失败: %v", err)
	}
	if len(psk) == 0 {
		t.Fatal("PSK 为空")
	}
}

func TestNewCrypto(t *testing.T) {
	psk, _ := GeneratePSK()
	c, err := New(psk, 30)
	if err != nil {
		t.Fatalf("创建 Crypto 失败: %v", err)
	}

	userID := c.GetUserID()
	if userID == [UserIDSize]byte{} {
		t.Fatal("UserID 为空")
	}
}

func TestEncryptDecrypt(t *testing.T) {
	psk, _ := GeneratePSK()
	c, _ := New(psk, 30)

	plaintext := []byte("Hello, Phantom!")

	encrypted, err := c.Encrypt(plaintext)
	if err != nil {
		t.Fatalf("加密失败: %v", err)
	}

	decrypted, err := c.Decrypt(encrypted)
	if err != nil {
		t.Fatalf("解密失败: %v", err)
	}

	if string(decrypted) != string(plaintext) {
		t.Fatalf("解密结果不匹配")
	}
}

func TestInvalidUserID(t *testing.T) {
	psk1, _ := GeneratePSK()
	psk2, _ := GeneratePSK()

	c1, _ := New(psk1, 30)
	c2, _ := New(psk2, 30)

	plaintext := []byte("Test message")
	encrypted, _ := c1.Encrypt(plaintext)

	_, err := c2.Decrypt(encrypted)
	if err == nil {
		t.Fatal("使用错误的 PSK 解密应该失败")
	}
}

func BenchmarkEncrypt(b *testing.B) {
	psk, _ := GeneratePSK()
	c, _ := New(psk, 30)
	data := make([]byte, 1024)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		_, _ = c.Encrypt(data)
	}
}
