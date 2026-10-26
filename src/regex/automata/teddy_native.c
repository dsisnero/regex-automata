// SIMD lane lookup for aho-corasick 1.1.4's SlimNeon Teddy searcher.
// Bucket construction and the short-haystack Rabin-Karp path live in Crystal.
#include <stdint.h>
#include <stddef.h>
#include <string.h>

#if defined(__aarch64__) && defined(__ARM_NEON) && defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#include <arm_neon.h>
#define RA_TEDDY_NEON 1
#else
#define RA_TEDDY_NEON 0
#endif

#if defined(__x86_64__) && defined(__SSE2__) && defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
#include <immintrin.h>
#define RA_TEDDY_X86 1
#else
#define RA_TEDDY_X86 0
#endif

int ra_teddy_neon_available(void) { return RA_TEDDY_NEON; }

int ra_teddy_capabilities(void) {
    int caps = RA_TEDDY_NEON;
#if defined(__x86_64__) && defined(__SSE2__) && defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    if (__builtin_cpu_supports("ssse3")) caps |= 2;
    if (__builtin_cpu_supports("avx2")) caps |= 4;
#endif
    return caps;
}

#if RA_TEDDY_NEON
// Rust's SlimNeon::candidate: one vector load, 1-4 nibble-table lookups, and
// shift-in of each preceding mask result. This keeps the packed hot path's
// load count and candidate order rather than probing every offset separately.
static inline uint8x16_t shifted(uint8x16_t previous, uint8x16_t current, int bytes) {
    switch (bytes) {
        case 1: return vextq_u8(previous, current, 15);
        case 2: return vextq_u8(previous, current, 14);
        default: return vextq_u8(previous, current, 13);
    }
}

static __attribute__((always_inline)) inline int find_one(
    const uint8_t *hay, size_t cur, size_t end,
    const uint8_t *masks, int mask_len, uint8x16_t previous[3],
    const uint8_t *const *patterns, const size_t *lengths,
    const int32_t *bucket_ids, const int32_t *bucket_offsets,
    size_t *out_start, int32_t *out_id
) {
    uint8x16_t bytes = vld1q_u8(hay + cur);
    uint8x16_t low = vandq_u8(bytes, vdupq_n_u8(0x0f));
    uint8x16_t high = vshrq_n_u8(bytes, 4);
    uint8x16_t candidate = vdupq_n_u8(0xff);
    for (int i = 0; i < mask_len; i++) {
        const uint8_t *mask = masks + 32 * i;
        uint8x16_t lo_bits = vqtbl1q_u8(vld1q_u8(mask), low);
        uint8x16_t hi_bits = vqtbl1q_u8(vld1q_u8(mask + 16), high);
        uint8x16_t member = vandq_u8(lo_bits, hi_bits);
        int shift = mask_len - 1 - i;
        if (shift) {
            candidate = vandq_u8(candidate, shifted(previous[i], member, shift));
            previous[i] = member;
        } else {
            candidate = vandq_u8(candidate, member);
        }
    }
    uint8_t lanes[16];
    vst1q_u8(lanes, candidate);
    size_t base = cur - (size_t)(mask_len - 1);
    // Rust's verify64 walks set bits in ascending lane/bucket order.
    uint64_t chunks[2];
    memcpy(chunks, lanes, sizeof(chunks));
    for (int chunk = 0; chunk < 2; chunk++) {
        uint64_t bits = chunks[chunk];
        while (bits) {
            unsigned bit = (unsigned)__builtin_ctzll(bits);
            bits &= bits - 1;
            size_t at = base + (size_t)(chunk * 8 + (bit >> 3));
            unsigned bucket = bit & 7u;
            for (int32_t j = bucket_offsets[bucket]; j < bucket_offsets[bucket + 1]; j++) {
                int32_t id = bucket_ids[j];
                size_t len = lengths[id];
                if (len <= end - at && memcmp(hay + at, patterns[id], len) == 0) {
                    *out_start = at;
                    *out_id = id;
                    return 1;
                }
            }
        }
    }
    return 0;
}

