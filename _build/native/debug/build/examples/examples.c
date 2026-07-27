#ifdef __cplusplus
extern "C" {
#endif

#include "moonbit.h"
#include "moonbit_simd.h"

#ifdef _MSC_VER
#define _Noreturn __declspec(noreturn)
#endif

#if defined(__clang__)
#pragma clang diagnostic ignored "-Wshift-op-parentheses"
#pragma clang diagnostic ignored "-Wtautological-compare"
#endif

MOONBIT_EXPORT _Noreturn void moonbit_panic(void);
MOONBIT_EXPORT void *moonbit_malloc_array(enum moonbit_block_kind kind,
                                          int elem_size_shift, int32_t len);
int memcmp(const void *s1, const void *s2, size_t n);
MOONBIT_EXPORT int moonbit_val_array_equal_sized(const void *lhs,
                                                 const void *rhs,
                                                 int32_t elem_size);
MOONBIT_EXPORT moonbit_string_t moonbit_add_string(moonbit_string_t s1,
                                                   moonbit_string_t s2);
MOONBIT_EXPORT void moonbit_unsafe_bytes_blit(moonbit_bytes_t dst,
                                              int32_t dst_start,
                                              moonbit_bytes_t src,
                                              int32_t src_offset, int32_t len);
MOONBIT_EXPORT moonbit_string_t moonbit_unsafe_bytes_sub_string(
    moonbit_bytes_t bytes, int32_t start, int32_t len);
MOONBIT_EXPORT int32_t moonbit_unsafe_val_array_blit(void *dst,
                                                     int32_t dst_offset,
                                                     void *src,
                                                     int32_t src_offset,
                                                     int32_t len,
                                                     int32_t elem_size);
MOONBIT_EXPORT int32_t moonbit_unsafe_ref_array_blit(void *dst,
                                                     int32_t dst_offset,
                                                     void *src,
                                                     int32_t src_offset,
                                                     int32_t len);
MOONBIT_EXPORT void moonbit_println(moonbit_string_t str);
MOONBIT_EXPORT moonbit_bytes_t *moonbit_get_cli_args(void);
MOONBIT_EXPORT void moonbit_runtime_init(int argc, char **argv);
MOONBIT_EXPORT void moonbit_drop_object(void *);
// Slow paths of the inlined value-enum retain/release below (defined in
// runtime.c). Internal helpers, so declared here rather than in the public
// moonbit.h; reached only when a value's current variant carries references.
MOONBIT_EXPORT void moonbit_incref_value_enum_loop(void *p);
MOONBIT_EXPORT void moonbit_decref_value_enum_loop(void *p);
MOONBIT_EXPORT int32_t moonbit_utf16_len_from_utf8(moonbit_bytes_t src,
                                                   int32_t src_offset,
                                                   int32_t src_length);
MOONBIT_EXPORT int32_t moonbit_utf8_decode_into_utf16(
    moonbit_bytes_t src, int32_t src_offset, int32_t src_length,
    moonbit_string_t dst, int32_t dst_offset);
MOONBIT_EXPORT int32_t moonbit_utf8_decode_lossy_into_utf16(
    moonbit_bytes_t src, int32_t src_offset, int32_t src_length,
    moonbit_string_t dst, int32_t dst_offset);
MOONBIT_EXPORT int32_t moonbit_utf8_len_from_utf16(moonbit_string_t src,
                                                   int32_t src_offset,
                                                   int32_t src_length);
MOONBIT_EXPORT int32_t moonbit_utf8_encode_from_utf16(
    moonbit_string_t src, int32_t src_offset, int32_t src_length,
    moonbit_bytes_t dst, int32_t dst_offset);

#if !defined(_WIN64) && !defined(_WIN32)
void *malloc(size_t size);
void free(void *ptr);
#define libc_malloc malloc
#define libc_free free
#endif

// several important runtime functions are inlined
static void *moonbit_malloc_inlined(size_t size) {
  struct moonbit_object *ptr = (struct moonbit_object *)libc_malloc(
      sizeof(struct moonbit_object) + size);
  Moonbit_init_dynamic_rc(ptr, moonbit_BLOCK_KIND_REGULAR);
  return ptr + 1;
}

#define moonbit_malloc(obj) moonbit_malloc_inlined(obj)
#define moonbit_free(obj) libc_free(Moonbit_object_header(obj))

#define MOONBIT_RC_COUNT_UNIT ((int32_t)(1u << MOONBIT_RC_COUNT_SHIFT))
#define raw_rc_is_dynamic(rc) ((int32_t)(rc) >= MOONBIT_RC_COUNT_UNIT)
#define raw_rc_is_shared(rc) ((int32_t)(rc) >= (MOONBIT_RC_COUNT_UNIT * 2))

extern const uint32_t *moonbit_layout_table;

static void moonbit_incref_inlined(void *ptr) {
  struct moonbit_object *header = Moonbit_object_header(ptr);
  int32_t const rc = header->rc;
  if (raw_rc_is_dynamic(rc)) {
    Moonbit_increase_rc_count(header);
  }
}

#define moonbit_incref moonbit_incref_inlined

static void moonbit_decref_inlined(void *ptr) {
  struct moonbit_object *header = Moonbit_object_header(ptr);
  int32_t const rc = header->rc;
  if (raw_rc_is_shared(rc)) {
    header->rc = rc - MOONBIT_RC_COUNT_UNIT;
  } else if (raw_rc_is_dynamic(rc)) {
    moonbit_drop_object(ptr);
  }
}

#define moonbit_decref moonbit_decref_inlined

// Value-enum retain/release: inline the cheap "does the current variant carry
// references?" test (a header read + class compare) so scalar-tag moves pay no
// call, and delegate the reference-walking loop to the out-of-line slow path in
// runtime.c. Mirrors the moonbit_incref/decref fast/slow split above.
static inline void moonbit_incref_value_enum_inlined(void *p) {
  if (Moonbit_header_layout_class(*(uint32_t *)p) ==
      MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED)
    moonbit_incref_value_enum_loop(p);
}

#define moonbit_incref_value_enum moonbit_incref_value_enum_inlined

static inline void moonbit_decref_value_enum_inlined(void *p) {
  if (Moonbit_header_layout_class(*(uint32_t *)p) ==
      MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED)
    moonbit_decref_value_enum_loop(p);
}

#define moonbit_decref_value_enum moonbit_decref_value_enum_inlined

#define moonbit_unsafe_make_string moonbit_make_string

#if defined(MOONBIT_V128_NEON)
#define Moonbit_v128_make(lo, hi)                                             \
  vreinterpretq_u8_u64(                                                       \
      vcombine_u64(vcreate_u64((uint64_t)(lo)), vcreate_u64((uint64_t)(hi))))
#define Moonbit_v128_lo(v) vgetq_lane_u64(vreinterpretq_u64_u8(v), 0)
#define Moonbit_v128_hi(v) vgetq_lane_u64(vreinterpretq_u64_u8(v), 1)
#define Moonbit_v128_load_storage(p) vld1q_u8((const uint8_t *)(p))
#define Moonbit_v128_store_storage(p, v) vst1q_u8((uint8_t *)(p), (v))
#elif defined(MOONBIT_V128_SSE2)
#define Moonbit_v128_make(lo, hi) _mm_set_epi64x((int64_t)(hi), (int64_t)(lo))
#define Moonbit_v128_lo(v) ((uint64_t)_mm_cvtsi128_si64(v))
#define Moonbit_v128_hi(v) ((uint64_t)_mm_cvtsi128_si64(_mm_srli_si128((v), 8)))
#define Moonbit_v128_load_storage(p) _mm_loadu_si128((const __m128i *)(p))
#define Moonbit_v128_store_storage(p, v) _mm_storeu_si128((__m128i *)(p), (v))
#else
#define Moonbit_v128_make(lo, hi) ((moonbit_v128_t){(lo), (hi)})
#define Moonbit_v128_lo(v) ((v).lo)
#define Moonbit_v128_hi(v) ((v).hi)
#define Moonbit_v128_load_storage(p) (*(p))
#define Moonbit_v128_store_storage(p, v) (*(p) = (v))
#endif

// detect whether compiler builtins exist for advanced bitwise operations
#ifdef __has_builtin

#if __has_builtin(__builtin_clz)
#define HAS_BUILTIN_CLZ
#endif

#if __has_builtin(__builtin_ctz)
#define HAS_BUILTIN_CTZ
#endif

#if __has_builtin(__builtin_popcount)
#define HAS_BUILTIN_POPCNT
#endif

#if __has_builtin(__builtin_sqrt)
#define HAS_BUILTIN_SQRT
#endif

#if __has_builtin(__builtin_sqrtf)
#define HAS_BUILTIN_SQRTF
#endif

#if __has_builtin(__builtin_fabs)
#define HAS_BUILTIN_FABS
#endif

#if __has_builtin(__builtin_fabsf)
#define HAS_BUILTIN_FABSF
#endif

#endif

// if there is no builtin operators, use software implementation
#ifdef HAS_BUILTIN_CLZ
static inline int32_t moonbit_clz32(int32_t x) {
  return x == 0 ? 32 : __builtin_clz(x);
}

static inline int32_t moonbit_clz64(int64_t x) {
  return x == 0 ? 64 : __builtin_clzll(x);
}

#undef HAS_BUILTIN_CLZ
#else
// table for [clz] value of 4bit integer.
static const uint8_t moonbit_clz4[] = {4, 3, 2, 2, 1, 1, 1, 1,
                                       0, 0, 0, 0, 0, 0, 0, 0};

int32_t moonbit_clz32(uint32_t x) {
  /* The ideas is to:

     1. narrow down the 4bit block where the most signficant "1" bit lies,
        using binary search
     2. find the number of leading zeros in that 4bit block via table lookup

     Different time/space tradeoff can be made here by enlarging the table
     and do less binary search.
     One benefit of the 4bit lookup table is that it can fit into a single cache
     line.
  */
  int32_t result = 0;
  if (x > 0xffff) {
    x >>= 16;
  } else {
    result += 16;
  }
  if (x > 0xff) {
    x >>= 8;
  } else {
    result += 8;
  }
  if (x > 0xf) {
    x >>= 4;
  } else {
    result += 4;
  }
  return result + moonbit_clz4[x];
}

int32_t moonbit_clz64(uint64_t x) {
  int32_t result = 0;
  if (x > 0xffffffff) {
    x >>= 32;
  } else {
    result += 32;
  }
  return result + moonbit_clz32((uint32_t)x);
}
#endif

#ifdef HAS_BUILTIN_CTZ
static inline int32_t moonbit_ctz32(int32_t x) {
  return x == 0 ? 32 : __builtin_ctz(x);
}

static inline int32_t moonbit_ctz64(int64_t x) {
  return x == 0 ? 64 : __builtin_ctzll(x);
}

#undef HAS_BUILTIN_CTZ
#else
int32_t moonbit_ctz32(int32_t x) {
  /* The algorithm comes from:

       Leiserson, Charles E. et al. “Using de Bruijn Sequences to Index a 1 in a
     Computer Word.” (1998).

     The ideas is:

     1. leave only the least significant "1" bit in the input,
        set all other bits to "0". This is achieved via [x & -x]
     2. now we have [x * n == n << ctz(x)], if [n] is a de bruijn sequence
        (every 5bit pattern occurn exactly once when you cycle through the bit
     string), we can find [ctz(x)] from the most significant 5 bits of [x * n]
 */
  static const uint32_t de_bruijn_32 = 0x077CB531;
  static const uint8_t index32[] = {0,  1,  28, 2,  29, 14, 24, 3,  30, 22, 20,
                                    15, 25, 17, 4,  8,  31, 27, 13, 23, 21, 19,
                                    16, 7,  26, 12, 18, 6,  11, 5,  10, 9};
  return (x == 0) * 32 + index32[(de_bruijn_32 * (x & -x)) >> 27];
}

int32_t moonbit_ctz64(int64_t x) {
  static const uint64_t de_bruijn_64 = 0x0218A392CD3D5DBF;
  static const uint8_t index64[] = {
      0,  1,  2,  7,  3,  13, 8,  19, 4,  25, 14, 28, 9,  34, 20, 40,
      5,  17, 26, 38, 15, 46, 29, 48, 10, 31, 35, 54, 21, 50, 41, 57,
      63, 6,  12, 18, 24, 27, 33, 39, 16, 37, 45, 47, 30, 53, 49, 56,
      62, 11, 23, 32, 36, 44, 52, 55, 61, 22, 43, 51, 60, 42, 59, 58};
  return (x == 0) * 64 + index64[(de_bruijn_64 * (x & -x)) >> 58];
}
#endif

#ifdef HAS_BUILTIN_POPCNT

#define moonbit_popcnt32 __builtin_popcount
#define moonbit_popcnt64 __builtin_popcountll
#undef HAS_BUILTIN_POPCNT

#else
int32_t moonbit_popcnt32(uint32_t x) {
  /* The classic SIMD Within A Register algorithm.
     ref: [https://nimrod.blog/posts/algorithms-behind-popcount/]
 */
  x = x - ((x >> 1) & 0x55555555);
  x = (x & 0x33333333) + ((x >> 2) & 0x33333333);
  x = (x + (x >> 4)) & 0x0F0F0F0F;
  return (x * 0x01010101) >> 24;
}

int32_t moonbit_popcnt64(uint64_t x) {
  x = x - ((x >> 1) & 0x5555555555555555);
  x = (x & 0x3333333333333333) + ((x >> 2) & 0x3333333333333333);
  x = (x + (x >> 4)) & 0x0F0F0F0F0F0F0F0F;
  return (x * 0x0101010101010101) >> 56;
}
#endif

/* The following sqrt implementation comes from
   [musl](https://git.musl-libc.org/cgit/musl),
   with some helpers inlined to make it zero dependency.
 */
#ifdef MOONBIT_NATIVE_NO_SYS_HEADER
const uint16_t __rsqrt_tab[128] = {
    0xb451, 0xb2f0, 0xb196, 0xb044, 0xaef9, 0xadb6, 0xac79, 0xab43, 0xaa14,
    0xa8eb, 0xa7c8, 0xa6aa, 0xa592, 0xa480, 0xa373, 0xa26b, 0xa168, 0xa06a,
    0x9f70, 0x9e7b, 0x9d8a, 0x9c9d, 0x9bb5, 0x9ad1, 0x99f0, 0x9913, 0x983a,
    0x9765, 0x9693, 0x95c4, 0x94f8, 0x9430, 0x936b, 0x92a9, 0x91ea, 0x912e,
    0x9075, 0x8fbe, 0x8f0a, 0x8e59, 0x8daa, 0x8cfe, 0x8c54, 0x8bac, 0x8b07,
    0x8a64, 0x89c4, 0x8925, 0x8889, 0x87ee, 0x8756, 0x86c0, 0x862b, 0x8599,
    0x8508, 0x8479, 0x83ec, 0x8361, 0x82d8, 0x8250, 0x81c9, 0x8145, 0x80c2,
    0x8040, 0xff02, 0xfd0e, 0xfb25, 0xf947, 0xf773, 0xf5aa, 0xf3ea, 0xf234,
    0xf087, 0xeee3, 0xed47, 0xebb3, 0xea27, 0xe8a3, 0xe727, 0xe5b2, 0xe443,
    0xe2dc, 0xe17a, 0xe020, 0xdecb, 0xdd7d, 0xdc34, 0xdaf1, 0xd9b3, 0xd87b,
    0xd748, 0xd61a, 0xd4f1, 0xd3cd, 0xd2ad, 0xd192, 0xd07b, 0xcf69, 0xce5b,
    0xcd51, 0xcc4a, 0xcb48, 0xca4a, 0xc94f, 0xc858, 0xc764, 0xc674, 0xc587,
    0xc49d, 0xc3b7, 0xc2d4, 0xc1f4, 0xc116, 0xc03c, 0xbf65, 0xbe90, 0xbdbe,
    0xbcef, 0xbc23, 0xbb59, 0xba91, 0xb9cc, 0xb90a, 0xb84a, 0xb78c, 0xb6d0,
    0xb617, 0xb560,
};

/* returns a*b*2^-32 - e, with error 0 <= e < 1.  */
static inline uint32_t mul32(uint32_t a, uint32_t b) {
  return (uint64_t)a * b >> 32;
}
#endif

#ifdef MOONBIT_NATIVE_NO_SYS_HEADER
float sqrtf(float x) {
  uint32_t ix, m, m1, m0, even, ey;

  ix = *(uint32_t *)&x;
  if (ix - 0x00800000 >= 0x7f800000 - 0x00800000) {
    /* x < 0x1p-126 or inf or nan.  */
    if (ix * 2 == 0)
      return x;
    if (ix == 0x7f800000)
      return x;
    if (ix > 0x7f800000)
      return (x - x) / (x - x);
    /* x is subnormal, normalize it.  */
    x *= 0x1p23f;
    ix = *(uint32_t *)&x;
    ix -= 23 << 23;
  }

  /* x = 4^e m; with int e and m in [1, 4).  */
  even = ix & 0x00800000;
  m1 = (ix << 8) | 0x80000000;
  m0 = (ix << 7) & 0x7fffffff;
  m = even ? m0 : m1;

  /* 2^e is the exponent part of the return value.  */
  ey = ix >> 1;
  ey += 0x3f800000 >> 1;
  ey &= 0x7f800000;

  /* compute r ~ 1/sqrt(m), s ~ sqrt(m) with 2 goldschmidt iterations.  */
  static const uint32_t three = 0xc0000000;
  uint32_t r, s, d, u, i;
  i = (ix >> 17) % 128;
  r = (uint32_t)__rsqrt_tab[i] << 16;
  /* |r*sqrt(m) - 1| < 0x1p-8 */
  s = mul32(m, r);
  /* |s/sqrt(m) - 1| < 0x1p-8 */
  d = mul32(s, r);
  u = three - d;
  r = mul32(r, u) << 1;
  /* |r*sqrt(m) - 1| < 0x1.7bp-16 */
  s = mul32(s, u) << 1;
  /* |s/sqrt(m) - 1| < 0x1.7bp-16 */
  d = mul32(s, r);
  u = three - d;
  s = mul32(s, u);
  /* -0x1.03p-28 < s/sqrt(m) - 1 < 0x1.fp-31 */
  s = (s - 1) >> 6;
  /* s < sqrt(m) < s + 0x1.08p-23 */

  /* compute nearest rounded result.  */
  uint32_t d0, d1, d2;
  float y, t;
  d0 = (m << 16) - s * s;
  d1 = s - d0;
  d2 = d1 + s + 1;
  s += d1 >> 31;
  s &= 0x007fffff;
  s |= ey;
  y = *(float *)&s;
  /* handle rounding and inexact exception. */
  uint32_t tiny = d2 == 0 ? 0 : 0x01000000;
  tiny |= (d1 ^ d2) & 0x80000000;
  t = *(float *)&tiny;
  y = y + t;
  return y;
}
#endif

#ifdef MOONBIT_NATIVE_NO_SYS_HEADER
/* returns a*b*2^-64 - e, with error 0 <= e < 3.  */
static inline uint64_t mul64(uint64_t a, uint64_t b) {
  uint64_t ahi = a >> 32;
  uint64_t alo = a & 0xffffffff;
  uint64_t bhi = b >> 32;
  uint64_t blo = b & 0xffffffff;
  return ahi * bhi + (ahi * blo >> 32) + (alo * bhi >> 32);
}

double sqrt(double x) {
  uint64_t ix, top, m;

  /* special case handling.  */
  ix = *(uint64_t *)&x;
  top = ix >> 52;
  if (top - 0x001 >= 0x7ff - 0x001) {
    /* x < 0x1p-1022 or inf or nan.  */
    if (ix * 2 == 0)
      return x;
    if (ix == 0x7ff0000000000000)
      return x;
    if (ix > 0x7ff0000000000000)
      return (x - x) / (x - x);
    /* x is subnormal, normalize it.  */
    x *= 0x1p52;
    ix = *(uint64_t *)&x;
    top = ix >> 52;
    top -= 52;
  }

  /* argument reduction:
     x = 4^e m; with integer e, and m in [1, 4)
     m: fixed point representation [2.62]
     2^e is the exponent part of the result.  */
  int even = top & 1;
  m = (ix << 11) | 0x8000000000000000;
  if (even)
    m >>= 1;
  top = (top + 0x3ff) >> 1;

  /* approximate r ~ 1/sqrt(m) and s ~ sqrt(m) when m in [1,4)

     initial estimate:
     7bit table lookup (1bit exponent and 6bit significand).

     iterative approximation:
     using 2 goldschmidt iterations with 32bit int arithmetics
     and a final iteration with 64bit int arithmetics.

     details:

     the relative error (e = r0 sqrt(m)-1) of a linear estimate
     (r0 = a m + b) is |e| < 0.085955 ~ 0x1.6p-4 at best,
     a table lookup is faster and needs one less iteration
     6 bit lookup table (128b) gives |e| < 0x1.f9p-8
     7 bit lookup table (256b) gives |e| < 0x1.fdp-9
     for single and double prec 6bit is enough but for quad
     prec 7bit is needed (or modified iterations). to avoid
     one more iteration >=13bit table would be needed (16k).

     a newton-raphson iteration for r is
       w = r*r
       u = 3 - m*w
       r = r*u/2
     can use a goldschmidt iteration for s at the end or
       s = m*r

     first goldschmidt iteration is
       s = m*r
       u = 3 - s*r
       r = r*u/2
       s = s*u/2
     next goldschmidt iteration is
       u = 3 - s*r
       r = r*u/2
       s = s*u/2
     and at the end r is not computed only s.

     they use the same amount of operations and converge at the
     same quadratic rate, i.e. if
       r1 sqrt(m) - 1 = e, then
       r2 sqrt(m) - 1 = -3/2 e^2 - 1/2 e^3
     the advantage of goldschmidt is that the mul for s and r
     are independent (computed in parallel), however it is not
     "self synchronizing": it only uses the input m in the
     first iteration so rounding errors accumulate. at the end
     or when switching to larger precision arithmetics rounding
     errors dominate so the first iteration should be used.

     the fixed point representations are
       m: 2.30 r: 0.32, s: 2.30, d: 2.30, u: 2.30, three: 2.30
     and after switching to 64 bit
       m: 2.62 r: 0.64, s: 2.62, d: 2.62, u: 2.62, three: 2.62  */

  static const uint64_t three = 0xc0000000;
  uint64_t r, s, d, u, i;

  i = (ix >> 46) % 128;
  r = (uint32_t)__rsqrt_tab[i] << 16;
  /* |r sqrt(m) - 1| < 0x1.fdp-9 */
  s = mul32(m >> 32, r);
  /* |s/sqrt(m) - 1| < 0x1.fdp-9 */
  d = mul32(s, r);
  u = three - d;
  r = mul32(r, u) << 1;
  /* |r sqrt(m) - 1| < 0x1.7bp-16 */
  s = mul32(s, u) << 1;
  /* |s/sqrt(m) - 1| < 0x1.7bp-16 */
  d = mul32(s, r);
  u = three - d;
  r = mul32(r, u) << 1;
  /* |r sqrt(m) - 1| < 0x1.3704p-29 (measured worst-case) */
  r = r << 32;
  s = mul64(m, r);
  d = mul64(s, r);
  u = (three << 32) - d;
  s = mul64(s, u); /* repr: 3.61 */
  /* -0x1p-57 < s - sqrt(m) < 0x1.8001p-61 */
  s = (s - 2) >> 9; /* repr: 12.52 */
  /* -0x1.09p-52 < s - sqrt(m) < -0x1.fffcp-63 */

  /* s < sqrt(m) < s + 0x1.09p-52,
     compute nearest rounded result:
     the nearest result to 52 bits is either s or s+0x1p-52,
     we can decide by comparing (2^52 s + 0.5)^2 to 2^104 m.  */
  uint64_t d0, d1, d2;
  double y, t;
  d0 = (m << 42) - s * s;
  d1 = s - d0;
  d2 = d1 + s + 1;
  s += d1 >> 63;
  s &= 0x000fffffffffffff;
  s |= top << 52;
  y = *(double *)&s;
  return y;
}
#endif

#ifdef MOONBIT_NATIVE_NO_SYS_HEADER
double fabs(double x) {
  union {
    double f;
    uint64_t i;
  } u = {x};
  u.i &= 0x7fffffffffffffffULL;
  return u.f;
}
#endif

#ifdef MOONBIT_NATIVE_NO_SYS_HEADER
float fabsf(float x) {
  union {
    float f;
    uint32_t i;
  } u = {x};
  u.i &= 0x7fffffff;
  return u.f;
}
#endif

#ifdef _MSC_VER
/* MSVC treats syntactic division by zero as fatal error,
   even for float point numbers,
   so we have to use a constant variable to work around this */
static const int MOONBIT_ZERO = 0;
#else
#define MOONBIT_ZERO 0
#endif

#ifdef __cplusplus
}
#endif
struct _M0BTPB6Logger;

