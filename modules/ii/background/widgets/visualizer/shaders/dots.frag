#version 440
#extension GL_GOOGLE_include_directive : enable
#include "common.glsl"

// Dot matrix: columns of dots light up with the level, a falling dot marks the peak

const float PITCH = 14.0; // pixels between dot centers

void main() {
    loadSpectrum();
    vec2 pos = qt_TexCoord0 * resolution; // pixels, y down
    float cols = floor(resolution.x / PITCH);
    float rows = floor(resolution.y / PITCH);
    vec2 origin = vec2((resolution.x - cols * PITCH) * 0.5, resolution.y - rows * PITCH);
    vec2 g = (pos - origin) / PITCH;
    if (g.x < 0.0 || g.y < 0.0 || g.x >= cols || g.y >= rows) {
        fragColor = vec4(0.0);
        return;
    }
    vec2 cell = floor(g);
    vec2 f = g - cell - 0.5;

    float x = mirrored((cell.x + 0.5) / cols);
    float level = spectrum(x) * rows;
    float top = peak(x) * rows;
    float row = rows - 1.0 - cell.y; // 0 at the bottom

    float lit = step(row + 0.5, level);
    float isPeak = (1.0 - lit) * step(abs(row - floor(top)), 0.5) * step(1.0, top);
    float on = max(lit, isPeak);

    float d = length(f) - (0.30 + 0.06 * on);
    float aa = 1.2 / PITCH;
    float dotMask = 1.0 - smoothstep(-aa, aa, d);

    vec3 litColor = mix(color1.rgb, color2.rgb, row / max(rows - 1.0, 1.0));
    vec3 c = mix(color1.rgb, litColor, lit);
    c = mix(c, color3.rgb, isPeak);
    float alpha = mix(0.07, 1.0, on);

    vec4 col = vec4(c, 1.0) * alpha * dotMask;
    col.rgb += c * exp(-max(d, 0.0) * 6.0) * 0.18 * on * (1.0 + bass);
    fragColor = col * fade * qt_Opacity;
}
