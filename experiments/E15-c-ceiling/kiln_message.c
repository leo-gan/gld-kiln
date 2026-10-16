/* Frozen encode/decode of the Kiln message used in the Mojo probe. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static void put_u32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

static void put_u64(uint8_t *p, uint64_t v) {
    for (int i = 0; i < 8; i++) p[i] = (uint8_t)(v >> (8 * i));
}

static volatile int32_t g_i32 = -2;
static volatile uint64_t g_i64 = 99;

static int encode(uint8_t *out) {
    int n = 0;
    out[n++] = 1;
    put_u32(out + n, (uint32_t)g_i32);
    n += 4;
    put_u64(out + n, g_i64);
    n += 8;
    put_u64(out + n, 0x3FF8000000000000ull); /* 1.5 */
    n += 8;
    put_u32(out + n, 5);
    n += 4;
    memcpy(out + n, "hello", 5);
    n += 5;
    out[n++] = 0;
    put_u32(out + n, 7);
    n += 4;
    put_u32(out + n, 5);
    n += 4;
    memcpy(out + n, "world", 5);
    n += 5;
    return n;
}

static int decode(const uint8_t *in, int len) {
    if (len < 44) return 0;
    int32_t i32;
    memcpy(&i32, in + 1, 4);
    return (int)in[0] + i32 + (int)in[30];
}

int main(void) {
    uint8_t buf[64];
    int len = encode(buf);
    int sink = 0;
    for (int i = 0; i < 50; i++) sink += encode(buf);
    struct timespec a, b;
    clock_gettime(CLOCK_MONOTONIC, &a);
    const int reps = 100000;
    for (int i = 0; i < reps; i++) {
        sink += encode(buf);
        sink += buf[0];
    }
    clock_gettime(CLOCK_MONOTONIC, &b);
    long ns = (b.tv_sec - a.tv_sec) * 1000000000L + (b.tv_nsec - a.tv_nsec);
    printf("c_encode_mean %ld total_ns %ld len %d sink %d\n", ns / reps, ns, len, sink);
    clock_gettime(CLOCK_MONOTONIC, &a);
    for (int i = 0; i < reps; i++) sink += decode(buf, len) + buf[1];
    clock_gettime(CLOCK_MONOTONIC, &b);
    ns = (b.tv_sec - a.tv_sec) * 1000000000L + (b.tv_nsec - a.tv_nsec);
    printf("c_decode_mean %ld total_ns %ld sink %d\n", ns / reps, ns, sink);
    return 0;
}