static __attribute__((always_inline)) inline int find_kernel(
    const uint8_t *hay, size_t start, size_t end,
    const uint8_t *masks, int mask_len,
    const uint8_t *const *patterns, const size_t *lengths,
    const int32_t *bucket_ids, const int32_t *bucket_offsets,
    size_t *out_start, int32_t *out_id
) {
    if (end - start < (size_t)(16 + mask_len - 1)) return 0;
    size_t cur = start + (size_t)(mask_len - 1);
    uint8x16_t previous[3] = {
        vdupq_n_u8(0xff), vdupq_n_u8(0xff), vdupq_n_u8(0xff)
    };
    while (cur <= end - 16) {
        if (find_one(hay, cur, end, masks, mask_len, previous, patterns,
                     lengths, bucket_ids, bucket_offsets, out_start, out_id)) return 1;
        cur += 16;
    }
    if (cur < end) {
        cur = end - 16;
        previous[0] = vdupq_n_u8(0xff);
        previous[1] = vdupq_n_u8(0xff);
        previous[2] = vdupq_n_u8(0xff);
        if (find_one(hay, cur, end, masks, mask_len, previous, patterns,
                     lengths, bucket_ids, bucket_offsets, out_start, out_id)) return 1;
    }
    return 0;
}
#endif

int ra_teddy_neon_find(
    const uint8_t *hay, size_t start, size_t end,
    const uint8_t *masks, int mask_len,
    const uint8_t *const *patterns, const size_t *lengths,
    const int32_t *bucket_ids, const int32_t *bucket_offsets,
    size_t *out_start, int32_t *out_id
) {
#if RA_TEDDY_NEON
    // Rust has four const-generic BYTES variants. Passing literal widths
    // here lets the C optimizer specialize the same hot loop once per width.
    switch (mask_len) {
        case 1: return find_kernel(hay, start, end, masks, 1, patterns, lengths,
                                   bucket_ids, bucket_offsets, out_start, out_id);
        case 2: return find_kernel(hay, start, end, masks, 2, patterns, lengths,
                                   bucket_ids, bucket_offsets, out_start, out_id);
        case 3: return find_kernel(hay, start, end, masks, 3, patterns, lengths,
                                   bucket_ids, bucket_offsets, out_start, out_id);
        case 4: return find_kernel(hay, start, end, masks, 4, patterns, lengths,
                                   bucket_ids, bucket_offsets, out_start, out_id);
        default: return 0;
    }
#else
    (void)hay; (void)start; (void)end; (void)masks; (void)mask_len;
    (void)patterns; (void)lengths; (void)bucket_ids; (void)bucket_offsets;
    (void)out_start; (void)out_id;
    return 0;
#endif
}

#if RA_TEDDY_X86
static int verify_x86(
    const uint8_t *hay, size_t at, size_t end, uint16_t candidates,
    int buckets, const uint8_t *const *patterns, const size_t *lengths,
    const int32_t *bucket_ids, const int32_t *bucket_offsets,
    size_t *out_start, int32_t *out_id
) {
    while (candidates) {
        unsigned bucket = (unsigned)__builtin_ctz((unsigned)candidates);
        candidates &= candidates - 1;
        if ((int)bucket >= buckets) continue;
        for (int32_t j = bucket_offsets[bucket]; j < bucket_offsets[bucket + 1]; j++) {
            int32_t id = bucket_ids[j];
            size_t len = lengths[id];
            if (len <= end - at && memcmp(hay + at, patterns[id], len) == 0) {
                *out_start = at;
                *out_id = id;
                return 1;
            }
        }
    }
    return 0;
}

