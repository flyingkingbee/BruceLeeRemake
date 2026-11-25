// Bruce Lee, a Windows port.
// Copyright (C) 2026 Jacob Marner
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//
// No copyright is claimed over the original game, which is copyright 1984 Datasoft, Inc.

#include "crt.h"

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <immintrin.h>

#include <atomic>
#include <cmath>
#include <cstring>
#include <thread>
#include <vector>

namespace {

// Living-room television, not a fisheye. Nudge these after looking at a room.
constexpr float kBend = 0.08f;
// 0.50 keeps most of each pixel and lends a little to the columns beside it.
constexpr float kHorizontalSigma = 0.50f;
constexpr float kBeamSigma = 0.30f;
// 0.15 leaves the curved corners at about 85% of the color just inside them.
constexpr float kVignette = 0.15f;
constexpr float kVignetteStart = 0.6f;
constexpr float kVignetteEnd = 1.8f;

constexpr int kBeamPhases = 256;
constexpr int kEncodeSteps = 4096;

struct LinearRgb {
    float r;
    float g;
    float b;
};

struct Tables {
    float toLinear[256];
    uint8_t toSrgb[kEncodeSteps];
    int32_t toSrgb32[kEncodeSteps];  // the same, wide for AVX2 gathers
    float blurWeight[5];
    int beamRow[kBeamPhases][3];
    float beamWeight[kBeamPhases][3];
};

float SrgbByteToLinear(int channel) {
    const float c = static_cast<float>(channel) / 255.f;
    if (c <= 0.04045f) {
        return c / 12.92f;
    }
    return std::pow((c + 0.055f) / 1.055f, 2.4f);
}

float LinearToSrgb(float linear) {
    if (linear <= 0.0031308f) {
        return linear * 12.92f;
    }
    return 1.055f * std::pow(linear, 1.f / 2.4f) - 0.055f;
}

float BeamAt(float distance) {
    const float twoSigmaSq = 2.f * kBeamSigma * kBeamSigma;
    return std::exp(-(distance * distance) / twoSigmaSq);
}

// The beam weight is the same for every pixel that sits at the same fraction
// of a source row. Dividing by the average across one row keeps a flat color
// at its old brightness. Dividing by the local weight would flatten the lines.
void BuildBeam(Tables& tables) {
    float raw[kBeamPhases][3];
    double sum = 0.0;
    for (int phase = 0; phase < kBeamPhases; ++phase) {
        const float frac = (static_cast<float>(phase) + 0.5f) / static_cast<float>(kBeamPhases);
        int rows[4];
        float weight[4];
        float dist[4];
        for (int i = 0; i < 4; ++i) {
            rows[i] = i - 1;
            const float delta = frac - static_cast<float>(rows[i]);
            dist[i] = delta < 0.f ? -delta : delta;
            weight[i] = BeamAt(delta);
        }
        int order[4] = {0, 1, 2, 3};
        for (int a = 0; a < 3; ++a) {
            int best = a;
            for (int b = a + 1; b < 4; ++b) {
                if (dist[order[b]] < dist[order[best]]) {
                    best = b;
                }
            }
            const int swap = order[a];
            order[a] = order[best];
            order[best] = swap;
        }
        float total = 0.f;
        for (int i = 0; i < 3; ++i) {
            tables.beamRow[phase][i] = rows[order[i]];
            raw[phase][i] = weight[order[i]];
            total += weight[order[i]];
        }
        sum += static_cast<double>(total);
    }
    const float norm = static_cast<float>(sum / kBeamPhases);
    for (int phase = 0; phase < kBeamPhases; ++phase) {
        for (int i = 0; i < 3; ++i) {
            tables.beamWeight[phase][i] = raw[phase][i] / norm;
        }
    }
}

const Tables& Lut() {
    static Tables tables{};
    static bool ready = false;
    if (ready) {
        return tables;
    }
    for (int channel = 0; channel < 256; ++channel) {
        tables.toLinear[channel] = SrgbByteToLinear(channel);
    }
    for (int step = 0; step < kEncodeSteps; ++step) {
        const float linear = static_cast<float>(step) / static_cast<float>(kEncodeSteps - 1);
        int byte = static_cast<int>(LinearToSrgb(linear) * 255.f + 0.5f);
        if (byte < 0) {
            byte = 0;
        }
        if (byte > 255) {
            byte = 255;
        }
        tables.toSrgb[step] = static_cast<uint8_t>(byte);
        tables.toSrgb32[step] = byte;
    }
    float weightSum = 0.f;
    const float blurDenom = 2.f * kHorizontalSigma * kHorizontalSigma;
    for (int tap = -2; tap <= 2; ++tap) {
        const float weight = std::exp(-(static_cast<float>(tap * tap)) / blurDenom);
        tables.blurWeight[tap + 2] = weight;
        weightSum += weight;
    }
    for (float& weight : tables.blurWeight) {
        weight /= weightSum;
    }
    BuildBeam(tables);
    ready = true;
    return tables;
}

// Full brightness through the middle of the glass. The falloff is on the
// pre-bend radius, so it follows the tube rather than the bowed picture.
float Vignette(float radiusSq) {
    float t = (radiusSq - kVignetteStart) / (kVignetteEnd - kVignetteStart);
    if (t <= 0.f) {
        return 1.f;
    }
    if (t >= 1.f) {
        return 1.f - kVignette;
    }
    const float smooth = t * t * (3.f - 2.f * t);
    return 1.f - kVignette * smooth;
}

// The source in linear light, padded so the shading loop never clamps. Two
// rows of zeros above and below stand for the rows the beam skips past the
// picture, and one copy of the edge column on each side stands for the
// clamped column. Blur on stores the smeared row, blur off the plain pixel.
constexpr int kPadRows = 2;
constexpr int kPadCols = 1;

void BuildLinear(const Tables& tables, const uint32_t* src, int srcW, int srcH, bool blur,
                 std::vector<LinearRgb>& out) {
    const int stride = srcW + 2 * kPadCols;
    out.assign(static_cast<size_t>(stride) * static_cast<size_t>(srcH + 2 * kPadRows), LinearRgb{0.f, 0.f, 0.f});
    for (int y = 0; y < srcH; ++y) {
        const uint32_t* in = src + static_cast<size_t>(y) * static_cast<size_t>(srcW);
        LinearRgb* row = out.data() + static_cast<size_t>(y + kPadRows) * static_cast<size_t>(stride) + kPadCols;
        for (int x = 0; x < srcW; ++x) {
            if (!blur) {
                const uint32_t pixel = in[x];
                row[x] = LinearRgb{tables.toLinear[(pixel >> 16) & 255u], tables.toLinear[(pixel >> 8) & 255u],
                                   tables.toLinear[pixel & 255u]};
                continue;
            }
            float r = 0.f;
            float g = 0.f;
            float b = 0.f;
            for (int tap = 0; tap < 5; ++tap) {
                int xx = x + tap - 2;
                if (xx < 0) {
                    xx = 0;
                }
                if (xx >= srcW) {
                    xx = srcW - 1;
                }
                const uint32_t pixel = in[xx];
                const float weight = tables.blurWeight[tap];
                r += tables.toLinear[(pixel >> 16) & 255u] * weight;
                g += tables.toLinear[(pixel >> 8) & 255u] * weight;
                b += tables.toLinear[pixel & 255u] * weight;
            }
            row[x] = LinearRgb{r, g, b};
        }
        row[-1] = row[0];
        row[srcW] = row[srcW - 1];
    }
}

// std::floor is a library call in this loop. The source coordinate stays near
// the picture, so a truncating cast is the same result.
inline int FloorToInt(float value) {
    const int truncated = static_cast<int>(value);
    return static_cast<float>(truncated) > value ? truncated - 1 : truncated;
}

inline int Encode(const Tables& tables, float linear) {
    if (linear <= 0.f) {
        return 0;
    }
    if (linear >= 1.f) {
        return 255;
    }
    int step = static_cast<int>(linear * static_cast<float>(kEncodeSteps - 1));
    if (step >= kEncodeSteps) {
        step = kEncodeSteps - 1;
    }
    return tables.toSrgb[step];
}

inline int ScaleChannel(int byte, float vignette) {
    const int scaled = static_cast<int>(static_cast<float>(byte) * vignette + 0.5f);
    if (scaled > 255) {
        return 255;
    }
    return scaled < 0 ? 0 : scaled;
}

// What every band of one picture shares.
struct ShadeJob {
    const Tables* tables;
    const LinearRgb* linear;  // the first real pixel of the padded source
    int stride;               // the padded row length
    uint32_t* dest;
    int srcW;
    int srcH;
    int destW;
    int destH;
    const float* px;          // each column's position, -1 to 1
    const float* pxSq;
};

// Blur on interpolates the smeared row. Blur off takes the nearest column.
template <bool Blur>
inline void SampleX(const LinearRgb* row, float sx, float& r, float& g, float& b) {
    if (Blur) {
        const int x0 = FloorToInt(sx);
        const float frac = sx - static_cast<float>(x0);
        const LinearRgb& left = row[x0];
        const LinearRgb& right = row[x0 + 1];
        r = left.r + (right.r - left.r) * frac;
        g = left.g + (right.g - left.g) * frac;
        b = left.b + (right.b - left.b) * frac;
        return;
    }
    const LinearRgb& pixel = row[FloorToInt(sx + 0.5f)];
    r = pixel.r;
    g = pixel.g;
    b = pixel.b;
}

// One destination pixel. The AVX2 path below does the same operations in the
// same order on eight pixels at once, and this one finishes each row.
template <bool Curve, bool Scanlines, bool Blur, bool Vignetting>
inline uint32_t ShadePixel(const ShadeJob& job, float py, float py2, int x) {
    const Tables& tables = *job.tables;
    const float px = job.px[x];
    const float radiusSq = job.pxSq[x] + py2;
    float bx = px;
    float by = py;
    if (Curve) {
        const float bowed = (1.f + kBend * radiusSq) / (1.f + kBend);
        bx = px * bowed;
        by = py * bowed;
        if (bx < -1.f || bx > 1.f || by < -1.f || by > 1.f) {
            return 0xFF000000u;
        }
    }
    const float sx = (bx * 0.5f + 0.5f) * static_cast<float>(job.srcW) - 0.5f;
    const float sy = (by * 0.5f + 0.5f) * static_cast<float>(job.srcH) - 0.5f;
    const ptrdiff_t stride = job.stride;
    float r = 0.f;
    float g = 0.f;
    float b = 0.f;
    if (Scanlines) {
        const int base = FloorToInt(sy);
        float rowFrac = sy - static_cast<float>(base);
        if (rowFrac < 0.f) {
            rowFrac = 0.f;
        }
        int phase = static_cast<int>(rowFrac * static_cast<float>(kBeamPhases));
        if (phase >= kBeamPhases) {
            phase = kBeamPhases - 1;
        }
        // A row past the picture is zero padding. Adding its nothing leaves
        // the sum as it was when such rows were skipped.
        for (int i = 0; i < 3; ++i) {
            const ptrdiff_t row = base + tables.beamRow[phase][i];
            float rr;
            float gg;
            float bb;
            SampleX<Blur>(job.linear + row * stride, sx, rr, gg, bb);
            const float weight = tables.beamWeight[phase][i];
            r += rr * weight;
            g += gg * weight;
            b += bb * weight;
        }
    } else {
        int row = FloorToInt(sy + 0.5f);
        if (row >= job.srcH) {
            row = job.srcH - 1;
        }
        if (row < 0) {
            row = 0;
        }
        SampleX<Blur>(job.linear + row * stride, sx, r, g, b);
    }
    const float vignette = Vignetting ? Vignette(radiusSq) : 1.f;
    const int ir = ScaleChannel(Encode(tables, r), vignette);
    const int ig = ScaleChannel(Encode(tables, g), vignette);
    const int ib = ScaleChannel(Encode(tables, b), vignette);
    return 0xFF000000u | (static_cast<uint32_t>(ir) << 16) | (static_cast<uint32_t>(ig) << 8) |
           static_cast<uint32_t>(ib);
}

// The scalar floor, eight at a time: truncate, then step down where that
// went up.
inline __m256i FloorToInt8(__m256 value) {
    const __m256i truncated = _mm256_cvttps_epi32(value);
    const __m256 back = _mm256_cvtepi32_ps(truncated);
    const __m256i up = _mm256_castps_si256(_mm256_cmp_ps(back, value, _CMP_GT_OQ));
    return _mm256_add_epi32(truncated, up);  // up is -1 where true
}

inline __m256i Encode8(const Tables& tables, __m256 linear) {
    const __m256 zero = _mm256_setzero_ps();
    const __m256 one = _mm256_set1_ps(1.f);
    __m256i step = _mm256_cvttps_epi32(_mm256_mul_ps(linear, _mm256_set1_ps(static_cast<float>(kEncodeSteps - 1))));
    step = _mm256_min_epi32(_mm256_max_epi32(step, _mm256_setzero_si256()), _mm256_set1_epi32(kEncodeSteps - 1));
    __m256i byte = _mm256_i32gather_epi32(tables.toSrgb32, step, 4);
    const __m256i low = _mm256_castps_si256(_mm256_cmp_ps(linear, zero, _CMP_LE_OQ));
    const __m256i high = _mm256_castps_si256(_mm256_cmp_ps(linear, one, _CMP_GE_OQ));
    byte = _mm256_andnot_si256(low, byte);
    byte = _mm256_blendv_epi8(byte, _mm256_set1_epi32(255), high);
    return byte;
}

inline __m256i Scale8(__m256i byte, __m256 vignette) {
    const __m256 scaled = _mm256_add_ps(_mm256_mul_ps(_mm256_cvtepi32_ps(byte), vignette), _mm256_set1_ps(0.5f));
    const __m256i value = _mm256_cvttps_epi32(scaled);
    return _mm256_min_epi32(_mm256_max_epi32(value, _mm256_setzero_si256()), _mm256_set1_epi32(255));
}

// Linear light at a float index into the padded source (three floats a pixel).
inline void Gather3(const float* base, __m256i index, __m256& r, __m256& g, __m256& b) {
    r = _mm256_i32gather_ps(base, index, 4);
    g = _mm256_i32gather_ps(base + 1, index, 4);
    b = _mm256_i32gather_ps(base + 2, index, 4);
}

// The source row at row offset rowIndex (in pixels), sampled at sx.
template <bool Blur>
inline void SampleX8(const float* linear, __m256i rowIndex, __m256 sx, __m256& r, __m256& g, __m256& b) {
    const __m256i three = _mm256_set1_epi32(3);
    if (Blur) {
        const __m256i x0 = FloorToInt8(sx);
        const __m256 frac = _mm256_sub_ps(sx, _mm256_cvtepi32_ps(x0));
        const __m256i index = _mm256_mullo_epi32(_mm256_add_epi32(rowIndex, x0), three);
        __m256 lr, lg, lb, rr, rg, rb;
        Gather3(linear, index, lr, lg, lb);
        Gather3(linear + 3, index, rr, rg, rb);
        r = _mm256_add_ps(lr, _mm256_mul_ps(_mm256_sub_ps(rr, lr), frac));
        g = _mm256_add_ps(lg, _mm256_mul_ps(_mm256_sub_ps(rg, lg), frac));
        b = _mm256_add_ps(lb, _mm256_mul_ps(_mm256_sub_ps(rb, lb), frac));
        return;
    }
    const __m256i col = FloorToInt8(_mm256_add_ps(sx, _mm256_set1_ps(0.5f)));
    Gather3(linear, _mm256_mullo_epi32(_mm256_add_epi32(rowIndex, col), three), r, g, b);
}

// Eight pixels of a row at a time, from x0 up to the last whole group of eight
// before x1. Returns where the scalar loop takes over.
template <bool Curve, bool Scanlines, bool Blur, bool Vignetting>
int ShadeRowAvx2(const ShadeJob& job, float pyScalar, float py2Scalar, uint32_t* rowOut, int x0, int x1) {
    const Tables& tables = *job.tables;
    const float* linear = &job.linear->r;
    const __m256 py = _mm256_set1_ps(pyScalar);
    const __m256 py2 = _mm256_set1_ps(py2Scalar);
    const __m256 half = _mm256_set1_ps(0.5f);
    const __m256 one = _mm256_set1_ps(1.f);
    const __m256 minusOne = _mm256_set1_ps(-1.f);
    const __m256 zero = _mm256_setzero_ps();
    const __m256 sourceWidth = _mm256_set1_ps(static_cast<float>(job.srcW));
    const __m256 sourceHeight = _mm256_set1_ps(static_cast<float>(job.srcH));
    const __m256i stride = _mm256_set1_epi32(job.stride);
    int x = x0;
    for (; x + 8 <= x1; x += 8) {
        const __m256 px = _mm256_loadu_ps(job.px + x);
        const __m256 radiusSq = _mm256_add_ps(_mm256_loadu_ps(job.pxSq + x), py2);
        __m256 bx = px;
        __m256 by = py;
        __m256 outside = zero;
        if (Curve) {
            const __m256 bowed = _mm256_div_ps(_mm256_add_ps(one, _mm256_mul_ps(_mm256_set1_ps(kBend), radiusSq)),
                                               _mm256_set1_ps(1.f + kBend));
            bx = _mm256_mul_ps(px, bowed);
            by = _mm256_mul_ps(py, bowed);
            outside = _mm256_or_ps(_mm256_or_ps(_mm256_cmp_ps(bx, minusOne, _CMP_LT_OQ), _mm256_cmp_ps(bx, one, _CMP_GT_OQ)),
                                   _mm256_or_ps(_mm256_cmp_ps(by, minusOne, _CMP_LT_OQ), _mm256_cmp_ps(by, one, _CMP_GT_OQ)));
            if (_mm256_movemask_ps(outside) == 0xFF) {
                _mm256_storeu_si256(reinterpret_cast<__m256i*>(rowOut + x), _mm256_set1_epi32(static_cast<int>(0xFF000000u)));
                continue;
            }
            // Lanes off the glass sample the middle, so no read leaves the
            // picture, and are painted black at the end.
            bx = _mm256_andnot_ps(outside, bx);
            by = _mm256_andnot_ps(outside, by);
        }
        const __m256 sx = _mm256_sub_ps(_mm256_mul_ps(_mm256_add_ps(_mm256_mul_ps(bx, half), half), sourceWidth), half);
        const __m256 sy = _mm256_sub_ps(_mm256_mul_ps(_mm256_add_ps(_mm256_mul_ps(by, half), half), sourceHeight), half);
        __m256 r = zero;
        __m256 g = zero;
        __m256 b = zero;
        if (Scanlines) {
            const __m256i base = FloorToInt8(sy);
            const __m256 rowFrac = _mm256_max_ps(_mm256_sub_ps(sy, _mm256_cvtepi32_ps(base)), zero);
            __m256i phase = _mm256_cvttps_epi32(_mm256_mul_ps(rowFrac, _mm256_set1_ps(static_cast<float>(kBeamPhases))));
            phase = _mm256_min_epi32(phase, _mm256_set1_epi32(kBeamPhases - 1));
            const __m256i slot = _mm256_mullo_epi32(phase, _mm256_set1_epi32(3));
            for (int i = 0; i < 3; ++i) {
                const __m256i at = _mm256_add_epi32(slot, _mm256_set1_epi32(i));
                const __m256i row = _mm256_add_epi32(base, _mm256_i32gather_epi32(&tables.beamRow[0][0], at, 4));
                const __m256 weight = _mm256_i32gather_ps(&tables.beamWeight[0][0], at, 4);
                __m256 rr, gg, bb;
                SampleX8<Blur>(linear, _mm256_mullo_epi32(row, stride), sx, rr, gg, bb);
                r = _mm256_add_ps(r, _mm256_mul_ps(rr, weight));
                g = _mm256_add_ps(g, _mm256_mul_ps(gg, weight));
                b = _mm256_add_ps(b, _mm256_mul_ps(bb, weight));
            }
        } else {
            __m256i row = FloorToInt8(_mm256_add_ps(sy, half));
            row = _mm256_max_epi32(_mm256_min_epi32(row, _mm256_set1_epi32(job.srcH - 1)), _mm256_setzero_si256());
            SampleX8<Blur>(linear, _mm256_mullo_epi32(row, stride), sx, r, g, b);
        }
        __m256 vignette = one;
        if (Vignetting) {
            const __m256 t = _mm256_div_ps(_mm256_sub_ps(radiusSq, _mm256_set1_ps(kVignetteStart)),
                                           _mm256_set1_ps(kVignetteEnd - kVignetteStart));
            const __m256 smooth = _mm256_mul_ps(_mm256_mul_ps(t, t),
                                                _mm256_sub_ps(_mm256_set1_ps(3.f), _mm256_mul_ps(_mm256_set1_ps(2.f), t)));
            vignette = _mm256_sub_ps(one, _mm256_mul_ps(_mm256_set1_ps(kVignette), smooth));
            vignette = _mm256_blendv_ps(vignette, one, _mm256_cmp_ps(t, zero, _CMP_LE_OQ));
            vignette = _mm256_blendv_ps(vignette, _mm256_set1_ps(1.f - kVignette), _mm256_cmp_ps(t, one, _CMP_GE_OQ));
        }
        const __m256i ir = Scale8(Encode8(tables, r), vignette);
        const __m256i ig = Scale8(Encode8(tables, g), vignette);
        const __m256i ib = Scale8(Encode8(tables, b), vignette);
        __m256i pixel = _mm256_or_si256(_mm256_set1_epi32(static_cast<int>(0xFF000000u)),
                                        _mm256_or_si256(_mm256_slli_epi32(ir, 16),
                                                        _mm256_or_si256(_mm256_slli_epi32(ig, 8), ib)));
        if (Curve) {
            pixel = _mm256_blendv_epi8(pixel, _mm256_set1_epi32(static_cast<int>(0xFF000000u)), _mm256_castps_si256(outside));
        }
        _mm256_storeu_si256(reinterpret_cast<__m256i*>(rowOut + x), pixel);
    }
    return x;
}

bool HaveAvx2() {
    static const bool have = IsProcessorFeaturePresent(PF_AVX2_INSTRUCTIONS_AVAILABLE) != FALSE;
    return have;
}

// Destination rows y0 to y1, columns x0 to x1. Each part of the filter is a
// template switch, so the loop carries no test for a part that is off. Both
// paths give the same bytes as the plain per-pixel form, for every choice of
// parts, so a pixel comes out the same whichever piece of work shades it.
template <bool Curve, bool Scanlines, bool Blur, bool Vignetting>
void ShadeRows(const ShadeJob& job, int y0, int y1, int x0, int x1) {
    const float destHeight = static_cast<float>(job.destH);
    const bool wide = HaveAvx2();
    for (int y = y0; y < y1; ++y) {
        const float py = ((static_cast<float>(y) + 0.5f) / destHeight) * 2.f - 1.f;
        const float py2 = py * py;
        uint32_t* rowOut = job.dest + static_cast<size_t>(y) * static_cast<size_t>(job.destW);
        int x = wide ? ShadeRowAvx2<Curve, Scanlines, Blur, Vignetting>(job, py, py2, rowOut, x0, x1) : x0;
        for (; x < x1; ++x) {
            rowOut[x] = ShadePixel<Curve, Scanlines, Blur, Vignetting>(job, py, py2, x);
        }
    }
    if (wide) {
        _mm256_zeroupper();
    }
}

using ShadeFn = void (*)(const ShadeJob&, int, int, int, int);

template <int Mask>
constexpr ShadeFn ShadeFor() {
    return &ShadeRows<(Mask & 1) != 0, (Mask & 2) != 0, (Mask & 4) != 0, (Mask & 8) != 0>;
}

ShadeFn PickShade(CrtOptions options) {
    static constexpr ShadeFn table[16] = {
        ShadeFor<0>(),  ShadeFor<1>(),  ShadeFor<2>(),  ShadeFor<3>(),
        ShadeFor<4>(),  ShadeFor<5>(),  ShadeFor<6>(),  ShadeFor<7>(),
        ShadeFor<8>(),  ShadeFor<9>(),  ShadeFor<10>(), ShadeFor<11>(),
        ShadeFor<12>(), ShadeFor<13>(), ShadeFor<14>(), ShadeFor<15>(),
    };
    const int mask = (options.curve ? 1 : 0) | (options.scanlines ? 2 : 0) |
                     (options.blur ? 4 : 0) | (options.vignette ? 8 : 0);
    return table[mask];
}

// The picture is cut into blocks of this many rows and columns. The pool's
// threads and the calling thread each take the next piece of work until none
// is left, so a slow core holds up only the piece it has.
constexpr int kBandRows = 16;
constexpr int kBlockCols = 64;

struct Piece {
    int y0;
    int y1;
    int x0;
    int x1;
};

struct Dispatch {
    ShadeFn shade = nullptr;
    const ShadeJob* job = nullptr;
    const Piece* pieces = nullptr;
    int count = 0;
    std::atomic<int> next{0};
};

void RunPieces(Dispatch& work) {
    for (;;) {
        const int at = work.next.fetch_add(1, std::memory_order_relaxed);
        if (at >= work.count) {
            return;
        }
        const Piece& piece = work.pieces[at];
        work.shade(*work.job, piece.y0, piece.y1, piece.x0, piece.x1);
    }
}

VOID CALLBACK PieceWorker(PTP_CALLBACK_INSTANCE, PVOID context, PTP_WORK) {
    RunPieces(*static_cast<Dispatch*>(context));
}

// Everything one picture's shading needs, kept between calls so the column
// positions and the padded source buffer are not reallocated every frame.
struct Shader {
    std::vector<LinearRgb> linear;
    std::vector<float> px;
    std::vector<float> pxSq;
    ShadeJob job{};
};

void Prepare(Shader& shader, const uint32_t* src, int srcW, int srcH, uint32_t* dest, int destW, int destH,
             CrtOptions options) {
    const Tables& tables = Lut();
    BuildLinear(tables, src, srcW, srcH, options.blur, shader.linear);
    if (static_cast<int>(shader.px.size()) != destW) {
        shader.px.resize(static_cast<size_t>(destW));
        shader.pxSq.resize(static_cast<size_t>(destW));
        const float destWidth = static_cast<float>(destW);
        for (int x = 0; x < destW; ++x) {
            const float p = ((static_cast<float>(x) + 0.5f) / destWidth) * 2.f - 1.f;
            shader.px[static_cast<size_t>(x)] = p;
            shader.pxSq[static_cast<size_t>(x)] = p * p;
        }
    }
    ShadeJob& job = shader.job;
    job.tables = &tables;
    job.stride = srcW + 2 * kPadCols;
    job.linear = shader.linear.data() + static_cast<size_t>(kPadRows) * static_cast<size_t>(job.stride) + kPadCols;
    job.dest = dest;
    job.srcW = srcW;
    job.srcH = srcH;
    job.destW = destW;
    job.destH = destH;
    job.px = shader.px.data();
    job.pxSq = shader.pxSq.data();
}

// Paint comes out of the game's 59.85ms frame, so a large piece of work is
// shared with the Windows thread pool, which keeps its threads from one
// frame to the next. A small one stays on this thread.
void Run(const Shader& shader, CrtOptions options, const std::vector<Piece>& pieces) {
    if (pieces.empty()) {
        return;
    }
    Dispatch work;
    work.shade = PickShade(options);
    work.job = &shader.job;
    work.pieces = pieces.data();
    work.count = static_cast<int>(pieces.size());
    size_t area = 0;
    for (const Piece& piece : pieces) {
        area += static_cast<size_t>(piece.y1 - piece.y0) * static_cast<size_t>(piece.x1 - piece.x0);
    }
    const unsigned cores = std::thread::hardware_concurrency();
    unsigned helpers = cores > 1 ? cores - 1 : 0;
    if (helpers > static_cast<unsigned>(work.count - 1)) {
        helpers = static_cast<unsigned>(work.count - 1);
    }
    PTP_WORK pool = nullptr;
    if (helpers > 0 && area >= 640u * 400u / 4u) {
        pool = CreateThreadpoolWork(PieceWorker, &work, nullptr);
    }
    if (pool == nullptr) {
        RunPieces(work);
        return;
    }
    for (unsigned i = 0; i < helpers; ++i) {
        SubmitThreadpoolWork(pool);
    }
    RunPieces(work);
    WaitForThreadpoolWorkCallbacks(pool, FALSE);
    CloseThreadpoolWork(pool);
}

// Every band, the whole width.
void WholePicture(int destW, int destH, std::vector<Piece>& pieces) {
    pieces.clear();
    for (int y = 0; y < destH; y += kBandRows) {
        pieces.push_back(Piece{y, y + kBandRows < destH ? y + kBandRows : destH, 0, destW});
    }
}

// The source is compared in tiles of this many pixels a side.
constexpr int kTile = 8;

// How far from its own position a destination pixel reads the source: the
// blur's two columns each way and the next column it blends with, and the
// beam's row above and two below. One more each way covers the rounding.
constexpr int kReachLeft = 3;
constexpr int kReachRight = 4;
constexpr int kReachUp = 2;
constexpr int kReachDown = 3;

struct Incremental {
    Shader shader;
    std::vector<uint32_t> lastSrc;
    const uint32_t* dest = nullptr;
    int srcW = 0;
    int srcH = 0;
    int destW = 0;
    int destH = 0;
    int curve = -1;
    int mask = -1;
    bool valid = false;
    // For each block, the source tiles its pixels read: first and last tile
    // column, then first and last tile row. An empty box (first > last) is a
    // block wholly off the glass, which never changes.
    int blocksX = 0;
    int blocksY = 0;
    std::vector<int> box;
    std::vector<uint8_t> dirtyTile;
    std::vector<int> tileSum;
    std::vector<Piece> pieces;
    std::vector<CrtRect> rects;
};

Incremental& State() {
    static Incremental state;
    return state;
}

// Where a destination pixel lands in the source, as the shading loop works it
// out. False when the curve puts it off the glass.
bool SourceOf(const Shader& shader, bool curve, int x, int y, float& sx, float& sy) {
    const ShadeJob& job = shader.job;
    const float py = ((static_cast<float>(y) + 0.5f) / static_cast<float>(job.destH)) * 2.f - 1.f;
    const float px = job.px[x];
    float bx = px;
    float by = py;
    if (curve) {
        const float bowed = (1.f + kBend * (job.pxSq[x] + py * py)) / (1.f + kBend);
        bx = px * bowed;
        by = py * bowed;
        if (bx < -1.f || bx > 1.f || by < -1.f || by > 1.f) {
            return false;
        }
    }
    sx = (bx * 0.5f + 0.5f) * static_cast<float>(job.srcW) - 0.5f;
    sy = (by * 0.5f + 0.5f) * static_cast<float>(job.srcH) - 0.5f;
    return true;
}

// The source tiles each block reads. The curve maps a block to a connected
// patch of the source, so its edge pixels bound it, unless part of the block
// is off the glass, where every pixel is looked at.
void BuildBoxes(Incremental& state, bool curve) {
    const int destW = state.destW;
    const int destH = state.destH;
    state.blocksX = (destW + kBlockCols - 1) / kBlockCols;
    state.blocksY = (destH + kBandRows - 1) / kBandRows;
    state.box.assign(static_cast<size_t>(state.blocksX) * static_cast<size_t>(state.blocksY) * 4u, 0);
    const int tilesX = (state.srcW + kTile - 1) / kTile;
    const int tilesY = (state.srcH + kTile - 1) / kTile;
    for (int by = 0; by < state.blocksY; ++by) {
        for (int bx = 0; bx < state.blocksX; ++bx) {
            const int x0 = bx * kBlockCols;
            const int x1 = x0 + kBlockCols < destW ? x0 + kBlockCols : destW;
            const int y0 = by * kBandRows;
            const int y1 = y0 + kBandRows < destH ? y0 + kBandRows : destH;
            float minX = 1e9f;
            float maxX = -1e9f;
            float minY = 1e9f;
            float maxY = -1e9f;
            bool off = false;
            auto take = [&](int x, int y) {
                float sx;
                float sy;
                if (!SourceOf(state.shader, curve, x, y, sx, sy)) {
                    off = true;
                    return;
                }
                minX = sx < minX ? sx : minX;
                maxX = sx > maxX ? sx : maxX;
                minY = sy < minY ? sy : minY;
                maxY = sy > maxY ? sy : maxY;
            };
            for (int x = x0; x < x1; ++x) {
                take(x, y0);
                take(x, y1 - 1);
            }
            for (int y = y0; y < y1; ++y) {
                take(x0, y);
                take(x1 - 1, y);
            }
            if (off) {
                for (int y = y0; y < y1; ++y) {
                    for (int x = x0; x < x1; ++x) {
                        take(x, y);
                    }
                }
            }
            int* box = &state.box[(static_cast<size_t>(by) * static_cast<size_t>(state.blocksX) + static_cast<size_t>(bx)) * 4u];
            if (minX > maxX) {
                box[0] = 1;
                box[1] = 0;
                box[2] = 1;
                box[3] = 0;
                continue;
            }
            int left = FloorToInt(minX) - kReachLeft;
            int right = FloorToInt(maxX) + kReachRight;
            int top = FloorToInt(minY) - kReachUp;
            int bottom = FloorToInt(maxY) + kReachDown;
            left = left < 0 ? 0 : left;
            top = top < 0 ? 0 : top;
            right = right >= state.srcW ? state.srcW - 1 : right;
            bottom = bottom >= state.srcH ? state.srcH - 1 : bottom;
            box[0] = left / kTile;
            box[1] = right / kTile < tilesX ? right / kTile : tilesX - 1;
            box[2] = top / kTile;
            box[3] = bottom / kTile < tilesY ? bottom / kTile : tilesY - 1;
        }
    }
}

// The pieces whose blocks read a changed tile, one per run of such blocks in
// a band, and the rectangles to upload: each band's changed columns, joined
// with the bands below while they overlap.
void ChangedPieces(Incremental& state, const uint32_t* src) {
    const int srcW = state.srcW;
    const int srcH = state.srcH;
    const int tilesX = (srcW + kTile - 1) / kTile;
    const int tilesY = (srcH + kTile - 1) / kTile;
    state.dirtyTile.assign(static_cast<size_t>(tilesX) * static_cast<size_t>(tilesY), 0);
    bool any = false;
    for (int y = 0; y < srcH; ++y) {
        const uint32_t* now = src + static_cast<size_t>(y) * static_cast<size_t>(srcW);
        uint32_t* was = state.lastSrc.data() + static_cast<size_t>(y) * static_cast<size_t>(srcW);
        const int ty = y / kTile;
        for (int tx = 0; tx < tilesX; ++tx) {
            const int x0 = tx * kTile;
            const int count = x0 + kTile < srcW ? kTile : srcW - x0;
            if (std::memcmp(now + x0, was + x0, static_cast<size_t>(count) * sizeof(uint32_t)) != 0) {
                std::memcpy(was + x0, now + x0, static_cast<size_t>(count) * sizeof(uint32_t));
                state.dirtyTile[static_cast<size_t>(ty) * static_cast<size_t>(tilesX) + static_cast<size_t>(tx)] = 1;
                any = true;
            }
        }
    }
    state.pieces.clear();
    state.rects.clear();
    if (!any) {
        return;
    }
    // Sums over the tiles above and to the left, so a box is one lookup.
    const int sumW = tilesX + 1;
    state.tileSum.assign(static_cast<size_t>(sumW) * static_cast<size_t>(tilesY + 1), 0);
    for (int ty = 0; ty < tilesY; ++ty) {
        int row = 0;
        for (int tx = 0; tx < tilesX; ++tx) {
            row += state.dirtyTile[static_cast<size_t>(ty) * static_cast<size_t>(tilesX) + static_cast<size_t>(tx)];
            state.tileSum[static_cast<size_t>(ty + 1) * sumW + static_cast<size_t>(tx + 1)] =
                state.tileSum[static_cast<size_t>(ty) * sumW + static_cast<size_t>(tx + 1)] + row;
        }
    }
    auto changed = [&](const int* box) {
        if (box[0] > box[1] || box[2] > box[3]) {
            return false;
        }
        const int* sum = state.tileSum.data();
        const int total = sum[static_cast<size_t>(box[3] + 1) * sumW + static_cast<size_t>(box[1] + 1)] -
                          sum[static_cast<size_t>(box[2]) * sumW + static_cast<size_t>(box[1] + 1)] -
                          sum[static_cast<size_t>(box[3] + 1) * sumW + static_cast<size_t>(box[0])] +
                          sum[static_cast<size_t>(box[2]) * sumW + static_cast<size_t>(box[0])];
        return total > 0;
    };
    for (int by = 0; by < state.blocksY; ++by) {
        const int y0 = by * kBandRows;
        const int y1 = y0 + kBandRows < state.destH ? y0 + kBandRows : state.destH;
        int bandLeft = state.destW;
        int bandRight = 0;
        int runStart = -1;
        for (int bx = 0; bx <= state.blocksX; ++bx) {
            const bool hit = bx < state.blocksX &&
                changed(&state.box[(static_cast<size_t>(by) * static_cast<size_t>(state.blocksX) + static_cast<size_t>(bx)) * 4u]);
            if (hit && runStart < 0) {
                runStart = bx;
            }
            if (!hit && runStart >= 0) {
                const int x0 = runStart * kBlockCols;
                const int x1 = bx * kBlockCols < state.destW ? bx * kBlockCols : state.destW;
                state.pieces.push_back(Piece{y0, y1, x0, x1});
                bandLeft = x0 < bandLeft ? x0 : bandLeft;
                bandRight = x1 > bandRight ? x1 : bandRight;
                runStart = -1;
            }
        }
        if (bandLeft >= bandRight) {
            continue;
        }
        if (!state.rects.empty()) {
            CrtRect& last = state.rects.back();
            if (last.bottom == y0 && last.left < bandRight && bandLeft < last.right) {
                last.bottom = y1;
                last.left = bandLeft < last.left ? bandLeft : last.left;
                last.right = bandRight > last.right ? bandRight : last.right;
                continue;
            }
        }
        state.rects.push_back(CrtRect{bandLeft, y0, bandRight, y1});
    }
}

}  // namespace

