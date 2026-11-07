# Lighting: dark underground, real shadows, light sources

User direction (2026-11-06): "One overhead light is good, but underground should be dark unless
the sunlight shines down, or if there are lamps or lanterns or some sort of light source. Let's
investigate a more dynamic lighting system that obscures much more readily underground and
supports shadows and light sources, like torches."

## What exists

Light is a per-tile field, not Godot lighting. `core/world/light_engine.gd` keeps two bytes per
tile: `sky` (sunlight falling down each column to the first opaque tile, then flooding sideways
and down with falloff) and `block` (emissive tiles and carried lights). The view uploads the two
fields as R8 textures and every shader is `unshaded`, reading `gs_light_at(tile)` from
`view/shaders/light.gdshaderinc`. There are no `DirectionalLight3D`, `OmniLight3D` or shadow
casters anywhere; every mesh sets `cast_shadow` off. The rules (SRD Bright, Dim, Darkness for
Stealth and Darkvision) read the same field through `LightEngine.category_at`.

So "an unlit cave is black" is already true. Why it does not feel that way:

1. **You are a torch.** `game/view_presenter.gd:110` gives the local player a permanent
   `OWN_LIGHT` at full torch strength: 8 tiles Bright, 16 tiles Dim, whether or not a torch is
   held. Every cave you enter is lit by you. Other players carry one only at night.
2. **Sunlight floods far.** The sky field spreads from any opening with the same falloff as a
   torch, 16 tiles in every direction, so near-surface caves are lit by every crack.
3. **Rock glows.** Opaque tiles pass light at `SOLID_STEP`, so the first tiles of rock around a
   lit space are visible; a wall never reads as a hard edge.
4. **Flat.** The field is a scalar per tile: no direction, no shadow, no shaft. A torch on a
   wall and a torch in open air light the same circle.
5. **Night is brightened.** `WorldView.NIGHT_VISUAL` draws the night sky field at 0.25 when the
   rules say 0.04, with a moon tint.

Numbers: `STEP` 5 per tile, `DIAG` 7, `SOLID_STEP` 22, torch level 85, Bright at 45, Dim at 5.

## Design

Keep the field for the rules and as the darkness mask; put real lights on top for shadows and
direction. The field says *whether* a place is lit, Godot's lights say *how it looks*.

1. **No free light.** The player lights nothing unless they hold or wear a light: a torch in
   the hotbar's selected slot or off hand, a lantern, a Light spell, a Lantern spark. Darkvision
   remains a rules sense (grey, short) and gets a view treatment of its own: desaturated,
   `DARKVISION_TILES` radius, no colour. Data: `data/looks.json` `lights` table mapping item and
   effect slugs to level, colour and radius.
2. **Sunlight is a shaft, not a flood.** Sky light keeps its full strength straight down the
   open column and loses it fast sideways under cover: a separate `SKY_COVERED_STEP` (about
   3x `STEP`) for cells that are not in the open column. A cave mouth lights a few tiles, a
   shaft from a hole above lights the floor under it. Nothing changes in the open air.
3. **Hard walls.** `SOLID_STEP` rises so rock takes at most one tile of glow; the terrain shader
   draws the face at the lit cell's level, not the rock's.
4. **Real lights for look.** One `DirectionalLight3D` sun with shadows, angled from above and
   slightly in front of the play plane, following the clock (colour and elevation by hour), and
   an `OmniLight3D` with shadows per visible light source (torches, lamps, campfires, carried
   lights, emissive tiles), pooled, nearest N to the camera (data: `max_lights`, default 24;
   Forward+ clusters them cheaply). Terrain, dressing, actors and props cast shadows; the
   backdrop does not. Shaders become lit (`render_mode` default) with the field as a multiplier:
   `ALBEDO * field` keeps caves black and lets a torch throw a real shadow of the player on the
   wall. Material roughness and normal maps from Synty and monster-forge come back.
5. **Atmosphere.** Dust motes or god rays in sun shafts underground (a cheap billboard sheet in
   the lit column), a soft bloom on light sources, and the parallax backdrop (look track) lit
   by the sun colour only.
6. **Night.** `NIGHT_VISUAL` drops toward the rules value (about 0.1), moonlight becomes the
   directional light at low strength with a blue tint and long shadows, so a night walk needs a
   torch and towns glow by their lamps.

What does not change: `LightEngine` categories and the rules that read them, Darkvision species,
Stealth, the SRD numbers (torch 20 ft Bright and 20 ft Dim), the tile data, `core/`.

## Costs and risks

- Shadow maps on every chunk mesh: measure with `tools/bench_view.gd` on the GPU; the CPU
  renderer for screenshots (`tools/soft_godot.sh`) will be slow with shadows, so pictures use
  low shadow quality.
- Lit materials change every actor's look: `LitMaterials` must keep its tint, alpha scissor and
  vertex colour paths. Compare pictures of a Synty character and a forge monster before and
  after.
- Omni lights from emissive tiles need a scan of visible chunks for `emit` tiles: keep a per-chunk
  list built at mesh time.
- The look track is changing the same shaders (parallax, continuous faces): this track starts
  after it lands, on its result.

## Verification

- `tests/test_light.gd` grows: the covered sky falloff, no own light without a source, carried
  lights follow the selected slot, categories unchanged on every existing check.
- Pictures (CPU renderer, low shadows): the same cave with and without a torch; a sun shaft
  through a hole; a lamp-lit town street at night; a forge monster and a Synty character by a
  torch, before and after; frame time before and after on the GPU reported by the user.
- The user plays it: the one judgement that matters is "do I want a torch?"