__attribute__((target("ssse3")))
static int find_one_ssse3(
    const uint8_t *hay, size_t cur, size_t end, const uint8_t *masks,
    int mask_len, int mask_stride, int high_offset,
    __m128i previous[3], const uint8_t *const *patterns,
    const size_t *lengths, const int32_t *bucket_ids,
    const int32_t *bucket_offsets, size_t *out_start, int32_t *out_id
) {
    __m128i bytes = _mm_loadu_si128((const __m128i *)(hay + cur));
    __m128i low = _mm_and_si128(bytes, _mm_set1_epi8(0x0f));
    __m128i high = _mm_and_si128(_mm_srli_epi16(bytes, 4), _mm_set1_epi8(0x0f));
    __m128i candidate = _mm_set1_epi8(-1);
    for (int i = 0; i < mask_len; i++) {
        const uint8_t *mask = masks + mask_stride * i;
        __m128i lo = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i *)mask), low);
        __m128i hi = _mm_shuffle_epi8(_mm_loadu_si128((const __m128i *)(mask + high_offset)), high);
        __m128i member = _mm_and_si128(lo, hi);
        int shift = mask_len - 1 - i;
        if (shift == 1) candidate = _mm_and_si128(candidate, _mm_alignr_epi8(member, previous[i], 15));
        else if (shift == 2) candidate = _mm_and_si128(candidate, _mm_alignr_epi8(member, previous[i], 14));
        else if (shift == 3) candidate = _mm_and_si128(candidate, _mm_alignr_epi8(member, previous[i], 13));
        else candidate = _mm_and_si128(candidate, member);
        if (shift) previous[i] = member;
    }
    uint32_t positions = (uint32_t)~_mm_movemask_epi8(_mm_cmpeq_epi8(candidate, _mm_setzero_si128())) & 0xffffu;
    if (!positions) return 0;
    uint8_t lanes[16];
    _mm_storeu_si128((__m128i *)lanes, candidate);
    size_t base = cur - (size_t)(mask_len - 1);
    while (positions) {
        unsigned lane = (unsigned)__builtin_ctz(positions);
        positions &= positions - 1;
        if (verify_x86(hay, base + (size_t)lane, end, lanes[lane], 8,
            patterns, lengths, bucket_ids, bucket_offsets, out_start, out_id)) return 1;
    }
    return 0;
}

__attribute__((target("ssse3")))
static int find_ssse3(
    const uint8_t *hay, size_t start, size_t end, const uint8_t *masks,
    int mask_len, int mask_stride, int high_offset,
    const uint8_t *const *patterns, const size_t *lengths,
    const int32_t *bucket_ids, const int32_t *bucket_offsets,
    size_t *out_start, int32_t *out_id
) {
    if (end - start < (size_t)(16 + mask_len - 1)) return 0;
    size_t cur = start + (size_t)(mask_len - 1);
    __m128i previous[3] = {_mm_set1_epi8(-1), _mm_set1_epi8(-1), _mm_set1_epi8(-1)};
    while (cur <= end - 16) {
        if (find_one_ssse3(hay, cur, end, masks, mask_len, mask_stride,
            high_offset, previous, patterns,
            lengths, bucket_ids, bucket_offsets, out_start, out_id)) return 1;
        cur += 16;
    }
    if (cur < end) {
        cur = end - 16;
        previous[0] = previous[1] = previous[2] = _mm_set1_epi8(-1);
        return find_one_ssse3(hay, cur, end, masks, mask_len, mask_stride,
            high_offset, previous, patterns,
            lengths, bucket_ids, bucket_offsets, out_start, out_id);
    }
    return 0;
}

