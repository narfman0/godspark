# Track A: world generation and saving

Branch `ws/worldgen`. Everything here is in `core/` (RefCounted only, deterministic) apart
from the two tools.

## What was built

| File | What |
|---|---|
| `core/world/worldgen/world_gen.gd` | `WorldGen`: the stage list, `generate()`, `generate_named()`, `rng_for()`, `SIZES`, `grids()`, `last_timings` |
| `core/world/worldgen/gen_context.gd` | scratch state for one run: u8 tile and wall grids, bands, notes between stages, carve helpers, `to_world()` |
| `core/world/worldgen/stage_*.gd` | the stages (static functions), see below |
| `core/world/world_save.gd` | `WorldSave.save()` / `WorldSave.load()` |
| `data/worldgen/biomes.json` | surface biomes for the strip (only `meadow` for now) |
| `data/worldgen/ores.json` | ore veins: tile, depth range, density, vein size, host rock |
| `data/tiles.json` | appended tiles 16-20 (`copper_ore`, `iron_ore`, `silver_ore`, `cobblestone`, `slate`) and walls 8-9 (`slate_wall`, `cobble_wall`) |
| `tools/worldmap.gd` | PNG of a world, with sites and routes drawn over it |
| `tools/worldgen_sweep.gd` | runs the invariants in `tests/test_worldgen.gd` over many seeds |
| `tests/test_worldgen.gd`, `tests/test_world_save.gd` | see "Tests" |

### Stages (in order; the name is the RNG key)

| Stage | Does |
|---|---|
| `biomes` | splits the width into a biome strip from `biomes.json` (weighted picks, min/max widths, equal neighbours merged, no slivers at the edge). With one biome it is one segment. |
| `surface` | heightmap: three octaves of hills plus smooth mountains where a slow mask noise is high, scaled per column by the biome's `hill` (box-smoothed across biome edges). One flat stretch (48-80 tiles) is planned per `width / 340` slot for settlements and blended into the hills. Neighbouring columns never differ by more than 3. |
| `layers` | per column: bedrock (2-4 rows), slate below the deeps line (noisy), stone, biome soil (6-14 deep), the biome top tile. Walls behind everything below the top tile (slate, stone, soil walls). Soil pockets in the upper stone. |
| `caves` | noise caves (fbm blobs plus domain-warped "spaghetti" ridges gated by a third noise), densest in the caves band, sparser deeper, none in a 12-22 tile crust under the ground. Long, mostly level worm tunnels in the caves band and wider ones in the deeps. A few entrance worms break the surface (kept 50+ tiles from settlement flats). |
| `caverns` | `5 * width / 2048` very large caverns in the deeps band (radii ~48-75 tall, 2-3.4 times as wide), lobed by two noises, each with a guaranteed open and level plateau in the middle of a flat floor that curves up to the walls, and two stalagmite pillars. Neighbouring floors are kept within reach of a road that climbs at most one tile per three columns. The biggest `max(2, n / 4)` are marked settled. |
| `deep_road` | the deep road: a paved tunnel 6 tiles clear (`ROAD_H`), level across every cavern plateau, smoothstep-plus-noise between them, never steeper than one tile per column, from the first cavern's plateau to the last's. Floor is `cobblestone` (it bridges gaps), wall is `cobble_wall`. |
| `ascent` | a 45-degree paved ramp, 5 tiles clear (`RAMP_H`), with short level landings, from a settled cavern's plateau up to the surface. 24 candidates per settled cavern (start offset, direction, landing frequency) are simulated; the chosen one surfaces close to a settlement flat but never inside one, and its shallow tail never runs under one. Ramps pave only over rock, so they never wall off a cavern or cave they cross. |
| `portal` | a chamber in the nadir band, reached by a ramp down from a cavern plateau (preferring an unsettled cavern near the middle). |
| `ruins` | 1-3 buried ruin rooms (cobblestone floor, broken walls, pillars) in the caves band, kept away from anything built (roads, ramps). |
| `ores` | random-walk veins per `ores.json`: copper (upper), iron (middle), silver (deep). Only the listed host rock is replaced. |
| `finish` | surveys the surface (highest solid tile per column) and grows the top tile on soil left exposed at a column's top. |
| `sites` | settlements on each flat that survived (level over 80% of it, 8 tiles of headroom), deep settlements in the settled caverns, the portal, a surface ruin, the buried ruins, cave lairs (open pockets with a floor, spread apart). |
| `routes` | `road` between neighbouring surface settlements (by x); `deep_road` between neighbouring deep settlements along the road, from the ascent's deep settlement to the surface settlement nearest the ramp mouth, and from the nearest deep settlement down to the portal. |

