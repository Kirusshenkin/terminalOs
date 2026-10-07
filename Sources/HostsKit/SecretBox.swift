public import Foundation

/// Opening a libsodium `crypto_secretbox` (XSalsa20-Poly1305).
///
/// Termius шифрует им всё своё хранилище, а ни CryptoKit, ни CommonCrypto
/// этого шифра не знают. Своя реализация — сотня строк против чужой
/// библиотеки (CLAUDE.md), и проверяется она векторами, сгенерированными
/// эталонной `golang.org/x/crypto/nacl/secretbox` (`SecretBoxTests`).
///
/// Only opening: Phosphor reads these boxes, it never writes them.
public enum SecretBox {
    public static let keySize = 32
    public static let nonceSize = 24
    public static let tagSize = 16

    /// Plaintext of `box` (tag followed by ciphertext), or nil when the tag
    /// does not match: wrong key or altered bytes — the two look the same.
    public static func open(_ box: Data, nonce: Data, key: Data) -> Data? {
        guard key.count == keySize, nonce.count == nonceSize, box.count >= tagSize else { return nil }
        let keyBytes = [UInt8](key), nonceBytes = [UInt8](nonce), boxBytes = [UInt8](box)
        // XSalsa20: HSalsa20 по первым 16 байтам nonce даёт подключ, остальные
        // 8 — nonce обычного Salsa20.
        let subkey = hsalsa20(key: keyBytes, input: Array(nonceBytes[0..<16]))
        let streamNonce = Array(nonceBytes[16..<24])
        // Первые 32 байта потока — одноразовый ключ Poly1305, шифртекст
        // начинается с 33-го: так устроен crypto_secretbox.
        let ciphertext = Array(boxBytes[tagSize...])
        let stream = salsa20Stream(key: subkey, nonce: streamNonce, count: 32 + ciphertext.count)
        let tag = poly1305(message: ciphertext, key: Array(stream[0..<32]))
        guard constantTimeEqual(tag, Array(boxBytes[0..<tagSize])) else { return nil }
        var plain = [UInt8](repeating: 0, count: ciphertext.count)
        for index in plain.indices { plain[index] = ciphertext[index] ^ stream[32 + index] }
        return Data(plain)
    }

    // MARK: - Salsa20

    private static let sigma: [UInt32] = [0x6170_7865, 0x3320_646e, 0x7962_2d32, 0x6b20_6574]

    private static func word(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    /// Twenty rounds over the state, in place.
    private static func rounds(_ x: inout [UInt32]) {
        func quarter(_ a0: Int, _ b0: Int, _ c0: Int, _ d0: Int) {
            x[b0] ^= (x[a0] &+ x[d0]).rotatedLeft(7)
            x[c0] ^= (x[b0] &+ x[a0]).rotatedLeft(9)
            x[d0] ^= (x[c0] &+ x[b0]).rotatedLeft(13)
            x[a0] ^= (x[d0] &+ x[c0]).rotatedLeft(18)
        }
        for _ in 0..<10 {
            quarter(0, 4, 8, 12)
            quarter(5, 9, 13, 1)
            quarter(10, 14, 2, 6)
            quarter(15, 3, 7, 11)
            quarter(0, 1, 2, 3)
            quarter(5, 6, 7, 4)
            quarter(10, 11, 8, 9)
            quarter(15, 12, 13, 14)
        }
    }

    private static func state(key: [UInt8], input: [UInt8]) -> [UInt32] {
        [
            sigma[0], word(key, 0), word(key, 4), word(key, 8),
            word(key, 12), sigma[1], word(input, 0), word(input, 4),
            word(input, 8), word(input, 12), sigma[2], word(key, 16),
            word(key, 20), word(key, 24), word(key, 28), sigma[3],
        ]
    }

    /// HSalsa20: 16 input bytes → 32 key bytes. Also the second half of
    /// `crypto_box_beforenm`, which turns an X25519 secret into a box key.
    static func hsalsa20(key: [UInt8], input: [UInt8]) -> [UInt8] {
        var x = state(key: key, input: input)
        rounds(&x)
        // Без прибавления исходного состояния: этим HSalsa20 и отличается.
        return [0, 5, 10, 15, 6, 7, 8, 9].flatMap { x[$0].littleEndianBytes }
    }

    private static func salsa20Stream(key: [UInt8], nonce: [UInt8], count: Int) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(count + 64)
        var counter: UInt64 = 0
        while out.count < count {
            var input = nonce
            input += withUnsafeBytes(of: counter.littleEndian, Array.init)
            let start = state(key: key, input: input)
            var x = start
            rounds(&x)
            for index in 0..<16 { out += (x[index] &+ start[index]).littleEndianBytes }
            counter += 1
        }
        return Array(out[0..<count])
    }

    // MARK: - Poly1305