struct _M0BTPB4Show;

struct _M0TPB5ArrayGyE;

struct _M0TPC16string10StringView;

struct _M0KTPB6LoggerTPB13StringBuilder;

struct _M0TPB6Logger;

struct _M0TPB4Show;

struct _M0TPB13StringBuilder;

struct _M0TP410RabitLogic2s73src9transport9TcpConfig;

struct _M0TP410RabitLogic2s73src6client8S7Client;

struct _M0TP410RabitLogic2s73src9transport13TcpConnection;

struct _M0BTPB6Logger {
  int32_t(* $method_0)(void*, moonbit_string_t);
  int32_t(* $method_1)(void*, moonbit_string_t, int32_t, int32_t);
  int32_t(* $method_2)(void*, struct _M0TPC16string10StringView);
  int32_t(* $method_3)(void*, int32_t);
  int32_t(* $method_4)(void*, struct _M0TPB4Show);
  int32_t(* $method_5)(void*, struct _M0TPB4Show);
  
};

struct _M0BTPB4Show {
  int32_t(* $method_0)(void*, struct _M0TPB6Logger);
  moonbit_string_t(* $method_1)(void*);
  
};

struct _M0TPB5ArrayGyE {
  moonbit_bytes_t $0;
  int32_t $1;
  
};

struct _M0TPC16string10StringView {
  moonbit_string_t $0;
  int32_t $1;
  int32_t $2;
  
};

struct _M0KTPB6LoggerTPB13StringBuilder {
  struct _M0BTPB6Logger* $0;
  void* $1;
  
};

struct _M0TPB6Logger {
  struct _M0BTPB6Logger* $0;
  void* $1;
  
};

struct _M0TPB4Show {
  struct _M0BTPB4Show* $0;
  void* $1;
  
};

struct _M0TPB13StringBuilder {
  uint16_t* $0;
  int32_t $1;
  
};

struct _M0TP410RabitLogic2s73src9transport9TcpConfig {
  moonbit_string_t $0;
  int32_t $1;
  int32_t $2;
  int32_t $3;
  int32_t $4;
  int32_t $5;
  struct _M0TPB5ArrayGyE* $6;
  struct _M0TPB5ArrayGyE* $7;
  int32_t $8;
  int32_t $9;
  int32_t $10;
  
};

struct _M0TP410RabitLogic2s73src6client8S7Client {
  struct _M0TP410RabitLogic2s73src9transport13TcpConnection* $0;
  int32_t $1;
  int32_t $2;
  int32_t $3;
  
};

struct _M0TP410RabitLogic2s73src9transport13TcpConnection {
  struct _M0TP410RabitLogic2s73src9transport9TcpConfig* $0;
  int32_t $1;
  int32_t $2;
  int32_t $3;
  int32_t $4;
  struct _M0TPB5ArrayGyE* $5;
  struct _M0TPB5ArrayGyE* $6;
  
};

int32_t _M0MP410RabitLogic2s73src6client8S7Client13is__connected(
  struct _M0TP410RabitLogic2s73src6client8S7Client*
);

struct _M0TP410RabitLogic2s73src6client8S7Client* _M0MP410RabitLogic2s73src6client8S7Client17new__with__config(
  struct _M0TP410RabitLogic2s73src9transport9TcpConfig*
);

struct _M0TP410RabitLogic2s73src9transport13TcpConnection* _M0MP410RabitLogic2s73src9transport13TcpConnection3new(
  struct _M0TP410RabitLogic2s73src9transport9TcpConfig*
);

struct _M0TP410RabitLogic2s73src9transport9TcpConfig* _M0MP410RabitLogic2s73src9transport9TcpConfig11new_2einner(
  moonbit_string_t,
  int32_t,
  int32_t,
  int32_t,
  int32_t,
  int32_t,
  int32_t,
  int32_t
);

moonbit_string_t _M0FP310RabitLogic2s73src7version();

int32_t _M0FPB7printlnGsE(moonbit_string_t);

moonbit_string_t _M0IPC13int3IntPB4Show10to__string(int32_t);

moonbit_string_t _M0IPC14bool4BoolPB4Show10to__string(int32_t);

moonbit_string_t _M0IPC16string6StringPB4Show10to__string(moonbit_string_t);

