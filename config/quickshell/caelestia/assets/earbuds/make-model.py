#!/usr/bin/env python3
"""Modèle 3D des écouteurs CETW572 (boîtier galet + deux écouteurs à crochet).

Génère earbuds-model.js (.pragma library) lu par modules/spotlight/EarbudsScene.qml
via ProceduralMesh : aucune dépendance (pas d'assimp/balsam), le shell charge
des tableaux de nombres. Unités : millimètres. y vers le haut, z vers l'avant
(la charnière est à l'arrière, z = -B).

Relancer après modification : python3 make-model.py
"""

import json
import math
from pathlib import Path

import numpy as np

A, B, N = 36.0, 31.0, 3.0  # demi-largeur, demi-profondeur, exposant du galet
U = 132  # segments autour du boîtier
WALL = 2.0
TRAY_Y = -2.5


def se(theta, a, b):
    c, s = np.cos(theta), np.sin(theta)
    return np.sign(c) * np.abs(c) ** (2 / N) * a, np.sign(s) * np.abs(s) ** (2 / N) * b


# ── Profils : suites de (k, d, y) : point = k · galet(A-d, B-d) à la hauteur y ──
def arc(cd, cy, r, a0, a1, n):
    """Quart d'arrondi dans le plan (d, y) ; angles en degrés, d vers l'intérieur."""
    out = []
    for t in np.linspace(0, 1, n):
        a = math.radians(a0 + (a1 - a0) * t)
        out.append((1.0, cd + r * math.cos(a), cy + r * math.sin(a)))
    return out


def line(p0, p1, n):
    return [tuple(np.array(p0) + (np.array(p1) - np.array(p0)) * t) for t in np.linspace(0, 1, n)]


def cap(d, y0, y1, n, k0=0.0, k1=1.0, curve=2.0):
    """Disque : de k0 à k1, hauteur y0 au centre → y1 au bord (bombé)."""
    out = []
    for t in np.linspace(0, 1, n):
        k = k0 + (k1 - k0) * t
        y = y0 + (y1 - y0) * (abs(k) ** curve)
        out.append((k, d, y))
    return out


def join(*parts):
    pts = []
    for p in parts:
        for q in p:
            if pts and np.allclose(pts[-1], q, atol=1e-6):
                continue
            pts.append(q)
    return pts


def sweep(profile):
    th = np.linspace(0, 2 * np.pi, U, endpoint=False)
    M = len(profile)
    P = np.zeros((M, U, 3))
    for m, (k, d, y) in enumerate(profile):
        x, z = se(th, A - d, B - d)
        P[m, :, 0] = k * x
        P[m, :, 1] = y
        P[m, :, 2] = k * z
    return P


def grid_normals(P, wrap=True, flip=False):
    M, _Uu, _ = P.shape
    dth = np.roll(P, -1, axis=1) - np.roll(P, 1, axis=1) if wrap else np.gradient(P, axis=1)
    dv = np.zeros_like(P)
    dv[1:-1] = P[2:] - P[:-2]
    dv[0] = P[1] - P[0]
    dv[-1] = P[-1] - P[-2]
    n = np.cross(dv, dth)
    if flip:
        n = -n
    ln = np.linalg.norm(n, axis=2, keepdims=True)
    bad = ln[..., 0] < 1e-9
    n = n / np.maximum(ln, 1e-9)
    # Lignes dégénérées (centre d'un disque, pointe d'un tube) : moyenne de la voisine
    for m in range(M):
        if bad[m].all():
            nb = m + 1 if m + 1 < M else m - 1
            avg = n[nb].mean(axis=0)
            avg /= max(np.linalg.norm(avg), 1e-9)
            n[m] = avg
    return n


def grid_tris(M, Uu, wrap=True, rows=None):
    r0, r1 = rows if rows else (0, M - 1)
    idx = []
    cols = Uu if wrap else Uu - 1
    for m in range(r0, r1):
        for j in range(cols):
            j1 = (j + 1) % Uu
            a, b, c, d = m * Uu + j, (m + 1) * Uu + j, (m + 1) * Uu + j1, m * Uu + j1
            idx += [a, b, d, b, c, d]
    return idx


