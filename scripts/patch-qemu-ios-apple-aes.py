#!/usr/bin/env python3
"""Replace the QEMU-iOS board's OpenSSL AES shim with Apple's CommonCrypto.

The board only uses AES key setup and AES-CBC. OpenSSL is not part of the
pinned iOS dependency bundle, while CommonCrypto is provided by the iOS SDK.
"""
from pathlib import Path
import sys

header = Path(sys.argv[1])
source = header.read_text()
old = "#include <openssl/aes.h>"
replacement = r"""
#if defined(__APPLE__)
#include <CommonCrypto/CommonCryptor.h>

/* The iPod AES device only needs the key bytes; CommonCrypto expands them. */
typedef struct {
    uint8_t key[32];
    size_t key_len;
} AES_KEY;

#define AES_ENCRYPT 1
#define AES_DECRYPT 0

static inline int AES_set_encrypt_key(const unsigned char *user_key,
                                      const int bits, AES_KEY *key)
{
    if (!user_key || !key || (bits != 128 && bits != 192 && bits != 256)) {
        return -1;
    }
    key->key_len = (size_t)bits / 8;
    memcpy(key->key, user_key, key->key_len);
    return 0;
}

static inline int AES_set_decrypt_key(const unsigned char *user_key,
                                      const int bits, AES_KEY *key)
{
    return AES_set_encrypt_key(user_key, bits, key);
}

/* Match OpenSSL AES_cbc_encrypt's in-place support and mutable IV semantics. */
static inline void AES_cbc_encrypt(const unsigned char *in,
                                   unsigned char *out,
                                   size_t length,
                                   const AES_KEY *key,
                                   unsigned char *ivec,
                                   const int enc)
{
    size_t moved = 0;
    uint8_t last_ciphertext[16];
    if (length == 0) {
        return;
    }
    g_assert(in && out && key && ivec && key->key_len > 0);
    g_assert((length & 15) == 0);
    if (enc == AES_DECRYPT) {
        memcpy(last_ciphertext, in + length - sizeof(last_ciphertext),
               sizeof(last_ciphertext));
    }
    CCCryptorStatus status = CCCrypt(enc == AES_ENCRYPT ? kCCEncrypt : kCCDecrypt,
                                     kCCAlgorithmAES, 0,
                                     key->key, key->key_len, ivec,
                                     in, length, out, length, &moved);
    g_assert(status == kCCSuccess && moved == length);
    if (enc == AES_ENCRYPT) {
        memcpy(ivec, out + length - 16, 16);
    } else {
        memcpy(ivec, last_ciphertext, 16);
    }
}
#else
#include <openssl/aes.h>
#endif
"""
if old not in source:
    if "CommonCrypto/CommonCryptor.h" in source:
        print("CommonCrypto AES compatibility shim already installed")
        raise SystemExit(0)
    raise SystemExit(f"Expected OpenSSL include not found in {header}")
header.write_text(source.replace(old, replacement, 1))
print(f"Patched Apple AES compatibility in {header}")
