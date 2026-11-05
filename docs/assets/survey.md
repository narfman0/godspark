# Synty pack survey (Track G)

Source: the asset server's `index.json` (154 cooked packs, read 2026-11-05) plus probes of a
small sample. Sizes come from the glTF JSON alone (accessor min/max through the node graph,
no `.bin` fetched) and, for characters, from runtime loading with `tools/asset_probe.gd`
(skinned meshes measured where the skin draws them). No images are committed; screenshots
live outside the repo.

## The tile metric decision

**`K.TILE_M` stays 0.75 m.** Synty is used at scale 1.0 for people and for the standard
building kits; the 5 m castle and dungeon kits get a per-pack scale of 0.75.

Measured numbers:

| What | Measured | In tiles at 0.75 m |
|---|---|---|
| Synty humans (Knights soldier 1.88, knight 1.93 with crest, Fantasy Characters peasant 1.82, locomotion reference 1.79, Rivals dark elf 1.83) | about 1.8 m | 2.4 |
| Medium collision box (Track C) | 1.5 x 2.5 tiles | 1.125 x 1.875 m |
| "Base" modular kits (Dwarven Dungeon, Viking Realm, Elven Realm), Fantasy Village: wall | 2.50 x 3.01 m, 0.23 thick | 3.33 x 4.0 |
| same: half wall / quarter wall | 2.50 x 1.51 / 1.25 x 1.51 m | 3.33 x 2 / 1.67 x 2 |
| same: floor, floor half | 2.50 x 2.50 / 2.50 x 1.25 m | |
| same: door | 1.00 x 1.97 m | 1.33 x 2.63 |
| same: stairs | 2.50 wide, 1.83 high (+0.33 below) | |
| Fantasy Kingdom house wall | 2.50 x 2.50 m | 3.33 x 3.33 |
| Fantasy Kingdom castle wall, stone floor | 5.00 x 5.00 m, 5 x 5 m | 6.67 |
| Dungeon Pack walls | 5 m pieces cooked in cm (node scale 0.01, see "Cooking problems") | |
| Goblin War Camp part wall | 2.30 x 2.45 m | 3.07 x 3.27 |

Reasoning:

1. A person must match its box. At 0.75 m a 1.8 m Synty human is 2.4 tiles in a 2.5-tile box:
   no scaling, 0.6 tiles of headroom in a 3-tile corridor, feet on the box bottom. Any other
   tile size forces scaling people, and then buildings must be scaled the same way to keep
   Synty's own proportions (doors 1.97 m for 1.8 m people).
2. The wall-module to person ratio is fixed by Synty (2.5 m module : 1.8 m person), so no
   choice of tile size puts a single 2.5 m module on whole tiles while a person fills the
   box. What 0.75 m gives instead: the 3.0 m storey is exactly **4 tiles**, and a full plus a
   quarter wall (2.5 + 1.25 = 3.75 m) is exactly **5 tiles**. Building templates are laid
   out in 5-tile bays (or 10-tile spans of three full modules), storeys of 4 tiles; every
   bay boundary and every storey lands on a tile boundary at scale 1.0.
3. The 5 m kits (Kingdom castle, Dungeon Pack) at a uniform **0.75** become 3.75 m = 5 x 5
   tiles, the same bay. Kingdom house walls (2.5 x 2.5 m) at **0.9** become 3 x 3 tiles.
   Goblin camp part walls at about **0.98** are 3 tiles wide.
4. The fiction's tile is 2.5 ft = 0.762 m: 0.75 m is within 2%.

So `K.TILE_M` and `gs_tile_m` in project.godot were not changed, and the suite did not need a
re-run for it.

Per-pack scale for building skins (for the building-template work):

