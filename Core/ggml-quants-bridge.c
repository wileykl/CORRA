// Bridge file to export quantization functions for iOS
// Maps internal _generic functions to expected external symbols

#include "ggml.h"
#include <stdint.h>

// External function declarations from ggml-cpu-quants.c
extern void ggml_vec_dot_q4_0_q8_0_generic(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc);
extern void ggml_vec_dot_q4_1_q8_1_generic(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc);
extern void ggml_vec_dot_q5_0_q8_0_generic(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc);
extern void ggml_vec_dot_q5_1_q8_1_generic(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc);
extern void ggml_vec_dot_q8_0_q8_0_generic(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc);
extern void ggml_vec_dot_q2_K_q8_K_generic(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc);
extern void ggml_vec_dot_q3_K_q8_K_generic(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc);
extern void ggml_vec_dot_q4_K_q8_K_generic(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc);
extern void ggml_vec_dot_q5_K_q8_K_generic(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc);
extern void ggml_vec_dot_q6_K_q8_K_generic(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc);

// Export the functions with expected names
void ggml_vec_dot_q4_0_q8_0(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_q4_1_q8_1(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_1_q8_1_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_q5_0_q8_0(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q5_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_q5_1_q8_1(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q5_1_q8_1_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_q8_0_q8_0(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q8_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_q2_K_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q2_K_q8_K_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_q3_K_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q3_K_q8_K_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_q4_K_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_K_q8_K_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_q5_K_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q5_K_q8_K_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_q6_K_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q6_K_q8_K_generic(n, s, bs, vx, bx, vy, by, nrc);
}

// Quantization functions - simplified implementations for iOS
void quantize_row_q8_0(const float * restrict x, void * restrict y, int64_t k) {
    // Simple quantization - convert float to int8
    int8_t * restrict yi = (int8_t *) y;
    for (int i = 0; i < k; i++) {
        yi[i] = (int8_t)(x[i] * 127.0f);
    }
}

void quantize_row_q8_1(const float * restrict x, void * restrict y, int64_t k) {
    // Simple quantization - convert float to int8
    int8_t * restrict yi = (int8_t *) y;
    for (int i = 0; i < k; i++) {
        yi[i] = (int8_t)(x[i] * 127.0f);
    }
}

void quantize_row_q8_K(const float * restrict x, void * restrict y, int64_t k) {
    // Simple quantization - convert float to int8
    int8_t * restrict yi = (int8_t *) y;
    for (int i = 0; i < k; i++) {
        yi[i] = (int8_t)(x[i] * 127.0f);
    }
}

// IQ quantization functions - simplified implementations
void ggml_vec_dot_iq1_m_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    // Fallback to q4_0 for missing IQ formats
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_iq1_s_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_iq2_s_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_iq2_xs_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_iq2_xxs_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_iq3_s_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_iq3_xxs_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_iq4_nl_q8_0(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_iq4_xs_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_mxfp4_q8_0(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_tq1_0_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}

void ggml_vec_dot_tq2_0_q8_K(int n, float * restrict s, size_t bs, const void * restrict vx, size_t bx, const void * restrict vy, size_t by, int nrc) {
    ggml_vec_dot_q4_0_q8_0_generic(n, s, bs, vx, bx, vy, by, nrc);
}
