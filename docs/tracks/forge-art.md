# Track: forge art (monster-forge bodies replace the placeholders)

Branch `ws/forge-art`, 2026-11-08. The ask: monster-forge has hundreds of animated monsters now.
Replace the placeholders with them, and keep Synty where it fits (all people, town folk and
player classes, plus any creature whose Synty model is a real match). Investigate, then do it.
Pictures are not in git. They are under `~/.cache/gsfa/` on the dev machine, and the file names
below refer to them.

## Summary

- 311 of 330 SRD monsters are synced from the forge viewer over HTTP: LOD0, 3.5 GB, 20.6 s on the
  LAN. A re-run takes 1-2 s and 2 small requests per unchanged monster. `tools/bootstrap.sh` now
  does this by default.
- Of the 193 slugs the game can place, 146 now draw a forge body (100 were primitives before),
  36 keep Synty, and 11 stay primitives (snakes, worms, drider, grick, behir: no forge rig yet).
- The chain follows the ruling. Forge wins for non-human creatures even over a Synty stand-in
  row. Synty people, humanoid NPC rows and 16 hand-picked good stand-ins stay Synty. Quarantined
  slugs, and bodies that fail to load, fall to the next link.
- Fixed while checking renders:
  - walk playback from the clip's measured ground speed
  - one-unit swarms drawn as 3-8 units
  - forge props in the hand
  - texture memory: 98 MB to 19 MB of video memory per creature kind, 53 MB to about 8 MB of RAM
- Biggest open problem: the game moves monsters about 6.4x faster than SRD real time, and the
  forge walks are 0.35x of SRD speed. Feet need 12-45x playback, so they slide. That needs run
  clips from the forge and/or a decision on game speed.

## What was built (commits on ws/forge-art)

- `5b36863` (earlier session) and `f95d74f`: `tools/sync_monsters.py --http`.
  - Monster files come from the viewer's download API (`/api/download/<id>?lods=0`: name, url,
    bytes).
  - Who counts as usable comes from `/api/index.json`: rig and anim stages done, an idle clip
    and a move clip, not quarantined.
  - Re-runs are idempotent. If the manifest sha256 and every listed size match what was
    recorded, no other request is made. Otherwise a file is fetched only when its size or its
    Last-Modified (HEAD) differs.
  - GLBs are validated in `.incoming/` before they replace anything (magic, JSON chunk, skin,
    animation channels). A broken re-roll keeps the previous copy.
  - `monster.json` records `forge.url`, `manifest_sha256`, each file's bytes and Last-Modified,
    and the index's quality flags. `assets/monsters/_sync.json` records each run.
  - Options: `--all`, `--ids`, `--props`, `--lod` (default 0), `--dry-run`, `--prune`,
    `--force`, `-v`.
  - The local-checkout mode is unchanged.
- `786ebbb`: the looks chain (`view/actors/looks.gd`, `data/looks.json` "forge" block) and
  forge fallbacks in `ActorBody`.
  - A forge body that fails to load (bad GLB, no skeleton, no idle or move clip) falls to Synty
    or a primitive, and the slug is remembered.
  - Walk playback = body speed / clip ground speed, clamped 0.5-2.5x.
  - Swarm mates.
  - Tests in `tests/test_looks.gd`, passing with and without fetched art.
- `944b10c`: forge props (`assets/props/<slug>/model.glb`) on a forge body's `grip_r` bone, and
  `tools/forge_sheet.gd` (proof sheets of bodies as the game builds them).
- `4903095`: `tools/bootstrap.sh` syncs over HTTP by default (`--local`, `--no-monsters`).
  ForgeMonster drops a clip none of whose tracks names a bone of the model, so a half-synced
  re-rig falls back instead of T-posing.
- `1bb4abb`: `GltfCache.instance(path, lod, max_tex)`. Forge textures are scaled to at most
  1024, mipmapped once, and the parsed GLTFState is dropped after the template is built.
- The quarantine is `data/forge_quarantine.json` (slug -> reason, since). Today it holds only
  constrictor-snake: the index reports forge errors and the serpentine plan is on hold. The sync
  skips quarantined slugs; the resolver never shows them.

## The chain as it reads now

For a look `{slug, people?, player?}`, the first available link wins:

- **Forge GLB** (`assets/monsters/<slug>`), when all of these hold:
  - the slug is an SRD creature and not quarantined
  - the look has no player key
  - the look has no people key, or the slug is not a humanoid
  - the slug is not in a Synty-first set (next bullet)