| Pack | Scale | Bay | Storey |
|---|---|---|---|
| Dwarven_Dungeon_Map, Viking_Realm, ElvenRealm (Base kits), Fantasy_Village | 1.0 | 5 tiles (full + quarter) or 10 (3 full) | 4 tiles |
| Fantasy_Kingdom castle (5 m) | 0.75 | 5 tiles | 5 tiles |
| Fantasy_Kingdom house (2.5 m) | 0.9 | 3 tiles | 3 tiles |
| Dungeon_Pack (5 m, cooked in cm) | 75 (0.75 x the 100 that undoes the cm) | 5 tiles | 5 tiles |
| Goblin_War_Camp | 0.98 | 3 tiles | irregular |

## Characters and rigs

Two humanoid rig families, both driven by the same animation packs through
`view/actors/anim_retarget.gd` (bind-space retargeting, ported from glitchbound):

- **Classic Synty rig** (Root, Hips, Spine_01, UpperLeg_L ... 48-51 joints): Knights, Vikings
  multi-character file, ElvenRealm, Dark_Fantasy, Goblin_War_Camp, Dungeons_Realms, the
  multi-character `Characters.gltf` of Fantasy_Characters and Fantasy_Rivals, and the
  animation packs' own reference character.
- **UE-style rig** (Pelvis, spine_01, Thigh_L ... 55 joints, some with ik_* bones):
  Fantasy_Characters `SK_Character_*`, Fantasy_Rivals `SK_*` (including the "BR" big
  characters), Vikings individual files, Dungeon_Pack characters, Modular_Fantasy_Hero parts.

Animation packs (Polygon clips; also a Sidekick set for another rig, unused):

| Pack | What it has for this game |
|---|---|
| ANIMATION_Base_Locomotion | idle, walk, run, sprint (+ strafes, 25 degree slopes, crouch, turns), **jump** (idle/walking/running/sprinting), **fall** (short, large), land (soft/medium/hard); masculine and feminine sets |
| ANIMATION_Sword_Combat | light/heavy attacks and combos, hit staggers, deaths (with held poses) |
| ANIMATION_Bow_Combat | draw/aim/shoot, 1052 models (clips plus props) |
| ANIMATION_Idles | fidgets, gestures (pointing: a stand-in for casting) |
| ANIMATION_Goblin_Locomotion | neutral-rig idles, jumps, falls, lands, hunched locomotion |

There is **no climb, ladder or swim clip** in any animation pack on the server (searched
every pack name). Climbing uses the walk clip with the model turned away from the camera,
speed-scaled by vertical speed; swimming uses walk at 0.7 speed.

Character models (individual files unless noted; "multi" = one file holding several, picked
by mesh node name):

| Pack | Models |
|---|---|
| Fantasy_Characters | Male: Peasant_01, King, Wizard, Sorcerer, Baird (bard), Rouge_01 (rogue); Female: Peasant_01/02, Queen, Witch, Druid, Gypsy. 15 MB pack |
| Knights | Knight_01..03, Soldier_01..02 (+ multi) |
| Vikings | Viking_Chief_01, Grunt_01/02, Warrior_01/02, Shieldmaiden |
| ElvenRealm | Commoner M/F, Soldier M/F, Knight M, King, Queen, Nobility M, Scholar M, Priestess F, Rogue F (+ hair, cloak, hood attachments) |
| Dark_Fantasy | Hunter M/F, Priest F, Witch F, Gravedigger M, PlagueDoctor, DarkLord M, Demon M, Skeleton (plain, Flesh, LightArmor, HeavyArmor, Ranger); BigCharacters multi: Demon, Gargoyle |
| Goblin_War_Camp (multi) | Warrior M, Archer M/F, Shaman, King, Knight, BeastTamer, Cook, Wizard, Ranger, Prisoner 1-3 (goblins) |
| Fantasy_Rivals | DarkElf, Mystic, Medusa, ForestGuardian, ForestWitch, SpiritDemon, EvilGod, AncientWarrior, AncientQueen; "BR": Dwarf, Big_Ork, Troll, BarbarianGiant, Pig_Butcher, Slayer, MutantGuy, RedDemon, Fort/Elemental/Mechanical Golem |
| Dungeons_Realms | Hero M/F, Nomad M 1-3 / F 1-2 (bandits), Skeleton 1-3, Undead_Knight, demon wings |
| Dungeon_Pack | Hero_Knight M/F, Goblin Male/Female/Warrior M/F/Shaman/WarChief, Skeleton Soldier 1-2/Knight/Slave, Ghost 1-2, Tormented_Soul, Rock_Golem |
| Mini_Fantasy_Characters | chibi versions (not used: wrong proportions) |
| SIMPLE_Forest_Animals | Wolf 1-3, Fox, Bear 1-3, Boar, Stag, Doe, Moose M/F, Rabbit, Raccoon, Skunk (own rigs, one baked take each) |
| SIMPLE_Farm_Animals | Horse (5 coats), Cow/Bull, Goat/Sheep, Pig, Chick, Birds (own rigs) |
| POLYGON_Dogs | 13 dog breeds incl. wolf, hellhound, zombie dogs in one 14.5 MB file (82-joint rig, no clips): not used yet |

