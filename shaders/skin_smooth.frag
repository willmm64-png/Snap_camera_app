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
const int   RADIUS = 3;
const float KERNEL_UNIT = 0.0016;   // one kernel step = 0.16% of image height
const float SPATIAL_SIGMA = 2.0;
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
const float RING_START = 16.0;
const float RING_STEP = 12.0;

// Smoothing is switched off where local brightness varies more than this
// (hair, eyebrows, lashes, beard).
const float TEXTURE_LOW = 0.045;
const float TEXTURE_HIGH = 0.090;
// Blemish healing is also switched off in strongly textured areas (hair),
// but is more tolerant because a pimple edge also changes brightness.
const float HEAL_TEXTURE_LOW = 0.030;
const float HEAL_TEXTURE_HIGH = 0.060;

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

// 1.0 if the point is inside the image, 0.0 outside. Out-of-image samples must
// not count as "not skin", or skin near the screen edge would be left unprocessed.
float insideUv(vec2 p) {
    return step(0.0, p.x) * step(p.x, 1.0) * step(0.0, p.y) * step(p.y, 1.0);
}

// 8 unit directions (every 45 degrees). Constant table: much cheaper than cos/sin per tap.
vec2 dir8(int i) {
    const float k = 0.70710678;
    if (i == 0) return vec2(1.0, 0.0);
    if (i == 1) return vec2(k, k);
    if (i == 2) return vec2(0.0, 1.0);
    if (i == 3) return vec2(-k, k);
    if (i == 4) return vec2(-1.0, 0.0);
    if (i == 5) return vec2(-k, -k);
    if (i == 6) return vec2(0.0, -1.0);
    return vec2(k, -k);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uResolution;

    vec4 centerSample = texture(uTexture, uv);
    vec3 centerRaw = centerSample.rgb;
    float mask = skinMask(centerRaw);
    float intensity = clamp(uIntensity, 0.0, 1.0);
    float tanAmount = clamp(uTan, 0.0, 1.0);

    // Kernel step in uv units, equal in pixels on both axes.
    float aspect = uResolution.y / uResolution.x;
    vec2 unit = vec2(KERNEL_UNIT * aspect, KERNEL_UNIT);

    vec3 color = centerRaw;

    if ((intensity > 0.001 || tanAmount > 0.001) && mask > 0.01) {
        // ---- 0. Skin interior check ----
        // Sample 2 rings around the pixel. If many samples are NOT skin
        // (hair, ear edge, head outline, background) this pixel is near an
        // edge of the skin area and is left alone. Brown hair and shadowed
        // ears have skin-like colour, so colour alone is not enough.
        vec3 ringSum = vec3(0.0);
        float ringW = 0.0;
        float ringValid = 0.0;
        for (int ring = 0; ring < 2; ++ring) {
            float ringRadius = RING_START + RING_STEP * float(ring);
            for (int i = 0; i < 8; ++i) {
                vec2 p = uv + dir8(i) * unit * ringRadius;
                float ins = insideUv(p);
                vec3 s = texture(uTexture, p).rgb;
                float m = skinMask(s) * ins;
                ringSum += s * m;
                ringW += m;
                ringValid += ins;
            }
        }
        // 1.0 = surrounded by skin (only samples inside the image are counted)
        float coverage = (ringValid > 3.0) ? ringW / ringValid : 1.0;
        float interiorSmooth = smoothstep(0.55, 0.85, coverage);
        float interiorTan = smoothstep(0.30, 0.70, coverage);
        float healMask = mask * interiorSmooth;

        // Local brightness variation. Hair, eyebrows, lashes and beards are
        // strongly textured; skin is smooth. Textured areas get no smoothing.
        float l0 = dot(centerRaw, vec3(0.299, 0.587, 0.114));
        float sumL = l0;
        float sumL2 = l0 * l0;
        for (int i = 0; i < 8; ++i) {
            float l = dot(texture(uTexture, uv + dir8(i) * unit * 3.0).rgb,
                          vec3(0.299, 0.587, 0.114));
            sumL += l;
            sumL2 += l * l;
        }
        float meanL = sumL / 9.0;
        float lumaStd = sqrt(max(sumL2 / 9.0 - meanL * meanL, 0.0));
        float textureOk = 1.0 - smoothstep(TEXTURE_LOW, TEXTURE_HIGH, lumaStd);

        vec3 healed = centerRaw;

        if (intensity > 0.001 && healMask > 0.01) {
            // ---- 1. Blemish removal ----
            vec3 roughSkin = ringSum / max(ringW, 0.0001);
            float roughCr = chroma(roughSkin).y;

            // Pass B: same rings, ignoring red outliers (rest of a big pimple).
            vec3 cleanSum = vec3(0.0);
            float cleanW = 0.0;
            for (int ring = 0; ring < 2; ++ring) {
                float ringRadius = RING_START + RING_STEP * float(ring);
                for (int i = 0; i < 8; ++i) {
                    vec2 p = uv + dir8(i) * unit * ringRadius;
                    vec3 s = texture(uTexture, p).rgb;
                    float crS = chroma(s).y;
                    float w = skinMask(s) * insideUv(p)
                            * (1.0 - smoothstep(0.015, 0.040, crS - roughCr));
                    cleanSum += s * w;
                    cleanW += w;
                }
            }

            vec3 localSkin = (cleanW > 1.5) ? cleanSum / cleanW : roughSkin;
            float centerCr = chroma(centerRaw).y;
            float redness = centerCr - chroma(localSkin).y;
            // A pimple is a blob: neighbours must be red too. Isolated red
            // pixels (hair speckle, noise) are ignored.
            float agree = 0.0;
            for (int i = 0; i < 4; ++i) {
                vec3 n = texture(uTexture, uv + dir8(i * 2) * unit * 3.0).rgb;
                agree += smoothstep(SPOT_LOW, SPOT_HIGH, chroma(n).y - chroma(localSkin).y);
            }
            agree *= 0.25;
            // Pimples are about as bright as the skin around them. A big
            // brightness gap means hair/ear/shadow, so do not heal it.
            float lumaGap = abs(dot(centerRaw, vec3(0.299, 0.587, 0.114))
                              - dot(localSkin, vec3(0.299, 0.587, 0.114)));
            float spot = smoothstep(SPOT_LOW, SPOT_HIGH, redness)
                       * (1.0 - smoothstep(SPOT_MAX_LOW, SPOT_MAX_HIGH, redness))
                       * (1.0 - smoothstep(LIP_CR_LOW, LIP_CR_HIGH, centerCr))
                       * smoothstep(0.35, 0.75, agree)
                       * (1.0 - smoothstep(0.12, 0.22, lumaGap))
                       * (1.0 - smoothstep(HEAL_TEXTURE_LOW, HEAL_TEXTURE_HIGH, lumaStd));
            float healAmount = clamp(intensity * 1.6, 0.0, 1.0);
            float keep = spot * healAmount;      // 1 = this pixel is fully healed
            // Keep 20% of the pixel's own brightness so healed spots are not flat.
            float lumaC0 = dot(centerRaw, vec3(0.299, 0.587, 0.114));
            float lumaL0 = dot(localSkin, vec3(0.299, 0.587, 0.114));
            vec3 healTarget = clamp(localSkin + vec3((lumaC0 - lumaL0) * 0.2), 0.0, 1.0);
            healed = mix(centerRaw, healTarget, keep);

            // ---- 2. Edge-preserving smoothing (bilateral) ----
            float stepScale = (1.0 + intensity * 1.2) * 1.33;   // RADIUS 3 needs wider steps
            float twoSpatialSigma2 = 2.0 * SPATIAL_SIGMA * SPATIAL_SIGMA;
            // Range sigma scales with brightness: dark areas have small
            // absolute differences, so a fixed sigma smears dark detail.
            float lumaC = dot(healed, vec3(0.299, 0.587, 0.114));
            float dynRange = RANGE_SIGMA * (0.8 + 0.6 * intensity)
                           * clamp(0.35 + 1.3 * lumaC, 0.5, 1.3);
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

            // Healed pixels skip smoothing: the bilateral kernel only sees the
            // original red pixels and would blend the pimple straight back in.
            float smoothAmt = intensity * (1.0 - keep) * textureOk;
            color = mix(centerRaw, mix(healed, smoothed, smoothAmt), healMask);
        }

        // ---- 3. Tan (skin only) ----
        if (tanAmount > 0.001) {
            vec3 target = color * TAN_TINT;
            float l = dot(target, vec3(0.2126, 0.7152, 0.0722));
            target = mix(vec3(l), target, 1.1);   // slight saturation boost
            // Textured areas (hair, brows) get only 30% of the tan.
            float tanTex = mix(0.3, 1.0, textureOk);
            color = mix(color, target, tanAmount * mask * interiorTan * tanTex);
        }
    }

    fragColor = vec4(clamp(color, 0.0, 1.0), centerSample.a);
}