int32_t _M0IPB13StringBuilderPB6Logger11write__view(
  struct _M0TPB13StringBuilder*,
  struct _M0TPC16string10StringView
);

moonbit_string_t _M0MPC13int3Int18to__string_2einner(int32_t, int32_t);

int32_t _M0FPB14radix__count32(uint32_t, int32_t);

int32_t _M0FPB12hex__count32(uint32_t);

int32_t _M0FPB12dec__count32(uint32_t);

int32_t _M0FPB20int__to__string__dec(uint16_t*, uint32_t, int32_t, int32_t);

int32_t _M0FPB24int__to__string__generic(
  uint16_t*,
  uint32_t,
  int32_t,
  int32_t,
  int32_t
);

int32_t _M0FPB20int__to__string__hex(uint16_t*, uint32_t, int32_t, int32_t);

int32_t _M0IP016_24default__implPB4Show6outputGsE(
  moonbit_string_t,
  struct _M0TPB6Logger
);

int32_t _M0IP016_24default__implPB4Show6outputGiE(
  int32_t,
  struct _M0TPB6Logger
);

int32_t _M0IP016_24default__implPB4Show6outputGbE(
  int32_t,
  struct _M0TPB6Logger
);

int32_t _M0MPC16string10StringView13start__offset(
  struct _M0TPC16string10StringView
);

moonbit_string_t _M0MPC16string10StringView4data(
  struct _M0TPC16string10StringView
);

int32_t _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE(
  struct _M0TPB13StringBuilder*,
  moonbit_string_t,
  int32_t,
  int32_t
);

struct _M0TPC16string10StringView _M0MPC16string6String11sub_2einner(
  moonbit_string_t,
  int32_t,
  int64_t
);

int32_t _M0IP016_24default__implPB6Logger5writeGRPB13StringBuilderE(
  struct _M0TPB13StringBuilder*,
  struct _M0TPB4Show
);

int32_t _M0IP016_24default__implPB6Logger28write__string__interpolationGRPB13StringBuilderE(
  struct _M0TPB13StringBuilder*,
  struct _M0TPB4Show
);

int32_t _M0IPB13StringBuilderPB6Logger13write__string(
  struct _M0TPB13StringBuilder*,
  moonbit_string_t
);

int32_t _M0MPC15array10FixedArray26unsafe__blit__from__string(
  uint16_t*,
  int32_t,
  moonbit_string_t,
  int32_t,
  int32_t
);

int32_t _M0MPC16uint166UInt1623is__trailing__surrogate(int32_t);

int32_t _M0IPB13StringBuilderPB6Logger11write__char(
  struct _M0TPB13StringBuilder*,
  int32_t
);

int32_t _M0MPB13StringBuilder19grow__if__necessary(
  struct _M0TPB13StringBuilder*,
  int32_t
);

int32_t _M0MPC14uint4UInt10to__uint16(uint32_t);

uint32_t _M0MPC14char4Char8to__uint(int32_t);

moonbit_string_t _M0MPB13StringBuilder10to__string(
  struct _M0TPB13StringBuilder*
);

int32_t _M0IPC16uint166UInt16PB7Default7default();

uint16_t* _M0MPC15array10FixedArray23make__and__blit_2einnerGkE(
  uint16_t*,
  int32_t,
  int32_t,
  int32_t,
  int32_t,
  int32_t
);

uint16_t* _M0MPC15array10FixedArray23unsafe__make__and__blitGkE(
  uint16_t*,
  int32_t,
  int32_t,
  int32_t,
  int32_t,
  int32_t
);

struct _M0TPB13StringBuilder* _M0MPB13StringBuilder21StringBuilder_2einner(
  int32_t
);

int32_t _M0MPB13StringBuilder13write__objectGsE(
  struct _M0TPB13StringBuilder*,
  moonbit_string_t
);

int32_t _M0MPB13StringBuilder13write__objectGiE(
  struct _M0TPB13StringBuilder*,
  int32_t
);

int32_t _M0MPB13StringBuilder13write__objectGbE(
  struct _M0TPB13StringBuilder*,
  int32_t
);

int32_t _M0MPC15array10FixedArray12unsafe__blitGkE(
  uint16_t*,
  int32_t,
  uint16_t*,
  int32_t,
  int32_t
);

int32_t _M0FPC15abort5abortGuE(moonbit_string_t);

uint16_t* _M0FPC15abort5abortGAkE(moonbit_string_t);

int32_t _M0IP016_24default__implPB6Logger61write_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE(
  void*,
  struct _M0TPB4Show
);

int32_t _M0IP016_24default__implPB6Logger84write__string__interpolation_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE(
  void*,
  struct _M0TPB4Show
);

int32_t _M0IPB13StringBuilderPB6Logger67write__char_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void*,
  int32_t
);

int32_t _M0IPB13StringBuilderPB6Logger67write__view_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void*,
  struct _M0TPC16string10StringView
);

int32_t _M0IP016_24default__implPB6Logger72write__substring_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE(
  void*,
  moonbit_string_t,
  int32_t,
  int32_t
);

int32_t _M0IPB13StringBuilderPB6Logger69write__string_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void*,
  moonbit_string_t
);

struct { int32_t rc; uint32_t meta; uint16_t const data[1]; 
} const moonbit_string_literal_7 =
  { Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 0, 0};

struct { int32_t rc; uint32_t meta; uint16_t const data[16]; 
} const moonbit_string_literal_10 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 15, 44, 32, 
    100, 115, 116, 95, 111, 102, 102, 115, 101, 116, 32, 61, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[19]; 
} const moonbit_string_literal_6 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 18, 105, 110, 
    118, 97, 108, 105, 100, 32, 99, 111, 100, 101, 32, 112, 111, 105, 
    110, 116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[9]; 
} const moonbit_string_literal_16 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 8, 67, 111, 
    110, 102, 105, 103, 58, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[20]; 
} const moonbit_string_literal_28 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 19, 32, 32, 
    99, 112, 95, 105, 110, 102, 111, 32, 45, 62, 32, 67, 80, 73, 110, 
    102, 111, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[55]; 
} const moonbit_string_literal_22 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 54, 32, 32, 
    101, 98, 95, 114, 101, 97, 100, 47, 101, 98, 95, 119, 114, 105, 116, 
    101, 40, 115, 116, 97, 114, 116, 44, 32, 115, 105, 122, 101, 124, 
    100, 97, 116, 97, 41, 32, 32, 45, 32, 80, 114, 111, 99, 101, 115, 
    115, 32, 73, 110, 112, 117, 116, 115, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[22]; 
} const moonbit_string_literal_27 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 21, 32, 32, 
    99, 112, 117, 95, 105, 110, 102, 111, 32, 45, 62, 32, 67, 112, 117, 
    73, 110, 102, 111, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[12]; 
} const moonbit_string_literal_15 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 11, 49, 57, 
    50, 46, 49, 54, 56, 46, 48, 46, 49, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[31]; 
} const moonbit_string_literal_3 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 30, 114, 97, 
    100, 105, 120, 32, 109, 117, 115, 116, 32, 98, 101, 32, 98, 101, 
    116, 119, 101, 101, 110, 32, 50, 32, 97, 110, 100, 32, 51, 54, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[2]; 
} const moonbit_string_literal_4 =
  { Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 1, 48, 0};

struct { int32_t rc; uint32_t meta; uint16_t const data[26]; 
} const moonbit_string_literal_26 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 25, 32, 32, 
    112, 108, 99, 95, 115, 116, 97, 116, 117, 115, 32, 45, 62, 32, 67, 
    112, 117, 83, 116, 97, 116, 117, 115, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[46]; 
} const moonbit_string_literal_24 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 45, 32, 32, 
    109, 98, 95, 114, 101, 97, 100, 47, 109, 98, 95, 119, 114, 105, 116, 
    101, 40, 115, 116, 97, 114, 116, 44, 32, 115, 105, 122, 101, 124, 
    100, 97, 116, 97, 41, 32, 32, 45, 32, 70, 108, 97, 103, 115, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[9]; 
} const moonbit_string_literal_11 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 8, 44, 32, 
    108, 101, 110, 32, 61, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[6]; 
} const moonbit_string_literal_2 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 5, 102, 97, 
    108, 115, 101, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[37]; 
} const moonbit_string_literal_8 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 36, 98, 111, 
    117, 110, 100, 115, 32, 99, 104, 101, 99, 107, 32, 102, 97, 105, 
    108, 101, 100, 58, 32, 97, 108, 108, 111, 99, 97, 116, 101, 95, 108, 
    101, 110, 32, 61, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[17]; 
} const moonbit_string_literal_13 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 16, 61, 61, 
    61, 32, 83, 55, 32, 76, 105, 98, 114, 97, 114, 121, 32, 118, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[15]; 
} const moonbit_string_literal_19 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 14, 65, 80, 
    73, 32, 82, 101, 102, 101, 114, 101, 110, 99, 101, 58, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[5]; 
} const moonbit_string_literal_1 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 4, 116, 114, 
    117, 101, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[41]; 
} const moonbit_string_literal_21 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 40, 32, 32, 
    97, 103, 95, 114, 101, 97, 100, 47, 97, 103, 95, 119, 114, 105, 116, 
    101, 40, 100, 98, 44, 32, 115, 116, 97, 114, 116, 44, 32, 115, 105, 
    122, 101, 124, 100, 97, 116, 97, 41, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[37]; 
} const moonbit_string_literal_5 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 36, 48, 49, 
    50, 51, 52, 53, 54, 55, 56, 57, 97, 98, 99, 100, 101, 102, 103, 104, 
    105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 
    118, 119, 120, 121, 122, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[26]; 
} const moonbit_string_literal_18 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 25, 67, 108, 
    105, 101, 110, 116, 32, 114, 101, 97, 100, 121, 46, 32, 67, 111, 
    110, 110, 101, 99, 116, 101, 100, 58, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[16]; 
} const moonbit_string_literal_12 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 15, 44, 32, 
    115, 114, 99, 46, 108, 101, 110, 103, 116, 104, 32, 61, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[33]; 
} const moonbit_string_literal_25 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 32, 32, 32, 
    112, 108, 99, 95, 115, 116, 97, 114, 116, 47, 112, 108, 99, 95, 115, 
    116, 111, 112, 47, 112, 108, 99, 95, 114, 101, 115, 116, 97, 114, 
    116, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[56]; 
} const moonbit_string_literal_23 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 55, 32, 32, 
    97, 98, 95, 114, 101, 97, 100, 47, 97, 98, 95, 119, 114, 105, 116, 
    101, 40, 115, 116, 97, 114, 116, 44, 32, 115, 105, 122, 101, 124, 
    100, 97, 116, 97, 41, 32, 32, 45, 32, 80, 114, 111, 99, 101, 115, 
    115, 32, 79, 117, 116, 112, 117, 116, 115, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[2]; 
} const moonbit_string_literal_17 =
  { Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 1, 58, 0};

struct { int32_t rc; uint32_t meta; uint16_t const data[16]; 
} const moonbit_string_literal_9 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 15, 44, 32, 
    115, 114, 99, 95, 111, 102, 102, 115, 101, 116, 32, 61, 32, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[13]; 
} const moonbit_string_literal_29 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 12, 61, 61, 
    61, 32, 68, 111, 110, 101, 32, 61, 61, 61, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[6]; 
} const moonbit_string_literal_0 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 5, 48, 46, 
    51, 46, 48, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[5]; 
} const moonbit_string_literal_14 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 4, 32, 61, 
    61, 61, 0
  };

struct { int32_t rc; uint32_t meta; uint16_t const data[21]; 
} const moonbit_string_literal_20 =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_VAL_ARRAY), 20, 32, 32, 
    99, 111, 110, 110, 101, 99, 116, 47, 100, 105, 115, 99, 111, 110, 
    110, 101, 99, 116, 0
  };

uint32_t const moonbit_layout_table_data[19] =
  {
    sizeof(struct _M0TP410RabitLogic2s73src6client8S7Client) / 4, 1,
    offsetof(struct _M0TP410RabitLogic2s73src6client8S7Client, $0) / 4 * 2,
    sizeof(struct _M0TP410RabitLogic2s73src9transport13TcpConnection) / 4, 
    3,
    offsetof(struct _M0TP410RabitLogic2s73src9transport13TcpConnection, $0)
    / 4
    * 2,
    offsetof(struct _M0TP410RabitLogic2s73src9transport13TcpConnection, $5)
    / 4
    * 2,
    offsetof(struct _M0TP410RabitLogic2s73src9transport13TcpConnection, $6)
    / 4
    * 2, sizeof(struct _M0TPB5ArrayGyE) / 4, 1,
    offsetof(struct _M0TPB5ArrayGyE, $0) / 4 * 2,
    sizeof(struct _M0TP410RabitLogic2s73src9transport9TcpConfig) / 4, 
    3,
    offsetof(struct _M0TP410RabitLogic2s73src9transport9TcpConfig, $0)
    / 4
    * 2,
    offsetof(struct _M0TP410RabitLogic2s73src9transport9TcpConfig, $6)
    / 4
    * 2,
    offsetof(struct _M0TP410RabitLogic2s73src9transport9TcpConfig, $7)
    / 4
    * 2, sizeof(struct _M0TPB13StringBuilder) / 4, 1,
    offsetof(struct _M0TPB13StringBuilder, $0) / 4 * 2
  };

struct { int32_t rc; uint32_t meta; struct _M0BTPB6Logger data; 
} _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id$object =
  {
    Moonbit_make_static_rc(moonbit_BLOCK_KIND_REGULAR),
    Moonbit_make_regular_object_header(MOONBIT_REGULAR_LAYOUT_CLASS_SCALAR, 0, 0),
    {.$method_0 = _M0IPB13StringBuilderPB6Logger69write__string_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger,
       .$method_1 = _M0IP016_24default__implPB6Logger72write__substring_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE,
       .$method_2 = _M0IPB13StringBuilderPB6Logger67write__view_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger,
       .$method_3 = _M0IPB13StringBuilderPB6Logger67write__char_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger,
       .$method_4 = _M0IP016_24default__implPB6Logger84write__string__interpolation_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE,
       .$method_5 = _M0IP016_24default__implPB6Logger61write_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE}
  };

struct _M0BTPB6Logger* _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id =
  &_M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id$object.data;

int32_t _M0MP410RabitLogic2s73src6client8S7Client13is__connected(
  struct _M0TP410RabitLogic2s73src6client8S7Client* _M0L4selfS180
) {
  #line 47 "/home/rabitlogic/workspace/moonbit/s7/src/client/client.mbt"
  return _M0L4selfS180->$1;
}

