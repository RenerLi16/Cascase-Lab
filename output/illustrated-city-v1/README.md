# Illustrated city artwork, version 1 (archived)

These are the detailed illustrated terrain layers used before the light paper-board
redesign (October 2026). They are byte-identical to the former `assets/maps/*.png`
and to `output/map-alignment/*-terrain.png`.

To restore one, copy it back to `assets/maps/<name>.png`; the layouts in
`assets/maps/layouts/` use the same image size, so no coordinates change.
`tools/build_board_terrain.py` also reads these files to trace the river shapes.
