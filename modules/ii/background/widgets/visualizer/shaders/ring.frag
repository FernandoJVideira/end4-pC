#version 440
#extension GL_GOOGLE_include_directive : enable
#include "common.glsl"

// Radial bars around the cover art of the current track, turning slowly and pulsing on beats

layout(binding = 1) uniform sampler2D cover;

const float TAU = 6.28318530718;
const float BARS = 90.0;

void main() {
    loadSpectrum();
    vec2 p = (qt_TexCoord0 - 0.5) * 2.0; // -1..1, y down
    float r = length(p);
    float px = 2.0 / max(resolution.x, 1.0); // one pixel in p units

    // Angle as a fraction of a turn, 0 at the top
    float turn = fract(atan(p.x, -p.y) / TAU + 1.0 + time * 0.01);
    float center = (floor(turn * BARS) + 0.5) / BARS;
    // Mirrored halves: bass at the bottom, treble at the top
    float a = spectrum(abs(center - 0.5) * 2.0);

    float innerR = 0.50 * (1.0 + 0.06 * bass);
    float maxLen = 0.42;
    float len = 0.015 + a * maxLen;
    float across = (turn - center) * TAU * r; // arc distance to the bar axis
    float along = r - innerR;
    float halfW = TAU * innerR / BARS * 0.28;
    float dist = length(vec2(across, along - clamp(along, 0.0, len))) - halfW;
    float bar = 1.0 - smoothstep(-px, px, dist);
    float glow = exp(-max(dist, 0.0) / (0.015 + 0.05 * a)) * (0.25 + 0.75 * a) * 0.55;
    vec3 barColor = mix(color1.rgb, color2.rgb, clamp(along / maxLen, 0.0, 1.0));

    // Cover disc, with a gradient when there is no cover
    float coverR = innerR - 0.07;
    float disc = 1.0 - smoothstep(coverR - px, coverR + px, r);
    vec3 fallback = mix(color3.rgb, color1.rgb, 0.35 + 0.35 * p.y);
    vec3 coverColor = mix(fallback, texture(cover, p / (coverR * 2.0) + 0.5).rgb, hasCover);
    float rimR = coverR + 0.03;
    float rim = 1.0 - smoothstep(0.0, px * 1.5, abs(r - rimR) - px * 0.5);

    // Premultiplied composition: disc, rim, bars, then additive glows
    vec4 col = vec4(coverColor, 1.0) * disc;
    col += vec4(color1.rgb, 1.0) * rim * 0.55 * (1.0 - col.a);
    col = vec4(barColor, 1.0) * bar + col * (1.0 - bar);
    col.rgb += barColor * glow * (1.0 - bar);
    col.rgb += color2.rgb * exp(-abs(r - rimR) / 0.04) * 0.35 * bass;
    fragColor = col * fade * qt_Opacity;
}
