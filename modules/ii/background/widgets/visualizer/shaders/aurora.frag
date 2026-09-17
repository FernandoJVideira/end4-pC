#version 440
#extension GL_GOOGLE_include_directive : enable
#include "common.glsl"

// Aurora curtains drifting along the bottom of the screen. Each layer is a soft ribbon
// following the spectrum, with rays rising above it and shifting from color1 to color2.

float smoothSpectrum(float x) {
    return (spectrum(x - 0.08) + 2.0 * spectrum(x - 0.04) + 3.0 * spectrum(x)
        + 2.0 * spectrum(x + 0.04) + spectrum(x + 0.08)) / 9.0;
}

// Cheap 1D value noise
float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

float noise(float x) {
    float i = floor(x);
    float f = fract(x);
    return mix(hash(i), hash(i + 1.0), f * f * (3.0 - 2.0 * f));
}

// Theme colors are pastel, push them further from grey so the light keeps a hue
vec3 saturate(vec3 c, float amount) {
    float grey = dot(c, vec3(0.299, 0.587, 0.114));
    return clamp(mix(vec3(grey), c, amount), 0.0, 1.0);
}

void main() {
    loadSpectrum();
    vec2 uv = qt_TexCoord0;
    float y = 1.0 - uv.y; // 0 at the bottom edge
    float aspect = resolution.x / max(resolution.y, 1.0);
    vec3 light = vec3(0.0);
    float coverage = 0.0;

    for (int layer = 0; layer < 3; layer++) {
        float l = float(layer);
        float x = uv.x;
        float a = smoothSpectrum(mirrored(x) * 0.9 + 0.04 * l);

        float swell = sin(x * aspect * (0.9 + 0.5 * l) + time * (0.25 + 0.1 * l) + l * 2.1);
        float h = 0.10 + 0.08 * l + a * (0.42 - 0.08 * l) + 0.04 * swell;
        h *= 1.0 + 0.10 * bass;
        float d = y - h;

        // Rays: stretched noise across x, slowly sliding
        float rays = noise(x * resolution.x / (18.0 + 6.0 * l) + time * (0.4 + 0.15 * l) + l * 17.0);
        rays = 0.35 + 0.65 * rays * rays;
        float height = 0.18 + 0.45 * a;
        float curtain = exp(-max(d, 0.0) / height) * rays * smoothstep(-0.03, 0.05, d);
        float ribbon = exp(-(d * d) / 0.0012) * 0.8;
        float below = d < 0.0 ? exp(d / 0.05) * 0.35 : 0.0;
        float energy = (curtain * (0.35 + 0.9 * a) + ribbon * (0.3 + a) + below * (0.2 + 0.5 * a))
            * (1.0 - 0.25 * l);

        vec3 c = mix(color1.rgb, color2.rgb, clamp(d / height, 0.0, 1.0));
        c = mix(c, color3.rgb, 0.2 * l);
        c = saturate(c, 1.9);
        light += c * energy;
        coverage += energy * 0.05;
    }

    // Compress the light so bright areas keep their color, fade toward the top of the item.
    // Light is added over the wallpaper (rgb above alpha), coverage darkens it slightly.
    float top = smoothstep(1.0, 0.6, y);
    float k = top * fade;
    light = (vec3(1.0) - exp(-light * (0.9 + 0.4 * bass)));
    fragColor = vec4(light * k, clamp(coverage * k, 0.0, 0.35)) * qt_Opacity;
}
