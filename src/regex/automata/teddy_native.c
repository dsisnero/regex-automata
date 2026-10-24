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

int ra_teddy_neon_available(void) { return RA_TEDDY_NEON; }

#if RA_TEDDY_NEON
static int verify_at(
    const uint8_t *hay, size_t at, size_t end, uint8_t candidates,
    const uint8_t *const *patterns, const size_t *lengths,
    const int32_t *bucket_ids, const int32_t *bucket_offsets,
    size_t *out_start, int32_t *out_id
) {
    for (int bucket = 0; bucket < 8; bucket++) {
        if ((candidates & (uint8_t)(1u << bucket)) == 0) continue;
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
    for (int lane = 0; lane < 16; lane++) {
        if (lanes[lane] == 0) continue;
        if (verify_at(hay, base + (size_t)lane, end, lanes[lane], patterns, lengths,
                      bucket_ids, bucket_offsets, out_start, out_id)) return 1;
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