struct _M0TP410RabitLogic2s73src6client8S7Client* _M0MP410RabitLogic2s73src6client8S7Client17new__with__config(
  struct _M0TP410RabitLogic2s73src9transport9TcpConfig* _M0L1cS179
) {
  struct _M0TP410RabitLogic2s73src9transport13TcpConnection* _M0L6_2atmpS384;
  struct _M0TP410RabitLogic2s73src6client8S7Client* _block_400;
  #line 23 "/home/rabitlogic/workspace/moonbit/s7/src/client/client.mbt"
  #line 25 "/home/rabitlogic/workspace/moonbit/s7/src/client/client.mbt"
  _M0L6_2atmpS384
  = _M0MP410RabitLogic2s73src9transport13TcpConnection3new(_M0L1cS179);
  _block_400
  = (struct _M0TP410RabitLogic2s73src6client8S7Client*)moonbit_malloc(sizeof(struct _M0TP410RabitLogic2s73src6client8S7Client));
  Moonbit_object_header(_block_400)->meta
  = Moonbit_make_regular_object_header(MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED, 0, 0);
  _block_400->$0 = _M0L6_2atmpS384;
  _block_400->$1 = 0;
  _block_400->$2 = 1;
  _block_400->$3 = 480;
  return _block_400;
}

struct _M0TP410RabitLogic2s73src9transport13TcpConnection* _M0MP410RabitLogic2s73src9transport13TcpConnection3new(
  struct _M0TP410RabitLogic2s73src9transport9TcpConfig* _M0L1cS178
) {
  struct _M0TPB5ArrayGyE* _M0L11local__tsapS382;
  struct _M0TPB5ArrayGyE* _M0L12remote__tsapS383;
  struct _M0TP410RabitLogic2s73src9transport13TcpConnection* _block_401;
  #line 38 "/home/rabitlogic/workspace/moonbit/s7/src/transport/tcp.mbt"
  _M0L11local__tsapS382 = _M0L1cS178->$6;
  _M0L12remote__tsapS383 = _M0L1cS178->$7;
  moonbit_incref(_M0L1cS178);
  moonbit_incref(_M0L11local__tsapS382);
  moonbit_incref(_M0L12remote__tsapS383);
  _block_401
  = (struct _M0TP410RabitLogic2s73src9transport13TcpConnection*)moonbit_malloc(sizeof(struct _M0TP410RabitLogic2s73src9transport13TcpConnection));
  Moonbit_object_header(_block_401)->meta
  = Moonbit_make_regular_object_header(MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED, 3, 0);
  _block_401->$0 = _M0L1cS178;
  _block_401->$1 = 0;
  _block_401->$2 = -1;
  _block_401->$3 = 0;
  _block_401->$4 = 480;
  _block_401->$5 = _M0L11local__tsapS382;
  _block_401->$6 = _M0L12remote__tsapS383;
  return _block_401;
}

struct _M0TP410RabitLogic2s73src9transport9TcpConfig* _M0MP410RabitLogic2s73src9transport9TcpConfig11new_2einner(
  moonbit_string_t _M0L4hostS170,
  int32_t _M0L4portS171,
  int32_t _M0L16connect__timeoutS172,
  int32_t _M0L13read__timeoutS173,
  int32_t _M0L14write__timeoutS174,
  int32_t _M0L4rackS175,
  int32_t _M0L4slotS176,
  int32_t _M0L10conn__typeS177
) {
  moonbit_bytes_t _M0L6_2atmpS381;
  struct _M0TPB5ArrayGyE* _M0L6_2atmpS378;
  moonbit_bytes_t _M0L6_2atmpS380;
  struct _M0TPB5ArrayGyE* _M0L6_2atmpS379;
  struct _M0TP410RabitLogic2s73src9transport9TcpConfig* _block_402;
  #line 18 "/home/rabitlogic/workspace/moonbit/s7/src/transport/tcp.mbt"
  _M0L6_2atmpS381 = (moonbit_bytes_t)moonbit_make_bytes_raw(2);
  _M0L6_2atmpS381[0] = 1;
  _M0L6_2atmpS381[1] = 0;
  _M0L6_2atmpS378
  = (struct _M0TPB5ArrayGyE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGyE));
  Moonbit_object_header(_M0L6_2atmpS378)->meta
  = Moonbit_make_regular_object_header(MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED, 8, 0);
  _M0L6_2atmpS378->$0 = _M0L6_2atmpS381;
  _M0L6_2atmpS378->$1 = 2;
  _M0L6_2atmpS380 = (moonbit_bytes_t)moonbit_make_bytes_raw(2);
  _M0L6_2atmpS380[0] = 1;
  _M0L6_2atmpS380[1] = 1;
  _M0L6_2atmpS379
  = (struct _M0TPB5ArrayGyE*)moonbit_malloc(sizeof(struct _M0TPB5ArrayGyE));
  Moonbit_object_header(_M0L6_2atmpS379)->meta
  = Moonbit_make_regular_object_header(MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED, 8, 0);
  _M0L6_2atmpS379->$0 = _M0L6_2atmpS380;
  _M0L6_2atmpS379->$1 = 2;
  moonbit_incref(_M0L4hostS170);
  _block_402
  = (struct _M0TP410RabitLogic2s73src9transport9TcpConfig*)moonbit_malloc(sizeof(struct _M0TP410RabitLogic2s73src9transport9TcpConfig));
  Moonbit_object_header(_block_402)->meta
  = Moonbit_make_regular_object_header(MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED, 11, 0);
  _block_402->$0 = _M0L4hostS170;
  _block_402->$1 = _M0L4portS171;
  _block_402->$2 = _M0L16connect__timeoutS172;
  _block_402->$3 = _M0L13read__timeoutS173;
  _block_402->$4 = _M0L14write__timeoutS174;
  _block_402->$5 = 0;
  _block_402->$6 = _M0L6_2atmpS378;
  _block_402->$7 = _M0L6_2atmpS379;
  _block_402->$8 = _M0L4rackS175;
  _block_402->$9 = _M0L4slotS176;
  _block_402->$10 = _M0L10conn__typeS177;
  return _block_402;
}

moonbit_string_t _M0FP310RabitLogic2s73src7version() {
  #line 2 "/home/rabitlogic/workspace/moonbit/s7/src/lib.mbt"
  return (moonbit_string_t)moonbit_string_literal_0.data;
}

int32_t _M0FPB7printlnGsE(moonbit_string_t _M0L5inputS169) {
  moonbit_string_t _M0L6_2atmpS377;
  #line 36 "/home/rabitlogic/.moon/lib/core/builtin/console.mbt"
  #line 37 "/home/rabitlogic/.moon/lib/core/builtin/console.mbt"
  _M0L6_2atmpS377 = _M0IPC16string6StringPB4Show10to__string(_M0L5inputS169);
  #line 37 "/home/rabitlogic/.moon/lib/core/builtin/console.mbt"
  moonbit_println(_M0L6_2atmpS377);
  moonbit_decref(_M0L6_2atmpS377);
  return 0;
}

moonbit_string_t _M0IPC13int3IntPB4Show10to__string(int32_t _M0L4selfS168) {
  #line 35 "/home/rabitlogic/.moon/lib/core/builtin/show.mbt"
  #line 36 "/home/rabitlogic/.moon/lib/core/builtin/show.mbt"
  return _M0MPC13int3Int18to__string_2einner(_M0L4selfS168, 10);
}

moonbit_string_t _M0IPC14bool4BoolPB4Show10to__string(int32_t _M0L4selfS167) {
  #line 26 "/home/rabitlogic/.moon/lib/core/builtin/show.mbt"
  if (_M0L4selfS167) {
    return (moonbit_string_t)moonbit_string_literal_1.data;
  } else {
    return (moonbit_string_t)moonbit_string_literal_2.data;
  }
}

moonbit_string_t _M0IPC16string6StringPB4Show10to__string(
  moonbit_string_t _M0L4selfS166
) {
  #line 222 "/home/rabitlogic/.moon/lib/core/builtin/show.mbt"
  moonbit_incref(_M0L4selfS166);
  return _M0L4selfS166;
}

int32_t _M0IPB13StringBuilderPB6Logger11write__view(
  struct _M0TPB13StringBuilder* _M0L4selfS165,
  struct _M0TPC16string10StringView _M0L3strS164
) {
  int32_t _M0L3endS375;
  int32_t _M0L5startS376;
  int32_t _M0L8str__lenS163;
  int32_t _M0L3lenS368;
  int32_t _M0L6_2atmpS367;
  uint16_t* _M0L4dataS369;
  int32_t _M0L3lenS370;
  moonbit_string_t _M0L6_2atmpS371;
  int32_t _M0L6_2atmpS372;
  int32_t _M0L3lenS374;
  int32_t _M0L6_2atmpS373;
  #line 134 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0L3endS375 = _M0L3strS164.$2;
  _M0L5startS376 = _M0L3strS164.$1;
  _M0L8str__lenS163 = _M0L3endS375 - _M0L5startS376;
  if (_M0L8str__lenS163 == 0) {
    return 0;
  }
  _M0L3lenS368 = _M0L4selfS165->$1;
  _M0L6_2atmpS367 = _M0L3lenS368 + _M0L8str__lenS163;
  #line 142 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0MPB13StringBuilder19grow__if__necessary(_M0L4selfS165, _M0L6_2atmpS367);
  _M0L4dataS369 = _M0L4selfS165->$0;
  _M0L3lenS370 = _M0L4selfS165->$1;
  moonbit_incref(_M0L4dataS369);
  #line 145 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0L6_2atmpS371 = _M0MPC16string10StringView4data(_M0L3strS164);
  #line 146 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0L6_2atmpS372 = _M0MPC16string10StringView13start__offset(_M0L3strS164);
  #line 143 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0MPC15array10FixedArray26unsafe__blit__from__string(_M0L4dataS369, _M0L3lenS370, _M0L6_2atmpS371, _M0L6_2atmpS372, _M0L8str__lenS163);
  moonbit_decref(_M0L4dataS369);
  moonbit_decref(_M0L6_2atmpS371);
  _M0L3lenS374 = _M0L4selfS165->$1;
  _M0L6_2atmpS373 = _M0L3lenS374 + _M0L8str__lenS163;
  _M0L4selfS165->$1 = _M0L6_2atmpS373;
  return 0;
}

moonbit_string_t _M0MPC13int3Int18to__string_2einner(
  int32_t _M0L4selfS147,
  int32_t _M0L5radixS146
) {
  int32_t _if__result_403;
  int32_t _M0L12is__negativeS148;
  uint32_t _M0L3numS149;
  uint16_t* _M0L6bufferS150;
  #line 209 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
  if (_M0L5radixS146 < 2) {
    _if__result_403 = 1;
  } else {
    _if__result_403 = _M0L5radixS146 > 36;
  }
  if (_if__result_403) {
    #line 213 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
    _M0FPC15abort5abortGuE((moonbit_string_t)moonbit_string_literal_3.data);
  }
  if (_M0L4selfS147 == 0) {
    return (moonbit_string_t)moonbit_string_literal_4.data;
  }
  _M0L12is__negativeS148 = _M0L4selfS147 < 0;
  if (_M0L12is__negativeS148) {
    int32_t _M0L6_2atmpS366 = -_M0L4selfS147;
    _M0L3numS149 = *(uint32_t*)&_M0L6_2atmpS366;
  } else {
    _M0L3numS149 = *(uint32_t*)&_M0L4selfS147;
  }
  switch (_M0L5radixS146) {
    case 10: {
      int32_t _M0L10digit__lenS151;
      int32_t _M0L6_2atmpS363;
      int32_t _M0L10total__lenS152;
      uint16_t* _M0L6bufferS153;
      int32_t _M0L12digit__startS154;
      #line 235 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
      _M0L10digit__lenS151 = _M0FPB12dec__count32(_M0L3numS149);
      if (_M0L12is__negativeS148) {
        _M0L6_2atmpS363 = 1;
      } else {
        _M0L6_2atmpS363 = 0;
      }
      _M0L10total__lenS152 = _M0L10digit__lenS151 + _M0L6_2atmpS363;
      _M0L6bufferS153
      = (uint16_t*)moonbit_make_string(_M0L10total__lenS152, 0);
      if (_M0L12is__negativeS148) {
        _M0L12digit__startS154 = 1;
      } else {
        _M0L12digit__startS154 = 0;
      }
      #line 239 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
      _M0FPB20int__to__string__dec(_M0L6bufferS153, _M0L3numS149, _M0L12digit__startS154, _M0L10total__lenS152);
      _M0L6bufferS150 = _M0L6bufferS153;
      break;
    }
    
    case 16: {
      int32_t _M0L10digit__lenS155;
      int32_t _M0L6_2atmpS364;
      int32_t _M0L10total__lenS156;
      uint16_t* _M0L6bufferS157;
      int32_t _M0L12digit__startS158;
      #line 243 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
      _M0L10digit__lenS155 = _M0FPB12hex__count32(_M0L3numS149);
      if (_M0L12is__negativeS148) {
        _M0L6_2atmpS364 = 1;
      } else {
        _M0L6_2atmpS364 = 0;
      }
      _M0L10total__lenS156 = _M0L10digit__lenS155 + _M0L6_2atmpS364;
      _M0L6bufferS157
      = (uint16_t*)moonbit_make_string(_M0L10total__lenS156, 0);
      if (_M0L12is__negativeS148) {
        _M0L12digit__startS158 = 1;
      } else {
        _M0L12digit__startS158 = 0;
      }
      #line 247 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
      _M0FPB20int__to__string__hex(_M0L6bufferS157, _M0L3numS149, _M0L12digit__startS158, _M0L10total__lenS156);
      _M0L6bufferS150 = _M0L6bufferS157;
      break;
    }
    default: {
      int32_t _M0L10digit__lenS159;
      int32_t _M0L6_2atmpS365;
      int32_t _M0L10total__lenS160;
      uint16_t* _M0L6bufferS161;
      int32_t _M0L12digit__startS162;
      #line 251 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
      _M0L10digit__lenS159
      = _M0FPB14radix__count32(_M0L3numS149, _M0L5radixS146);
      if (_M0L12is__negativeS148) {
        _M0L6_2atmpS365 = 1;
      } else {
        _M0L6_2atmpS365 = 0;
      }
      _M0L10total__lenS160 = _M0L10digit__lenS159 + _M0L6_2atmpS365;
      _M0L6bufferS161
      = (uint16_t*)moonbit_make_string(_M0L10total__lenS160, 0);
      if (_M0L12is__negativeS148) {
        _M0L12digit__startS162 = 1;
      } else {
        _M0L12digit__startS162 = 0;
      }
      #line 255 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
      _M0FPB24int__to__string__generic(_M0L6bufferS161, _M0L3numS149, _M0L12digit__startS162, _M0L10total__lenS160, _M0L5radixS146);
      _M0L6bufferS150 = _M0L6bufferS161;
      break;
    }
  }
  if (_M0L12is__negativeS148) {
    _M0L6bufferS150[0] = 45;
  }
  return _M0L6bufferS150;
}