- **Synty-first slugs**: humanoid-type slugs with their own row (guard, mage, bandit...), and
  `looks.json forge.keep_synty`. These try Synty first and take the forge body only when the
  Synty files are missing.
- **Synty row**, then the by_type model.
- **Tinted primitive** with a nameplate.

A drow escort's giant spider carries a people key and still gets its forge spider. A row's tint
and scale no longer leak onto a forge body (they dressed the Synty stand-in).

`keep_synty` today (16 slugs), each with its reason in the file:

- Real matches: wolf, brown-bear, boar, deer, elk, riding-horse, skeleton, zombie, ghost,
  wight, goblin-minion, goblin-warrior, goblin-boss.
- Forge reads worse:
  - medusa: the snake hair is a detached green mass beside the body
  - stone-golem: reads as painted armour
  - iron-golem: reads as a knight

Judged on `compare_forge.png` against `compare_synty.png` (32 slugs) and `doubtful.png`. Tinted
reuses went to forge: dire-wolf, winter-wolf, polar-bear (still brown in Synty), black-bear,
giant-boar, draft-horse, warhorse, giant-elk, goat (the Synty goat lies on its side).

## Inventory of placeholders (before this branch, without forge art)

Sources:
- `tools/spawn_sim.gd`: seeds 4, 7 and 11, 8 minutes each, plus a settlement run; 1638
  creatures.
- `tools/ecology_report.gd`.
- 2000 `build_pack` draws.
- Lairs read from `data/sim/lairs.json`.

### What the game places

- 193 of 330 slugs can be placed:
  - 162 by the spawn director
  - 48 by lairs (12 of them lair-only: aboleth, dretch, gibbering-mouther, hill-giant, imp,
    lamia, lemure, purple-worm, wyvern, young black, green and red dragons)
  - 34 by life and the sim (town folk, caravans, patrols, raids, armies)
  - 9 by director raiders
- 137 are never placed:
  - 49 lair-only with no lair row (every adult and ancient dragon, the wyrmlings, lich, vampire,
    sphinxes, cloud and storm giants, tarrasque, kraken, roc, dragon-turtle)
  - 39 fiends and celestials behind portals
  - 38 wild creatures no band, biome or CR picks (dinosaurs, treant, frost-giant, unicorn,
    pegasus, griffon, mammoth; the sea creatures of the not-generated coast and tundra biomes)
  - 7 people blocks no culture uses
  - 4 with spawn = none
- Most met (spawn_sim count) and what they were:
  - goblin-minion 90, goblin-warrior 84: Synty goblin
  - darkmantle 69: primitive
  - rat 57: primitive
  - skeleton 55: Synty
  - hobgoblin-warrior 39: goblin knight, tinted
  - zombie 38: Synty
  - giant-rat 37: primitive
  - ghoul 35: zombie, tinted
  - giant-spider 30: primitive
  - specter 23: ghost, tinted
  - hyena, jackal and raven 21 each: primitive
  - kobold-warrior 19: goblin, tinted
  - spider 19: primitive
  - stone-golem 19: Synty
  - warhorse-skeleton 19: a live horse, tinted
- Lairs add, by weight: wolf packs, ogre, owlbear, troll, manticore, the undead barrow,
  giant-spider plus ettercap, grick, darkmantle, oozes, roper, cloaker, drider, black-pudding,
  otyugh and chuul.

### What the 193 resolved to without forge

