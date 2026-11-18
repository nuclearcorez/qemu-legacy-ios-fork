#ifndef PROJECT_ASTRA_OPENSSL_AES_COMPAT_H
#define PROJECT_ASTRA_OPENSSL_AES_COMPAT_H

/*
 * QEMU's iPod-touch AES device uses the small OpenSSL AES API surface below.
 * iOS does not ship OpenSSL headers, so the iOS build maps that surface onto
 * Apple's CommonCrypto. Non-Apple builds keep using their normal OpenSSL.
 */
#if defined(__APPLE__)

#include <CommonCrypto/CommonCryptor.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

#define AES_BLOCK_SIZE 16
#define AES_ENCRYPT 1
#define AES_DECRYPT 0

typedef struct project_astra_aes_key_st {
    uint8_t key[32];
    int bits;
} AES_KEY;

static inline int AES_set_encrypt_key(const unsigned char *user_key,
                                      const int bits, AES_KEY *key)
{
    if (!user_key || !key || (bits != 128 && bits != 192 && bits != 256)) {
        return -1;
    }
    memset(key, 0, sizeof(*key));
    memcpy(key->key, user_key, (size_t)bits / 8);
    key->bits = bits;
    return 0;
}

static inline int AES_set_decrypt_key(const unsigned char *user_key,
                                      const int bits, AES_KEY *key)
{
    return AES_set_encrypt_key(user_key, bits, key);
}

/* CBC is implemented one block at a time so the caller's IV is advanced
 * exactly as OpenSSL's AES_cbc_encrypt does, including for in-place buffers. */
static inline void AES_cbc_encrypt(const unsigned char *in,
                                   unsigned char *out,
                                   size_t length,
                                   const AES_KEY *key,
                                   unsigned char *ivec,
                                   const int enc)
{
    if (!in || !out || !key || !ivec || (length % AES_BLOCK_SIZE) != 0) {
        return;
    }

    for (size_t offset = 0; offset < length; offset += AES_BLOCK_SIZE) {
        uint8_t input_block[AES_BLOCK_SIZE];
        uint8_t output_block[AES_BLOCK_SIZE];
        size_t moved = 0;
        memcpy(input_block, in + offset, AES_BLOCK_SIZE);

        if (enc == AES_ENCRYPT) {
            for (size_t i = 0; i < AES_BLOCK_SIZE; ++i) {
                input_block[i] ^= ivec[i];
            }
        }

        CCCryptorStatus status = CCCrypt(
            enc == AES_ENCRYPT ? kCCEncrypt : kCCDecrypt,
            kCCAlgorithmAES,
            kCCOptionECBMode | kCCOptionNoPadding,
            key->key,
            (size_t)key->bits / 8,
            NULL,
            input_block,
            AES_BLOCK_SIZE,
            output_block,
            AES_BLOCK_SIZE,
            &moved
        );
        if (status != kCCSuccess || moved != AES_BLOCK_SIZE) {
            memset(output_block, 0, sizeof(output_block));
        }

        if (enc == AES_DECRYPT) {
            for (size_t i = 0; i < AES_BLOCK_SIZE; ++i) {
                output_block[i] ^= ivec[i];
            }
            memcpy(ivec, input_block, AES_BLOCK_SIZE);
        } else {
            memcpy(ivec, output_block, AES_BLOCK_SIZE);
        }
        memcpy(out + offset, output_block, AES_BLOCK_SIZE);
    }
}

#else
#include_next <openssl/aes.h>
#endif

#endif /* PROJECT_ASTRA_OPENSSL_AES_COMPAT_H */