    /// Poly1305 over 26-bit limbs (the "donna-32" layout): every product fits
    /// in 64 bits without carries between multiplications.
    static func poly1305(message: [UInt8], key: [UInt8]) -> [UInt8] {
        let mask: UInt32 = 0x3ff_ffff
        let r0 = UInt64(word(key, 0) & 0x3ff_ffff)
        let r1 = UInt64((word(key, 3) >> 2) & 0x3ff_ff03)
        let r2 = UInt64((word(key, 6) >> 4) & 0x3ff_c0ff)
        let r3 = UInt64((word(key, 9) >> 6) & 0x3f0_3fff)
        let r4 = UInt64((word(key, 12) >> 8) & 0x00f_ffff)
        let s1 = r1 * 5, s2 = r2 * 5, s3 = r3 * 5, s4 = r4 * 5
        var h0: UInt64 = 0, h1: UInt64 = 0, h2: UInt64 = 0, h3: UInt64 = 0, h4: UInt64 = 0

        var offset = 0
        while offset < message.count {
            var block = [UInt8](repeating: 0, count: 17)
            let take = min(16, message.count - offset)
            block.replaceSubrange(0..<take, with: message[offset..<(offset + take)])
            // Неполный последний блок дополняется единицей сразу за данными,
            // полный — единицей в 129-м бите.
            block[take] = 1
            let hibit = UInt64(block[16]) << 24
            h0 += UInt64(word(block, 0) & mask)
            h1 += UInt64((word(block, 3) >> 2) & mask)
            h2 += UInt64((word(block, 6) >> 4) & mask)
            h3 += UInt64((word(block, 9) >> 6) & mask)
            h4 += UInt64(word(block, 12) >> 8) | hibit

            let d0 = h0 * r0 + h1 * s4 + h2 * s3 + h3 * s2 + h4 * s1
            var d1 = h0 * r1 + h1 * r0 + h2 * s4 + h3 * s3 + h4 * s2
            var d2 = h0 * r2 + h1 * r1 + h2 * r0 + h3 * s4 + h4 * s3
            var d3 = h0 * r3 + h1 * r2 + h2 * r1 + h3 * r0 + h4 * s4
            var d4 = h0 * r4 + h1 * r3 + h2 * r2 + h3 * r1 + h4 * r0
            var carry = d0 >> 26
            h0 = d0 & UInt64(mask)
            d1 += carry
            carry = d1 >> 26
            h1 = d1 & UInt64(mask)
            d2 += carry
            carry = d2 >> 26
            h2 = d2 & UInt64(mask)
            d3 += carry
            carry = d3 >> 26
            h3 = d3 & UInt64(mask)
            d4 += carry
            carry = d4 >> 26
            h4 = d4 & UInt64(mask)
            h0 += carry * 5
            carry = h0 >> 26
            h0 &= UInt64(mask)
            h1 += carry
            offset += 16
        }

        // Полная свёртка по модулю 2^130 - 5.
        var carry = h1 >> 26
        h1 &= UInt64(mask)
        h2 += carry
        carry = h2 >> 26
        h2 &= UInt64(mask)
        h3 += carry
        carry = h3 >> 26
        h3 &= UInt64(mask)
        h4 += carry
        carry = h4 >> 26
        h4 &= UInt64(mask)
        h0 += carry * 5
        carry = h0 >> 26
        h0 &= UInt64(mask)
        h1 += carry

        // h - p: если не ушло в минус, берём его, иначе h.
        var g0 = h0 + 5
        carry = g0 >> 26
        g0 &= UInt64(mask)
        var g1 = h1 + carry
        carry = g1 >> 26
        g1 &= UInt64(mask)
        var g2 = h2 + carry
        carry = g2 >> 26
        g2 &= UInt64(mask)
        var g3 = h3 + carry
        carry = g3 >> 26
        g3 &= UInt64(mask)
        let g4 = h4 &+ carry &- (1 << 26)
        let keepG = (g4 >> 63) &- 1  // all ones when g4 did not go negative
        let keepH = ~keepG
        h0 = (h0 & keepH) | (g0 & keepG)
        h1 = (h1 & keepH) | (g1 & keepG)
        h2 = (h2 & keepH) | (g2 & keepG)
        h3 = (h3 & keepH) | (g3 & keepG)
        h4 = (h4 & keepH) | (g4 & keepG)

        return serialize([h0, h1, h2, h3, h4], key: key)
    }

    /// Limbs back into 128 bits, plus the second half of the key.
    private static func serialize(_ limbs: [UInt64], key: [UInt8]) -> [UInt8] {
        let (h0, h1, h2, h3, h4) = (limbs[0], limbs[1], limbs[2], limbs[3], limbs[4])
        let w0 = (h0 | h1 << 26) & 0xffff_ffff
        let w1 = (h1 >> 6 | h2 << 20) & 0xffff_ffff
        let w2 = (h2 >> 12 | h3 << 14) & 0xffff_ffff
        let w3 = (h3 >> 18 | h4 << 8) & 0xffff_ffff
        var sum = w0 + UInt64(word(key, 16))
        var tag: [UInt8] = UInt32(truncatingIfNeeded: sum).littleEndianBytes
        sum = w1 + UInt64(word(key, 20)) + (sum >> 32)
        tag += UInt32(truncatingIfNeeded: sum).littleEndianBytes
        sum = w2 + UInt64(word(key, 24)) + (sum >> 32)
        tag += UInt32(truncatingIfNeeded: sum).littleEndianBytes
        sum = w3 + UInt64(word(key, 28)) + (sum >> 32)
        tag += UInt32(truncatingIfNeeded: sum).littleEndianBytes
        return tag
    }

    private static func constantTimeEqual(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for index in lhs.indices { diff |= lhs[index] ^ rhs[index] }
        return diff == 0
    }
}

extension UInt32 {
    fileprivate func rotatedLeft(_ count: UInt32) -> UInt32 { self << count | self >> (32 - count) }
    fileprivate var littleEndianBytes: [UInt8] { withUnsafeBytes(of: littleEndian, Array.init) }
}
