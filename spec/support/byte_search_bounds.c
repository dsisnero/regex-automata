// Sanitizer oracle for the C bridge: exact-sized allocations prohibit overreads.
#include <assert.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "../../src/regex/automata/byte_search_native.c"
int main(void) {
    for (size_t n = 0; n <= 160; ++n) {
        for (size_t alignment = 0; alignment < 32; ++alignment) {
            uint8_t *allocation = malloc(n + alignment + 1);
            uint8_t *h = allocation + alignment + 1;
            for (size_t i = 0; i < n; ++i) h[i] = (uint8_t)((i * 17 + n) % 256);
            for (int count = 1; count <= 3; ++count) {
                for (int reverse = 0; reverse <= 1; ++reverse) {
                    int64_t want = scan_scalar(h, n, 0, 127, 255, count, reverse);
                    assert(ra_byte_find(h, n, 0, 127, 255, count, reverse) == want);
                }
            }
            for (size_t len = 2; len <= 40; ++len) {
                uint8_t *needle = malloc(len);
                for (size_t i = 0; i < len; ++i) needle[i] = (uint8_t)(i * 17 + 9);
                for (int verify = 0; verify <= 1; ++verify) {
                    int64_t want = pair_scalar(h, n, needle, len, 0, len - 1, verify);
                    assert(ra_pair_find(h, n, needle, len, 0, len - 1, verify) == want);
                    if (n >= len) {
                        memcpy(h + n - len, needle, len);
                        want = pair_scalar(h, n, needle, len, 0, len - 1, verify);
                        assert(ra_pair_find(h, n, needle, len, 0, len - 1, verify) == want);
                    }
                }
                free(needle);
            }
            free(allocation);
        }
    }
    return 0;
}