### Peoples and cultures (data/looks.json "people:*")

| SRD people | Synty stand-in | Notes |
|---|---|---|
| human commoner | Fantasy_Characters Peasant M / F | |
| human guard | Knights Soldier_01 | captain: Knight_01 |
| human noble | Fantasy_Characters King / Queen | |
| human mage | Fantasy_Characters Wizard (archmage: Sorcerer) | |
| human priest | Dark_Fantasy Priest F | acolyte tinted |
| human bandit | Dungeons_Realms Nomad M 02 (captain: Nomad 03) | also pirates |
| human scout | Dark_Fantasy Hunter M | |
| human cultist | Dark_Fantasy DarkLord, tinted | |
| human berserker | Vikings Warrior_01 | |
| dwarf | Fantasy_Rivals BR Dwarf at 1.45 m | stocky build; commoners: Viking Warrior at 1.4 m |
| elf | ElvenRealm Commoner / Soldier / Nobility / Scholar / Priestess | |
| drow | Fantasy_Rivals DarkElf (raider); ElvenRealm Rogue F, Soldier, Scholar, Priestess tinted violet-grey | SRD drow is an elf lineage; dark armour and skin by tint |
| halfling | Peasant M / F at 0.95 m, small box | uniform scale reads as child-like proportions |
| gnome | Wizard at 0.95 m | same caveat |
| orc | Fantasy_Rivals BR Big_Ork | |
| tiefling | Fantasy_Rivals Mystic, red tint | |
| goblin | Goblin_War_Camp Warrior M (archer, shaman, boss = King) at 1.1 m, small box | |
| hobgoblin | Goblin_War_Camp Knight at 1.8 m, orange-red tint | |
| kobold | goblin at 0.85 m, red-brown tint | no reptilian model on the server |
| gnoll | Fantasy_Rivals Pig_Butcher, tan tint, nameplate | no hyena-headed model |
| bugbear | Big_Ork, brown tint, nameplate | |
| skeleton | Dark_Fantasy Skeleton_01 (armoured: HeavyArmor) | |
| zombie, ghoul, ghast, mummy | Dark_Fantasy Skeleton_Flesh, tinted | |
| player classes | fighter Knight_01, paladin Knight_02, rogue Rouge_01, ranger Hunter M, wizard Wizard, sorcerer Sorcerer, warlock DarkLord, cleric Priest F, druid Druid, bard Baird, barbarian Viking Warrior, monk Peasant M | |

### SRD monsters with a Synty stand-in (81 rows in data/looks.json)

