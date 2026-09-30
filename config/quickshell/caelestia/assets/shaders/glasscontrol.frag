#version 440

// Verre bombé façon iOS pour les petits contrôles (boutons, interrupteurs, cases, curseurs).
// La forme (rectangle arrondi) est calculée exactement : on en tire une vraie surface en
// relief (biseau arrondi), éclairée par deux lumières, avec halo de Fresnel, franges de
// couleur sur le bord et lumière concentrée en bas (caustique), comme un vrai verre épais.
// `lens` = 1 pendant l'appui : le verre devient transparent, seuls les reflets restent.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec4 tint;
    float radius;
    float lens;
    float hover;
    float light;
};

float sdRound(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void main() {
    vec2 half_ = size * 0.5;
    vec2 p = (qt_TexCoord0 - 0.5) * size;
    float r = min(radius, min(half_.x, half_.y));
    float d = sdRound(p, half_, r);
    float aa = clamp(0.5 - d, 0.0, 1.0);
    if (aa <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }

    // Direction vers l'extérieur (gradient de la distance)
    const float e = 0.5;
    vec2 g = vec2(sdRound(p + vec2(e, 0.0), half_, r) - sdRound(p - vec2(e, 0.0), half_, r),
                  sdRound(p + vec2(0.0, e), half_, r) - sdRound(p - vec2(0.0, e), half_, r));
    vec2 dir = length(g) > 1e-5 ? normalize(g) : vec2(0.0);

    // Biseau arrondi : 0 au bord, 1 sur le plateau
    float bw = max(2.0, min(size.x, size.y) * 0.42);
    float t = clamp(-d / bw, 0.0, 1.0);
    float s = 1.0 - t;
    float slope = min(s / max(sqrt(max(1.0 - s * s, 0.0)), 0.12), 5.0);
    vec3 n = normalize(vec3(dir * slope, 1.0));

    vec3 V = vec3(0.0, 0.0, 1.0);
    vec3 L1 = normalize(vec3(-0.45, -0.75, 0.55)); // lumière principale en haut à gauche
    vec3 L2 = normalize(vec3(0.5, 0.8, 0.45));     // contre-jour en bas à droite
    float spec1 = pow(max(dot(reflect(-L1, n), V), 0.0), 14.0) * 0.75;
    float spec2 = pow(max(dot(reflect(-L2, n), V), 0.0), 10.0) * 0.3;
    float fres = pow(1.0 - n.z, 2.2);

    float cy = p.y / max(half_.y, 1.0); // -1 en haut, 1 en bas
    // Caustique : la lumière traverse le verre et se concentre en bas, à l'intérieur du bord
    float caustic = smoothstep(0.05, 1.0, cy) * exp(-pow((t - 0.32) / 0.22, 2.0));
    // Ombre interne sous le bord supérieur : épaisseur du verre
    float shade = smoothstep(0.1, -1.0, cy) * exp(-pow((t - 0.5) / 0.3, 2.0)) * 0.14;

    vec3 col = tint.rgb * (1.0 - shade);
    float a = tint.a * mix(1.0, 0.18, lens);

    // Bord : halo de Fresnel légèrement irisé
    vec3 fringe = vec3(0.55 + 0.45 * dir.x, 0.62 + 0.25 * dir.y, 0.55 - 0.45 * dir.x);
    vec3 rimCol = mix(vec3(1.0), fringe, 0.35);
    float rim = fres * (0.55 + 0.6 * lens);
    col = mix(col, rimCol, clamp(rim * 0.65 * light, 0.0, 1.0));
    a += rim * 0.32;

    float spec = (spec1 + spec2) * (0.8 + 0.4 * lens);
    col = mix(col, vec3(1.0), clamp(spec * light, 0.0, 1.0));
    a += spec * 0.55;

    col = mix(col, vec3(1.0), clamp(caustic * (0.22 + 0.3 * lens), 0.0, 1.0));
    a += caustic * (0.1 + 0.12 * lens);

    col = mix(col, vec3(1.0), hover * 0.06);
    a += hover * 0.04;

    a = clamp(a, 0.0, 1.0) * aa * qt_Opacity;
    fragColor = vec4(col * a, a);
}