- 67 had their own Synty row, 26 a by_type model, 100 a primitive.
- Real matches (27): wolf and its tints, the bears, boars, deer, elk, giant-elk (moose), goats,
  horses, skeleton, zombie, ghost, troll (a Synty troll, not the SRD's), medusa, stone and iron
  golem, the goblins, hill-giant, dryad, wight.
- Loose analogues (22):
  - kobold (tinted goblin)
  - hobgoblins (goblin knight)
  - bugbears (orc)
  - gnoll (pig butcher)
  - ogre, ogre-zombie, flesh-golem, fire-giant and stone-giant (all the barbarian giant)
  - clay-golem and shield-guardian (golem reuse)
  - ghoul, ghast and mummy (tinted zombie)
  - vampire-spawn (tinted peasant)
  - specter and wraith (tinted ghost)
  - minotaur-skeleton (armoured skeleton)
  - warhorse-skeleton (a live horse)
  - werewolf (a human hunter)
- The by_type stand-ins (26) were all poor:
  - giant-eagle and giant-owl drawn as a priest
  - worg, blink-dog, centaur, satyr, sprite and the hags as the forest witch
  - imp, lemure, dretch, hell-hound and lamia as the red demon
  - gargoyle, xorn, earth- and fire-elemental and salamander as the elemental golem
  - gorgon, animated-armor and the rug as the iron golem
  - shadow, will-o-wisp and crawling claws as a skeleton
- Primitives (100): every aberration, beast without a row, dragon, monstrosity, ooze and plant.

### Now, with 311 synced

- 146 forge.
- 36 Synty:
  - the 18 human NPC blocks (they only ever arrive with a people key)
  - the 16 keep_synty slugs
  - lamia and xorn (by_type, no forge body yet)
- 11 primitives: behir, constrictor-snake, drider, flying-snake, giant-constrictor-snake,
  giant-venomous-snake, grick, purple-worm, scorpion, swarm-of-venomous-snakes, venomous-snake.

### Humans and people (staying Synty; listed only to confirm)

- 13 `player*` rows and 48 `people:*` rows, all Synty models.
- The 18 humanoid blocks the game places (bandit, bandit-captain, scout, spy, assassin, tough,
  tough-boss, mage, priest, priest-acolyte, warrior-infantry, warrior-veteran, guard,
  guard-captain, knight, noble, commoner, berserker) always come with a people key.
- The only humanoid-type slug that reaches the view as a bare slug is `vampire-familiar`
  (director), which now takes its forge body. The debug `spawn=SLUG` also makes bare-slug
  looks.
- Goblinoids, kobolds and gnolls are SRD fey, dragon and fiend, not humanoid. They arrive as
  bare slugs, so forge covers them except the goblins in keep_synty.

### Weapons, dressing, buildings

- Weapons: 32 rows, all Synty meshes. 6 SRD weapons have none: dart, sling, whip, blowgun,
  musket, pistol. Loot can roll dart, sling and whip (bar placeholders in the player's hand).
  The forge has whip and pistol props (open item below).
- Forge props: 32 synced (16 MB). Forge monsters now hold them: 68 synced monsters have
  `wields` and a `grip_r`.
- Dressing (`data/dressing.json`, 117 objects):
  - 82 name a Synty model; 21 of those also have a primitive fallback, and 61 draw nothing
    without the file
  - 35 are primitive-only (fungal, crystal, drip, magma, dark-rock and drow décor)
  - out of forge's scope
- Buildings: tile shells. 32 piece ids, all Synty; 18 have a primitive fallback and 14 are
  skipped when missing. Out of scope.

## Coverage (forge index, generated 2026-11-08 07:21 and 07:40)

- 330 SRD monsters: 315 rigged, 312 rig+anim, 308 anim_complete.
- The 4 rig+anim monsters that are not complete only miss optional clips:
  - centaur-trooper, djinni, manticore: no attack_ranged
  - gibbering-mouther: no swim
- No forge body yet (18):
  - no rig: behir, couatl, drider, flying-snake, giant-constrictor-snake,
    giant-venomous-snake, grick, guardian-naga, lamia, plesiosaurus, purple-worm, scorpion,
    spirit-naga, swarm-of-venomous-snakes, venomous-snake
  - rigged, no anims: giant-seahorse, seahorse, xorn
- constrictor-snake: rig+anim, but the index reports 2 forge errors. Quarantined.
- Known defects, per the index:
  - `rig_quality.problems` is set on 130 monsters (legs, leg_pairs, spine, tail, wings). It is
    noisy: the wolf-family rigs and every dragon carry flags and still read well on the sheets.
    So it is a warning in the sync log, not a quarantine reason.
  - `facing.ok` is false on 8: adult-brass-dragon, ancient-brass-dragon, gorgon,
    ancient-white-dragon, black-bear, giant-hyena, giant-scorpion, pteranodon. The sheets show
    them facing the right way after the game's PI turn; worth a look by the owner.
- Known defects, per the forge's HANDOFF (2026-11-07):
  - winged quadrupeds that fly with one wing or none: being fixed upstream
  - needs a GPU re-rig: ancient-silver-dragon, adult-red-dragon, young-silver-dragon,
    pseudodragon, hippogriff, adult-bronze-dragon, brass-dragon-wyrmling, remorhaz, rat,
    bronze-dragon-wyrmling, bulette, crocodile, giant-toad, giant-scorpion, polar-bear,
    salamander
  - swim stretch on five ancient dragons
  None of these reads worse than the primitive or tinted analogue it replaces at the game's
  distance, so none is quarantined. The owner can add any with a reason.
- **Moving target, observed during this session.** At 07:40, 73 rigify bipeds served only
  `anims/walk.glb`: the UAL re-animation was in progress, with `anims_ual/` dirs appearing. The
  sync reported them "skipped (no idle clip)" and kept the earlier complete local copies. That
  is the intended behaviour, but it means the bipeds on this machine are the pre-UAL
  SkinTokens versions. A re-sync after the forge settles brings the UAL ones in.

## Measured costs

- Download, LOD0 (`/api/download?lods=0`): 3.70 GB for 315. On disk: 3.5 GB for 311, plus
  16 MB of props.
- With LOD1-3: 3.94 GB, i.e. LODs add 0.23 GB. Not fetched: the user asked for LOD0 only, and
  the loader does not use them.
- Sync time: 20.6 s for 1.7 GB new (LAN) and 3272 requests.
- Re-run with nothing changed: 1.0-1.8 s, 616-752 requests, 8-10 MB (mostly the 1 MB index and
  the manifests).
- Load time per kind, first instance (`speed_probe.tsv`, headless, 286 forge kinds):
  - median 236 ms, p90 269 ms, max 1170 ms
  - under CPU Vulkan with textures shrunk: about 330 ms
  - a second instance of a kind: about 3 ms (GltfCache template)
  - tiny creatures (bats, piranhas): 80-95 ms
  - the cost is the PNG decode of three 2048 maps
- Memory with many on screen (`crowd_probe`, 10 kinds × 4 = 40 bodies, CPU Vulkan):
  - before `1bb4abb`: video memory +981 MB, RAM +535 MB
  - after: video memory +189 MB (19 MB per kind), RAM +86 MB
  - animation step for 40 bodies: 0.25 ms per frame (AnimationPlayer, manual advance)
  - CPU Vulkan frame times are not meaningful; headless: 6.5 ms
- LOD switching: not needed for the game's distances. Bodies are 40-60 px tall at the default
  camera, and the forge's LOD0 is 4-15 k tris. Not built.
- Instancing: not needed for dozens. 40 skinned bodies cost 0.25 ms of animation; draw calls
  are one or two surfaces each. A real swarm-of-hundreds would want a MultiMesh of a baked
  pose, which the game does not do today.

## PoC: the sync, and a sample log

Sample of 10 diverse monsters (`~/.cache/gsfa/sync_sample1.log`, then `sync_sample2.log`).
Most were already present from the earlier session; this run added `anims/clips.json`,
switched them to LOD0, and fetched the four new ones:

- goblin-warrior: updated (4 files, 3.5 KB)
- ape: updated (4 files, 3.2 KB)
- wolf: updated (4 files, 3.1 KB)
- young-red-dragon: added (9 files, 12.9 MB)
- black-pudding: updated (4 files, 1.9 KB)
- aboleth: updated (4 files, 2.9 KB)
- swarm-of-rats: added (7 files, 14.9 MB)
- ghost: updated (4 files, 2.2 KB)
- shrieker-fungus: added (7 files, 8.2 MB)
- owlbear: added (7 files, 14.5 MB), with the warning `rig_quality spine`
- 3 props updated
- done in 0.7 s: 108 requests, 51.5 MB downloaded

The second run: `{'unchanged': 13}` in 0.2 s, 33 requests, 1.1 MB (the index).

The full run (`sync_all.log`): `{'skipped': 18, 'quarantined': 1, 'unchanged': 13,
'updated': 151, 'added': 179}`, 20.6 s, 1.7 GB.

## How the samples read (renders)

Each picture was looked at, and close-ups were cropped. Sheets are drawn by
`tools/forge_sheet.gd` through ActorBody: yellow frame = collision box, brown line = ground.

### The sample set (`sample_{idle_day,walk_day,attack_torch,death_torch}.png`)

- goblin-warrior: feet on the ground, faces +X, a sensible 1.0 m in its small box. Now Synty by
  keep_synty.
- ape (UAL-verdict biped, still the SkinTokens rig here): reads well; the walk is a crouched
  knuckle walk.
- wolf: excellent, in every state.
- young-red-dragon: excellent, both wings up, inside the box.
- black-pudding: a flat blob with tendrils. Fine. The death clip flattens it almost to nothing.
- aboleth: reads well but floats a body-height above the ground at idle (its move clip is
  swim). Right in water, odd on land.
- swarm-of-rats (made as one mesh): good.
- ghost: good. The death clip leaves its cell toward +X.
- shrieker-fungus: good. In death it falls toward the camera, showing its cap face-on.
- owlbear and griffon: excellent.
- draft-horse: good, with a saddle.

### The 48-monster proof sheet (`sheet_idle_day.png`, every body plan)

- Everything faces +X and stands on the ground. Fliers and swimmers hover above it, as their
  idles do.
- Bad: one-unit swarms (bats, insects, piranhas, claws) were a single tiny unit in a large
  box, invisible at game distance. Fixed with mates (`swarms.png`): ravens and piranhas now read
  as swarms; bats, insects and claws are still small, because their units are small.
- marilith, salamander, aboleth and air-elemental fill their box height via the 1.15x clamp
  and read thin but correct.
- The box clamp (height ≤ 1.15 × box, length ≤ 2.2 × box) shrinks huge and gargantuan
  creatures to about 0.33-0.6. Dragons and giants then look smaller than their SRD size, which
  is the clamp doing its job.

### Torch light

LitMaterials works on forge bodies. Warm and readable, with no black materials
(`sample_attack_torch.png`).

### Mixed scenes (`world_hobgoblin-warrior_day.png`, `crop_hob.png`, `world_owlbear_day.png`)

- The Synty hero and the forge hobgoblin are the same height and face each other.
- Styles differ: Synty is flat and low-poly; forge is painted and saturated. At 40-60 px this
  is a mild difference, not a clash.
- The owlbear reads as big and right.

### Weapons (`weapons_idle.png`, `weapons_attack.png`)

- Forge props sit in the grip, point forward and follow the swing: hobgoblin longsword, azer
  warhammer, centaur pike, minotaur glaive, merrow harpoon, giant greatclubs.
- The gnoll's longbow lies horizontal at idle (vertical in the attack).

### Doubtful bodies (`doubtful.png`)

- medusa, stone-golem, iron-golem: worse than Synty, so keep_synty.
- werewolf: a coat-wearing wolf-man with a stray thin black line from its snout and a pale
  smoky tail. Still far better than the Synty hunter it replaced.

## The walk-speed finding (the 0.38 claim)

- The claim holds. Measured by forward kinematics on the planted feet listed in
  `anims/clips.json`, for 220 of 286 forge kinds; the others have no feet (fliers, swimmers,
  oozes).
  - The walk's ground speed is median 0.35x the SRD walk speed in real time (p10 0.16, p90
    0.71).
  - Examples: goblin-warrior 0.30 m/s (0.19x), wolf 0.68 m/s (0.33x), ogre 1.12 m/s (0.55x).
  - Slowest: rat 0.035 m/s, giant-spider 0.22 m/s, and the other small multi-legged ones.
- It is not the main problem. The game runs a 30 ft body at 13 tiles/s = 9.75 m/s
  (`data/movement.json run.tiles_per_s_per_30ft`), 6.4x SRD real time. Monster AI moves at full
  run speed.
  - Keeping feet planted would need 11.6-45x playback (median 22x); the rat would need 185x.
  - The Synty humans have the same issue, only milder: their 6 m/s sprint plays 1.6x at
    9.75 m/s.
- What the game does now (`786ebbb`):
  - playback = body speed / (ground speed × scale), clamped 0.5-2.5x
  - standing below 0.25 m/s plays idle
  - kinds without a measured ground speed are scaled by height, like Synty
  - result: right at slow speeds, a brisk cycle with sliding feet at chase speed
- Proper fixes, in order:
  1. Forge: export `ground_speed_mps` per clip in clips.json (the HANDOFF already proposes it),
     and give every walker a run clip (UAL Jog_Fwd / Sprint for bipeds, a procedural gallop for
     quadrupeds) at 3-5x walk speed. The game would then switch walk to run like it does for
     Synty.
  2. Game: decide whether monsters really chase at 6.4x SRD speed. Wandering at a walk (say
     0.3 of run speed) would let the walk clips play near 1-2x.

## Humans and humanoid monsters

- People stay Synty (see the chain). No player-character pipeline here.
- Humanoid-shaped creatures forge now covers (none of them people):
  - goblinoids other than goblins (hobgoblins, bugbears), kobold, gnoll
  - ogres and giants (hill, stone, fire)
  - undead: ghoul, ghast, mummy, vampire-spawn, specter, wraith, minotaur-skeleton,
    ogre-zombie, shadow
  - flesh-golem, clay-golem, shield-guardian
  - fiends: imp, lemure, dretch
  - werewolf, wererat, hags, satyr, sprite, doppelganger, green-hag, sea-hag
- UAL clip mapping (forge `docs/anim-reuse.md`):
  - idle = Idle_Loop, walk = Walk_Loop, run = Jog_Fwd_Loop (or Sprint_Loop),
    attack = Sword_Attack and Sword_Regular_A/B/C, hit = Hit_Chest/Head, death = Death01
  - UAL1 also has Jump_*, Swim, Roll and Crouch; UAL2 has Climb, Slide and Zombie_Idle/Walk
  - fly, swim, breath, burrow and attack_ranged stay procedural
- The game's states that Synty lacks clips for are climb, swim and jump/fall (and roll exists).
  UAL has all four for bipeds. Today the forge exports only idle, walk, run (some), attack_*,
  hit, death, plus procedural fly, swim, burrow, breath, cast.
  - Ask the forge to export `climb`, `jump`, `fall` and `swim` from UAL for bipeds.
  - ForgeMonster.play already maps jump/fall to fly else idle, swim to swim else the move clip,
    and climb to the move clip. It picks the real clips up the moment they exist.
- Coherence: same height class as Synty people (the box clamp and the forge's metric scale_m
  agree). The painted style is visibly richer than Synty's flat palette, but it reads as one
  world at game distance (`crop_hob.png`).

## Props and weapons

- Forge props replace the weapon placeholders on forge bodies: end to end, checked on 12
  wielders. Prop space matches `looks.json weapons.forge_grip` (rot 0, offset 0) with no
  tuning. Props are scaled by wielder height / 1.8, or rider_height_m for centauroids.
- Not done:
  - Using forge props in Synty people's hands. The grip conventions differ (`weapons.grip`
    rot 90°), and the Synty meshes are fine there.
  - The 6 weapons without a row: the forge has whip and pistol props. A row pointing at
    `assets/props/whip/model.glb`, or a WeaponMesh fallback to the forge prop, would cover
    them for players (small, next).
  - Shields (forge `shield` prop, `shield: true` in monster.json): not mounted.
