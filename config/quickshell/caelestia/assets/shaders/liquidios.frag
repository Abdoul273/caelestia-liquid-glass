#version 440

// Liquid glass façon iOS 26/27 pour une forme quelconque (cadre, barre, panneaux).
// Différences avec glassblob.frag (style « classique ») :
//  - verre bien plus clair (peu de teinte) : on voit vraiment ce qu'il y a derrière ;
//  - réfraction : près des bords, le fond d'écran est dévié comme à travers une lentille
//    épaisse, avec des franges de couleur (aberration chromatique) ;
//  - double reflet spéculaire (coin éclairé + coin opposé), halo de Fresnel et
//    ombre interne qui donnent l'épaisseur du verre.
// Le fond d'écran n'est dévié que dans la zone du cadre et de la barre (au-dessus des
// fenêtres, on ne peut pas lire l'image : le flou de Hyprland fait le reste).

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
    vec4 zone;       // largeur du cadre à gauche, en haut, à droite, en bas (px)
    float refraction; // 0 = pas de réfraction
};

layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D wallpaper;
layout(binding = 3) uniform sampler2D windows; // blanc là où une fenêtre est sous le verre

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

    float p0 = texture(source, uv + vec2(16.0, 0.0) * texel).a;
    float p1 = texture(source, uv - vec2(16.0, 0.0) * texel).a;
    float p2 = texture(source, uv + vec2(0.0, 16.0) * texel).a;
    float p3 = texture(source, uv - vec2(0.0, 16.0) * texel).a;
    float pMax = max(max(p0, p1), max(p2, p3));
    float pMin = min(min(p0, p1), min(p2, p3));

    if (a0 < 0.004) {
        if (pMax < 0.004 || shadowStrength <= 0.0) {
            fragColor = vec4(0.0);
            return;
        }
        vec2 g;
        float sh = ring(uv - vec2(0.0, 5.0) * texel, 12.0, 10, g) * shadowStrength;
        fragColor = vec4(0.0, 0.0, 0.0, sh) * qt_Opacity;
        return;
    }

    // Profil du bord : large (biseau de la lentille) et fin (liseré)
    vec2 gWide = vec2(0.0);
    float avgWide = 1.0;
    float avgMid = 1.0;
    float avgNarrow = 1.0;
    if (pMin < 0.996) {
        avgWide = ring(uv, 15.0, 14, gWide);
        vec2 gMid;
        avgMid = ring(uv, 6.0, 8, gMid);
        vec2 gNarrow;
        avgNarrow = ring(uv, 1.6, 6, gNarrow);
    }

    float bevel = clamp((1.0 - avgWide) * 2.0, 0.0, 1.0);   // 1 au bord, 0 à ~15 px
    float bevelIn = clamp((1.0 - avgMid) * 2.0, 0.0, 1.0);  // 1 au bord, 0 à ~6 px
    float line = clamp((1.0 - avgNarrow) * 2.2, 0.0, 1.0);
    vec2 n = length(gWide) > 1e-4 ? normalize(gWide) : vec2(0.0); // vers l'extérieur

    // Éclairage : lumière en haut à gauche, reflet secondaire en bas à droite
    vec2 L = normalize(vec2(-0.5, -0.87));
    float facing = dot(n, L);
    float key = pow(max(facing, 0.0), 1.6);
    float back = pow(max(-facing, 0.0), 2.2) * 0.7;

    // ─── Fond : teinte légère
    vec3 col = tint;
    float a = tintAlpha;

    // ─── Réfraction du fond d'écran dans le biseau : cadre, barre, et tout panneau posé
    //     sur le bureau (aucune fenêtre dessous, sinon on garde le flou de Hyprland)
    vec2 px = uv / texel;
    vec2 size = 1.0 / texel;
    float outside = min(min(px.x - zone.x, px.y - zone.y), min(size.x - zone.z - px.x, size.y - zone.w - px.y));
    float zoneMask = 1.0 - smoothstep(0.0, 36.0, outside);
    zoneMask = max(zoneMask, 1.0 - texture(windows, uv).r);
    float lens = pow(bevel, 1.6) * refraction * zoneMask;
    if (lens > 0.002) {
        // La lentille « aspire » l'image depuis l'intérieur : effet de loupe sur les bords
        vec2 disp = -n * lens * 26.0 * texel;
        vec3 refr;
        refr.r = texture(wallpaper, uv + disp * 1.12).r;
        refr.g = texture(wallpaper, uv + disp).g;
        refr.b = texture(wallpaper, uv + disp * 0.86).b;
        // Le verre éclaircit et sature un peu ce qu'il réfracte
        float luma = dot(refr, vec3(0.299, 0.587, 0.114));
        refr = mix(vec3(luma), refr, 1.25) * 1.06;
        float w = clamp(lens * 1.3, 0.0, 0.92);
        col = mix(col, refr, w / max(a + w * (1.0 - a), 1e-3));
        a = a + w * (1.0 - a);
    }

    // ─── Épaisseur : ombre interne juste à l'intérieur du biseau
    float innerShade = bevel * (1.0 - bevelIn) * 0.14;
    col *= 1.0 - innerShade;

    // ─── Halo de Fresnel : le bord du verre s'éclaire
    float fresnel = pow(bevelIn, 2.0);
    col = mix(col, vec3(1.0), fresnel * 0.1 * light);
    a += fresnel * 0.06;

    // ─── Reflets spéculaires : large sur le biseau, net sur le liseré
    vec3 rimTint = mix(vec3(1.0), vec3(0.5 + 0.5 * n.x, 0.55 + 0.2 * (n.x + n.y), 0.5 + 0.5 * n.y), 0.22);
    float specWide = (key + back) * bevel * bevel * 0.35;
    float lineLit = line * (0.22 + 0.9 * max(key, back * 1.3));
    col = mix(col, rimTint, clamp((specWide + lineLit * 0.85) * light, 0.0, 1.0));
    a += specWide * 0.2 + lineLit * 0.45;

    // ─── Reflet qui suit le pointeur (surtout sur les bords)
    vec2 md = (uv - mouse) / texel;
    float d2 = dot(md, md);
    float spot = exp(-d2 / (2.0 * 120.0 * 120.0)) * hover;
    float spotRim = exp(-d2 / (2.0 * 80.0 * 80.0)) * hover * (line + bevel * 0.8);
    col = mix(col, vec3(1.0), clamp(spot * 0.06 + spotRim * 0.55, 0.0, 1.0));
    a += spot * 0.03 + spotRim * 0.3;

    a = clamp(a, 0.0, 1.0) * a0 * qt_Opacity;
    fragColor = vec4(col * a, a);
}
