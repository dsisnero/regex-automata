// memchr 2.8.1 combined byte and packed-pair vector operations.
// Bounds, candidate order and NEON nibble masks follow its vector.rs and
// arch/{generic,aarch64,x86_64} implementations. One FFI entry per scan.
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#if !defined(RA_BYTE_FORCE_SCALAR) && defined(__aarch64__) && defined(__ARM_NEON) && defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#include <arm_neon.h>
#define RA_BYTE_NEON 1
#else
#define RA_BYTE_NEON 0
#endif
#if !defined(RA_BYTE_FORCE_SCALAR) && defined(__x86_64__) && defined(__SSE2__)
#include <immintrin.h>
#define RA_BYTE_X86 1
#else
#define RA_BYTE_X86 0
#endif

static int64_t scan_scalar(const uint8_t *h, size_t n, uint8_t a, uint8_t b, uint8_t c, int count, int reverse) {
    if (reverse) {
        while (n) { --n; uint8_t x = h[n]; if (x == a || (count > 1 && x == b) || (count > 2 && x == c)) return (int64_t)n; }
    } else {
        for (size_t i = 0; i < n; ++i) { uint8_t x = h[i]; if (x == a || (count > 1 && x == b) || (count > 2 && x == c)) return (int64_t)i; }
    }
    return -1;
}

static int64_t pair_scalar(const uint8_t *h, size_t n, const uint8_t *needle, size_t len, size_t a, size_t b, int verify) {
    if (n < len) return -1;
    for (size_t i = 0; i <= n - len; ++i) {
        if (h[i + a] == needle[a] && h[i + b] == needle[b] && (!verify || memcmp(h + i, needle, len) == 0)) return (int64_t)i;
    }
    return -1;
}

// FACTOR bits represent each lane (four on NEON, one on x86).
#define DEFINE_SCANS(NAME, ATTR, V, W, LOAD, SPLAT, EQ, OR, AND, MASK, FACTOR) \
ATTR static int64_t scan_##NAME(const uint8_t *h, size_t n, uint8_t a, uint8_t b, uint8_t c, int count, int reverse) { \
    V va = SPLAT(a), vb = SPLAT(b), vc = SPLAT(c); size_t pos = reverse ? n : 0; \
    while (reverse ? pos >= W : n - pos >= W) { \
        if (reverse) pos -= W; V data = LOAD(h + pos); V matches = EQ(data, va); \
        if (count > 1) matches = OR(matches, EQ(data, vb)); \
        if (count > 2) matches = OR(matches, EQ(data, vc)); \
        uint64_t bits = MASK(matches); \
        if (bits) { size_t lane = reverse ? (63u - (unsigned)__builtin_clzll(bits)) / FACTOR : (unsigned)__builtin_ctzll(bits) / FACTOR; return (int64_t)(pos + lane); } \
        if (!reverse) pos += W; \
    } \
    int64_t tail = reverse ? scan_scalar(h, pos, a, b, c, count, 1) : scan_scalar(h + pos, n - pos, a, b, c, count, 0); \
    return tail < 0 || reverse ? tail : (int64_t)pos + tail; \
} \
ATTR static int64_t pair_##NAME(const uint8_t *h, size_t n, const uint8_t *needle, size_t len, size_t a, size_t b, int verify) { \
    if (n < len) return -1; size_t count = n - len + 1; size_t pos = 0; \
    V va = SPLAT(needle[a]), vb = SPLAT(needle[b]); \
    while (count - pos >= W) { \
        V matches = AND(EQ(LOAD(h + pos + a), va), EQ(LOAD(h + pos + b), vb)); uint64_t bits = MASK(matches); \
        while (bits) { size_t lane = (unsigned)__builtin_ctzll(bits) / FACTOR; bits &= ~(((UINT64_C(1) << FACTOR) - 1) << (lane * FACTOR)); \
            size_t at = pos + lane; if (!verify || memcmp(h + at, needle, len) == 0) return (int64_t)at; } \
        pos += W; \
    } \
    int64_t tail = pair_scalar(h + pos, n - pos, needle, len, a, b, verify); return tail < 0 ? tail : (int64_t)pos + tail; \
}

#if RA_BYTE_NEON
#define NLOAD(p) vld1q_u8(p)
#define NMASK(v) vget_lane_u64(vreinterpret_u64_u8(vshrn_n_u16(vreinterpretq_u16_u8(v), 4)), 0)
DEFINE_SCANS(neon, , uint8x16_t, 16, NLOAD, vdupq_n_u8, vceqq_u8, vorrq_u8, vandq_u8, NMASK, 4)
#endif
#if RA_BYTE_X86
#define SLOAD(p) _mm_loadu_si128((const __m128i *)(p))
#define ALOAD(p) _mm256_loadu_si256((const __m256i *)(p))
#define SMASK(v) ((uint32_t)_mm_movemask_epi8(v))
#define AMASK(v) ((uint32_t)_mm256_movemask_epi8(v))
DEFINE_SCANS(sse2, __attribute__((target("sse2"))), __m128i, 16, SLOAD, _mm_set1_epi8, _mm_cmpeq_epi8, _mm_or_si128, _mm_and_si128, SMASK, 1)
DEFINE_SCANS(avx2, __attribute__((target("avx2"))), __m256i, 32, ALOAD, _mm256_set1_epi8, _mm256_cmpeq_epi8, _mm256_or_si256, _mm256_and_si256, AMASK, 1)
#endif

int ra_byte_vector_width(void) {
#if RA_BYTE_X86
#ifndef RA_BYTE_FORCE_SSE2
    if (__builtin_cpu_supports("avx2")) return 32;
#endif
    return 16;
#elif RA_BYTE_NEON
    return 16;
#else
    return 0;
#endif
}

int64_t ra_byte_find(const uint8_t *h, size_t n, uint8_t a, uint8_t b, uint8_t c, int count, int reverse) {
    if (!n || count < 1 || count > 3) return -1;
    if (!reverse && count == 1) { const uint8_t *found = (const uint8_t *)memchr(h, a, n); return found ? (int64_t)(found - h) : -1; }
#if RA_BYTE_X86
#ifndef RA_BYTE_FORCE_SSE2
    if (__builtin_cpu_supports("avx2")) return scan_avx2(h, n, a, b, c, count, reverse);
#endif
    return scan_sse2(h, n, a, b, c, count, reverse);
#elif RA_BYTE_NEON
    return scan_neon(h, n, a, b, c, count, reverse);
#else
    return scan_scalar(h, n, a, b, c, count, reverse);
#endif
}

int64_t ra_pair_find(const uint8_t *h, size_t n, const uint8_t *needle, size_t len, size_t a, size_t b, int verify) {
#if RA_BYTE_X86
#ifndef RA_BYTE_FORCE_SSE2
    if (__builtin_cpu_supports("avx2")) return pair_avx2(h, n, needle, len, a, b, verify);
#endif
    return pair_sse2(h, n, needle, len, a, b, verify);
#elif RA_BYTE_NEON
    return pair_neon(h, n, needle, len, a, b, verify);
#else
    return pair_scalar(h, n, needle, len, a, b, verify);
#endif
}