class Mesh:
    def __init__(self):
        self.p, self.n, self.i = [], [], []

    def add(self, P, Nn, tris, row_range=None):
        """Ajoute une grille ; vérifie que l'enroulement suit les normales."""
        M, Uu, _ = P.shape
        r0, r1 = row_range if row_range else (0, M - 1)
        sub_p = P[r0:r1 + 1].reshape(-1, 3)
        sub_n = Nn[r0:r1 + 1].reshape(-1, 3)
        base_off = r0 * Uu
        tri = np.array(tris).reshape(-1, 3) - base_off
        v = sub_p
        cr = np.cross(v[tri[:, 1]] - v[tri[:, 0]], v[tri[:, 2]] - v[tri[:, 0]])
        dots = np.einsum("ij,ij->i", cr, sub_n[tri[:, 0]])
        if dots.sum() < 0:
            tri = tri[:, [0, 2, 1]]
        off = len(self.p)
        self.p += sub_p.tolist()
        self.n += sub_n.tolist()
        self.i += (tri + off).flatten().tolist()

    def add_grid(self, P, Nn, wrap=True, rows=None):
        M, Uu, _ = P.shape
        tris = grid_tris(M, Uu, wrap, rows)
        self.add(P, Nn, tris, rows)

    def transformed(self, fn):
        m = Mesh()
        m.p = [fn(np.array(p)).tolist() for p in self.p]
        m.n = self.n
        m.i = self.i
        return m

    def mirrored_x(self):
        m = Mesh()
        m.p = [[-x, y, z] for x, y, z in self.p]
        m.n = [[-x, y, z] for x, y, z in self.n]
        m.i = np.array(self.i).reshape(-1, 3)[:, [0, 2, 1]].flatten().tolist()
        return m

    def merge(self, other):
        off = len(self.p)
        self.p += other.p
        self.n += other.n
        self.i += [i + off for i in other.i]
        return self

    def export(self):
        return {
            "p": [round(c, 2) for v in self.p for c in v],
            "n": [round(c, 3) for v in self.n for c in v],
            "i": self.i,
        }


meshes = {}

# ── Bas du boîtier : coque extérieure, bord, paroi intérieure, plateau ──
H, R = 18.0, 8.0
base_prof = join(
    cap(R, -H, -H + 0.35, 10, curve=2.0),  # dessous très légèrement bombé
    arc(R, -H + R, R, 180, 270, 16)[::-1] and [(1.0, R - R * math.sin(math.radians(a)), -H + R - R * math.cos(math.radians(a))) for a in np.linspace(0, 90, 16)],
    line((1.0, 0.0, -H + R), (1.0, 0.0, -0.7), 8),
    [(1.0, 0.7 - 0.7 * math.cos(math.radians(a)), -0.7 + 0.7 * math.sin(math.radians(a))) for a in np.linspace(0, 90, 6)],
    line((1.0, 0.7, 0.0), (1.0, WALL - 0.5, 0.0), 3),
    [(1.0, WALL - 0.5 + 0.5 * math.sin(math.radians(a)), -0.5 + 0.5 * math.cos(math.radians(a))) for a in np.linspace(0, 90, 5)],
    line((1.0, WALL, -0.5), (1.0, WALL, TRAY_Y + 1.0), 4),
    [(1.0, WALL + 1.0 - 1.0 * math.cos(math.radians(a)), TRAY_Y + 1.0 - 1.0 * math.sin(math.radians(a))) for a in np.linspace(0, 90, 6)],
)
tray_start = len(base_prof) - 1
base_prof = join(base_prof, cap(WALL + 1.0, TRAY_Y, TRAY_Y, 10, curve=2.0)[::-1])
P = sweep(base_prof)
Nn = grid_normals(P)
shell = Mesh()
shell.add_grid(P, Nn, rows=(0, tray_start))
tray = Mesh()
tray.add_grid(P, Nn, rows=(tray_start, len(base_prof) - 1))
meshes["caseShell"] = shell
meshes["caseTray"] = tray

# ── Couvercle : intérieur noir (plafond, paroi, lèvre) puis coque bombée ──
LW, LR, LTOP = 3.0, 8.0, 11.0
inner_top = 9.3
lid_prof = join(
    cap(WALL + 3.0, inner_top + 0.3, inner_top, 8, curve=2.0),
    [(1.0, WALL + 3.0 - 3.0 * math.sin(math.radians(a)), inner_top - 3.0 + 3.0 * math.cos(math.radians(a))) for a in np.linspace(0, 90, 7)],
    line((1.0, WALL, inner_top - 3.0), (1.0, WALL, 0.5), 5),
    [(1.0, WALL - 0.5 + 0.5 * math.cos(math.radians(a)), 0.5 - 0.5 * math.sin(math.radians(a))) for a in np.linspace(0, 90, 5)],
    line((1.0, WALL - 0.5, 0.0), (1.0, 0.7, 0.0), 3),
)
lid_split = len(lid_prof) - 1
lid_prof = join(
    lid_prof,
    [(1.0, 0.7 - 0.7 * math.sin(math.radians(a)), 0.7 - 0.7 * math.cos(math.radians(a))) for a in np.linspace(0, 90, 6)],
    line((1.0, 0.0, 0.7), (1.0, 0.0, LW), 4),
    [(1.0, LR - LR * math.cos(math.radians(a)), LW + LR * math.sin(math.radians(a))) for a in np.linspace(0, 90, 18)],
    cap(LR, LTOP + 2.2, LTOP, 14, curve=2.0)[::-1],
)
P = sweep(lid_prof)
Nn = grid_normals(P)
lid_in = Mesh()
lid_in.add_grid(P, Nn, rows=(0, lid_split))
lid_out = Mesh()
lid_out.add_grid(P, Nn, rows=(lid_split, len(lid_prof) - 1))
meshes["lidInner"] = lid_in
meshes["lidOuter"] = lid_out


