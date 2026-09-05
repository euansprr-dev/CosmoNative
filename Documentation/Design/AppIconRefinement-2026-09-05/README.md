# Cosmo app icon refinement

The first pass had uneven curve transitions, bulky merged shapes, and an indistinct leaf in 02 and 05. This revision rebuilds all five marks around continuous orbital curves and a deliberately drawn botanical leaf.

The clarified brief is **leaf shape and veins**, not a literal V monogram. The orbit, seed, forest green, and parchment remain the identity.

## What changed

- Orbital curves now derive from analytical ellipses, with aligned tangents at segment joins. The transition into the leaf stem follows the same direction.
- Rounded stroke caps no longer protrude through the leaf tip or vein junctions. The upper orbit stops with an intentional gap before the leaf.
- The leaf has a pointed almond contour, a central vein, and two articulated side veins. Its internal openings are larger and more legible.
- 02 and 05 have a larger leaf and a flat two-tone interior. 05 also uses a muted sage rear orbit against the parchment foreground.
- The orbit crossings use clear over-and-under breaks, expressed entirely as flat graphic shapes.

## Directions

| Icon | Character |
|---|---|
| 01 Living Orbit | Closest to the original, with restrained line weights |
| 02 Verdant | A more prominent leaf, sage interior, and stronger primary orbit |
| 03 Folio | An open orbital C and an independent leaf silhouette |
| 04 Meridian | A fine-line version with a muted gilt seed |
| 05 Evergreen | Parchment and sage on deep forest; the most distinctive color treatment |

## Files

- `svg/`: editable vector masters in default, dark, and single-ink appearances.
- `png/`: opaque 1024 × 1024 exports for every appearance, plus 4096 × 4096 default exports for all five designs.
- `comparison.png`: all five revised designs with small-size previews.
- `proofs/`: enlarged leaf details, geometry checks, and browser verification records.
- `build.cjs`: reproducible vector definitions and exports.

Geometry stays identical between appearances. No 3D rendering, beveling, drop shadows, or photographic textures are used. The source artwork remains square; rounded corners belong to presentation previews.

## Verification

The SVG curve check covered 180 orbital joins. The largest measured tangent-angle difference after coordinate rounding was approximately 0.000164°. Leaf tips and vein branches have intentional corners and are excluded from that smooth-orbit check.

All 15 SVG files parse correctly. All 20 PNG exports have their stated dimensions and opaque RGB color. The review includes 60-, 40-, and 29-pixel reductions and enlarged leaf inspection. These are design proofs; final system-rendered tinted and clear appearances still require Icon Composer/device review after selecting the production icon.

The existing app asset catalogs have not been changed. The previous study and its 33 reference icons remain in the adjacent `AppIconExploration-2026-09-05` folder.
