#ifndef PROJECT_ASTRA_OPENSSL_BN_COMPAT_H
#define PROJECT_ASTRA_OPENSSL_BN_COMPAT_H

/*
 * Minimal OpenSSL BIGNUM API used by ipod_touch_pke.c.
 * Backed by GMP, which is already part of the pinned Orchard iOS dependency
 * archive. Values are imported little-endian from the emulated PKE SRAM and
 * exported as fixed-width big-endian RSA/Montgomery results.
 */
#include <gmp.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

typedef struct bignum_st {
    mpz_t value;
} BIGNUM;

typedef struct project_astra_bn_ctx_st {
    int unused;
} BN_CTX;

static inline BIGNUM *BN_new(void)
{
    BIGNUM *value = calloc(1, sizeof(*value));
    if (value) {
        mpz_init(value->value);
    }
    return value;
}

static inline void BN_free(BIGNUM *value)
{
    if (value) {
        mpz_clear(value->value);
        free(value);
    }
}

static inline BN_CTX *BN_CTX_new(void)
{
    return calloc(1, sizeof(BN_CTX));
}

static inline void BN_CTX_free(BN_CTX *ctx)
{
    free(ctx);
}

static inline BIGNUM *BN_lebin2bn(const unsigned char *bytes, int length,
                                  BIGNUM *result)
{
    if (!bytes || length < 0) {
        return NULL;
    }
    if (!result) {
        result = BN_new();
    }
    if (!result) {
        return NULL;
    }
    mpz_import(result->value, (size_t)length, -1, 1, 0, 0, bytes);
    return result;
}

static inline void BN_set_negative(BIGNUM *value, int negative)
{
    if (!value) {
        return;
    }
    if (negative) {
        if (mpz_sgn(value->value) > 0) {
            mpz_neg(value->value, value->value);
        }
    } else {
        mpz_abs(value->value, value->value);
    }
}

static inline int BN_one(BIGNUM *value)
{
    if (!value) {
        return 0;
    }
    mpz_set_ui(value->value, 1);
    return 1;
}

static inline int BN_is_odd(const BIGNUM *value)
{
    return value && mpz_odd_p(value->value);
}

static inline int BN_is_one(const BIGNUM *value)
{
    return value && mpz_cmp_ui(value->value, 1) == 0;
}

static inline int BN_set_bit(BIGNUM *value, int bit)
{
    if (!value || bit < 0) {
        return 0;
    }
    mpz_setbit(value->value, (mp_bitcnt_t)bit);
    return 1;
}

static inline BIGNUM *BN_mod_inverse(BIGNUM *result, const BIGNUM *a,
                                     const BIGNUM *modulus, BN_CTX *ctx)
{
    (void)ctx;
    if (!result || !a || !modulus ||
        mpz_invert(result->value, a->value, modulus->value) == 0) {
        return NULL;
    }
    return result;
}

static inline int BN_mod_mul(BIGNUM *result, const BIGNUM *a,
                             const BIGNUM *b, const BIGNUM *modulus,
                             BN_CTX *ctx)
{
    (void)ctx;
    if (!result || !a || !b || !modulus || mpz_sgn(modulus->value) <= 0) {
        return 0;
    }
    mpz_mul(result->value, a->value, b->value);
    mpz_mod(result->value, result->value, modulus->value);
    return 1;
}

static inline int BN_bn2binpad(const BIGNUM *value, unsigned char *output,
                               int output_length)
{
    if (!value || !output || output_length < 0 ||
        mpz_sgn(value->value) < 0) {
        return -1;
    }
    if (mpz_sgn(value->value) == 0) {
        memset(output, 0, (size_t)output_length);
        return output_length;
    }
    size_t bytes = (mpz_sizeinbase(value->value, 2) + 7) / 8;
    if (bytes > (size_t)output_length) {
        return -1;
    }
    memset(output, 0, (size_t)output_length);
    size_t written = 0;
    if (bytes) {
        mpz_export(output + output_length - bytes, &written, 1, 1, 1, 0,
                   value->value);
    }
    return written == bytes ? output_length : -1;
}

#endif /* PROJECT_ASTRA_OPENSSL_BN_COMPAT_H */
