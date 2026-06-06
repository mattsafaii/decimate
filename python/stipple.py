#!/usr/bin/env python3
"""Weighted Voronoi stippling (Secord-style Lloyd relaxation).

CLI contract: stipple.py <workdir>
  reads  <workdir>/input.pgm   (binary 8-bit grayscale, P5)
         <workdir>/params.json {points, iterations, minRadius, maxRadius}
  writes <workdir>/output.json {width, height, points: [{x, y, r}, ...]}

Coordinates are in input pixel space, origin at the top-left. The result is
the point list only — rendering to SVG/PNG happens on the Swift side.
"""

import json
import sys
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree


def read_pgm(path):
    raw = path.read_bytes()
    if not raw.startswith(b"P5"):
        raise ValueError("input.pgm must be binary PGM (P5)")
    tokens = []
    i = 2
    while len(tokens) < 3:
        while i < len(raw) and raw[i : i + 1].isspace():
            i += 1
        if raw[i : i + 1] == b"#":
            while i < len(raw) and raw[i : i + 1] != b"\n":
                i += 1
            continue
        start = i
        while i < len(raw) and not raw[i : i + 1].isspace():
            i += 1
        tokens.append(int(raw[start:i]))
    i += 1  # single whitespace separating maxval from pixel data
    width, height, maxval = tokens
    pixels = np.frombuffer(raw, dtype=np.uint8, count=width * height, offset=i)
    return pixels.reshape(height, width).astype(np.float64) / maxval


def main():
    workdir = Path(sys.argv[1])
    params = json.loads((workdir / "params.json").read_text())
    iterations = max(1, int(params.get("iterations", 20)))
    min_r = float(params.get("minRadius", 1.0))
    max_r = float(params.get("maxRadius", 3.0))

    gray = read_pgm(workdir / "input.pgm")
    height, width = gray.shape
    n_points = min(max(1, int(params.get("points", 4000))), gray.size)

    density = 1.0 - gray  # stipple where the image is dark
    if density.sum() <= 0:
        density = np.full_like(density, 1e-6)

    flat = density.ravel()
    prob = flat / flat.sum()
    rng = np.random.default_rng(7)

    # Importance-sample initial points from the density map
    idx = rng.choice(flat.size, size=n_points, replace=False, p=prob)
    points = np.column_stack([idx % width, idx // width]).astype(np.float64)
    points += rng.uniform(-0.5, 0.5, size=points.shape)

    ys, xs = np.mgrid[0:height, 0:width]
    coords = np.column_stack([xs.ravel(), ys.ravel()]).astype(np.float64)

    # Weighted Lloyd's relaxation: move each point to the density-weighted
    # centroid of its Voronoi cell (cells computed discretely over pixels).
    labels = np.zeros(flat.size, dtype=np.int64)
    for _ in range(iterations):
        tree = cKDTree(points)
        _, labels = tree.query(coords, workers=-1)
        wsum = np.bincount(labels, weights=flat, minlength=n_points)
        wx = np.bincount(labels, weights=flat * coords[:, 0], minlength=n_points)
        wy = np.bincount(labels, weights=flat * coords[:, 1], minlength=n_points)
        occupied = wsum > 0
        points[occupied, 0] = wx[occupied] / wsum[occupied]
        points[occupied, 1] = wy[occupied] / wsum[occupied]
        starving = ~occupied
        if starving.any():  # respawn points whose cell has no ink
            ridx = rng.choice(flat.size, size=int(starving.sum()), p=prob)
            points[starving, 0] = ridx % width
            points[starving, 1] = ridx // width

    # Size each dot by the mean darkness of its final cell
    tree = cKDTree(points)
    _, labels = tree.query(coords, workers=-1)
    counts = np.bincount(labels, minlength=n_points)
    wsum = np.bincount(labels, weights=flat, minlength=n_points)
    mean_density = np.where(counts > 0, wsum / np.maximum(counts, 1), 0.0)
    peak = mean_density.max()
    norm = mean_density / peak if peak > 0 else np.zeros_like(mean_density)
    radii = min_r + (max_r - min_r) * np.sqrt(norm)

    output = {
        "width": width,
        "height": height,
        "points": [
            {"x": round(float(x), 2), "y": round(float(y), 2), "r": round(float(r), 2)}
            for (x, y), r in zip(points, radii)
        ],
    }
    (workdir / "output.json").write_text(json.dumps(output))


if __name__ == "__main__":
    main()
