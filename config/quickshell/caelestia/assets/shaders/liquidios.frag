#version 440

// Liquid glass façon iOS 26/27 pour une forme quelconque (cadre, barre, panneaux).
// Avec clearGlass, tout le corps posé sur le bureau est une lentille nette (pas seulement le bord).
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
    float thickAlpha; // opacité du verre « épais » quand le fond risque de noyer le contenu
    float unknownBg;  // 1 = on ne sait pas ce qu'il y a derrière (fenêtre flottante) : verre épais
    float clearGlass; // 1 = tout le corps est une lentille nette (iOS 26 / macOS 27), 0 = flou de Hyprland
    float clearVeil;  // voile de lisibilité posé sur le fond net
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

    vec2 px = uv / texel;
    vec2 size = 1.0 / texel;
    float outside = min(min(px.x - zone.x, px.y - zone.y), min(size.x - zone.z - px.x, size.y - zone.w - px.y));
    float frameMask = 1.0 - smoothstep(0.0, 36.0, outside);
    float overWin = texture(windows, uv).r;

    // ─── Fond : teinte adaptative, comme les matériaux de macOS. Le verre reste clair quand
    //     ce qui est derrière s'accorde avec lui, et s'épaissit quand le fond contraste
    //     (page blanche sous un panneau sombre, fenêtre sombre sous un panneau clair) :
    //     le panneau garde sa couleur et le texte reste lisible quoi qu'il y ait derrière.
    float tintL = dot(tint, vec3(0.299, 0.587, 0.114));
    vec3 wp = texture(wallpaper, uv).rgb * 0.4
            + texture(wallpaper, uv + vec2(48.0, 0.0) * texel).rgb * 0.15
            + texture(wallpaper, uv - vec2(48.0, 0.0) * texel).rgb * 0.15
            + texture(wallpaper, uv + vec2(0.0, 48.0) * texel).rgb * 0.15
            + texture(wallpaper, uv - vec2(0.0, 48.0) * texel).rgb * 0.15;
    float wpContrast = abs(dot(wp, vec3(0.299, 0.587, 0.114)) - tintL);
    float wpThick = smoothstep(0.12, 0.5, wpContrast) * 0.75;
    // Sous une fenêtre on ne voit pas son contenu : on part du pire (verre épais)
    float unknown = max(unknownBg, overWin * (1.0 - frameMask));
    float thick = max(unknown, wpThick * (1.0 - frameMask));
    vec3 col = tint;
    float a = mix(tintAlpha, max(thickAlpha, tintAlpha), thick);

    // ─── Réfraction du fond d'écran dans le biseau : cadre, barre, et tout panneau posé
    //     sur le bureau (aucune fenêtre dessous, sinon on garde le flou de Hyprland)
    float zoneMask = max(frameMask, 1.0 - overWin);

    // ─── Corps de la lentille : sur le bureau, tout l'intérieur du verre montre le fond
    //     NET (pas le flou épais), grossi et courbé sur ~44 px près du bord comme une
    //     goutte d'eau, avec un voile juste assez dense pour que le texte reste lisible.
    float body = zoneMask * clearGlass;
    if (body > 0.002) {
        vec2 gBig = vec2(0.0);
        float avgBig = 1.0;
        float q0 = texture(source, uv + vec2(44.0, 0.0) * texel).a;
        float q1 = texture(source, uv - vec2(44.0, 0.0) * texel).a;
        float q2 = texture(source, uv + vec2(0.0, 44.0) * texel).a;
        float q3 = texture(source, uv - vec2(0.0, 44.0) * texel).a;
        if (min(min(q0, q1), min(q2, q3)) < 0.996)
            avgBig = ring(uv, 44.0, 12, gBig);
        float dome = clamp((1.0 - avgBig) * 2.0, 0.0, 1.0); // 1 au bord, 0 à ~44 px
        vec2 nBig = length(gBig) > 1e-4 ? normalize(gBig) : vec2(0.0);
        // Le bord « aspire » l'image depuis l'intérieur, comme une goutte d'eau : forte
        // loupe tout près du bord, centre intact, couleurs légèrement séparées
        float bend = pow(dome, 1.7);
        vec2 duv = uv - nBig * bend * 34.0 * texel;
        vec2 cshift = -nBig * bend * 3.0 * texel;
        // Très léger adoucissement (le fond reste net, juste moins granuleux)
        vec2 o = 1.2 * texel;
        vec3 core = vec3(texture(wallpaper, duv + cshift).r, texture(wallpaper, duv).g, texture(wallpaper, duv - cshift).b);
        vec3 bg = core * 0.4
                + texture(wallpaper, duv + vec2(o.x, o.y)).rgb * 0.15
                + texture(wallpaper, duv + vec2(-o.x, o.y)).rgb * 0.15
                + texture(wallpaper, duv + vec2(o.x, -o.y)).rgb * 0.15
                + texture(wallpaper, duv + vec2(-o.x, -o.y)).rgb * 0.15;
        // Le verre ravive un peu les couleurs qu'il laisse passer
        float bl = dot(bg, vec3(0.299, 0.587, 0.114));
        bg = mix(vec3(bl), bg, 1.15);
        // Voile : plus dense si le fond contraste avec le panneau (lune, page blanche…)
        float veil = mix(clearVeil, max(thickAlpha + 0.08, clearVeil), thick);
        vec3 glassCol = mix(bg, tint, veil);
        // Verre clair d'iOS 27 : léger voile laiteux, plus lumineux vers le bord bombé
        glassCol = mix(glassCol, vec3(1.0), (0.045 + bend * 0.07) * light);
        col = mix(col, glassCol, body);
        a = mix(a, 1.0, body);
    }
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
    float specWide = (key + back) * bevel * bevel * 0.45;
    float lineLit = line * (0.32 + 1.0 * max(key, back * 1.3));
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
