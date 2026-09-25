#version 440

// Liquid glass pour une forme quelconque (cadre de l'écran, barre, sidebar…).
// La forme est lue dans le canal alpha de la texture : on en déduit la normale
// et la distance au bord par échantillonnage en anneau, puis on éclaire le biseau.
// Le flou de l'arrière-plan est fourni par Hyprland.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texel;
    vec3 tint;
    float tintAlpha;
    float light;
    float shadowStrength;
    vec2 mouse;
    float hover;
};

layout(binding = 1) uniform sampler2D source;

const float PI2 = 6.28318530718;

float ring(vec2 uv, float radius, int n, out vec2 grad) {
    float sum = 0.0;
    grad = vec2(0.0);
    for (int i = 0; i < n; i++) {
        float ang = PI2 * (float(i) + 0.5) / float(n);
        vec2 dir = vec2(cos(ang), sin(ang));
        float s = texture(source, uv + dir * radius * texel).a;
        sum += s;
        grad -= dir * s;
    }
    return sum / float(n);
}

void main() {
    vec2 uv = qt_TexCoord0;
    float a0 = texture(source, uv).a;

    // Test rapide sur 4 points : la grande majorité des pixels (loin de la forme,
    // ou au cœur d'un panneau) évitent l'échantillonnage complet.
    float p0 = texture(source, uv + vec2(12.0, 0.0) * texel).a;
    float p1 = texture(source, uv - vec2(12.0, 0.0) * texel).a;
    float p2 = texture(source, uv + vec2(0.0, 12.0) * texel).a;
    float p3 = texture(source, uv - vec2(0.0, 12.0) * texel).a;
    float pMax = max(max(p0, p1), max(p2, p3));
    float pMin = min(min(p0, p1), min(p2, p3));

    if (a0 < 0.004) {
        if (pMax < 0.004 || shadowStrength <= 0.0) {
            fragColor = vec4(0.0);
            return;
        }
        // Ombre douce sous la forme (gardée sous le seuil de flou de Hyprland)
        vec2 g;
        float sh = ring(uv - vec2(0.0, 4.0) * texel, 10.0, 10, g) * shadowStrength;
        fragColor = vec4(0.0, 0.0, 0.0, sh) * qt_Opacity;
        return;
    }

    vec2 gWide = vec2(0.0);
    float avgWide = 1.0;
    float avgNarrow = 1.0;
    if (pMin < 0.996) {
        avgWide = ring(uv, 11.0, 12, gWide);
        vec2 gNarrow;
        avgNarrow = ring(uv, 1.8, 6, gNarrow);
    }

    float bevel = clamp((1.0 - avgWide) * 2.0, 0.0, 1.0);
    bevel = bevel * bevel;
    float line = clamp((1.0 - avgNarrow) * 2.2, 0.0, 1.0);

    vec2 n = length(gWide) > 1e-4 ? normalize(gWide) : vec2(0.0);

    vec2 L = normalize(vec2(-0.55, -0.85));
    float facing = dot(n, L);
    float key = pow(max(facing, 0.0), 2.0);
    float back = pow(max(-facing, 0.0), 3.0) * 0.45;
    float spec = (key + back) * bevel;

    vec3 chroma = vec3(0.5 + 0.5 * n.x, 0.5 + 0.25 * (n.x + n.y), 0.5 + 0.5 * n.y);
    vec3 rimCol = mix(vec3(1.0), chroma, 0.3);

    float lineLit = line * (0.18 + 0.82 * max(key, back * 1.6));

    vec3 col = tint;
    float a = tintAlpha;
    col = mix(col, rimCol, clamp(spec * 0.45 * light + lineLit * 0.8, 0.0, 1.0));
    a += spec * 0.22 * light + lineLit * 0.4;

    // Épaisseur du verre : léger assombrissement juste derrière le liseré
    col *= 1.0 - (1.0 - line) * bevel * 0.08;

    // Reflet qui suit le pointeur sur toute la surface de verre
    vec2 md = (uv - mouse) / texel;
    float d2 = dot(md, md);
    float spot = exp(-d2 / (2.0 * 110.0 * 110.0)) * hover;
    float spotRim = exp(-d2 / (2.0 * 70.0 * 70.0)) * hover * (line + bevel * 0.7);
    col = mix(col, vec3(1.0), clamp(spot * 0.08 + spotRim * 0.5, 0.0, 1.0));
    a += spot * 0.05 + spotRim * 0.3;

    a = clamp(a, 0.0, 1.0) * a0 * qt_Opacity;
    fragColor = vec4(col * a, a);
}