int32_t _M0FPB14radix__count32(
  uint32_t _M0L5valueS140,
  int32_t _M0L5radixS142
) {
  uint32_t _M0L4baseS141;
  uint32_t _M0L3numS143;
  int32_t _M0L5countS144;
  #line 189 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
  if (_M0L5valueS140 == 0u) {
    return 1;
  }
  _M0L4baseS141 = *(uint32_t*)&_M0L5radixS142;
  _M0L3numS143 = _M0L5valueS140;
  _M0L5countS144 = 0;
  while (1) {
    if (_M0L3numS143 > 0u) {
      uint32_t _M0L6_2atmpS361 = _M0L3numS143 / _M0L4baseS141;
      int32_t _M0L6_2atmpS362 = _M0L5countS144 + 1;
      _M0L3numS143 = _M0L6_2atmpS361;
      _M0L5countS144 = _M0L6_2atmpS362;
      continue;
    } else {
      return _M0L5countS144;
    }
    break;
  }
}

int32_t _M0FPB12hex__count32(uint32_t _M0L5valueS138) {
  #line 177 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
  if (_M0L5valueS138 == 0u) {
    return 1;
  } else {
    int32_t _M0L14leading__zerosS139;
    int32_t _M0L6_2atmpS360;
    int32_t _M0L6_2atmpS359;
    #line 182 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
    _M0L14leading__zerosS139 = moonbit_clz32(_M0L5valueS138);
    _M0L6_2atmpS360 = 31 - _M0L14leading__zerosS139;
    _M0L6_2atmpS359 = _M0L6_2atmpS360 / 4;
    return _M0L6_2atmpS359 + 1;
  }
}

int32_t _M0FPB12dec__count32(uint32_t _M0L5valueS137) {
  #line 143 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
  if (_M0L5valueS137 >= 100000u) {
    if (_M0L5valueS137 >= 10000000u) {
      if (_M0L5valueS137 >= 1000000000u) {
        return 10;
      } else if (_M0L5valueS137 >= 100000000u) {
        return 9;
      } else {
        return 8;
      }
    } else if (_M0L5valueS137 >= 1000000u) {
      return 7;
    } else {
      return 6;
    }
  } else if (_M0L5valueS137 >= 1000u) {
    if (_M0L5valueS137 >= 10000u) {
      return 5;
    } else {
      return 4;
    }
  } else if (_M0L5valueS137 >= 100u) {
    return 3;
  } else if (_M0L5valueS137 >= 10u) {
    return 2;
  } else {
    return 1;
  }
}

int32_t _M0FPB20int__to__string__dec(
  uint16_t* _M0L6bufferS123,
  uint32_t _M0L3numS135,
  int32_t _M0L12digit__startS124,
  int32_t _M0L10total__lenS136
) {
  int32_t _M0L6_2atmpS358;
  uint32_t _M0L3numS113;
  int32_t _M0L6offsetS114;
  #line 88 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
  _M0L6_2atmpS358 = _M0L10total__lenS136 - _M0L12digit__startS124;
  _M0L3numS113 = _M0L3numS135;
  _M0L6offsetS114 = _M0L6_2atmpS358;
  while (1) {
    if (_M0L3numS113 >= 10000u) {
      uint32_t _M0L1tS115 = _M0L3numS113 / 10000u;
      uint32_t _M0L6_2atmpS335 = _M0L3numS113 % 10000u;
      int32_t _M0L1rS116 = *(int32_t*)&_M0L6_2atmpS335;
      int32_t _M0L2d1S117 = _M0L1rS116 / 100;
      int32_t _M0L2d2S118 = _M0L1rS116 % 100;
      int32_t _M0L6_2atmpS334 = _M0L2d1S117 / 10;
      int32_t _M0L6_2atmpS333 = 48 + _M0L6_2atmpS334;
      int32_t _M0L6d1__hiS119 = (uint16_t)_M0L6_2atmpS333;
      int32_t _M0L6_2atmpS332 = _M0L2d1S117 % 10;
      int32_t _M0L6_2atmpS331 = 48 + _M0L6_2atmpS332;
      int32_t _M0L6d1__loS120 = (uint16_t)_M0L6_2atmpS331;
      int32_t _M0L6_2atmpS330 = _M0L2d2S118 / 10;
      int32_t _M0L6_2atmpS329 = 48 + _M0L6_2atmpS330;
      int32_t _M0L6d2__hiS121 = (uint16_t)_M0L6_2atmpS329;
      int32_t _M0L6_2atmpS328 = _M0L2d2S118 % 10;
      int32_t _M0L6_2atmpS327 = 48 + _M0L6_2atmpS328;
      int32_t _M0L6d2__loS122 = (uint16_t)_M0L6_2atmpS327;
      int32_t _M0L6_2atmpS319 = _M0L12digit__startS124 + _M0L6offsetS114;
      int32_t _M0L6_2atmpS318 = _M0L6_2atmpS319 - 4;
      int32_t _M0L6_2atmpS321;
      int32_t _M0L6_2atmpS320;
      int32_t _M0L6_2atmpS323;
      int32_t _M0L6_2atmpS322;
      int32_t _M0L6_2atmpS325;
      int32_t _M0L6_2atmpS324;
      int32_t _M0L6_2atmpS326;
      _M0L6bufferS123[_M0L6_2atmpS318] = _M0L6d1__hiS119;
      _M0L6_2atmpS321 = _M0L12digit__startS124 + _M0L6offsetS114;
      _M0L6_2atmpS320 = _M0L6_2atmpS321 - 3;
      _M0L6bufferS123[_M0L6_2atmpS320] = _M0L6d1__loS120;
      _M0L6_2atmpS323 = _M0L12digit__startS124 + _M0L6offsetS114;
      _M0L6_2atmpS322 = _M0L6_2atmpS323 - 2;
      _M0L6bufferS123[_M0L6_2atmpS322] = _M0L6d2__hiS121;
      _M0L6_2atmpS325 = _M0L12digit__startS124 + _M0L6offsetS114;
      _M0L6_2atmpS324 = _M0L6_2atmpS325 - 1;
      _M0L6bufferS123[_M0L6_2atmpS324] = _M0L6d2__loS122;
      _M0L6_2atmpS326 = _M0L6offsetS114 - 4;
      _M0L3numS113 = _M0L1tS115;
      _M0L6offsetS114 = _M0L6_2atmpS326;
      continue;
    } else {
      int32_t _M0L6_2atmpS357 = *(int32_t*)&_M0L3numS113;
      int32_t _M0L9remainingS126 = _M0L6_2atmpS357;
      int32_t _M0L6offsetS127 = _M0L6offsetS114;
      while (1) {
        if (_M0L9remainingS126 >= 100) {
          int32_t _M0L1tS128 = _M0L9remainingS126 / 100;
          int32_t _M0L1dS129 = _M0L9remainingS126 % 100;
          int32_t _M0L6_2atmpS344 = _M0L1dS129 / 10;
          int32_t _M0L6_2atmpS343 = 48 + _M0L6_2atmpS344;
          int32_t _M0L5d__hiS130 = (uint16_t)_M0L6_2atmpS343;
          int32_t _M0L6_2atmpS342 = _M0L1dS129 % 10;
          int32_t _M0L6_2atmpS341 = 48 + _M0L6_2atmpS342;
          int32_t _M0L5d__loS131 = (uint16_t)_M0L6_2atmpS341;
          int32_t _M0L6_2atmpS337 = _M0L12digit__startS124 + _M0L6offsetS127;
          int32_t _M0L6_2atmpS336 = _M0L6_2atmpS337 - 2;
          int32_t _M0L6_2atmpS339;
          int32_t _M0L6_2atmpS338;
          int32_t _M0L6_2atmpS340;
          _M0L6bufferS123[_M0L6_2atmpS336] = _M0L5d__hiS130;
          _M0L6_2atmpS339 = _M0L12digit__startS124 + _M0L6offsetS127;
          _M0L6_2atmpS338 = _M0L6_2atmpS339 - 1;
          _M0L6bufferS123[_M0L6_2atmpS338] = _M0L5d__loS131;
          _M0L6_2atmpS340 = _M0L6offsetS127 - 2;
          _M0L9remainingS126 = _M0L1tS128;
          _M0L6offsetS127 = _M0L6_2atmpS340;
          continue;
        } else if (_M0L9remainingS126 >= 10) {
          int32_t _M0L6_2atmpS352 = _M0L9remainingS126 / 10;
          int32_t _M0L6_2atmpS351 = 48 + _M0L6_2atmpS352;
          int32_t _M0L5d__hiS133 = (uint16_t)_M0L6_2atmpS351;
          int32_t _M0L6_2atmpS350 = _M0L9remainingS126 % 10;
          int32_t _M0L6_2atmpS349 = 48 + _M0L6_2atmpS350;
          int32_t _M0L5d__loS134 = (uint16_t)_M0L6_2atmpS349;
          int32_t _M0L6_2atmpS346 = _M0L12digit__startS124 + _M0L6offsetS127;
          int32_t _M0L6_2atmpS345 = _M0L6_2atmpS346 - 2;
          int32_t _M0L6_2atmpS348;
          int32_t _M0L6_2atmpS347;
          _M0L6bufferS123[_M0L6_2atmpS345] = _M0L5d__hiS133;
          _M0L6_2atmpS348 = _M0L12digit__startS124 + _M0L6offsetS127;
          _M0L6_2atmpS347 = _M0L6_2atmpS348 - 1;
          _M0L6bufferS123[_M0L6_2atmpS347] = _M0L5d__loS134;
        } else {
          int32_t _M0L6_2atmpS356 = _M0L12digit__startS124 + _M0L6offsetS127;
          int32_t _M0L6_2atmpS353 = _M0L6_2atmpS356 - 1;
          int32_t _M0L6_2atmpS355 = 48 + _M0L9remainingS126;
          int32_t _M0L6_2atmpS354 = (uint16_t)_M0L6_2atmpS355;
          _M0L6bufferS123[_M0L6_2atmpS353] = _M0L6_2atmpS354;
        }
        break;
      }
    }
    break;
  }
  return 0;
}

int32_t _M0FPB24int__to__string__generic(
  uint16_t* _M0L6bufferS103,
  uint32_t _M0L3numS107,
  int32_t _M0L12digit__startS104,
  int32_t _M0L10total__lenS106,
  int32_t _M0L5radixS97
) {
  uint32_t _M0L4baseS96;
  int32_t _M0L6_2atmpS303;
  int32_t _M0L6_2atmpS302;
  #line 57 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
  _M0L4baseS96 = *(uint32_t*)&_M0L5radixS97;
  _M0L6_2atmpS303 = _M0L5radixS97 - 1;
  _M0L6_2atmpS302 = _M0L5radixS97 & _M0L6_2atmpS303;
  if (_M0L6_2atmpS302 == 0) {
    int32_t _M0L5shiftS98;
    uint32_t _M0L4maskS99;
    int32_t _M0L6_2atmpS310;
    int32_t _M0L6offsetS100;
    uint32_t _M0L1nS101;
    #line 68 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
    _M0L5shiftS98 = moonbit_ctz32(_M0L5radixS97);
    _M0L4maskS99 = _M0L4baseS96 - 1u;
    _M0L6_2atmpS310 = _M0L10total__lenS106 - _M0L12digit__startS104;
    _M0L6offsetS100 = _M0L6_2atmpS310;
    _M0L1nS101 = _M0L3numS107;
    while (1) {
      if (_M0L1nS101 > 0u) {
        uint32_t _M0L6_2atmpS309 = _M0L1nS101 & _M0L4maskS99;
        int32_t _M0L5digitS102 = *(int32_t*)&_M0L6_2atmpS309;
        int32_t _M0L6_2atmpS306 = _M0L12digit__startS104 + _M0L6offsetS100;
        int32_t _M0L6_2atmpS304 = _M0L6_2atmpS306 - 1;
        int32_t _M0L6_2atmpS305 =
          ((moonbit_string_t)moonbit_string_literal_5.data)[_M0L5digitS102];
        int32_t _M0L6_2atmpS307;
        uint32_t _M0L6_2atmpS308;
        _M0L6bufferS103[_M0L6_2atmpS304] = _M0L6_2atmpS305;
        _M0L6_2atmpS307 = _M0L6offsetS100 - 1;
        _M0L6_2atmpS308 = _M0L1nS101 >> (_M0L5shiftS98 & 31);
        _M0L6offsetS100 = _M0L6_2atmpS307;
        _M0L1nS101 = _M0L6_2atmpS308;
        continue;
      }
      break;
    }
  } else {
    int32_t _M0L6_2atmpS317 = _M0L10total__lenS106 - _M0L12digit__startS104;
    int32_t _M0L6offsetS108 = _M0L6_2atmpS317;
    uint32_t _M0L1nS109 = _M0L3numS107;
    while (1) {
      if (_M0L1nS109 > 0u) {
        uint32_t _M0L1qS110 = _M0L1nS109 / _M0L4baseS96;
        uint32_t _M0L6_2atmpS316 = _M0L1qS110 * _M0L4baseS96;
        uint32_t _M0L6_2atmpS315 = _M0L1nS109 - _M0L6_2atmpS316;
        int32_t _M0L5digitS111 = *(int32_t*)&_M0L6_2atmpS315;
        int32_t _M0L6_2atmpS313 = _M0L12digit__startS104 + _M0L6offsetS108;
        int32_t _M0L6_2atmpS311 = _M0L6_2atmpS313 - 1;
        int32_t _M0L6_2atmpS312 =
          ((moonbit_string_t)moonbit_string_literal_5.data)[_M0L5digitS111];
        int32_t _M0L6_2atmpS314;
        _M0L6bufferS103[_M0L6_2atmpS311] = _M0L6_2atmpS312;
        _M0L6_2atmpS314 = _M0L6offsetS108 - 1;
        _M0L6offsetS108 = _M0L6_2atmpS314;
        _M0L1nS109 = _M0L1qS110;
        continue;
      }
      break;
    }
  }
  return 0;
}

