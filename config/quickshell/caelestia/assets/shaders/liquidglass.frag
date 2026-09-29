#version 440

// Surface « liquid glass » façon macOS : teinte translucide, biseau lumineux,
// reflet spéculaire qui suit le pointeur et fine aberration chromatique sur les bords.
// Le flou de l'arrière-plan est fourni par Hyprland (layer rule blur).

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float radius;
    vec3 tint;
    float tintAlpha;
    vec2 mouse;
    float hover;
    float light;
};

float sdRoundRect(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec2 rimNormal(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    vec2 n;
    if (q.x > 0.0 && q.y > 0.0)
        n = normalize(q);
    else
        n = q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    return n * sign(p);
}

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * size;
    vec2 b = size * 0.5;
    float r = min(radius, min(b.x, b.y));

    float d = sdRoundRect(p, b, r);
    float mask = clamp(0.5 - d, 0.0, 1.0);
    if (mask <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    float e = max(-d, 0.0); // distance au bord, vers l'intérieur
    vec2 n = rimNormal(p, b, r);
    vec2 uv = qt_TexCoord0;

    // Teinte de base + voile vertical (plus clair en haut, comme une lentille éclairée d'en haut)
    vec3 col = tint;
    float a = tintAlpha;
    float sheen = mix(0.10, 0.0, smoothstep(0.0, 0.55, uv.y)) * light;
    col = mix(col, vec3(1.0), sheen);
    a += sheen * 0.5;

    // Biseau : zone de réfraction simulée le long du bord
    float bevelW = 9.0;
    float bevel = exp(-e / bevelW * 2.2);

    // Lumière principale en haut à gauche, contre-reflet en bas à droite
    vec2 L = normalize(vec2(-0.55, -0.85));
    float facing = dot(n, L);
    float key = pow(max(facing, 0.0), 2.0);
    float back = pow(max(-facing, 0.0), 3.0) * 0.45;
    float spec = (key + back) * bevel;

    // Liseré net d'un pixel (le « bord de verre »)
    float line = (1.0 - smoothstep(0.2, 1.25, e));
    float lineLit = line * (0.10 + 0.62 * max(key, back * 1.6));

    // Aberration chromatique sur le biseau : léger décalage des teintes selon la normale
    vec3 chroma = vec3(0.5 + 0.5 * n.x, 0.5 + 0.25 * (n.x + n.y), 0.5 + 0.5 * n.y);
    vec3 rimCol = mix(vec3(1.0), chroma, 0.08);

    col = mix(col, rimCol, clamp(spec * 0.55 * light + lineLit * 0.62, 0.0, 1.0));
    a += spec * 0.18 * light + lineLit * 0.28;

    // Épaisseur : léger assombrissement intérieur juste derrière le liseré
    float inner = smoothstep(2.0, 5.0, e) * (1.0 - smoothstep(5.0, 22.0, e));
    col *= 1.0 - inner * 0.06;

    // Reflet spéculaire qui suit le pointeur
    vec2 mp = (mouse - 0.5) * size;
    float md = length(p - mp);
    float spot = exp(-(md * md) / (2.0 * 90.0 * 90.0)) * hover;
    float spotRim = exp(-(md * md) / (2.0 * 55.0 * 55.0)) * hover * (line + bevel * 0.6);
    col = mix(col, vec3(1.0), clamp(spot * 0.10 + spotRim * 0.30, 0.0, 1.0));
    a += spot * 0.06 + spotRim * 0.18;

    a = clamp(a, 0.0, 1.0) * mask * qt_Opacity;
    fragColor = vec4(col * a, a);
}