- Wields come from the forge registry of a local monster-forge checkout. Here that checkout is
  behind origin, so a few `wields` may be stale until the registry is served over HTTP (ask the
  owner), or until the sync reads `git show origin/master:` of it.

## Prioritised migration plan

1. **Done (this branch).** HTTP sync, the chain, fallbacks, walk speed, swarms, props,
   texture memory, bootstrap. Low risk: everything falls back, and the tests pass with no art.
2. **Re-sync when the forge settles (this repo, minutes).**
   - Run `tools/sync_monsters.py --http --all`, or `tools/bootstrap.sh`.
   - It brings in the UAL bipeds (73 are mid-change upstream now), any newly rigged serpents,
     and fixed dragons.
   - Then re-run `tools/forge_sheet.gd pick=48` and look at it; adjust `keep_synty` and
     `data/forge_quarantine.json`.
   - Check that the forge goblins are not better than Synty's after UAL.
3. **Run clips and ground speed (forge owner, then this repo, small).**
   - Forge: `ground_speed_mps` in clips.json; `run` for every walker; UAL `climb`, `jump`,
     `fall`, `swim` for bipeds.
   - This repo: read `ground_speed_mps` when present (skip the FK measure) and switch walk/run
     by speed.
   - Medium risk: the forge's procedural gallop is new work.