__attribute__((target("avx2")))
static int find_one_avx2(
    const uint8_t *hay, size_t cur, size_t end, const uint8_t *masks,
    int mask_len, int fat, __m256i previous[3], const uint8_t *const *patterns,
    const size_t *lengths, const int32_t *bucket_ids,
    const int32_t *bucket_offsets, size_t *out_start, int32_t *out_id
) {
    __m256i bytes = fat ? _mm256_broadcastsi128_si256(_mm_loadu_si128((const __m128i *)(hay + cur)))
                        : _mm256_loadu_si256((const __m256i *)(hay + cur));
    __m256i low = _mm256_and_si256(bytes, _mm256_set1_epi8(0x0f));
    __m256i high = _mm256_and_si256(_mm256_srli_epi16(bytes, 4), _mm256_set1_epi8(0x0f));
    __m256i candidate = _mm256_set1_epi8(-1);
    for (int i = 0; i < mask_len; i++) {
        const uint8_t *mask = masks + 64 * i;
        __m256i lo = _mm256_shuffle_epi8(_mm256_loadu_si256((const __m256i *)mask), low);
        __m256i hi = _mm256_shuffle_epi8(_mm256_loadu_si256((const __m256i *)(mask + 32)), high);
        __m256i member = _mm256_and_si256(lo, hi);
        int shift = mask_len - 1 - i;
        if (shift) {
            __m256i bridge = fat ? previous[i] : _mm256_permute2x128_si256(previous[i], member, 0x21);
            if (shift == 1) candidate = _mm256_and_si256(candidate, _mm256_alignr_epi8(member, bridge, 15));
            else if (shift == 2) candidate = _mm256_and_si256(candidate, _mm256_alignr_epi8(member, bridge, 14));
            else candidate = _mm256_and_si256(candidate, _mm256_alignr_epi8(member, bridge, 13));
            previous[i] = member;
        } else candidate = _mm256_and_si256(candidate, member);
    }
    uint32_t nonzero = (uint32_t)~_mm256_movemask_epi8(_mm256_cmpeq_epi8(candidate, _mm256_setzero_si256()));
    uint32_t positions = fat ? ((nonzero | (nonzero >> 16)) & 0xffffu) : nonzero;
    if (!positions) return 0;
    uint8_t lanes[32];
    _mm256_storeu_si256((__m256i *)lanes, candidate);
    size_t base = cur - (size_t)(mask_len - 1);
    while (positions) {
        unsigned lane = (unsigned)__builtin_ctz(positions);
        positions &= positions - 1;
        uint16_t bits = fat ? (uint16_t)(lanes[lane] | ((uint16_t)lanes[lane + 16] << 8)) : lanes[lane];
        if (verify_x86(hay, base + (size_t)lane, end, bits, fat ? 16 : 8,
            patterns, lengths, bucket_ids, bucket_offsets, out_start, out_id)) return 1;
    }
    return 0;
}

__attribute__((target("avx2")))
static int find_avx2(
    const uint8_t *hay, size_t start, size_t end, const uint8_t *masks,
    int mask_len, int fat, const uint8_t *const *patterns, const size_t *lengths,
    const int32_t *bucket_ids, const int32_t *bucket_offsets,
    size_t *out_start, int32_t *out_id
) {
    int width = fat ? 16 : 32;
    if (end - start < (size_t)(width + mask_len - 1)) return 0;
    size_t cur = start + (size_t)(mask_len - 1);
    __m256i previous[3] = {_mm256_set1_epi8(-1), _mm256_set1_epi8(-1), _mm256_set1_epi8(-1)};
    while (cur <= end - (size_t)width) {
        if (find_one_avx2(hay, cur, end, masks, mask_len, fat, previous,
            patterns, lengths, bucket_ids, bucket_offsets, out_start, out_id)) return 1;
        cur += (size_t)width;
    }
    if (cur < end) {
        cur = end - (size_t)width;
        previous[0] = previous[1] = previous[2] = _mm256_set1_epi8(-1);
        return find_one_avx2(hay, cur, end, masks, mask_len, fat, previous,
            patterns, lengths, bucket_ids, bucket_offsets, out_start, out_id);
    }
    return 0;
}
#endif

int ra_teddy_x86_find(
    const uint8_t *hay, size_t start, size_t end, const uint8_t *masks,
    int mask_len, int mode, const uint8_t *const *patterns,
    const size_t *lengths, const int32_t *bucket_ids,
    const int32_t *bucket_offsets, size_t *out_start, int32_t *out_id
) {
#if RA_TEDDY_X86
    if ((mode == 2 || mode == 5) && __builtin_cpu_supports("ssse3"))
        return find_ssse3(hay, start, end, masks, mask_len,
            mode == 5 ? 64 : 32, mode == 5 ? 32 : 16, patterns,
            lengths, bucket_ids, bucket_offsets, out_start, out_id);
    if ((mode == 3 || mode == 4) && __builtin_cpu_supports("avx2"))
        return find_avx2(hay, start, end, masks, mask_len, mode == 4,
            patterns, lengths, bucket_ids, bucket_offsets, out_start, out_id);
#else
    (void)hay; (void)start; (void)end; (void)masks; (void)mask_len;
    (void)mode; (void)patterns; (void)lengths; (void)bucket_ids;
    (void)bucket_offsets; (void)out_start; (void)out_id;
#endif
    return 0;
}