int32_t _M0FPB20int__to__string__hex(
  uint16_t* _M0L6bufferS90,
  uint32_t _M0L3numS95,
  int32_t _M0L12digit__startS91,
  int32_t _M0L10total__lenS94
) {
  int32_t _M0L6_2atmpS301;
  int32_t _M0L6offsetS85;
  uint32_t _M0L1nS86;
  #line 29 "/home/rabitlogic/.moon/lib/core/builtin/to_string.mbt"
  _M0L6_2atmpS301 = _M0L10total__lenS94 - _M0L12digit__startS91;
  _M0L6offsetS85 = _M0L6_2atmpS301;
  _M0L1nS86 = _M0L3numS95;
  while (1) {
    if (_M0L6offsetS85 >= 2) {
      uint32_t _M0L6_2atmpS298 = _M0L1nS86 & 255u;
      int32_t _M0L9byte__valS87 = *(int32_t*)&_M0L6_2atmpS298;
      int32_t _M0L2hiS88 = _M0L9byte__valS87 / 16;
      int32_t _M0L2loS89 = _M0L9byte__valS87 % 16;
      int32_t _M0L6_2atmpS292 = _M0L12digit__startS91 + _M0L6offsetS85;
      int32_t _M0L6_2atmpS290 = _M0L6_2atmpS292 - 2;
      int32_t _M0L6_2atmpS291 =
        ((moonbit_string_t)moonbit_string_literal_5.data)[_M0L2hiS88];
      int32_t _M0L6_2atmpS295;
      int32_t _M0L6_2atmpS293;
      int32_t _M0L6_2atmpS294;
      int32_t _M0L6_2atmpS296;
      uint32_t _M0L6_2atmpS297;
      _M0L6bufferS90[_M0L6_2atmpS290] = _M0L6_2atmpS291;
      _M0L6_2atmpS295 = _M0L12digit__startS91 + _M0L6offsetS85;
      _M0L6_2atmpS293 = _M0L6_2atmpS295 - 1;
      _M0L6_2atmpS294
      = ((moonbit_string_t)moonbit_string_literal_5.data)[
        _M0L2loS89
      ];
      _M0L6bufferS90[_M0L6_2atmpS293] = _M0L6_2atmpS294;
      _M0L6_2atmpS296 = _M0L6offsetS85 - 2;
      _M0L6_2atmpS297 = _M0L1nS86 >> 8;
      _M0L6offsetS85 = _M0L6_2atmpS296;
      _M0L1nS86 = _M0L6_2atmpS297;
      continue;
    } else if (_M0L6offsetS85 == 1) {
      uint32_t _M0L6_2atmpS300 = _M0L1nS86 & 15u;
      int32_t _M0L6nibbleS93 = *(int32_t*)&_M0L6_2atmpS300;
      int32_t _M0L6_2atmpS299 =
        ((moonbit_string_t)moonbit_string_literal_5.data)[_M0L6nibbleS93];
      _M0L6bufferS90[_M0L12digit__startS91] = _M0L6_2atmpS299;
    }
    break;
  }
  return 0;
}

int32_t _M0IP016_24default__implPB4Show6outputGsE(
  moonbit_string_t _M0L4selfS80,
  struct _M0TPB6Logger _M0L6loggerS79
) {
  moonbit_string_t _M0L6_2atmpS287;
  #line 159 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  #line 160 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  _M0L6_2atmpS287 = _M0IPC16string6StringPB4Show10to__string(_M0L4selfS80);
  #line 160 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  _M0L6loggerS79.$0->$method_0(_M0L6loggerS79.$1, _M0L6_2atmpS287);
  moonbit_decref(_M0L6_2atmpS287);
  return 0;
}

int32_t _M0IP016_24default__implPB4Show6outputGiE(
  int32_t _M0L4selfS82,
  struct _M0TPB6Logger _M0L6loggerS81
) {
  moonbit_string_t _M0L6_2atmpS288;
  #line 159 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  #line 160 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  _M0L6_2atmpS288 = _M0IPC13int3IntPB4Show10to__string(_M0L4selfS82);
  #line 160 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  _M0L6loggerS81.$0->$method_0(_M0L6loggerS81.$1, _M0L6_2atmpS288);
  moonbit_decref(_M0L6_2atmpS288);
  return 0;
}

int32_t _M0IP016_24default__implPB4Show6outputGbE(
  int32_t _M0L4selfS84,
  struct _M0TPB6Logger _M0L6loggerS83
) {
  moonbit_string_t _M0L6_2atmpS289;
  #line 159 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  #line 160 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  _M0L6_2atmpS289 = _M0IPC14bool4BoolPB4Show10to__string(_M0L4selfS84);
  #line 160 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  _M0L6loggerS83.$0->$method_0(_M0L6loggerS83.$1, _M0L6_2atmpS289);
  moonbit_decref(_M0L6_2atmpS289);
  return 0;
}

int32_t _M0MPC16string10StringView13start__offset(
  struct _M0TPC16string10StringView _M0L4selfS78
) {
  #line 99 "/home/rabitlogic/.moon/lib/core/builtin/stringview.mbt"
  return _M0L4selfS78.$1;
}

moonbit_string_t _M0MPC16string10StringView4data(
  struct _M0TPC16string10StringView _M0L4selfS77
) {
  moonbit_string_t _M0L8_2afieldS388;
  #line 92 "/home/rabitlogic/.moon/lib/core/builtin/stringview.mbt"
  _M0L8_2afieldS388 = _M0L4selfS77.$0;
  moonbit_incref(_M0L8_2afieldS388);
  return _M0L8_2afieldS388;
}

int32_t _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE(
  struct _M0TPB13StringBuilder* _M0L4selfS73,
  moonbit_string_t _M0L5valueS74,
  int32_t _M0L5startS75,
  int32_t _M0L3lenS76
) {
  int32_t _M0L6_2atmpS286;
  int64_t _M0L6_2atmpS285;
  struct _M0TPC16string10StringView _M0L6_2atmpS284;
  #line 122 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  _M0L6_2atmpS286 = _M0L5startS75 + _M0L3lenS76;
  _M0L6_2atmpS285 = (int64_t)_M0L6_2atmpS286;
  #line 123 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  _M0L6_2atmpS284
  = _M0MPC16string6String11sub_2einner(_M0L5valueS74, _M0L5startS75, _M0L6_2atmpS285);
  #line 123 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  _M0IPB13StringBuilderPB6Logger11write__view(_M0L4selfS73, _M0L6_2atmpS284);
  moonbit_decref(_M0L6_2atmpS284.$0);
  return 0;
}

struct _M0TPC16string10StringView _M0MPC16string6String11sub_2einner(
  moonbit_string_t _M0L4selfS68,
  int32_t _M0L5startS72,
  int64_t _M0L3endS70
) {
  int32_t _M0L3lenS67;
  int32_t _M0L3endS69;
  int32_t _if__result_410;
  #line 754 "/home/rabitlogic/.moon/lib/core/builtin/stringview.mbt"
  _M0L3lenS67 = Moonbit_array_length(_M0L4selfS68);
  if (_M0L3endS70 == 4294967296ll) {
    _M0L3endS69 = _M0L3lenS67;
  } else {
    int64_t _M0L7_2aSomeS71 = _M0L3endS70;
    _M0L3endS69 = (int32_t)_M0L7_2aSomeS71;
  }
  if (_M0L5startS72 >= 0) {
    if (_M0L5startS72 <= _M0L3endS69) {
      _if__result_410 = _M0L3endS69 <= _M0L3lenS67;
    } else {
      _if__result_410 = 0;
    }
  } else {
    _if__result_410 = 0;
  }
  if (_if__result_410) {
    if (_M0L5startS72 < _M0L3lenS67) {
      int32_t _M0L6_2atmpS281 = _M0L4selfS68[_M0L5startS72];
      int32_t _M0L6_2atmpS280;
      #line 763 "/home/rabitlogic/.moon/lib/core/builtin/stringview.mbt"
      _M0L6_2atmpS280
      = _M0MPC16uint166UInt1623is__trailing__surrogate(_M0L6_2atmpS281);
      if (!_M0L6_2atmpS280) {
        
      } else {
        #line 763 "/home/rabitlogic/.moon/lib/core/builtin/stringview.mbt"
        moonbit_panic();
      }
    }
    if (_M0L3endS69 < _M0L3lenS67) {
      int32_t _M0L6_2atmpS283 = _M0L4selfS68[_M0L3endS69];
      int32_t _M0L6_2atmpS282;
      #line 766 "/home/rabitlogic/.moon/lib/core/builtin/stringview.mbt"
      _M0L6_2atmpS282
      = _M0MPC16uint166UInt1623is__trailing__surrogate(_M0L6_2atmpS283);
      if (!_M0L6_2atmpS282) {
        
      } else {
        #line 766 "/home/rabitlogic/.moon/lib/core/builtin/stringview.mbt"
        moonbit_panic();
      }
    }
    moonbit_incref(_M0L4selfS68);
    return (struct _M0TPC16string10StringView){.$0 = _M0L4selfS68,
                                                 .$1 = _M0L5startS72,
                                                 .$2 = _M0L3endS69};
  } else {
    #line 761 "/home/rabitlogic/.moon/lib/core/builtin/stringview.mbt"
    moonbit_panic();
  }
}

int32_t _M0IP016_24default__implPB6Logger5writeGRPB13StringBuilderE(
  struct _M0TPB13StringBuilder* _M0L4selfS66,
  struct _M0TPB4Show _M0L4showS65
) {
  struct _M0TPB6Logger _M0L6_2atmpS279;
  #line 116 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  moonbit_incref(_M0L4selfS66);
  _M0L6_2atmpS279
  = (struct _M0TPB6Logger){
    _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id,
      _M0L4selfS66
  };
  #line 117 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  _M0L4showS65.$0->$method_0(_M0L4showS65.$1, _M0L6_2atmpS279);
  if (_M0L6_2atmpS279.$1) {
    moonbit_decref(_M0L6_2atmpS279.$1);
  }
  return 0;
}

int32_t _M0IP016_24default__implPB6Logger28write__string__interpolationGRPB13StringBuilderE(
  struct _M0TPB13StringBuilder* _M0L4selfS64,
  struct _M0TPB4Show _M0L4showS63
) {
  struct _M0TPB6Logger _M0L6_2atmpS278;
  #line 111 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  moonbit_incref(_M0L4selfS64);
  _M0L6_2atmpS278
  = (struct _M0TPB6Logger){
    _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id,
      _M0L4selfS64
  };
  #line 112 "/home/rabitlogic/.moon/lib/core/builtin/traits.mbt"
  _M0L4showS63.$0->$method_0(_M0L4showS63.$1, _M0L6_2atmpS278);
  if (_M0L6_2atmpS278.$1) {
    moonbit_decref(_M0L6_2atmpS278.$1);
  }
  return 0;
}

int32_t _M0IPB13StringBuilderPB6Logger13write__string(
  struct _M0TPB13StringBuilder* _M0L4selfS62,
  moonbit_string_t _M0L3strS61
) {
  int32_t _M0L8str__lenS60;
  int32_t _M0L3lenS273;
  int32_t _M0L6_2atmpS272;
  uint16_t* _M0L4dataS274;
  int32_t _M0L3lenS275;
  int32_t _M0L3lenS277;
  int32_t _M0L6_2atmpS276;
  #line 86 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0L8str__lenS60 = Moonbit_array_length(_M0L3strS61);
  if (_M0L8str__lenS60 == 0) {
    return 0;
  }
  _M0L3lenS273 = _M0L4selfS62->$1;
  _M0L6_2atmpS272 = _M0L3lenS273 + _M0L8str__lenS60;
  #line 91 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0MPB13StringBuilder19grow__if__necessary(_M0L4selfS62, _M0L6_2atmpS272);
  _M0L4dataS274 = _M0L4selfS62->$0;
  _M0L3lenS275 = _M0L4selfS62->$1;
  moonbit_incref(_M0L4dataS274);
  #line 92 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0MPC15array10FixedArray26unsafe__blit__from__string(_M0L4dataS274, _M0L3lenS275, _M0L3strS61, 0, _M0L8str__lenS60);
  moonbit_decref(_M0L4dataS274);
  _M0L3lenS277 = _M0L4selfS62->$1;
  _M0L6_2atmpS276 = _M0L3lenS277 + _M0L8str__lenS60;
  _M0L4selfS62->$1 = _M0L6_2atmpS276;
  return 0;
}

int32_t _M0MPC15array10FixedArray26unsafe__blit__from__string(
  uint16_t* _M0L4selfS56,
  int32_t _M0L11dst__offsetS59,
  moonbit_string_t _M0L3strS57,
  int32_t _M0L11str__offsetS52,
  int32_t _M0L3lenS53
) {
  int32_t _M0L16end__str__offsetS51;
  int32_t _M0L1iS54;
  int32_t _M0L1jS55;
  #line 71 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0L16end__str__offsetS51 = _M0L11str__offsetS52 + _M0L3lenS53;
  _M0L1iS54 = _M0L11str__offsetS52;
  _M0L1jS55 = _M0L11dst__offsetS59;
  while (1) {
    if (_M0L1iS54 < _M0L16end__str__offsetS51) {
      int32_t _M0L6_2atmpS269 = _M0L3strS57[_M0L1iS54];
      int32_t _M0L6_2atmpS270;
      int32_t _M0L6_2atmpS271;
      _M0L4selfS56[_M0L1jS55] = _M0L6_2atmpS269;
      _M0L6_2atmpS270 = _M0L1iS54 + 1;
      _M0L6_2atmpS271 = _M0L1jS55 + 1;
      _M0L1iS54 = _M0L6_2atmpS270;
      _M0L1jS55 = _M0L6_2atmpS271;
      continue;
    }
    break;
  }
  return 0;
}

int32_t _M0MPC16uint166UInt1623is__trailing__surrogate(int32_t _M0L4selfS50) {
  #line 45 "/home/rabitlogic/.moon/lib/core/builtin/uint16_char.mbt"
  if (_M0L4selfS50 >= 56320) {
    return _M0L4selfS50 <= 57343;
  } else {
    return 0;
  }
}

