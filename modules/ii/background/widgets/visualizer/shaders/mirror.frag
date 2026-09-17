#version 440
#extension GL_GOOGLE_include_directive : enable
#include "common.glsl"

// Rounded bars standing on a baseline, reflected below it, with falling peak caps

const float PITCH = 10.0; // pixels per bar
const float BAR = 6.0;    // bar width in pixels

void main() {
    loadSpectrum();
    vec2 pos = qt_TexCoord0 * resolution;
    float count = floor(resolution.x / PITCH);
    float gx = (pos.x - (resolution.x - count * PITCH) * 0.5) / PITCH;
    if (gx < 0.0 || gx >= count) {
        fragColor = vec4(0.0);
        return;
    }
    float id = floor(gx);
    float x = mirrored((id + 0.5) / count);
    float baseline = resolution.y * 0.72;
    float maxH = baseline - 12.0; // room for the peak caps
    float h = max(BAR, spectrum(x) * maxH);
    float peakY = peak(x) * maxH;

    float lx = (gx - id - 0.5) * PITCH; // pixels from the bar axis
    float up = baseline - pos.y;        // pixels above the baseline
    float halfW = BAR * 0.5;

    // Flat foot on the baseline, rounded top
    float dBar = length(vec2(lx, up - clamp(up, 0.0, max(h - halfW, 0.0)))) - halfW;
    float bar = (1.0 - smoothstep(-0.7, 0.7, dBar)) * step(0.0, up);

    float down = -up;
    float dRef = length(vec2(lx, down - clamp(down, 0.0, max(h - halfW, 0.0)))) - halfW;
    float reflection = (1.0 - smoothstep(-0.7, 0.7, dRef)) * step(0.0, down)
        * exp(-down / (0.18 * maxH)) * 0.35;

    vec2 qd = abs(vec2(lx, up - (peakY + 5.0))) - vec2(halfW, 1.25);
    float dPeak = length(max(qd, 0.0)) + min(max(qd.x, qd.y), 0.0);
    float cap = (1.0 - smoothstep(-0.6, 0.6, dPeak)) * step(1.0, peakY);

    float t = clamp(up / maxH, 0.0, 1.0);
    vec3 barColor = mix(color2.rgb, color1.rgb, t);
    float glow = exp(-max(dBar, 0.0) / (3.0 + 6.0 * t)) * 0.3 * step(0.0, up) * (1.0 - bar);
    float line = (1.0 - smoothstep(0.0, 1.0, abs(up))) * 0.12;

    // Premultiplied composition
    vec4 col = vec4(barColor, 1.0) * bar;
    col += vec4(mix(color2.rgb, color1.rgb, 0.3), 1.0) * reflection * (1.0 - col.a);
    col = vec4(color3.rgb, 1.0) * cap + col * (1.0 - cap);
    col.rgb += barColor * glow * (1.0 + bass);
    col += vec4(color1.rgb, 1.0) * line * (1.0 - col.a);
    fragColor = col * fade * qt_Opacity;
}