# ── Écouteurs ──
def lathe(profile, cx, cz, seg=56, y0=0.0):
    th = np.linspace(0, 2 * np.pi, seg, endpoint=False)
    M = len(profile)
    P = np.zeros((M, seg, 3))
    for m, (r, y) in enumerate(profile):
        P[m, :, 0] = cx + r * np.cos(th)
        P[m, :, 1] = y0 + y
        P[m, :, 2] = cz + r * np.sin(th)
    return P


def catmull(pts, n):
    pts = np.array(pts, dtype=float)
    pts = np.vstack([2 * pts[0] - pts[1], pts, 2 * pts[-1] - pts[-2]])
    out = []
    segs = len(pts) - 3
    for s in range(segs):
        p0, p1, p2, p3 = pts[s:s + 4]
        for t in np.linspace(0, 1, n // segs, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-2])
    return np.array(out)


def tube(path, w, t, seg=18):
    """Bande à section elliptique (w à plat, t en épaisseur), bouts arrondis."""
    T = np.gradient(path, axis=0)
    T /= np.linalg.norm(T, axis=1, keepdims=True)
    up = np.array([0.0, 1.0, 0.0])
    # Bouts arrondis : petites sections qui se referment
    endcap = [math.sin(math.radians(a)) for a in (0, 35, 60, 80)]
    centers = []
    for e, s in zip(range(len(endcap)), endcap):
        back = (1 - s) * w * 0.5
        centers.append((path[0] - T[0] * back, T[0], s))
    for i in range(len(path)):
        centers.append((path[i], T[i], 1.0))
    for s in endcap[::-1]:
        back = (1 - s) * w * 0.5
        centers.append((path[-1] + T[-1] * back, T[-1], s))
    phi = np.linspace(0, 2 * np.pi, seg, endpoint=False)
    P = np.zeros((len(centers), seg, 3))
    Nn = np.zeros_like(P)
    for i, (c, tg, s) in enumerate(centers):
        side = np.cross(tg, up)
        side /= np.linalg.norm(side)
        for j, f in enumerate(phi):
            P[i, j] = c + side * (w * s * math.cos(f)) + up * (t * s * math.sin(f))
            nv = side * (math.cos(f) / w) + up * (math.sin(f) / t)
            nv = nv / np.linalg.norm(nv)
            # vers le bout : la normale s'incline le long de la tangente
            lean = math.sqrt(max(0.0, 1 - s * s))
            direction = -1 if i < len(endcap) else (1 if i >= len(centers) - len(endcap) else 0)
            nv = nv * s + tg * direction * lean
            Nn[i, j] = nv / np.linalg.norm(nv)
    return P, Nn


BUD_X, BUD_Z = -22.0, 16.0
BUD_R = 6.4
BUD_Y0 = TRAY_Y - 1.6  # l'écouteur s'enfonce un peu dans son logement

hook_pts = [
    (-24.6, 0, 10.6), (-28.8, 0, 2.0), (-28.0, 0, -9.5), (-22.5, 0, -17.6),
    (-14.5, 0, -18.6), (-8.8, 0, -12.5), (-6.8, 0, -2.5), (-6.3, 0, 7.5),
]
hy = TRAY_Y + 0.55
path = catmull([(x, hy, z) for x, _, z in hook_pts], 96)
path[:, 1] = hy
# le crochet remonte légèrement là où il rejoint l'écouteur
for i in range(len(path)):
    f = max(0.0, 1 - i / 14)
    path[i, 1] += 0.9 * f * f
P, Nn = tube(path, 2.7, 1.2)
hook = Mesh()
hook.add_grid(P, Nn, wrap=True)

body_prof = join(
    [(r, 0.0) for r in np.linspace(0, BUD_R - 1.8, 4)],
    [(BUD_R - 1.8 + 1.8 * math.sin(math.radians(a)), 1.8 - 1.8 * math.cos(math.radians(a))) for a in np.linspace(0, 90, 8)],
    [(BUD_R, y) for y in np.linspace(1.8, 3.9, 4)],
    [(BUD_R - 0.9 + 0.9 * math.cos(math.radians(a)), 3.9 + 0.9 * math.sin(math.radians(a))) for a in np.linspace(0, 90, 7)],
    [(BUD_R - 0.9 - 0.2 * t, 4.8) for t in np.linspace(0, 1, 2)],
)
P = lathe(body_prof, BUD_X, BUD_Z, y0=BUD_Y0)
bud = Mesh()
bud.add_grid(P, grid_normals(P))
bud.merge(hook)

# Anneau argenté (tore) et capuchon brillant
ring = Mesh()
RR, RT = BUD_R - 1.15, 0.55
seg, segt = 64, 14
th = np.linspace(0, 2 * np.pi, seg, endpoint=False)
ph = np.linspace(0, 2 * np.pi, segt, endpoint=False)
P = np.zeros((segt, seg, 3))
Nn = np.zeros_like(P)
for i, f in enumerate(ph):
    rr = RR + RT * math.cos(f)
    P[i, :, 0] = BUD_X + rr * np.cos(th)
    P[i, :, 1] = BUD_Y0 + 4.85 + RT * math.sin(f)
    P[i, :, 2] = BUD_Z + rr * np.sin(th)
    Nn[i, :, 0] = math.cos(f) * np.cos(th)
    Nn[i, :, 1] = math.sin(f)
    Nn[i, :, 2] = math.cos(f) * np.sin(th)
tris = []
for i in range(segt):
    i1 = (i + 1) % segt
    for j in range(seg):
        j1 = (j + 1) % seg
        a, b, c, d = i * seg + j, i1 * seg + j, i1 * seg + j1, i * seg + j1
        tris += [a, b, d, b, c, d]
ring.add(P, Nn, tris, (0, segt - 1))

capm = Mesh()
cap_prof = [(r, 4.75 + 0.45 * (1 - (r / (RR - 0.2)) ** 2)) for r in np.linspace(0, RR - 0.2, 8)]
P = lathe(cap_prof, BUD_X, BUD_Z, y0=BUD_Y0)
capm.add_grid(P, grid_normals(P, flip=True))
# la normale du capuchon doit pointer vers le haut
if np.mean(np.array(capm.n)[:, 1]) < 0:
    capm.n = [[-a, -b, -c] for a, b, c in capm.n]
    capm.i = np.array(capm.i).reshape(-1, 3)[:, [0, 2, 1]].flatten().tolist()

meshes["budL"] = bud
meshes["budR"] = bud.mirrored_x()
meshes["budRingL"] = ring
meshes["budRingR"] = ring.mirrored_x()
meshes["budCapL"] = capm
meshes["budCapR"] = capm.mirrored_x()


# ── Détails de face : port USB-C, voyant, encoche du couvercle ──
def stadium(cx, cy, z, w, h, seg=14, depth=0.0):
    """Plaque arrondie face à +z (disque en éventail)."""
    r = h / 2
    pts = []
    for a in np.linspace(-90, 90, seg):
        pts.append((cx + w / 2 - r + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))))
    for a in np.linspace(90, 270, seg):
        pts.append((cx - w / 2 + r + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a))))
    m = Mesh()
    m.p = [[cx, cy, z + depth]] + [[x, y, z] for x, y in pts]
    m.n = [[0, 0, 1]] * len(m.p)
    n = len(pts)
    m.i = []
    for k in range(n):
        m.i += [0, 1 + k, 1 + (k + 1) % n]
    return m


meshes["portRim"] = stadium(0.0, -6.6, B + 0.05, 8.8, 3.1)
meshes["portHole"] = stadium(0.0, -6.6, B + 0.09, 7.6, 2.1)
meshes["portTongue"] = stadium(0.0, -6.6, B + 0.12, 4.6, 0.55)
meshes["lidNotch"] = stadium(0.0, 1.35, B + 0.05, 13.5, 1.5)

out = {k: v.export() for k, v in meshes.items()}
counts = {k: len(v.p) for k, v in meshes.items()}
dest = Path(__file__).with_name("earbuds-model.js")
dest.write_text(
    ".pragma library\n// Généré par make-model.py : ne pas éditer à la main.\nvar meshes = "
    + json.dumps(out, separators=(",", ":"))
    + ";\n",
    encoding="utf-8",
)
print("sommets :", counts, "total", sum(counts.values()))
print("taille :", dest.stat().st_size // 1024, "Kio")