int32_t _M0IPB13StringBuilderPB6Logger11write__char(
  struct _M0TPB13StringBuilder* _M0L4selfS48,
  int32_t _M0L2chS47
) {
  uint32_t _M0L4codeS46;
  #line 98 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  #line 99 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0L4codeS46 = _M0MPC14char4Char8to__uint(_M0L2chS47);
  if (_M0L4codeS46 <= 65535u) {
    int32_t _M0L3lenS248 = _M0L4selfS48->$1;
    int32_t _M0L6_2atmpS247 = _M0L3lenS248 + 1;
    uint16_t* _M0L4dataS249;
    int32_t _M0L3lenS250;
    int32_t _M0L6_2atmpS251;
    int32_t _M0L3lenS253;
    int32_t _M0L6_2atmpS252;
    #line 101 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
    _M0MPB13StringBuilder19grow__if__necessary(_M0L4selfS48, _M0L6_2atmpS247);
    _M0L4dataS249 = _M0L4selfS48->$0;
    _M0L3lenS250 = _M0L4selfS48->$1;
    moonbit_incref(_M0L4dataS249);
    #line 102 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
    _M0L6_2atmpS251 = _M0MPC14uint4UInt10to__uint16(_M0L4codeS46);
    if (
      _M0L3lenS250 < 0 || _M0L3lenS250 >= Moonbit_array_length(_M0L4dataS249)
    ) {
      #line 102 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
      moonbit_panic();
    }
    _M0L4dataS249[_M0L3lenS250] = _M0L6_2atmpS251;
    moonbit_decref(_M0L4dataS249);
    _M0L3lenS253 = _M0L4selfS48->$1;
    _M0L6_2atmpS252 = _M0L3lenS253 + 1;
    _M0L4selfS48->$1 = _M0L6_2atmpS252;
  } else if (_M0L4codeS46 <= 1114111u) {
    int32_t _M0L3lenS255 = _M0L4selfS48->$1;
    int32_t _M0L6_2atmpS254 = _M0L3lenS255 + 2;
    uint32_t _M0L4codeS49;
    uint16_t* _M0L4dataS256;
    int32_t _M0L3lenS257;
    uint32_t _M0L6_2atmpS260;
    uint32_t _M0L6_2atmpS259;
    int32_t _M0L6_2atmpS258;
    uint16_t* _M0L4dataS261;
    int32_t _M0L3lenS266;
    int32_t _M0L6_2atmpS262;
    uint32_t _M0L6_2atmpS265;
    uint32_t _M0L6_2atmpS264;
    int32_t _M0L6_2atmpS263;
    int32_t _M0L3lenS268;
    int32_t _M0L6_2atmpS267;
    #line 105 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
    _M0MPB13StringBuilder19grow__if__necessary(_M0L4selfS48, _M0L6_2atmpS254);
    _M0L4codeS49 = _M0L4codeS46 - 65536u;
    _M0L4dataS256 = _M0L4selfS48->$0;
    _M0L3lenS257 = _M0L4selfS48->$1;
    _M0L6_2atmpS260 = _M0L4codeS49 >> 10;
    _M0L6_2atmpS259 = 55296u + _M0L6_2atmpS260;
    moonbit_incref(_M0L4dataS256);
    #line 107 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
    _M0L6_2atmpS258 = _M0MPC14uint4UInt10to__uint16(_M0L6_2atmpS259);
    if (
      _M0L3lenS257 < 0 || _M0L3lenS257 >= Moonbit_array_length(_M0L4dataS256)
    ) {
      #line 107 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
      moonbit_panic();
    }
    _M0L4dataS256[_M0L3lenS257] = _M0L6_2atmpS258;
    moonbit_decref(_M0L4dataS256);
    _M0L4dataS261 = _M0L4selfS48->$0;
    _M0L3lenS266 = _M0L4selfS48->$1;
    _M0L6_2atmpS262 = _M0L3lenS266 + 1;
    _M0L6_2atmpS265 = _M0L4codeS49 & 1023u;
    _M0L6_2atmpS264 = 56320u + _M0L6_2atmpS265;
    moonbit_incref(_M0L4dataS261);
    #line 108 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
    _M0L6_2atmpS263 = _M0MPC14uint4UInt10to__uint16(_M0L6_2atmpS264);
    if (
      _M0L6_2atmpS262 < 0
      || _M0L6_2atmpS262 >= Moonbit_array_length(_M0L4dataS261)
    ) {
      #line 108 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
      moonbit_panic();
    }
    _M0L4dataS261[_M0L6_2atmpS262] = _M0L6_2atmpS263;
    moonbit_decref(_M0L4dataS261);
    _M0L3lenS268 = _M0L4selfS48->$1;
    _M0L6_2atmpS267 = _M0L3lenS268 + 2;
    _M0L4selfS48->$1 = _M0L6_2atmpS267;
  } else {
    #line 111 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
    _M0FPC15abort5abortGuE((moonbit_string_t)moonbit_string_literal_6.data);
  }
  return 0;
}

int32_t _M0MPB13StringBuilder19grow__if__necessary(
  struct _M0TPB13StringBuilder* _M0L4selfS40,
  int32_t _M0L8requiredS41
) {
  uint16_t* _M0L4dataS246;
  int32_t _M0L12current__lenS39;
  int32_t _M0L13enough__spaceS42;
  int32_t _M0L13enough__spaceS43;
  uint16_t* _M0L4dataS242;
  int32_t _M0L6_2atmpS243;
  int32_t _M0L3lenS244;
  uint16_t* _M0L9new__dataS45;
  uint16_t* _M0L6_2aoldS393;
  #line 46 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0L4dataS246 = _M0L4selfS40->$0;
  _M0L12current__lenS39 = Moonbit_array_length(_M0L4dataS246);
  if (_M0L8requiredS41 <= _M0L12current__lenS39) {
    return 0;
  }
  _M0L13enough__spaceS43 = _M0L12current__lenS39;
  while (1) {
    if (_M0L13enough__spaceS43 < _M0L8requiredS41) {
      int32_t _M0L6_2atmpS245 = _M0L13enough__spaceS43 * 2;
      _M0L13enough__spaceS43 = _M0L6_2atmpS245;
      continue;
    } else {
      _M0L13enough__spaceS42 = _M0L13enough__spaceS43;
    }
    break;
  }
  _M0L4dataS242 = _M0L4selfS40->$0;
  moonbit_incref(_M0L4dataS242);
  #line 64 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0L6_2atmpS243 = _M0IPC16uint166UInt16PB7Default7default();
  _M0L3lenS244 = _M0L4selfS40->$1;
  #line 61 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0L9new__dataS45
  = _M0MPC15array10FixedArray23make__and__blit_2einnerGkE(_M0L4dataS242, _M0L13enough__spaceS42, _M0L6_2atmpS243, _M0L3lenS244, 0, 0);
  moonbit_decref(_M0L4dataS242);
  _M0L6_2aoldS393 = _M0L4selfS40->$0;
  moonbit_decref(_M0L6_2aoldS393);
  _M0L4selfS40->$0 = _M0L9new__dataS45;
  return 0;
}

int32_t _M0MPC14uint4UInt10to__uint16(uint32_t _M0L4selfS38) {
  int32_t _M0L6_2atmpS241;
  #line 2676 "/home/rabitlogic/.moon/lib/core/builtin/intrinsics.mbt"
  _M0L6_2atmpS241 = *(int32_t*)&_M0L4selfS38;
  return (uint16_t)_M0L6_2atmpS241;
}

uint32_t _M0MPC14char4Char8to__uint(int32_t _M0L4selfS37) {
  int32_t _M0L6_2atmpS240;
  #line 1254 "/home/rabitlogic/.moon/lib/core/builtin/intrinsics.mbt"
  _M0L6_2atmpS240 = _M0L4selfS37;
  return *(uint32_t*)&_M0L6_2atmpS240;
}

moonbit_string_t _M0MPB13StringBuilder10to__string(
  struct _M0TPB13StringBuilder* _M0L4selfS35
) {
  int32_t _M0L3lenS231;
  #line 154 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  _M0L3lenS231 = _M0L4selfS35->$1;
  if (_M0L3lenS231 == 0) {
    return (moonbit_string_t)moonbit_string_literal_7.data;
  } else {
    int32_t _M0L3lenS232 = _M0L4selfS35->$1;
    uint16_t* _M0L4dataS234 = _M0L4selfS35->$0;
    int32_t _M0L6_2atmpS233 = Moonbit_array_length(_M0L4dataS234);
    if (_M0L3lenS232 == _M0L6_2atmpS233) {
      uint16_t* _M0L4dataS235 = _M0L4selfS35->$0;
      moonbit_incref(_M0L4dataS235);
      return _M0L4dataS235;
    } else {
      uint16_t* _M0L4dataS236 = _M0L4selfS35->$0;
      int32_t _M0L3lenS237 = _M0L4selfS35->$1;
      int32_t _M0L6_2atmpS238;
      int32_t _M0L3lenS239;
      uint16_t* _M0L4dataS36;
      moonbit_incref(_M0L4dataS236);
      #line 163 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
      _M0L6_2atmpS238 = _M0IPC16uint166UInt16PB7Default7default();
      _M0L3lenS239 = _M0L4selfS35->$1;
      #line 160 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
      _M0L4dataS36
      = _M0MPC15array10FixedArray23make__and__blit_2einnerGkE(_M0L4dataS236, _M0L3lenS237, _M0L6_2atmpS238, _M0L3lenS239, 0, 0);
      moonbit_decref(_M0L4dataS236);
      return _M0L4dataS36;
    }
  }
}

int32_t _M0IPC16uint166UInt16PB7Default7default() {
  #line 176 "/home/rabitlogic/.moon/lib/core/builtin/uint16_char.mbt"
  return 0;
}

uint16_t* _M0MPC15array10FixedArray23make__and__blit_2einnerGkE(
  uint16_t* _M0L3srcS32,
  int32_t _M0L13allocate__lenS28,
  int32_t _M0L4initS33,
  int32_t _M0L3lenS29,
  int32_t _M0L11src__offsetS30,
  int32_t _M0L11dst__offsetS31
) {
  int32_t _if__result_413;
  #line 97 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
  if (_M0L13allocate__lenS28 >= 0) {
    if (_M0L3lenS29 >= 0) {
      if (_M0L11src__offsetS30 >= 0) {
        if (_M0L11dst__offsetS31 >= 0) {
          int32_t _M0L6_2atmpS227 = _M0L11src__offsetS30 + _M0L3lenS29;
          int32_t _M0L6_2atmpS228 = Moonbit_array_length(_M0L3srcS32);
          if (_M0L6_2atmpS227 <= _M0L6_2atmpS228) {
            int32_t _M0L6_2atmpS226 = _M0L11dst__offsetS31 + _M0L3lenS29;
            _if__result_413 = _M0L6_2atmpS226 <= _M0L13allocate__lenS28;
          } else {
            _if__result_413 = 0;
          }
        } else {
          _if__result_413 = 0;
        }
      } else {
        _if__result_413 = 0;
      }
    } else {
      _if__result_413 = 0;
    }
  } else {
    _if__result_413 = 0;
  }
  if (_if__result_413) {
    moonbit_incref(_M0L3srcS32);
    #line 115 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    return _M0MPC15array10FixedArray23unsafe__make__and__blitGkE(_M0L3srcS32, _M0L13allocate__lenS28, _M0L4initS33, _M0L11src__offsetS30, _M0L11dst__offsetS31, _M0L3lenS29);
  } else {
    struct _M0TPB13StringBuilder* _M0L18_2astring__builderS34;
    int32_t _M0L6_2atmpS230;
    moonbit_string_t _M0L6_2atmpS229;
    uint16_t* _result_414;
    #line 112 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _M0L18_2astring__builderS34
    = _M0MPB13StringBuilder21StringBuilder_2einner(89);
    #line 112 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _M0IPB13StringBuilderPB6Logger13write__string(_M0L18_2astring__builderS34, (moonbit_string_t)moonbit_string_literal_8.data);
    #line 112 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _M0MPB13StringBuilder13write__objectGiE(_M0L18_2astring__builderS34, _M0L13allocate__lenS28);
    #line 112 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _M0IPB13StringBuilderPB6Logger13write__string(_M0L18_2astring__builderS34, (moonbit_string_t)moonbit_string_literal_9.data);
    #line 112 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _M0MPB13StringBuilder13write__objectGiE(_M0L18_2astring__builderS34, _M0L11src__offsetS30);
    #line 112 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _M0IPB13StringBuilderPB6Logger13write__string(_M0L18_2astring__builderS34, (moonbit_string_t)moonbit_string_literal_10.data);
    #line 112 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _M0MPB13StringBuilder13write__objectGiE(_M0L18_2astring__builderS34, _M0L11dst__offsetS31);
    #line 112 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _M0IPB13StringBuilderPB6Logger13write__string(_M0L18_2astring__builderS34, (moonbit_string_t)moonbit_string_literal_11.data);
    #line 112 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _M0MPB13StringBuilder13write__objectGiE(_M0L18_2astring__builderS34, _M0L3lenS29);
    #line 112 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _M0IPB13StringBuilderPB6Logger13write__string(_M0L18_2astring__builderS34, (moonbit_string_t)moonbit_string_literal_12.data);
    _M0L6_2atmpS230 = Moonbit_array_length(_M0L3srcS32);
    #line 112 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _M0MPB13StringBuilder13write__objectGiE(_M0L18_2astring__builderS34, _M0L6_2atmpS230);
    #line 112 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _M0L6_2atmpS229
    = _M0MPB13StringBuilder10to__string(_M0L18_2astring__builderS34);
    moonbit_decref(_M0L18_2astring__builderS34);
    #line 111 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
    _result_414 = _M0FPC15abort5abortGAkE(_M0L6_2atmpS229);
    moonbit_decref(_M0L6_2atmpS229);
    return _result_414;
  }
}

uint16_t* _M0MPC15array10FixedArray23unsafe__make__and__blitGkE(
  uint16_t* _M0L3srcS25,
  int32_t _M0L13allocate__lenS22,
  int32_t _M0L4initS23,
  int32_t _M0L11src__offsetS26,
  int32_t _M0L11dst__offsetS24,
  int32_t _M0L9blit__lenS27
) {
  uint16_t* _M0L3dstS21;
  #line 79 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
  _M0L3dstS21
  = (uint16_t*)moonbit_make_string(_M0L13allocate__lenS22, _M0L4initS23);
  moonbit_incref(_M0L3dstS21);
  #line 90 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
  moonbit_unsafe_val_array_blit(_M0L3dstS21, _M0L11dst__offsetS24, _M0L3srcS25, _M0L11src__offsetS26, _M0L9blit__lenS27, sizeof(uint16_t));
  return _M0L3dstS21;
}

struct _M0TPB13StringBuilder* _M0MPB13StringBuilder21StringBuilder_2einner(
  int32_t _M0L10size__hintS19
) {
  int32_t _M0L7initialS18;
  uint16_t* _M0L4dataS20;
  struct _M0TPB13StringBuilder* _block_415;
  #line 32 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder_buffer.mbt"
  if (_M0L10size__hintS19 < 1) {
    _M0L7initialS18 = 1;
  } else {
    int32_t _M0L6_2atmpS225 = _M0L10size__hintS19 + 1;
    _M0L7initialS18 = _M0L6_2atmpS225 / 2;
  }
  _M0L4dataS20 = (uint16_t*)moonbit_make_string(_M0L7initialS18, 0);
  _block_415
  = (struct _M0TPB13StringBuilder*)moonbit_malloc(sizeof(struct _M0TPB13StringBuilder));
  Moonbit_object_header(_block_415)->meta
  = Moonbit_make_regular_object_header(MOONBIT_REGULAR_LAYOUT_CLASS_INDEXED, 16, 0);
  _block_415->$0 = _M0L4dataS20;
  _block_415->$1 = 0;
  return _block_415;
}