4. **Spawn hitch (this repo, small to medium).** A first sight of a kind costs about 240-330 ms
   on the main thread.
   - Pre-warm the kinds a biome or lair can spawn (`GltfCache.instance` in a WorkerThreadPool
     task when a chunk band is entered), or load on a thread and show the primitive until it
     is ready.
   - Alternatively, the forge ships 1024 textures (or KTX2/Basis), which also halves the
     download.
5. **Serpentine, centauroid and worm bodies (forge owner).** Covers the 11 remaining
   primitives, among them flying-snake, venomous-snake, drider and behir, which spawn often.
6. **Small polish (this repo):**
   - aboleth and other swimmers float on land; a grounded idle offset when not in water
   - bat and insect swarms: more and larger mates
   - whip and pistol rows from forge props
   - mount shields
   - the gnoll's bow orientation at idle

## Re-syncing later (finalising)

- Command: `tools/sync_monsters.py --http --all`, or `tools/bootstrap.sh` (also refreshes
  Synty and fonts).
  - Set `MONSTER_FORGE_URL` if the viewer moves.
  - `--dry-run` first shows what would change and its size.
- What a re-sync changes:
  - Monsters whose manifest sha256 or file sizes changed: changed files are re-fetched and
    validated before replacing anything.
  - New usable monsters are added.
  - Monsters no longer usable upstream (mid re-rig, lost idle) are **kept as they are**; the
    log says "kept". `--prune` deletes them.
  - A monster that fails validation keeps its previous copy and is reported as failed (exit
    code 1).
  - `assets/monsters/_sync.json` lists the status of every id. Each `monster.json` has
    `forge.manifest_sha256`, to diff against a later run.