## API as built

```gdscript
WorldGen.generate(width: int, height: int, seed: int, opts := {}) -> TileWorld
WorldGen.generate_named("dev" | "small" | "medium" | "large", seed, opts := {}) -> TileWorld
WorldGen.SIZES          # dev 2048x1024, small 4096x1536, medium 8192x2560, large 16384x4096
WorldGen.rng_for(seed, stage_name) -> RandomNumberGenerator   # SHA-256 of "godspark/<seed>/<name>"
WorldGen.last_timings   # {stage: msec, "pack": msec, "total": msec} of the last run
WorldGen.grids(world) -> [fg: PackedByteArray, bg: PackedByteArray]   # u8 per tile, for maps
opts: {"stop_after": "<stage>"}   # debugging: stop early (meta still filled)

WorldSave.save(world: TileWorld, dir: String) -> Error
WorldSave.load(dir: String) -> TileWorld        # null if missing, unreadable or corrupt
```

Adding a stage: write a static `func name(c: GenContext, rng: RandomNumberGenerator)` and
add `[name, script, method]` to `WorldGen.STAGES` where it belongs. Renaming a stage
changes every world (the name is the RNG key).

### meta, as filled

```
surface: [int] * width        highest solid tile per column (after all carving)
biomes:  [{x0, x1, biome}]    covers 0..width-1 in order
bands:   {sky, surface, caves, deeps, nadir: [y0, y1]}   inclusive, contiguous, 0..height-1
         (cuts at 14%, 42%, 66%, 83% of the height; the Underdark is deeps + nadir, 42%)
sites:   [{id, kind, x, y, biome, band, size}]
routes:  [{id, a, b, kind, length}]
```

Conventions the schema leaves open:
- Site `y` is the feet row: the first open tile, with solid ground at `y - 1`.
- Site `biome`: the strip biome for surface sites, `"caves"` for the caves band,
  `"underdark"` for deeps and nadir.
- Site `size`: settlements = width of the flat ground in tiles (deep: about the cavern
  floor width); ruins = room width (12 for the surface ruin); portal = chamber width;
  lairs = 8 (a radius).
- Route `length` is walking distance in tiles along the actual path (surface profile, deep
  road floor, ramp steps), not straight-line distance.
- A route linking a deep site to the surface has kind `deep_road` (it is a tunnel).
- Site and route ids are their index in the arrays.

### Save format

```
<dir>/world.json         {format: 1, width, height, seed, region: 16, meta}
<dir>/r_<rx>_<ry>.bin    "GSR1", then for each chunk of the 16x16-chunk region in row order
                         (cy, then cx): u8 modified, u32 length, Chunk.to_bytes() blob
```

Each file is written as `<name>.tmp` and renamed into place; `world.json` goes last. Loading
turns JSON floats that are whole numbers back into ints, so `meta` compares equal. The
chunk `modified` flag is saved. A dev world saves to 246 KB in 9 ms and loads in 7 ms; small is 703 KB, 29 ms / 27 ms.

## Deviations from architecture.md

- **Writes don't go through the `quiet` setters.** Stages write flat u8 grids in a
  `GenContext`; `to_world()` packs them into chunks at the end (R8 to RG8 image conversion
  gives the u16 little-endian layout; `Image.get_region` cuts the chunks), assigning
  `chunk.fg` / `chunk.bg` directly through `chunk_at()`. No signals are emitted (the same
  as quiet writes) and chunks are left unmodified. This is what makes generation fast.
  TileWorld, Chunk and TileDefs were **not changed**.
- Tile ids during generation must be below 256 (the grids are u8). All worldgen ids are
  16-63, so this only matters if a later stage wants a tile from 256 up.
- `WorldGen` has extras beyond the contract (`generate_named`, `SIZES`, `rng_for`,
  `grids`, `last_timings`, `opts.stop_after`), all additive.
- An extra tool, `tools/worldgen_sweep.gd`.

## Tests

`tests/test_worldgen.gd` (seven worlds: 512x256 for seeds 7, 8, 3, 21, 99, 12345 and
1024x512 seed 5): the same seed gives the same `content_hash` and meta, different seeds
differ, and stage RNGs are stable and independent. Then for every world:
- the meta keys are present and survive JSON
- `surface[x]` really is the highest solid tile in every column
- the biome strip and the bands cover the world exactly
- site and route keys match the schema, kinds and bands are valid, ids are unique
- every site stands on solid ground with room above it
- settlements have 6 rows of headroom and a solid floor across 17 columns
- there are at least 2 surface settlements, 1 deep settlement, 1 portal, lairs and ruins
- every route's endpoints exist; roads and deep roads exist; one route links the deep to
  the surface and one links two deep sites
