#version 460 core
#include <flutter/runtime_effect.glsl>

// Float uniforms first (float indices 0..3), then samplers.
uniform vec2 uResolution;   // float idx 0,1: output size (width, height)
uniform float uIntensity;   // float idx 2: smoothing + blemish removal, 0..1
uniform float uTan;         // float idx 3: tan amount, 0..1
uniform sampler2D uTexture; // camera frame or photo

out vec4 fragColor;

// ---------------- Tuning constants ----------------
// Kernel size is a fraction of image HEIGHT so preview and full-res photo
// look the same (old code used 1 pixel steps, so photos were barely smoothed).
const int   RADIUS = 4;
const float KERNEL_UNIT = 0.0016;   // one kernel step = 0.16% of image height
const float SPATIAL_SIGMA = 2.6;
const float RANGE_SIGMA = 0.09;     // lower = more precise edges (eyes/hair/lips kept)
const float DETAIL_KEEP = 0.20;     // fraction of fine skin texture kept (pores)

// Blemish (red spot) removal: how much redder than surrounding skin.
const float SPOT_LOW = 0.015;       // below this = ignored (normal skin variation)
const float SPOT_HIGH = 0.040;      // above this = fully treated
const float SPOT_MAX_LOW = 0.09;    // very red areas fade out (protects lips)
const float SPOT_MAX_HIGH = 0.14;
const float LIP_CR_LOW = 0.685;     // absolute redness above this is treated as lips
const float LIP_CR_HIGH = 0.715;
// Rings used to sample the surrounding skin. Radius is in kernel steps.
// Must be bigger than the largest pimple you want removed.
const float RING_START = 14.0;
const float RING_STEP = 8.0;

// Tan: multiplies skin by a warm tint. Strength comes from uTan.
const vec3 TAN_TINT = vec3(0.95, 0.86, 0.74);

vec2 chroma(vec3 c) {
    float cb = 0.5 - 0.168736 * c.r - 0.331264 * c.g + 0.5 * c.b;
    float cr = 0.5 + 0.5 * c.r - 0.418688 * c.g - 0.081312 * c.b;
    return vec2(cb, cr);
}

// Soft 0..1 skin mask from YCbCr chroma range. Works for light and dark skin.
float skinMask(vec3 c) {
    vec2 cc = chroma(c);
    float luma = dot(c, vec3(0.299, 0.587, 0.114));
    float mCb = smoothstep(0.28, 0.32, cc.x) * (1.0 - smoothstep(0.48, 0.52, cc.x));
    float mCr = smoothstep(0.50, 0.54, cc.y) * (1.0 - smoothstep(0.69, 0.74, cc.y));
    float mL = smoothstep(0.10, 0.20, luma);
    return mCb * mCr * mL;
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uResolution;

    vec4 centerSample = texture(uTexture, uv);
    vec3 centerRaw = centerSample.rgb;
    float mask = skinMask(centerRaw);
    float intensity = clamp(uIntensity, 0.0, 1.0);

    // Kernel step in uv units, equal in pixels on both axes.
    float aspect = uResolution.y / uResolution.x;
    vec2 unit = vec2(KERNEL_UNIT * aspect, KERNEL_UNIT);

    vec3 color = centerRaw;

    if (intensity > 0.001 && mask > 0.01) {
        // ---- 1. Blemish removal ----
        // Pass A: rough average skin colour on 3 rings around the pixel.
        vec3 ringSum = vec3(0.0);
        float ringW = 0.0;
        for (int ring = 0; ring < 3; ++ring) {
            float ringRadius = RING_START + RING_STEP * float(ring);
            for (int i = 0; i < 8; ++i) {
                float a = float(i) * 0.785398;
                vec2 dir = vec2(cos(a), sin(a));
                vec3 s = texture(uTexture, uv + dir * unit * ringRadius).rgb;
                float m = skinMask(s);
                ringSum += s * m;
                ringW += m;
            }
        }

        vec3 healed = centerRaw;
        if (ringW > 6.0) {
            vec3 roughSkin = ringSum / ringW;
            float roughCr = chroma(roughSkin).y;

            // Pass B: repeat, but ignore samples that are red outliers
            // (e.g. the rest of a big pimple), so the target is clean skin.
            vec3 cleanSum = vec3(0.0);
            float cleanW = 0.0;
            for (int ring = 0; ring < 3; ++ring) {
                float ringRadius = RING_START + RING_STEP * float(ring);
                for (int i = 0; i < 8; ++i) {
                    float a = float(i) * 0.785398;
                    vec2 dir = vec2(cos(a), sin(a));
                    vec3 s = texture(uTexture, uv + dir * unit * ringRadius).rgb;
                    float crS = chroma(s).y;
                    float w = skinMask(s)
                            * (1.0 - smoothstep(0.015, 0.040, crS - roughCr));
                    cleanSum += s * w;
                    cleanW += w;
                }
            }

            vec3 localSkin = (cleanW > 2.0) ? cleanSum / cleanW : roughSkin;
            float centerCr = chroma(centerRaw).y;
            float redness = centerCr - chroma(localSkin).y;
            float spot = smoothstep(SPOT_LOW, SPOT_HIGH, redness)
                       * (1.0 - smoothstep(SPOT_MAX_LOW, SPOT_MAX_HIGH, redness))
                       * (1.0 - smoothstep(LIP_CR_LOW, LIP_CR_HIGH, centerCr));
            float healAmount = clamp(intensity * 1.6, 0.0, 1.0);
            healed = mix(centerRaw, localSkin, spot * healAmount);
        }

        // ---- 2. Edge-preserving smoothing (bilateral) ----
        float stepScale = 1.0 + intensity * 1.2;
        float twoSpatialSigma2 = 2.0 * SPATIAL_SIGMA * SPATIAL_SIGMA;
        float dynRange = RANGE_SIGMA * (0.8 + 0.6 * intensity);
        float twoRangeSigma2 = 2.0 * dynRange * dynRange;

        vec3 sumColor = vec3(0.0);
        float sumWeight = 0.0;

        for (int x = -RADIUS; x <= RADIUS; ++x) {
            for (int y = -RADIUS; y <= RADIUS; ++y) {
                float d2 = float(x * x + y * y);
                if (d2 > float(RADIUS * RADIUS) + 0.5) {
                    continue;
                }
                vec2 offset = vec2(float(x), float(y)) * unit * stepScale;
                vec3 s = texture(uTexture, uv + offset).rgb;
                vec3 diff = s - healed;
                float w = exp(-d2 / twoSpatialSigma2)
                        * exp(-dot(diff, diff) / twoRangeSigma2);
                sumColor += s * w;
                sumWeight += w;
            }
        }

        vec3 smoothed = sumColor / max(sumWeight, 0.0001);

        // Keep a little fine texture so skin does not look plastic.
        smoothed += (healed - smoothed) * DETAIL_KEEP;

        // Apply to skin only.
        color = mix(healed, smoothed, intensity * mask);
    }

    // ---- 3. Tan (skin only) ----
    float tanAmount = clamp(uTan, 0.0, 1.0);
    if (tanAmount > 0.001 && mask > 0.01) {
        vec3 target = color * TAN_TINT;
        float l = dot(target, vec3(0.2126, 0.7152, 0.0722));
        target = mix(vec3(l), target, 1.1);   // slight saturation boost
        color = mix(color, target, tanAmount * mask);
    }

    fragColor = vec4(clamp(color, 0.0, 1.0), centerSample.a);
}
