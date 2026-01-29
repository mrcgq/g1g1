package crypto

import (
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/binary"
	"fmt"
	"io"
	"time"

	"golang.org/x/crypto/chacha20poly1305"
	"golang.org/x/crypto/hkdf"
)

const (
	PSKSize       = 32
	UserIDSize    = 4
	TimestampSize = 2
	NonceSize     = 12
	TagSize       = 16
	HeaderSize    = UserIDSize + TimestampSize // 6 bytes 明文头
)

// Crypto 加密器
type Crypto struct {
	psk        []byte
	userID     [UserIDSize]byte
	timeWindow int
}

// New 创建加密器
func New(pskBase64 string, timeWindow int) (*Crypto, error) {
	psk, err := base64.StdEncoding.DecodeString(pskBase64)
	if err != nil {
		return nil, fmt.Errorf("PSK 解码失败: %w", err)
	}
	if len(psk) != PSKSize {
		return nil, fmt.Errorf("PSK 长度必须是 %d 字节", PSKSize)
	}

	c := &Crypto{
		psk:        psk,
		timeWindow: timeWindow,
	}

	// 派生 UserID
	c.userID = c.deriveUserID()

	return c, nil
}

// deriveUserID 从 PSK 派生 UserID
func (c *Crypto) deriveUserID() [UserIDSize]byte {
	var id [UserIDSize]byte
	reader := hkdf.New(sha256.New, c.psk, nil, []byte("phantom-userid-v2"))
	io.ReadFull(reader, id[:])
	return id
}

// GetUserID 返回 UserID
func (c *Crypto) GetUserID() [UserIDSize]byte {
	return c.userID
}

// deriveKey 从 PSK 和时间窗口派生会话密钥
func (c *Crypto) deriveKey(window int64) []byte {
	salt := make([]byte, 8)
	binary.BigEndian.PutUint64(salt, uint64(window))

	reader := hkdf.New(sha256.New, c.psk, salt, []byte("phantom-key-v2"))
	key := make([]byte, chacha20poly1305.KeySize)
	io.ReadFull(reader, key)
	return key
}

// currentWindow 返回当前时间窗口
func (c *Crypto) currentWindow() int64 {
	return time.Now().Unix() / int64(c.timeWindow)
}

// validWindows 返回有效的时间窗口列表（允许 ±1 容差）
func (c *Crypto) validWindows() []int64 {
	w := c.currentWindow()
	return []int64{w - 1, w, w + 1}
}

// Encrypt 加密数据
// 返回: [UserID(4)] + [Timestamp(2)] + [Nonce(12)] + [Ciphertext] + [Tag(16)]
func (c *Crypto) Encrypt(plaintext []byte) ([]byte, error) {
	window := c.currentWindow()
	key := c.deriveKey(window)

	aead, err := chacha20poly1305.New(key)
	if err != nil {
		return nil, err
	}

	// 生成随机 nonce
	nonce := make([]byte, NonceSize)
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}

	// 时间戳（当前 Unix 时间的低 16 位）
	timestamp := uint16(time.Now().Unix() & 0xFFFF)

	// 构建输出
	// Header: UserID(4) + Timestamp(2)
	// Body: Nonce(12) + Ciphertext + Tag(16)
	output := make([]byte, HeaderSize+NonceSize+len(plaintext)+TagSize)

	copy(output[:UserIDSize], c.userID[:])
	binary.BigEndian.PutUint16(output[UserIDSize:HeaderSize], timestamp)
	copy(output[HeaderSize:HeaderSize+NonceSize], nonce)

	// 加密（使用 header 作为附加数据）
	ciphertext := aead.Seal(nil, nonce, plaintext, output[:HeaderSize])
	copy(output[HeaderSize+NonceSize:], ciphertext)

	return output, nil
}

// Decrypt 解密数据
// 输入: [UserID(4)] + [Timestamp(2)] + [Nonce(12)] + [Ciphertext] + [Tag(16)]
func (c *Crypto) Decrypt(data []byte) ([]byte, error) {
	minSize := HeaderSize + NonceSize + TagSize
	if len(data) < minSize {
		return nil, fmt.Errorf("数据太短")
	}

	// 验证 UserID
	var userID [UserIDSize]byte
	copy(userID[:], data[:UserIDSize])
	if userID != c.userID {
		return nil, fmt.Errorf("UserID 不匹配")
	}

	// 验证时间戳
	timestamp := binary.BigEndian.Uint16(data[UserIDSize:HeaderSize])
	if !c.validateTimestamp(timestamp) {
		return nil, fmt.Errorf("时间戳无效")
	}

	// 提取 nonce 和密文
	nonce := data[HeaderSize : HeaderSize+NonceSize]
	ciphertext := data[HeaderSize+NonceSize:]
	header := data[:HeaderSize]

	// 尝试所有有效时间窗口
	for _, window := range c.validWindows() {
		key := c.deriveKey(window)
		aead, err := chacha20poly1305.New(key)
		if err != nil {
			continue
		}

		plaintext, err := aead.Open(nil, nonce, ciphertext, header)
		if err == nil {
			return plaintext, nil
		}
	}

	return nil, fmt.Errorf("解密失败")
}

// validateTimestamp 验证时间戳是否在有效范围内
func (c *Crypto) validateTimestamp(ts uint16) bool {
	current := uint16(time.Now().Unix() & 0xFFFF)
	diff := int(current) - int(ts)

	// 处理回绕
	if diff < -32768 {
		diff += 65536
	} else if diff > 32768 {
		diff -= 65536
	}

	// 取绝对值
	if diff < 0 {
		diff = -diff
	}

	return diff <= c.timeWindow*2
}

// GeneratePSK 生成新的 PSK
func GeneratePSK() (string, error) {
	psk := make([]byte, PSKSize)
	if _, err := rand.Read(psk); err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(psk), nil
}