void ApplyCrt(const uint32_t* src, int srcW, int srcH, uint32_t* dest, int destW, int destH,
              CrtOptions options) {
    if (src == nullptr || dest == nullptr || srcW < 1 || srcH < 1 || destW < 1 || destH < 1) {
        return;
    }
    static Shader shader;
    static std::vector<Piece> pieces;
    Prepare(shader, src, srcW, srcH, dest, destW, destH, options);
    WholePicture(destW, destH, pieces);
    Run(shader, options, pieces);
}

const std::vector<CrtRect>& ApplyCrtChanged(const uint32_t* src, int srcW, int srcH, uint32_t* dest, int destW,
                                            int destH, CrtOptions options) {
    Incremental& state = State();
    state.rects.clear();
    if (src == nullptr || dest == nullptr || srcW < 1 || srcH < 1 || destW < 1 || destH < 1) {
        state.valid = false;
        return state.rects;
    }
    const int mask = (options.curve ? 1 : 0) | (options.scanlines ? 2 : 0) | (options.blur ? 4 : 0) |
                     (options.vignette ? 8 : 0);
    const bool sameShape = state.valid && state.dest == dest && state.srcW == srcW && state.srcH == srcH &&
                           state.destW == destW && state.destH == destH;
    const bool sameBoxes = sameShape && state.curve == (options.curve ? 1 : 0);
    Prepare(state.shader, src, srcW, srcH, dest, destW, destH, options);
    if (!sameShape || state.mask != mask) {
        state.dest = dest;
        state.srcW = srcW;
        state.srcH = srcH;
        state.destW = destW;
        state.destH = destH;
        state.mask = mask;
        state.lastSrc.assign(src, src + static_cast<size_t>(srcW) * static_cast<size_t>(srcH));
        if (!sameBoxes) {
            state.curve = options.curve ? 1 : 0;
            BuildBoxes(state, options.curve);
        }
        state.valid = true;
        WholePicture(destW, destH, state.pieces);
        Run(state.shader, options, state.pieces);
        state.rects.push_back(CrtRect{0, 0, destW, destH});
        return state.rects;
    }
    ChangedPieces(state, src);
    Run(state.shader, options, state.pieces);
    return state.rects;
}

void ForgetCrtPicture() {
    State().valid = false;
}
