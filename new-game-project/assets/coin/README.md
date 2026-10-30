# Midnight coin

`midnight_coin.glb` is a self-contained octagonal coin modeled after the approved
sun and crescent reference. All antique gold and bronze materials are embedded.
The borders, sun rays, crescent, stars, orbital ring and studs are beveled mesh
geometry. There are no image planes, external textures or particle effects.

The centered pivot uses +Z for Heads. Tails is rotated 180 degrees around X so it
reads upright when the existing toss lands at an X rotation of PI.

Rebuild from the project directory with `python tools/build_coin.py`. The builder
uses only Python's standard library. It creates the GLB without Blender or extra
packages. The hand-painted surface texture of the reference is represented by
material colors rather than baked into a flat face image.