- every deep route (between deep sites, and deep to surface) passes a flood fill through
  cells with 4 open tiles above them, end to end. This proves the deep road and the
  ascent are open to something wagon-tall, ignoring gravity.

`tests/test_world_save.gd`: a round trip keeps `content_hash`, meta (ints stay ints),
size, seed and modified flags; saving over an existing save works; a missing directory,
a truncated region and a corrupt `world.json` all load as null; no temp files are left.

Seed sweeps with the same checks (`tools/worldgen_sweep.gd`), all with 0 failures:
100 seeds at 512x256, 60 at 1024x512, 30 at dev (2048x1024), 6 at small (4096x1536).

## Measured

Generation time from `WorldGen.last_timings["total"]`: all stages plus packing into
chunks, excluding Godot startup and PNG rendering. Headless, on this machine, final code.

| Size | Tiles | Generate | Biggest stages | Peak RSS (worldmap tool) |
|---|---|---|---|---|
| dev 2048x1024 | 2.1 M | 592-617 ms (seeds 1-3) | caves 375-394, layers 111-116, caverns 62-67 | 137 MB |
| small 4096x1536 | 6.3 M | 1747-1778 ms (seeds 1-3) | caves 1142-1178, layers 340-345, caverns 147-163 | 164 MB |
| medium 8192x2560 | 21 M | 5648 ms (seed 1) | | 306 MB |
| large 16384x4096 | 67 M | 17667 ms (seed 1) | caves about 13 s | 753 MB |

The whole test suite (8 worlds generated, flood fills, save round trip) runs in about
2.5 s.

`caves` dominates. That stage is the per-tile threshold loop over three noise grids in
GDScript; the noise itself is sampled in C++ through `FastNoiseLite.get_image`, which is
cheap. Medium and large were only generated and looked at for one seed each; the invariants weren't swept at those sizes.

## Known weaknesses

- **One surface biome.** The strip machinery works but has only been exercised with
  `meadow`. The per-biome `hill` factor is the only biome hook in the heightmap.
- **The deep band is one line.** Caverns sit in a single row along the deep road. In tall
  worlds (medium, large) most of the deeps band and all of the nadir is just noise caves
  and solid slate. There are no deeper tiers yet, no liquids, and no deep biomes.
- **The ascent is a straight 45-degree ramp** with landings, not a winding route. Big
  worlds still get only one ascent.
- **Traversal is checked for "open", not "walkable".** The flood fill ignores gravity:
  noise caves and worms can leave drops a player can't climb back up without digging.
  Ramp floors that cross a cave have holes (ramps only pave over rock).
- Settlement flats are planned before carving, and a site whose flat was damaged is
  dropped rather than repaired. The sweeps never saw it, but small worlds then have
  fewer settlements.
- Lairs are only placed in the caves band. No lairs in the deeps yet.
- The surface ruin is a site with no tiles behind it (nothing is built there).
- Ore placement ignores caves (veins can sit next to open air, which is fine) and has no
  size scaling with world height.
- `gen_context.gd` u8 grids cost 2 bytes per tile, plus up to three noise grids of 1 byte
  per tile during `caves`. Large peaks at about 750 MB RSS in the worldmap tool.

## What the next worldgen pass should do

1. More surface biomes (forest, hills/alpine, desert, swamp): rows in `biomes.json`,
   with stage hooks for trees and other dressing, biome-specific soil and caves.
2. Liquids: water pools in caves, an underground sea or lake in the nadir (the aboleth
   sea in plan.md), lava near the bottom. `Chunk.liquid` is still all zero.
3. Deeper Underdark tiers: a second cavern row in the nadir with its own road, linked
   by shafts. Deep biomes (fungus forests) and cavern dressing (stalactites, fungus
   tiles).
4. More ascents in big worlds (one per few deep settlements), and winding ones.
5. A gravity-aware reachability check (jump height, step-up) on the main routes, and
   ladders or platforms where a route needs them (Track C's tiles 8-15).
6. Settlement footprints: stamp building templates onto the flats (M4), and give the
   surface ruin real broken walls.
7. If generation gets slow: move the `caves` per-tile loop to a GDExtension, or split
   the noise into chunk-sized windows and run them on `WorkerThreadPool` (stages are
   pure, so that would stay deterministic).