- After a re-sync:
  - `tools/test.sh looks` (must pass)
  - `tools/soft_godot.sh -s res://tools/forge_sheet.gd -- out=~/sheet.png pick=48`, and look
    at it
  - update `keep_synty` and `data/forge_quarantine.json` by eye

## Risks and decisions for the user

- **Fallback chain.** Forge for non-human creatures; Synty for people, humanoid NPC rows and
  `keep_synty` (16); primitive last. Synty stand-in rows stay in looks.json as the fallback for
  machines without forge art. Decision: is the keep_synty list right? In particular goblins,
  wolf and skeleton, which are both good and among the most-met.
- **Speed.** Do monsters chase at 6.4x SRD speed? It drives the foot-sliding fix.
- **Licensing.**
  - The forge art derives from SRD 5.2.1 (CC-BY-4.0). Any distributed build that includes it
    must carry the attribution in monster-forge's README "License and attribution"; Godspark's
    README already has an SRD notice.
  - UAL clips are CC0.
  - Open question: the forge's reference images name an artist's style in the prompt ("Kim
    Jung Gi style"), and the generator models have their own licenses (JuggernautXL / SDXL
    derivative; `pixal3d` for meshes). Check before distributing.
  - Synty may not be redistributed as source (already handled: fetched, never committed).