int32_t _M0MPB13StringBuilder13write__objectGsE(
  struct _M0TPB13StringBuilder* _M0L4selfS13,
  moonbit_string_t _M0L3objS12
) {
  struct _M0TPB6Logger _M0L6_2atmpS222;
  #line 17 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder.mbt"
  moonbit_incref(_M0L4selfS13);
  _M0L6_2atmpS222
  = (struct _M0TPB6Logger){
    _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id,
      _M0L4selfS13
  };
  #line 23 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder.mbt"
  _M0IP016_24default__implPB4Show6outputGsE(_M0L3objS12, _M0L6_2atmpS222);
  if (_M0L6_2atmpS222.$1) {
    moonbit_decref(_M0L6_2atmpS222.$1);
  }
  return 0;
}

int32_t _M0MPB13StringBuilder13write__objectGiE(
  struct _M0TPB13StringBuilder* _M0L4selfS15,
  int32_t _M0L3objS14
) {
  struct _M0TPB6Logger _M0L6_2atmpS223;
  #line 17 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder.mbt"
  moonbit_incref(_M0L4selfS15);
  _M0L6_2atmpS223
  = (struct _M0TPB6Logger){
    _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id,
      _M0L4selfS15
  };
  #line 23 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder.mbt"
  _M0IP016_24default__implPB4Show6outputGiE(_M0L3objS14, _M0L6_2atmpS223);
  if (_M0L6_2atmpS223.$1) {
    moonbit_decref(_M0L6_2atmpS223.$1);
  }
  return 0;
}

int32_t _M0MPB13StringBuilder13write__objectGbE(
  struct _M0TPB13StringBuilder* _M0L4selfS17,
  int32_t _M0L3objS16
) {
  struct _M0TPB6Logger _M0L6_2atmpS224;
  #line 17 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder.mbt"
  moonbit_incref(_M0L4selfS17);
  _M0L6_2atmpS224
  = (struct _M0TPB6Logger){
    _M0FP0119moonbitlang_2fcore_2fbuiltin_2fStringBuilder_2eas___40moonbitlang_2fcore_2fbuiltin_2eLogger_2estatic__method__table__id,
      _M0L4selfS17
  };
  #line 23 "/home/rabitlogic/.moon/lib/core/builtin/stringbuilder.mbt"
  _M0IP016_24default__implPB4Show6outputGbE(_M0L3objS16, _M0L6_2atmpS224);
  if (_M0L6_2atmpS224.$1) {
    moonbit_decref(_M0L6_2atmpS224.$1);
  }
  return 0;
}

int32_t _M0MPC15array10FixedArray12unsafe__blitGkE(
  uint16_t* _M0L3dstS3,
  int32_t _M0L11dst__offsetS5,
  uint16_t* _M0L3srcS4,
  int32_t _M0L11src__offsetS6,
  int32_t _M0L3lenS8
) {
  int32_t _if__result_416;
  #line 38 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
  if (_M0L3dstS3 == _M0L3srcS4) {
    _if__result_416 = _M0L11dst__offsetS5 < _M0L11src__offsetS6;
  } else {
    _if__result_416 = 0;
  }
  if (_if__result_416) {
    int32_t _M0L1iS7 = 0;
    while (1) {
      if (_M0L1iS7 < _M0L3lenS8) {
        int32_t _M0L6_2atmpS213 = _M0L11dst__offsetS5 + _M0L1iS7;
        int32_t _M0L6_2atmpS215 = _M0L11src__offsetS6 + _M0L1iS7;
        int32_t _M0L6_2atmpS214;
        int32_t _M0L6_2atmpS216;
        if (
          _M0L6_2atmpS215 < 0
          || _M0L6_2atmpS215 >= Moonbit_array_length(_M0L3srcS4)
        ) {
          #line 50 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS214 = (int32_t)_M0L3srcS4[_M0L6_2atmpS215];
        if (
          _M0L6_2atmpS213 < 0
          || _M0L6_2atmpS213 >= Moonbit_array_length(_M0L3dstS3)
        ) {
          #line 50 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L3dstS3[_M0L6_2atmpS213] = _M0L6_2atmpS214;
        _M0L6_2atmpS216 = _M0L1iS7 + 1;
        _M0L1iS7 = _M0L6_2atmpS216;
        continue;
      } else {
        moonbit_decref(_M0L3srcS4);
        moonbit_decref(_M0L3dstS3);
      }
      break;
    }
  } else {
    int32_t _M0L6_2atmpS221 = _M0L3lenS8 - 1;
    int32_t _M0L1iS10 = _M0L6_2atmpS221;
    while (1) {
      if (_M0L1iS10 >= 0) {
        int32_t _M0L6_2atmpS217 = _M0L11dst__offsetS5 + _M0L1iS10;
        int32_t _M0L6_2atmpS219 = _M0L11src__offsetS6 + _M0L1iS10;
        int32_t _M0L6_2atmpS218;
        int32_t _M0L6_2atmpS220;
        if (
          _M0L6_2atmpS219 < 0
          || _M0L6_2atmpS219 >= Moonbit_array_length(_M0L3srcS4)
        ) {
          #line 54 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L6_2atmpS218 = (int32_t)_M0L3srcS4[_M0L6_2atmpS219];
        if (
          _M0L6_2atmpS217 < 0
          || _M0L6_2atmpS217 >= Moonbit_array_length(_M0L3dstS3)
        ) {
          #line 54 "/home/rabitlogic/.moon/lib/core/builtin/fixedarray_block.mbt"
          moonbit_panic();
        }
        _M0L3dstS3[_M0L6_2atmpS217] = _M0L6_2atmpS218;
        _M0L6_2atmpS220 = _M0L1iS10 - 1;
        _M0L1iS10 = _M0L6_2atmpS220;
        continue;
      } else {
        moonbit_decref(_M0L3srcS4);
        moonbit_decref(_M0L3dstS3);
      }
      break;
    }
  }
  return 0;
}

int32_t _M0FPC15abort5abortGuE(moonbit_string_t _M0L3msgS1) {
  #line 47 "/home/rabitlogic/.moon/lib/core/abort/abort.mbt"
  #line 49 "/home/rabitlogic/.moon/lib/core/abort/abort.mbt"
  moonbit_println(_M0L3msgS1);
  #line 50 "/home/rabitlogic/.moon/lib/core/abort/abort.mbt"
  moonbit_panic();
  return 0;
}

uint16_t* _M0FPC15abort5abortGAkE(moonbit_string_t _M0L3msgS2) {
  #line 47 "/home/rabitlogic/.moon/lib/core/abort/abort.mbt"
  #line 49 "/home/rabitlogic/.moon/lib/core/abort/abort.mbt"
  moonbit_println(_M0L3msgS2);
  #line 50 "/home/rabitlogic/.moon/lib/core/abort/abort.mbt"
  moonbit_panic();
}

int32_t _M0IP016_24default__implPB6Logger61write_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE(
  void* _M0L11_2aobj__ptrS205,
  struct _M0TPB4Show _M0L8_2aparamS204
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS203 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS205;
  _M0IP016_24default__implPB6Logger5writeGRPB13StringBuilderE(_M0L7_2aselfS203, _M0L8_2aparamS204);
  return 0;
}

int32_t _M0IP016_24default__implPB6Logger84write__string__interpolation_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE(
  void* _M0L11_2aobj__ptrS202,
  struct _M0TPB4Show _M0L8_2aparamS201
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS200 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS202;
  _M0IP016_24default__implPB6Logger28write__string__interpolationGRPB13StringBuilderE(_M0L7_2aselfS200, _M0L8_2aparamS201);
  return 0;
}

int32_t _M0IPB13StringBuilderPB6Logger67write__char_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void* _M0L11_2aobj__ptrS199,
  int32_t _M0L8_2aparamS198
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS197 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS199;
  _M0IPB13StringBuilderPB6Logger11write__char(_M0L7_2aselfS197, _M0L8_2aparamS198);
  return 0;
}

int32_t _M0IPB13StringBuilderPB6Logger67write__view_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void* _M0L11_2aobj__ptrS196,
  struct _M0TPC16string10StringView _M0L8_2aparamS195
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS194 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS196;
  _M0IPB13StringBuilderPB6Logger11write__view(_M0L7_2aselfS194, _M0L8_2aparamS195);
  return 0;
}

int32_t _M0IP016_24default__implPB6Logger72write__substring_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLoggerGRPB13StringBuilderE(
  void* _M0L11_2aobj__ptrS193,
  moonbit_string_t _M0L8_2aparamS190,
  int32_t _M0L8_2aparamS191,
  int32_t _M0L8_2aparamS192
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS189 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS193;
  _M0IP016_24default__implPB6Logger16write__substringGRPB13StringBuilderE(_M0L7_2aselfS189, _M0L8_2aparamS190, _M0L8_2aparamS191, _M0L8_2aparamS192);
  return 0;
}

int32_t _M0IPB13StringBuilderPB6Logger69write__string_2edyncall__as___40moonbitlang_2fcore_2fbuiltin_2eLogger(
  void* _M0L11_2aobj__ptrS188,
  moonbit_string_t _M0L8_2aparamS187
) {
  struct _M0TPB13StringBuilder* _M0L7_2aselfS186 =
    (struct _M0TPB13StringBuilder*)_M0L11_2aobj__ptrS188;
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L7_2aselfS186, _M0L8_2aparamS187);
  return 0;
}

void moonbit_init() {
  moonbit_layout_table = moonbit_layout_table_data;
}

int main(int argc, char** argv) {
  struct _M0TPB13StringBuilder* _M0L18_2astring__builderS181;
  moonbit_string_t _M0L6_2atmpS207;
  moonbit_string_t _M0L6_2atmpS206;
  struct _M0TP410RabitLogic2s73src9transport9TcpConfig* _M0L3cfgS182;
  struct _M0TPB13StringBuilder* _M0L18_2astring__builderS183;
  moonbit_string_t _M0L4hostS209;
  int32_t _M0L4portS210;
  moonbit_string_t _M0L6_2atmpS208;
  struct _M0TP410RabitLogic2s73src6client8S7Client* _M0L2clS184;
  struct _M0TPB13StringBuilder* _M0L18_2astring__builderS185;
  int32_t _M0L6_2atmpS212;
  moonbit_string_t _M0L6_2atmpS211;
  moonbit_runtime_init(argc, argv);
  moonbit_init();
  #line 3 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0L18_2astring__builderS181
  = _M0MPB13StringBuilder21StringBuilder_2einner(20);
  #line 3 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L18_2astring__builderS181, (moonbit_string_t)moonbit_string_literal_13.data);
  #line 3 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0L6_2atmpS207 = _M0FP310RabitLogic2s73src7version();
  #line 3 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0MPB13StringBuilder13write__objectGsE(_M0L18_2astring__builderS181, _M0L6_2atmpS207);
  moonbit_decref(_M0L6_2atmpS207);
  #line 3 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L18_2astring__builderS181, (moonbit_string_t)moonbit_string_literal_14.data);
  #line 3 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0L6_2atmpS206
  = _M0MPB13StringBuilder10to__string(_M0L18_2astring__builderS181);
  moonbit_decref(_M0L18_2astring__builderS181);
  #line 3 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE(_M0L6_2atmpS206);
  moonbit_decref(_M0L6_2atmpS206);
  #line 4 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0L3cfgS182
  = _M0MP410RabitLogic2s73src9transport9TcpConfig11new_2einner((moonbit_string_t)moonbit_string_literal_15.data, 102, 5000, 5000, 5000, 0, 1, 1);
  #line 10 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0L18_2astring__builderS183
  = _M0MPB13StringBuilder21StringBuilder_2einner(9);
  #line 10 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L18_2astring__builderS183, (moonbit_string_t)moonbit_string_literal_16.data);
  _M0L4hostS209 = _M0L3cfgS182->$0;
  moonbit_incref(_M0L4hostS209);
  #line 10 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0MPB13StringBuilder13write__objectGsE(_M0L18_2astring__builderS183, _M0L4hostS209);
  moonbit_decref(_M0L4hostS209);
  #line 10 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L18_2astring__builderS183, (moonbit_string_t)moonbit_string_literal_17.data);
  _M0L4portS210 = _M0L3cfgS182->$1;
  #line 10 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0MPB13StringBuilder13write__objectGiE(_M0L18_2astring__builderS183, _M0L4portS210);
  #line 10 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0L6_2atmpS208
  = _M0MPB13StringBuilder10to__string(_M0L18_2astring__builderS183);
  moonbit_decref(_M0L18_2astring__builderS183);
  #line 10 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE(_M0L6_2atmpS208);
  moonbit_decref(_M0L6_2atmpS208);
  #line 11 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0L2clS184
  = _M0MP410RabitLogic2s73src6client8S7Client17new__with__config(_M0L3cfgS182);
  moonbit_decref(_M0L3cfgS182);
  #line 12 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0L18_2astring__builderS185
  = _M0MPB13StringBuilder21StringBuilder_2einner(25);
  #line 12 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0IPB13StringBuilderPB6Logger13write__string(_M0L18_2astring__builderS185, (moonbit_string_t)moonbit_string_literal_18.data);
  #line 12 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0L6_2atmpS212
  = _M0MP410RabitLogic2s73src6client8S7Client13is__connected(_M0L2clS184);
  moonbit_decref(_M0L2clS184);
  #line 12 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0MPB13StringBuilder13write__objectGbE(_M0L18_2astring__builderS185, _M0L6_2atmpS212);
  #line 12 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0L6_2atmpS211
  = _M0MPB13StringBuilder10to__string(_M0L18_2astring__builderS185);
  moonbit_decref(_M0L18_2astring__builderS185);
  #line 12 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE(_M0L6_2atmpS211);
  moonbit_decref(_M0L6_2atmpS211);
  #line 15 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_7.data);
  #line 16 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_19.data);
  #line 17 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_20.data);
  #line 18 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_21.data);
  #line 19 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_22.data);
  #line 20 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_23.data);
  #line 21 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_24.data);
  #line 22 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_25.data);
  #line 23 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_26.data);
  #line 24 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_27.data);
  #line 25 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_28.data);
  #line 26 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_7.data);
  #line 27 "/home/rabitlogic/workspace/moonbit/s7/examples/main.mbt"
  _M0FPB7printlnGsE((moonbit_string_t)moonbit_string_literal_29.data);
  return 0;
}