#version 440

// Liquid glass « eau » façon macOS 26/27 : le verre ne se contente plus d'un flou teinté,
// il montre réellement ce qu'il y a derrière (fond d'écran + fenêtres capturées en direct)
// à travers une lentille épaisse :
//  - centre presque limpide (à peine adouci), comme une goutte d'eau ;
//  - profil de dôme : plus on approche du bord, plus l'image est aspirée et courbée ;
//  - franges de couleur (dispersion) dans la zone courbée ;
//  - liseré lumineux qui accroche la lumière, ombre interne d'épaisseur, reflet au pointeur.
// Sans image de l'arrière-plan (hasScene = 0), on retombe sur un verre translucide classique.

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
    float hasScene;
    float lensWidth;   // largeur de la zone courbée (px)
    float lensDepth;   // déplacement maximal de l'image au bord (px)
    float frost;       // flou de l'arrière-plan (niveau de mipmap, ~3-4 = verre dépoli de macOS)
    float calm;        // 0..1 : atténue le contraste de ce qui est derrière pour garder le texte lisible
};

layout(binding = 1) uniform sampler2D source; // la forme (opaque)
layout(binding = 2) uniform sampler2D scene;  // ce qu'il y a derrière le verre

const float PI = 3.14159265359;
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

// Distance au bord estimée à partir de la part d'un cercle de rayon R qui tombe dans la forme :
// sur un bord droit, cette part vaut 1 - acos(d / R) / PI.
float edgeDistance(float coverage, float R) {
    return R * cos(PI * (1.0 - clamp(coverage, 0.5, 1.0)));
}

// Flou large et bon marché : disque de 9 points pris dans un niveau de mipmap réduit
vec3 sampleScene(vec2 uv, float lod) {
    vec2 o = exp2(lod) * 1.6 * texel;
    vec3 c = textureLod(scene, uv, lod).rgb * 0.2;
    for (int i = 0; i < 8; i++) {
        float ang = PI2 * (float(i) + 0.25) / 8.0;
        c += textureLod(scene, uv + vec2(cos(ang), sin(ang)) * o, lod).rgb * 0.1;
    }
    return c;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float a0 = texture(source, uv).a;
    float R = max(lensWidth, 4.0);

    float p0 = texture(source, uv + vec2(R, 0.0) * texel).a;
    float p1 = texture(source, uv - vec2(R, 0.0) * texel).a;
    float p2 = texture(source, uv + vec2(0.0, R) * texel).a;
    float p3 = texture(source, uv - vec2(0.0, R) * texel).a;
    float pMax = max(max(p0, p1), max(p2, p3));
    float pMin = min(min(p0, p1), min(p2, p3));

    // ─── Hors de la forme : ombre portée douce
    if (a0 < 0.004) {
        if (pMax < 0.004 || shadowStrength <= 0.0) {
            fragColor = vec4(0.0);
            return;
        }
        vec2 g;
        float sh = ring(uv - vec2(0.0, 6.0) * texel, 14.0, 10, g) * shadowStrength;
        fragColor = vec4(0.0, 0.0, 0.0, sh) * qt_Opacity;
        return;
    }

    // ─── Géométrie de la lentille
    float dist = R;            // distance au bord (px), R = au cœur
    float distNear = 8.0;
    float rimLine = 0.0;
    vec2 n = vec2(0.0);        // normale vers l'extérieur
    if (pMin < 0.996) {
        vec2 g;
        float cov = ring(uv, R, 16, g);
        dist = edgeDistance(cov, R);
        n = length(g) > 1e-4 ? normalize(g) : vec2(0.0);
        vec2 gn;
        float covNear = ring(uv, 8.0, 10, gn);
        distNear = edgeDistance(covNear, 8.0);
        vec2 gl;
        rimLine = clamp((1.0 - ring(uv, 1.6, 6, gl)) * 2.2, 0.0, 1.0);
    }

    float x = clamp(dist / R, 0.0, 1.0);      // 0 au bord, 1 au cœur
    float slope = 1.0 - sqrt(max(1.0 - (1.0 - x) * (1.0 - x), 0.0)); // pente d'un dôme : forte au bord
    float bevel = 1.0 - x;

    // Éclairage : lumière en haut à gauche, contre-jour en bas à droite
    vec2 L = normalize(vec2(-0.5, -0.87));
    float facing = dot(n, L);
    float key = pow(max(facing, 0.0), 1.5);
    float back = pow(max(-facing, 0.0), 2.0) * 0.75;

    vec3 col;
    float a;

    if (hasScene > 0.5) {
        // ─── Réfraction : le bord « aspire » l'image depuis l'intérieur et la courbe
        vec2 disp = -n * slope * lensDepth * texel;
        float lod = frost;
        float spread = 0.06 + 0.12 * slope; // dispersion, seulement là où ça courbe
        vec3 refr;
        refr.r = sampleScene(uv + disp * (1.0 + spread), lod).r;
        refr.g = sampleScene(uv + disp, lod).g;
        refr.b = sampleScene(uv + disp * (1.0 - spread), lod).b;

        // Lisibilité : on écrase les contrastes de l'arrière-plan vers sa teinte moyenne
        // (comme le verre de macOS), un peu moins sur le bord pour garder l'effet de lentille
        vec3 avg = textureLod(scene, uv, frost + 3.0).rgb;
        refr = mix(refr, avg, calm * (1.0 - 0.5 * bevel));
        float luma = dot(refr, vec3(0.299, 0.587, 0.114));
        refr = mix(vec3(luma), refr, 1.1);

        col = mix(refr, tint, tintAlpha);
        a = 1.0;
    } else {
        col = tint;
        a = tintAlpha + 0.18;
    }

    // ─── Épaisseur : ombre interne juste derrière le liseré, caustique claire un peu plus loin
    float nearX = clamp(distNear / 8.0, 0.0, 1.0);
    float innerShade = (1.0 - nearX) * smoothstep(0.0, 0.25, nearX) * 0.10;
    col *= 1.0 - innerShade;
    float caustic = pow(bevel, 3.0) * (0.35 * back + 0.25 * key);
    col = mix(col, vec3(1.0), caustic * 0.35 * light);

    // ─── Liseré : accroche la lumière d'un côté, contre-reflet de l'autre
    vec3 rimTint = mix(vec3(1.0), vec3(0.5 + 0.5 * n.x, 0.55 + 0.2 * (n.x + n.y), 0.5 + 0.5 * n.y), 0.18);
    float lineLit = rimLine * (0.18 + 0.95 * max(key, back * 1.2));
    float specBand = pow(bevel, 4.0) * (key + back) * 0.30;
    col = mix(col, rimTint, clamp((lineLit * 0.85 + specBand) * light, 0.0, 1.0));
    a += (lineLit * 0.4 + specBand * 0.2) * (1.0 - a);

    // ─── Reflet qui suit le pointeur, surtout sur le bord
    vec2 md = (uv - mouse) / texel;
    float d2 = dot(md, md);
    float spot = exp(-d2 / (2.0 * 130.0 * 130.0)) * hover;
    float spotRim = exp(-d2 / (2.0 * 80.0 * 80.0)) * hover * (rimLine + pow(bevel, 2.0) * 0.8);
    col = mix(col, vec3(1.0), clamp(spot * 0.05 + spotRim * 0.5, 0.0, 1.0));
    a += (spot * 0.03 + spotRim * 0.3) * (1.0 - a);

    a = clamp(a, 0.0, 1.0) * a0 * qt_Opacity;
    fragColor = vec4(col * a, a);
}
