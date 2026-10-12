#version 460 core
#include <flutter/runtime_effect.glsl>

// Uniforms ordered for Flutter's FragmentShader:
// Floats/vectors first, followed by samplers.
uniform vec2 uResolution;      // Output viewport resolution (width, height) in pixels
uniform float uIntensity;      // Smoothing intensity, typically in range [0.0, 1.0]
uniform sampler2D uTexture;    // Camera feed or image texture

out vec4 fragColor;

// Spatial and photometric constants for bilateral filtering
const int RADIUS = 4;
const float SPATIAL_SIGMA = 3.5;
// RANGE_SIGMA defines color distance tolerance:
// Pixels within this color distance are blurred (skin tones);
// pixels with larger distance (edges: eyes, hair, eyebrows) are preserved.
const float RANGE_SIGMA = 0.14;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 uv = fragCoord / uResolution;

    vec4 centerColor = texture(uTexture, uv);

    // Bypass filter if intensity is essentially zero
    if (uIntensity <= 0.001) {
        fragColor = centerColor;
        return;
    }

    vec2 texelSize = 1.0 / uResolution;
    // Step size scales dynamically with blur intensity
    float stepScale = 1.0 + clamp(uIntensity, 0.0, 1.0) * 1.2;

    float twoSpatialSigma2 = 2.0 * SPATIAL_SIGMA * SPATIAL_SIGMA;
    // Range sigma widens slightly with higher intensity for stronger smoothing
    float dynamicRangeSigma = RANGE_SIGMA * (0.8 + 0.6 * clamp(uIntensity, 0.0, 1.0));
    float twoRangeSigma2 = 2.0 * dynamicRangeSigma * dynamicRangeSigma;

    vec3 sumColor = vec3(0.0);
    float sumWeight = 0.0;

    // Sample neighboring pixels within a circular kernel of radius RADIUS
    for (int x = -RADIUS; x <= RADIUS; ++x) {
        for (int y = -RADIUS; y <= RADIUS; ++y) {
            float dSpatial2 = float(x * x + y * y);
            // Prune corners to maintain an isotropic circular filter kernel
            if (dSpatial2 > float(RADIUS * RADIUS) + 0.5) {
                continue;
            }

            vec2 offset = vec2(float(x), float(y)) * texelSize * stepScale;
            vec4 sampleColor = texture(uTexture, uv + offset);

            // Compute Euclidean color distance in RGB space
            vec3 colorDiff = sampleColor.rgb - centerColor.rgb;
            float dColor2 = dot(colorDiff, colorDiff);

            // Bilateral weight: product of spatial Gaussian and color distance Gaussian
            float spatialWeight = exp(-dSpatial2 / twoSpatialSigma2);
            float rangeWeight = exp(-dColor2 / twoRangeSigma2);
            float weight = spatialWeight * rangeWeight;

            sumColor += sampleColor.rgb * weight;
            sumWeight += weight;
        }
    }

    // Normalized bilateral filtered color
    vec3 blurredColor = sumColor / max(sumWeight, 0.0001);

    // Smoothly blend filtered result with original based on intensity
    vec3 finalColor = mix(centerColor.rgb, blurredColor, clamp(uIntensity, 0.0, 1.0));

    fragColor = vec4(finalColor, centerColor.a);
}
