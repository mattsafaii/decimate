# Decimate

Native Mac companion app for Affinity Designer/Photo. Affinity has no programmatic image effects and can't run Photoshop plugins, so Decimate covers that gap: algorithmic effects (stippling, dithering, halftone, and more over time) applied to an image and exported back into Affinity as PNG or — for vector effects — SVG. v1 is personal tooling; long-term vision is a full-featured distributed app with a growing effect catalog.

## Stack

- Swift + SwiftUI, Xcode project, app name **Decimate**, bundle id `com.safaii.decimate`
- Targets current macOS, Apple Silicon
- CoreImage for built-in filters
- Python 3 + SciPy via subprocess for numerical algorithms (no PythonKit, no sockets)
- **No third-party Swift dependencies in v1**

## Architecture

**Effect catalog as abstraction** — each effect is a declaration: name, engine, parameter list (label, type, range, default), supported output formats. The shell renders parameter UI and routes execution from the declaration. New effects must be additive — no shell surgery.

**Engine decision rule:**
- CoreImage if the filter exists built-in
- Pure Swift for sequential per-pixel algorithms (dithering)
- Python subprocess for numerical/vector algorithms (stippling)
- Custom Metal shader if an effect is per-pixel parallel but not in CoreImage's catalog (no v1 effect needs Metal — future option only)

**Python bridge** — file-based CLI contract: Swift writes input image + params JSON to a temp dir, invokes the script via `Process` against the app-managed venv, reads the output file back.

**Python setup** — app creates its own venv under `~/Library/Application Support/` from bundled `python/requirements.txt` on first launch, with visible progress. Blocks Python-engine effects (not the app) until complete. Clear error if no `python3` found. Skipped on later launches.

**Stippling contract** — the Python script returns the **point list (positions + sizes)** as its result, not a finished image. Swift renders points to SVG/PNG. This keeps future custom-shape stippling a rendering-layer change only.

**Preview pipeline** — preview renders on a downsampled copy (full-res Voronoi can take minutes); export renders full resolution.

## Surfaces

- **Main window:** image preview, effect picker, parameter panel (rendered from declarations), export action
- **First-launch setup:** venv creation with progress
- **Export panel:** save dialog offering the formats the selected effect declares (PNG; PNG + SVG for stippling)

## Core flow

Open image (picker or drag-drop) → pick effect → adjust params (downsampled live preview) → export full-res (PNG, or SVG for stippling) → SVG imports into Affinity as editable vector dots.

## v1 effect catalog

| Effect | Engine | Output |
|---|---|---|
| Stippling (weighted Voronoi) | Python/SciPy | SVG + PNG |
| Floyd-Steinberg dithering | Swift | PNG |
| Bayer dithering | Swift | PNG |
| Halftone | CoreImage | PNG |
| Noise | CoreImage | PNG |

## No-gos (do not build these)

- Distribution packaging (signing, notarization, bundled Python runtime, installer)
- Video processing
- Batch processing of multiple images
- Custom icon/shape stippling modes (architecture leaves the door open; not built in v1)
- Affinity plugin integration — standalone companion, files move via export/import
- Effect stacking/chaining — one effect at a time
- No features beyond the Build todolist without asking Matt first

## Basecamp

Repo config is set — `basecamp` commands work without flags from this directory.

- Account: `REDACTED` (Safaii Studio)
- Project: `REDACTED` (Decimate)
- Build todolist: `REDACTED`
- PRD doc: https://app.basecamp.com/REDACTED/buckets/REDACTED/documents/REDACTED
- Pitch + PRD card: https://app.basecamp.com/REDACTED/buckets/REDACTED/card_tables/cards/REDACTED

Workflow: work the Build todolist in order, comment the commit SHA on each todo before checking it off.