Goblinoids and kobolds (goblin-minion/warrior/boss, hobgoblin-warrior/captain,
kobold-warrior, gnoll-warrior, bugbear-warrior/stalker); NPC stat blocks (commoner, guard,
guard-captain, knight, noble, mage, archmage, priest, priest-acolyte, druid, bandit,
bandit-captain, scout, spy, assassin, tough, tough-boss, berserker, gladiator,
warrior-infantry, warrior-veteran, cultist, cultist-fanatic, pirate, pirate-captain);
undead (skeleton, minotaur-skeleton, warhorse-skeleton, zombie, ogre-zombie, ghoul, ghast,
wight, mummy, lich, vampire, vampire-spawn, ghost, specter, wraith); giants and golems
(troll, ogre, hill/stone/frost/fire giant, stone/clay/iron/flesh golem, shield-guardian);
fey and others (medusa, dryad, treant, werewolf); beasts (wolf, dire-wolf, winter-wolf,
mastiff, black/brown/polar bear, boar, giant-boar, deer, elk, giant-elk, riding/draft
horse, warhorse, goat, giant-goat). Unlisted slugs fall to `by_type`: celestial (Priest,
gold), construct (Mechanical Golem), elemental (Elemental Golem), fey (Forest Witch), fiend
(Red Demon), giant (Barbarian Giant), humanoid (bandit), undead (skeleton); aberration,
beast, dragon, monstrosity, ooze and plant have no humanoid-shaped stand-in and stay
primitives with their type colour until monster-forge has them. 17 monsters were synced
from monster-forge at the time of writing (black-pudding, centaur-trooper,
constrictor-snake, ghost, giant-eagle, giant-octopus, giant-spider, goblin-warrior, harpy,
hunter-shark, merfolk-skirmisher, owlbear, swarm-of-bats, swarm-of-rats, violet-fungus,
wolf, young-red-dragon); these win over the Synty rows.

## Nature props by kind

Counts of model files whose names contain the kind (collision meshes excluded):

| Pack | Trees | Rocks | Bushes | Grass | Flowers | Mushrooms | Crystals | Other |
|---|---|---|---|---|---|---|---|---|
| NatureBiomes_MeadowForest | 9 | 22 | 4 | 19 | 13 | 17 | 0 | fences, stone walls, camp props, windmill, well |
| NatureBiomes_AlpineMountain | 2 | 32 | 6 | 2 | 4 | 0 | 0 | |
| NatureBiomes_AridDesert | 2 | 58 | 2 | 1 | 0 | 0 | 0 | 3 cacti |
| NatureBiomes_SwampMarshland (v3) | 28 | 1 | 2 | 15 | 4 | 0 | 0 | |
| NatureBiomes_TropicalJungle | 16 | 31 | 12 | 13 | 14 | 0 | 0 | |
| EnchantedForest | 15 | 6 | 0 | 4 | 0 | 36 | 8 | giant mushrooms (6 m) |
| Nature (v2, older) | 66 | 30 | 9 | 11 | 7 | 6 | 0 | logs, stumps, willows, pines, ruins, cave rocks |
| Dungeon_Pack | 5 | 83 | 0 | 3 | 2 | 13 | 5 | 7 stalagmites, wall mushrooms, ladder, torches |
| Dwarven_Dungeon_Map | 9 | 15 | 14 | 30 | 8 | 18 | 0 | |
| Dungeons_Realms | 12 | 80 | 1 | 11 | 0 | 0 | 30 | crystal rocks, dwarf torches, obelisks |

Sampled sizes (m, w x h): Meadow Tree_Birch_01 5.1 x 10.6, Tree_Meadow_01 17 x 15,
Bush_01 2.7 x 2.9, Rock_02 2.4 x 1.5, Grass_Tall_Clump 1 x 1, Wildflowers 0.7 x 0.7,
Sunflower 0.8 x 1.7; Nature Tree_Round_02 3.9 x 4.7, Tree_Generic_01 3.4 x 5.6, Tree_Large_01
9.3 x 8.8, Plant_Bush_01 1.6 x 2.0; EnchantedForest Mushroom_01 5.2 x 6.0, Crystal_02
1.4 x 1.6; Dungeons_Realms Crystals_Cluster_Large 5.7 x 7.5. Trees and grass are much bigger
than a sidescroller wants, so dressing fits each object to a height in tiles (`fit_h`).