- **Moving target.** Pinning is by manifest hash per monster, recorded in monster.json. The
  index carries no forge commit; ask the owner to add `commit` to `/api/index.json`, so
  `_sync.json` can name the forge revision.
- **Where art lives.** `assets/monsters`, `assets/props` and `assets/meshes` are git-ignored,
  with a `.gdignore` (never imported by the editor). Nothing in this branch commits art (checked
  with `git status`).
- **Export.** There is no `export_presets.cfg` yet. When there is one, it must include
  `assets/monsters/**` and `assets/props/**` as non-resource files: the game loads them at
  runtime with GLTFDocument, and the `.gdignore` hides them from the importer. Decide whether
  shipped builds bundle forge art (3.5 GB at 2048 textures; about 1.2 GB if the forge ships
  1024) or fetch it on first run.

## Deviations, open issues, honesty notes

- Found by the inventory, not fixed (pre-existing, outside this scope): `Looks.keys_for` tries
  the slug before the people key. So `{slug: "scout", people: "elf:drow:scout"}` resolves to
  the `scout` row (human hunter), and most elf, dwarf, gnome and halfling people rows are never
  reached for slugs that have their own row. Worth a small fix in the people track.
- Looks built with `slug = "player:<class>"` (`core/host/world_host.gd:242`) are not SRD slugs.
  The forge rule now ignores them.
- `git fetch` was run once in `~/workspace/monster-forge` to read `origin/master` docs. It
  updated only its remote-tracking refs; nothing else was touched there.
- The bipeds on this machine are pre-UAL (see Coverage). The UAL rig has not been loaded in
  Godot yet.
- Frame-time numbers come from CPU Vulkan, so only memory and animation step costs are
  meaningful.
- Pictures: `~/.cache/gsfa/*.png`; probes and logs under `~/.cache/gsfa/`.
