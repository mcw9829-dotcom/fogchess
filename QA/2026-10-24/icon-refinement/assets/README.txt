Fogchess Gold & Blue UI — v2

17 semantic icons × dark/light variants = 34 standalone SVG files.
Original project vector artwork; no external pack or font dependency.
48×48 viewBox, 96px import, 2.2-unit rounded strokes.
Use 40px on menu cards and 26px in navigation.
Root SVGs are dark variants; light/ contains matching light variants.
manifest.json records semantic names, palettes, aliases and file paths.

Godot: app._icon(parent, "rank", 40)
The common icon Control reads FogMenuIcon/light_mode from the inherited Theme.
Theme switches update existing icons and new dialogs automatically.
Static access: Icon.asset_path("rank", true) selects the light SVG.
Existing play / people / target aliases remain supported.
Web or other applications: choose the root/light file from the current theme.