## Cooking problems found (and what handles them)

- **Meadow trees and bushes lost their leaf materials.** Each cooked tree has one material:
  Tree_Birch maps everything to `Branches_02.png` (leaves invisible), Tree_Fruit and Bush to
  the general atlas (speckled black-orange leaf cards). Not usable; the meadow set uses the
  older POLYGON_Nature trees and bushes instead. Meadow grass, flowers, rocks, mushrooms and
  sunflowers are fine.
- **POLYGON_Nature lost its atlas reference.** Trees, bushes and rocks have UVs into
  `PolygonNature_01.png` but their materials reference no image (they render white), and
  `Tree_Generic`/`Tree_Birch` trunks point at the leaf texture (red mask channel).
  `data/dressing.json` "textures" restores the atlas per material (`*` = untextured
  materials) and gives trunks a flat bark colour.
- **Dungeon_Pack environment pieces are cooked in centimetres** with a 0.01 node scale and a
  Z-up rotation (walls measure 5 cm). `fit_h` makes dressing immune; building skins need a
  per-pack factor (above).
- **Synty LOD chains** come as sibling nodes `<name>_LOD0.._LOD3`; GltfCache keeps LOD0.
- **Skinned Synty rigs carry a 0.01-scaled Armature** that the bind poses undo, so node-chain
  AABBs are 100x too small: `GltfCache.mesh_xform` measures skinned meshes where the skin
  draws them.
- **Runtime glTF under the headless renderer** leaves `ImporterMeshInstance3D` nodes;
  GltfCache swaps them for `MeshInstance3D`.
- **`generate_scene()` twice on one `GLTFState` renames bones** (Hips, Hips_2, Hips_2_2),
  which silently broke retargeting for the second actor using a clip. GltfCache generates once
  per file and duplicates the result.
- **glitchbound's material patcher** turns every material whose texture has an alpha channel
  into alpha-tested; that is right for grass cards and harmless on the character atlases seen
  so far, but worth remembering if a character shows holes.

## Modular_Fantasy_Hero (equipment on the player)

1496 models: 720 skinned parts in `FBX/ModularParts_Unreal` (UE-style rig), the same 720 as
static meshes, 54 weapons, one 4096 atlas. Part families with variant counts: Hair 38,
Torso M/F 29, Hips M/F 29, Head M/F 23, Upper arms 21, Shoulder attachments 21, Legs 20,
Lower arms 19, Hands 18, Facial hair 18, Shields 20 + 16 long, Back attachment 15, Helmet
attachment 13, Head coverings 13 + 11, Hips attachment 12, Knee attachments 11, Elbow
attachments 6, Eyebrows. Each part file holds **only the bones it uses** (a torso: 9 joints
Pelvis..clavicles; a head: 7), not the full skeleton. How gear swapping would work:

1. A master skeleton: the full UE-style rig (Fantasy_Characters `SK_Character_*` has all 55
   bones and matches these names).
2. For each slot (head, torso, hips, arms, legs, hands, attachments) load the chosen part and
   re-skin its mesh to the master skeleton: a new `Skin` whose binds name master bones, with
   the part's own bind poses (the same technique as monster.gd's LOD re-skinning). Check that
   the part's bind poses agree with the master rest pose; if they do not, convert through
   bind space as AnimRetarget does.
3. The animation is retargeted once onto the master skeleton and shared by every part.
4. Equipment items map to part ids in data (e.g. chain shirt -> Torso_Male_07 +
   ArmUpper_*_05), with SRD items only as keys.

Not built: step 2's bind-pose check needs a probe of several parts against a master, and the
part ids need a visual catalogue. Expect a day of work; whole-character models are used
until then.
