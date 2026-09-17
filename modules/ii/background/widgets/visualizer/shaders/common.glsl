// Shared by the visualizer fragment shaders, see build.sh.
// Every shader declares the same uniform block so one ShaderEffect can drive any style.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;       // seconds, only advances while audio plays
    float bass;       // 0..1 beat pulse
    float fade;       // 0..1, follows playback
    vec2 resolution;  // item size in pixels
    float bandCount;  // valid bands, at most 52
    float hasCover;   // ring: 1 when the cover texture is meaningful
    vec4 color1;
    vec4 color2;
    vec4 color3;
    // Smoothed band levels (0..1), four per vector
    vec4 b0; vec4 b1; vec4 b2; vec4 b3; vec4 b4; vec4 b5; vec4 b6;
    vec4 b7; vec4 b8; vec4 b9; vec4 b10; vec4 b11; vec4 b12;
    // Falling peak levels, same layout
    vec4 p0; vec4 p1; vec4 p2; vec4 p3; vec4 p4; vec4 p5; vec4 p6;
    vec4 p7; vec4 p8; vec4 p9; vec4 p10; vec4 p11; vec4 p12;
};

vec4 bandBlocks[13];
vec4 peakBlocks[13];

void loadSpectrum() {
    bandBlocks = vec4[13](b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11, b12);
    peakBlocks = vec4[13](p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10, p11, p12);
}

int clampBand(int i) {
    return clamp(i, 0, max(int(bandCount) - 1, 0));
}

float bandAt(int i) {
    i = clampBand(i);
    int k = i / 4;
    return bandBlocks[k][i - k * 4];
}

float peakAt(int i) {
    i = clampBand(i);
    int k = i / 4;
    return peakBlocks[k][i - k * 4];
}

// Level at x in [0, 1], lowest to highest band, Catmull-Rom between bands
float spectrum(float x) {
    float f = clamp(x, 0.0, 1.0) * max(bandCount - 1.0, 0.0);
    int i = int(floor(f));
    float t = f - float(i);
    float v0 = bandAt(i - 1);
    float v1 = bandAt(i);
    float v2 = bandAt(i + 1);
    float v3 = bandAt(i + 2);
    float v = v1 + 0.5 * t * (v2 - v0 + t * (2.0 * v0 - 5.0 * v1 + 4.0 * v2 - v3
        + t * (3.0 * (v1 - v2) + v3 - v0)));
    return clamp(v, 0.0, 1.0);
}

float peak(float x) {
    float f = clamp(x, 0.0, 1.0) * max(bandCount - 1.0, 0.0);
    int i = int(floor(f));
    return mix(peakAt(i), peakAt(i + 1), f - float(i));
}

// Horizontal position folded around the center: bass in the middle, treble on the sides
float mirrored(float x) {
    return abs(x - 0.5) * 2.0;
}
