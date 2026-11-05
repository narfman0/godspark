# Track: items and sparks (M2 wave 1)

Inventory, equipment, bonding, item data and generation, loot on the ground and loot
tables, sparks and the constellation, and digging/placing through the inventory. The
system is `HostSystem.ITEMS` (3): `core/items/items_system.gd` (`ItemsSystem`) and
`core/items/items_client.gd` (`ItemsClient`), installed by `Systems` from their paths.

## Files

| File | What |
|---|---|
| `core/items/items.gd` | `Items`: the catalogue (SRD weapons and armour from the addon tables, `tile:<name>` rows from `data/tiles.json`, `data/items/base.json`, the 258 SRD magic items), record rules, `mods`, `tags`, the +3 budget |
| `core/items/item_gen.gd` | `ItemGen.roll(rng, base, level_hint, rank)`, `ItemGen.name(item)` |
| `core/items/inventory.gd` | `Inventory`: 10-slot hotbar + 40-slot bag, stacking, coin |
| `core/items/equipment.gd` | `Equipment`: 19 body slots, slot rules, `mods_list`, `tags`, `dress(c, ch, srd)` |
| `core/items/constellation.gd` | `Constellation`: kindled sparks in order, star spots, sigil |
| `core/items/sparks.gd` | `Sparks`: `data/sparks.json`, `apply(kindled, stats, out)`, `move_stats(speeds, size, kindled)` |
| `core/items/loot.gd` | `Loot`: loot tables, `roll(rng, info)`, depth bands |
| `core/items/drops.gd` | `Drops`: loot on the ground (falls, rests, merges, despawns, saves) |
| `core/items/items_codec.gd` | `ItemsCodec`: every SYS layout of this system |
| `core/items/items_system.gd`, `items_client.gd` | the host and client systems |
| `data/items/base.json` | non-SRD rows (coin, spark, ingots, cloth, leather, bone, ichor, gem), `tile_drops` |
| `data/items/magic.json` | per SRD magic item: slot, kind, bases, mods / tags / tiers, status |
| `data/items/materials.json` | materials, quality tiers, bases that take no metal |
| `data/items/affixes.json` | 37 affixes, three tiers each |
| `data/items/recipes.json` | hand-crafting from wood |
| `data/loot/loot.json` | CR bands, creature types, ranks |
| `data/sparks.json` | 20 sparks x 3 ranks; spark rank weights by depth band |
| `tools/loot_sim.gd` | `-- monster=SLUG rank=R n=1000 band=B` or `-- table` |
| `tests/test_items.gd`, `test_items_system.gd`, `test_items_net.gd`, `test_items_codec.gd`, `test_sparks.gd` | 339 checks |

## The item record

```
{base, count, material?, quality?, affixes?: [id or "id:tier"], magic?: slug, tier?: int,
 spark?: {id, rank}, bonded?: true}
```

- `base`: an SRD weapon or armour slug (`longsword`, `chain-mail`, `shield`), `tile:<name>`,
  a `base.json` row (`coin`, `spark`, `ingot:iron`, `cloth` ...), or an SRD magic item slug
  for magic items that are not weapons or armour (`ring-of-protection`, `potions-of-healing`).
- `magic`: an SRD magic item slug. Magic weapons and armour keep their base
  (`{base: "scimitar", magic: "flame-tongue"}`); other magic items have `base == magic`.
- `tier`: the variant of a magic item: +N - 1 for the `-1-2-or-3` items, the damage type of
  Ring/Armor of Resistance, the giant of a Belt of Giant Strength, the potion of healing's
  potency (0 Healing 2d4+2, 1 Greater 4d4+4, 2 Superior 8d4+8, 3 Supreme 10d4+20).
  *Added to the contract's record.*
- `bonded`: the SRD's attunement, done once at a campfire. Dropping an item on the ground
  clears it. *Added to the contract's record.*
- Records stack when everything but `count` is equal (`Items.same_stack`), up to
  `Items.stack_max` (tiles and materials 999, potions and sparks 20, gear 1, coin is a number).

```gdscript
Items.mods(item, active_only := false) -> Array   # base, material, quality, affixes, magic; budget applied
Items.tags(item) -> Dictionary                    # game effects other systems read
Items.budget_of(item) -> Vector2i                 # (to-hit, AC) the mods add up to
Items.make(base, n), make_magic(slug, tier, base), spark_item(id, rank), coin(n)
Items.kind(item), slot_kind(item), needs_bond(item), can_bond(item, class), magic_active(item)
Items.tile_of(item) -> int ; Items.tile_drop(tile_id) -> base ; Items.use_of(item) ; value ; weight
ItemGen.roll(rng, base := "", level_hint, rank := "standard") -> item ; ItemGen.name(item)
```

**The +3 budget** lives in one place, `Items.mods`: to-hit (weapons) and AC (armour,
shields) from material + quality + magic are capped at `Items.BUDGET` = 3 per item, trimming
quality first, then material. Material gives at most +1 (mithral and adamantine weapons);
quality gives none (it is value, weight and a perk); +N magic is the SRD's. `ItemGen` also
keeps +N within what the material leaves. Affixes never carry `attack`, `ac`, `save`,
`spell_*`, `damage`, `unarmored_ac`, `initiative` or ability mods
(`Items.FORBIDDEN_AFFIX_MODS`). Tested over 4000 generated items.

### Materials and quality (`data/items/materials.json`, original content)

| Material | From level | Weapon | Armour |
|---|---|---|---|
| copper | 1 | dig_speed +0.05 | light +1 |
| iron | 1 | - | knockback_resist +0.1 |
| silver | 15 | `silvered` tag | resist necrotic |
| mithral | 40 | +1 to hit, swing_recovery +0.1 | SRD Mithral: no STR need, no Stealth disadvantage |
| adamantine | 65 | +1 to hit, dig_speed +0.5, `sunder` | SRD Adamantine: crits become hits |

Wooden and leather bases (club, quarterstaff, bows, sling, whip, dart, blowgun, padded,
leather, studded leather, hide) take no material. Quality: crude (value x0.5, weight x1.25,
swing_recovery -0.05 / knockback_resist -0.1), common, fine (x2.5, x0.9, +0.05 / +0.15),
masterwork (x8, x0.8, swing_recovery +0.1 and dig_speed +0.1 / speed +5 ft and
knockback_resist +0.25). Rolled 25/55/15/5, shifted up by rank.

### Affixes (`data/items/affixes.json`, 37, original)

Suffixes: of Embers / Rime / the Crackle / Bile / the Wasp / Thunderclaps / Dusk / Dawn / the
Nagging Itch (extra 1d4 / 1d6 / 1d8 of a damage type by tier), of the Mole (dig_speed), of the
Glowworm (light), of the Magpie (pickup_radius), of the Hare (speed), of Quick Wrists
(swing_recovery), of the Long Arm (reach), of the Hearth / Kiln / Grounding / Iron Gut /
Gravedigger / Brine (resistances), of Bright Coins (coin_find), of Soft Landings
(fall_resist), of the Cat's Eye (dim_sight). Prefixes: Gleaming, Whistling, Burrowing,
Greedy, Lucky, Sturdy, Featherweight, Bristling (thorns), Barnacled (swim), Hearty (regen),
Spring-Heeled (jump), Snuffling (ore_sense), Gossamer (fall_resist). Count by rank
(0/1/2/3 weights): minion 80/20/0/0, standard 55/35/9/1, elite 10/50/32/8, champion
0/20/50/30, boss 0/0/30/70; at most one prefix. Tier by level_hint: <30, <65, the rest.

### Tags (read by other systems: `items.tags(e)` on the host, `ItemsClient.tags()` on the client)

dig_speed, light, pickup_radius (used here), swing_recovery, reach, swim, jump, climb,
fall_resist, knockback_resist, coin_find and drop_find (used by loot here), dim_sight,
ore_sense, regen, thorns, breath, weight_mult, silvered, sunder; from sparks also cast_move,
price_mult, reputation_mult, beast_peace. Only pickup_radius, coin_find and drop_find are
consumed in this track; the rest wait for their systems (see Open issues).

## SRD magic items: coverage

258 items, from the addon (name, rarity, variants, attunement, attunement_by, text), with
`data/items/magic.json` authored on top (slot, kind, bases, mods/tags/tiers, status). The
mods for 38 items came from glitchbound's `data/items/magic.json` (same author), re-keyed by
SRD slug; the rest were written here from the SRD text.

| Status | Count | Meaning |
|---|---|---|
| works | 27 | the item's effect is applied (Ring of Protection, Amulet of Health, Belt of Giant Strength (6 tiers), +N weapons/armour/shields, Ring and Armor of Resistance, Mithral and Adamantine Armor, potions of healing, Goggles of Night ...) |
| partial | 63 | the main number is applied, the rest is text (Flame Tongue's 2d6 fire on every hit, Holy Avenger's +3, Boots of Speed's +30 ft always on, Staff of Power's bonuses ...) |
| inert | 168 | carried as text only for now (bags, decks, figurines, most wands and staffs' spells, scrolls, most potions) |

90 of 258 have working mods. Slots: main_hand 44, off_hand 26 (shields, wands, rods), ring
22, armor 17 (robes too), neck 16, head 13, cloak 10, feet 7, hands 6, belt 2, none 95
(carried or consumed). Bonding: 140 need it (SRD attunement), any number may be bonded;
`SRDItems.can_attune` decides class limits ("a Wizard", "a Spellcaster").

## Inventory and equipment

- Unified indices for the wire and the UI: 0-9 hotbar, 10-49 bag, 50-68 equipment in
  `Equipment.SLOTS` order: head, neck, cloak, armor, hands, belt, feet, main_hand, off_hand,
  ring_1 .. ring_10.
- `Inventory.add` tops up stacks, then fills empty slots hotbar first, and returns the
  leftover. Coin goes to `coin`.
- `Equipment.can_equip(item, slot)` reasons: `bad_slot`, `not_wearable`, `stack`,
  `two_handed` (off hand while a two-handed weapon is held), `off_hand_busy` (the system
  then moves the off-hand item to the bag if there is room), `not_light` (an off-hand weapon
  and the main-hand weapon must both be Light, the SRD's Light property). Shields, wands and
  rods go in the off hand.
- `Equipment.dress(c, character, srd)`: sets `c.weapon` from the main-hand base
  (`srd.make_weapon`, proficiency from the class, Protector clerics included), armour,
  shield, off-hand weapon, Monk unarmed weapon (`kit.adapt_weapon`), puts the wielded weapon
  first in the mastery picks, applies every worn item's mods through `ItemEffects.apply`
  (unbonded magic left out), then sets max hit points from `LevelTrack.max_hp` with the
  gear's CON (current hit points follow the max). It works on a live combatant (no rebuild),
  so hit points, slots and effects are kept.

**Persistence: one place, the Character record.** `Character.inventory`, `equipment` and
`sparks` are now `Inventory`, `Equipment` and `Constellation`; `to_dict` / `from_dict` call
theirs (exact round trip, JSON numbers cleaned). `ItemsSystem.save_player` returns `{}`.
Drops are world state (`save_world`, `host.json` systems["3"]).

**Starting kit** (`ItemsSystem.give_kit`, once per character, `Inventory.kit_given`): the
class's `Character.DEFAULTS` gear worn (iron where metal: fighter longsword, chain mail,
shield; rogue rapier, leather; wizard quarterstaff; cleric mace, chain mail, shield; other
classes a dagger), and on the hotbar: 30 wood, 10 torches, a campfire, 2 Potions of
Healing.

**Crafting** (`data/items/recipes.json`, no station): 1 wood -> 2 platforms, 1 wood -> 2
ladders, 1 wood -> 3 torches, 5 wood -> campfire, 8 wood -> bed. Ores and ingots craft into
nothing yet.

## Sparks

`data/sparks.json`. THE RULE: no spark touches the combatant; `tests/test_sparks.gd` checks
attack bonus, AC, all six saves, spell save DC, spell attack and DC bonus, weapon dice and
type, bonus damage and hit riders for every spark at every rank on a fighter and a wizard,
one at a time and all twenty at rank III together.

| Spark | I | II | III |
|---|---|---|---|
| Fleet | run x1.1 | x1.2 | x1.3 |
| Spring | jump +1 tile | +2 | +3 (same gravity) |
| Skyhook | 1 air jump at 0.7 v | 1 at 0.9 v | 2 at 0.9 v |
| Dash | 26 t/s for 0.15 s, 1.2 s cooldown | 29, 0.9 s | 32, 0.6 s |
| Featherfall | fall at most 9 t/s holding jump | 6 | 4 |
| Mole | dig_speed +0.25 | +0.5 | +0.75 |
| Longarm | reach +1 tile | +2 | +3 |
| Gecko | wall cling, climb 3 t/s | 5 | 7 |
| Otter | swim x1.25 | x1.5 | x1.8 |
| Lantern | light 6 | 9 | 12 |
| Owl | dim_sight +4 tiles | +8 | +12 |
| Magnet | pickup_radius +2 tiles | +4 | +6 |
| Dowser | ore_sense 6 tiles | 10 | 14 |
| Quickhand | swing_recovery +0.1 | +0.2 | +0.3 |
| Steady | cast_move 0.4 | 0.7 | 1.0 |
| Surefoot | knockback_resist 0.33 | 0.66 | 1.0 |
| Silver Tongue | price_mult 0.05 | 0.10 | 0.15 |
| Hearthfriend | reputation_mult 0.25 | 0.5 | 0.75 |
| Beastfriend | beast_peace 0.25 | 0.5 | 0.75 |
| Scavenger | drop_find 0.1 | 0.2 | 0.3 |

- `Constellation`: `slots` from `LevelTrack.spark_slots(level)` (the system sets it on every
  refresh and every second), `kindled` in order, `kindle` (refusals: unknown, full,
  duplicate: one star per spark, swap to change its rank), `swap(i, spark)` returns the old
  one. Each star gets a grid spot (16 x 16, near the previous star, from a hash of the
  character name) that it keeps when swapped; `sigil()` is `{stars, lines}` with lines in
  kindling order. Saved as `{kindled: [{id, rank, at: [x, y]}]}`.
- Kindle and swap need a shrine (tile 66) within 3 tiles of the body's box; the replaced
  spark goes back into the slot the new one came from.
- **Movement.** `MoveStats` gained `air_jumps`, `air_jump_mult`, `dash_speed`, `dash_time`,
  `dash_cooldown`, `dash_window`, `glide_fall` (all off by default); `Body` gained the state
  for them (`air_jumps_left`, `dash_left`, `dash_dir`, `dash_cd`, `tap_dir`, `tap_t`,
  `last_move_x`, copied by `duplicate_body`); `PlayerInput` gained `dash` (flag bit 7, so
  the byte layout is unchanged when it is false). `PlayerController`: an air jump on a jump
  press in the air while jumps are left (reset on the floor, a ladder, in water or clinging);
  Dash on `input.dash` or a direction tapped twice within `dash_window` (a flat burst,
  gravity paused); Featherfall brakes the fall to `glide_fall` while jump is held. Gecko
  uses the existing cling mode (`climb_speed`). With no spark the nine trace scenarios hash
  bit-identically to before (positions, velocities and modes every step); new scenarios
  `airjump`, `dash`, `glide` in `tools/trace_run.gd`.
- **Same stats on both sides.** The host sets `e.stats = Sparks.move_stats(speeds, size,
  kindled)` with the speeds and size of `character.move_stats(combatant)`, and sends STARS
  (speeds, size, slots, stars) to the owner whenever any of that changes; the client sets
  `cw.stats` from the same function. The host's movement check reads `e.stats`, so it uses
  the sparked numbers. Dash is not in `_check_move`'s speed bound: a 0.15 s burst at 32 t/s
  stays inside `MOVE_MARGIN` (tested: 10 s of dashing, triple-jumping, Fleet III, Spring III
  at 30 Hz states, no correction).

## Digging and placing through the inventory

- Dig: the host gives the digger `Items.tile_drop(old)` (grass -> dirt, ore -> its ore tile,
  everything else itself; bedrock nothing). A full inventory drops it on the ground at the
  cell.
- Place: refused with the new `WorldHost.Reason.NO_ITEM` unless the player holds the tile's
  item; on success one is taken (the selected hotbar slot if it holds that tile, else the
  first stack). The SLOTS update is queued before the place's EDIT_RESULT.
- Client: `ItemsClient.allow_place(tile)` lets ClientWorld predict and send a place only when
  the mirror holds that tile minus places already predicted (`held_tiles`), so a client
  never predicts what it does not have. Until the host's items system has spoken (`live`)
  places are not gated (a host without the system). A refused place rolls back as before.
- Keys 1-4 (`game/local_input.gd`): with the items system they select hotbar slots 1-4 and
  you place what is selected; without it, the old fixed blocks.

## Loot on the ground

Drops are records in the items system (`Drops`), not entities. Gravity 40 t/s^2, terminal
20 t/s, rest on solid or platform tops, wake when dug out from under (checked each tick),
merge with an identical resting stack within 1.25 tiles, despawn after 900 s, at most 1500
(oldest go). Pickup: within 2 tiles of the body centre plus the `pickup_radius` tag, after
0.4 s (2 s for the one who dropped it); players are tried in entity order and the first to
touch takes what fits (no instancing). Each player is told of drops within
`Interest.DEFAULT_RADIUS` chunks and told they are gone past radius + 1 (checked every 10
ticks); clients step their copies with the same `Drops.move` and take the host's word on
landing (MOVED).

## Loot tables (`data/loot/loot.json`, `tools/loot_sim.gd`)

A kill rolls coin (chance by creature type, dice by CR band: 1d6, 2d6+2, 2d8+6, 4d10+15,
8d10+40, about a tenth of the SRD's individual treasure for ARPG kill rates), then `rolls`
draws (minion 0.1, standard 1, elite 2, champion 3, boss 5), each a drop with the band's
chance (0.22 to 0.36) times (1 + drop_find), its kind by creature type (gear / material /
potion / magic), then sparks: elite 12% chance, champion a spark or an item guaranteed,
boss a spark and a magic item. Spark ranks by depth band (surface 85/14/1 ... nadir
5/40/55). Magic items by the band's rarity weights; items with working mods weigh 4x.
Rank comes from `e.meta.rank` if the entity has a `meta` Dictionary, else `e.look.rank`,
else standard. `on_kill` uses the drop_find / coin_find of the nearest player within 24 tiles.

`tools/loot_sim.gd -- table` (1000 kills each, caves band), items per kill (coin per kill):

| | minion | standard | elite | champion | boss |
|---|---|---|---|---|---|
| goblin warrior (fey, CR 1/4) | 0.02 (0.1) | 0.23 (1.0) | 0.58 (2.9) | 1.69 (5.0) | 3.07 (12.7) |
| wolf (beast) | 0.03 (0.0) | 0.24 (0.1) | 0.58 (0.2) | 1.69 (0.6) | 3.15 (1.1) |
| bandit captain (humanoid, CR 2) | 0.03 (0.8) | 0.28 (5.4) | 0.65 (13.1) | 1.78 (26.2) | 3.27 (64.4) |
| young red dragon (CR 10) | 0.04 (2.0) | 0.29 (13.5) | 0.72 (34.0) | 1.88 (68.0) | 3.54 (162) |

Sparks per 1000 kills: elite about 120, champion about 490, boss 1000. A standard kill
drops a quarter of an item, mostly stackable materials and potions, so a run of 100
standard kills fills about 10 bag slots.

## Messages (`ItemsCodec`, SYS system 3)

| Kind | Dir | Layout |
|---|---|---|
| SLOTS 1 | h->c | u32 coin, u8 selected, u8 n, n x (u8 index, u8 has, rec) |
| STARS 2 | h->c | u16 walk, climb, swim, fly (ft), str size, u8 slots, u8 n, n x (str id, u8 rank, u8 x, u8 y) |
| DROPS 3 | h->c | u16 n, n x (u32 id, f32 x, y, vx, vy, rec): add or update |
| GONE 4 | h->c | u16 n, n x (u32 id, u32 by): by = picker's entity id, 0 = despawned or out of view |
| MOVED 5 | h->c | u16 n, n x (u32 id, f32 x, y, vx, vy) |
| NOTE 6 | h->c | u8 op, u8 ok, str word: the answer to a request ("ok" or a reason) |
| BONDING 7 | h->c | u8 index, u16 ms left (0: done or stopped) |
| MOVE 16 | c->h | u8 a, u8 b (255: first free bag slot) |
| USE 17 | c->h | u8 index |
| DROP 18 | c->h | u8 index, u16 n |
| SELECT 19 | c->h | u8 hotbar slot |
| BOND 20 | c->h | u8 index |
| KINDLE 21 | c->h | u8 index |
| SWAP 22 | c->h | u8 star, u8 index |
| CRAFT 23 | c->h | str recipe, u8 times |

rec: str base, u16 count, u8 flags (1 material, 2 quality, 4 affixes, 8 magic, 16 tier, 32
spark, 64 bonded), then the flagged fields in that order. A full SLOTS of 69 rich records
is under 6 KB; the smoke run's whole items traffic was 22 messages, 1015 bytes.

## The client surface (for the Interface track)

`var items: ItemsClient = cw.system(HostSystem.ITEMS)`

```gdscript
# signals
inventory_changed(indices: Array)    # unified indices; coin and selection are re-read too
equipment_changed(slots: Array)      # slot names
constellation_changed()
drop_added(id, pos: Vector2, item)   # also on count change (merge, partial pickup)
drop_removed(id, by: int)            # by: picker's entity id, 0 = gone
note(op: int, ok: bool, word: String)   # the host's answer to each request (ItemsCodec.K op)
bonding(index: int, ms_left: int)
# state
items.live; items.inventory (Inventory); items.equipment (Equipment); items.constellation
items.item(index) -> Dictionary; coin(); selected(); hotbar() -> Array; selected_tile()
items.name_of(item) -> String; tags() -> Dictionary; move_stats(); sigil() -> {stars, lines}
items.drops_in_view() -> [{id, pos, item}]; held_tiles(tile_id)
Items.value(item), Items.weight(item), Items.needs_bond(item), Items.slot_kind(item), Items.use_of(item)
Items.magic_entry(slug)["text"] / ["rarity"]; Sparks.row(id) (name, text, group)
# requests (validated on the host; the mirror changes and a note comes back)
move(a, b); equip(slot, "ring_3" or index); unequip("off_hand", to := 255); use(slot)
drop(slot, n := 1); select_hotbar(i); bond(index); kindle(slot); swap_spark(star, slot)
craft(recipe, times := 1)
```

Refusal words: full, bad_index, empty, no_move, bad_slot, not_wearable, stack, two_handed,
off_hand_busy, not_light, occupied, full_hp, not_usable, no_body, no_bond_needed, bonded,
class, no_campfire, interrupted, not_a_spark, no_shrine, unknown, duplicate, no_star,
missing.

## Calls offered to other systems (host)

```gdscript
items.gear_mods(e) -> Array; items.wielded(e) -> Dictionary
items.outfit(e, c := e.combatant)        # Equipment.dress: weapon, armour, mods, max HP from LevelTrack
items.apply_sparks(e, stats, out)        # Sparks.apply with e's kindled list
items.tags(e) -> Dictionary              # gear + spark tags
items.give(entity_id, item) -> leftover; items.drop(pos, items, from := 0)
items.on_kill(victim) -> Array           # the items dropped
items.refresh(e)                         # after gear, sparks or level change (see below)
items.give_kit(character)                # static
```

`items.refresh(e)` calls `rules.refresh(e)` when the rules system has one (which should
rebuild or keep the combatant and call `items.outfit(e)`), else `outfit(e)` itself; then it
sets `e.stats` (base speeds + sparks, what the client mirrors) and the tags. It is
re-entrant-safe (rules may call `items.refresh` back once). Every 30 ticks it re-checks
level (spark slots), base speeds and whether someone replaced `e.stats`, and fixes and
re-mirrors them.

## Hooks added outside my files

| Where | What | Why |
|---|---|---|
| `core/host/host_system.gd` | `allow_place(host, e, tile_id) -> bool` (default true), `tile_edited(host, e, x, y, old, now)` (no-op) | the edit flow asks systems before a place and tells them after a dig or place |
| `core/host/world_host.gd` | `Reason.NO_ITEM` appended to the enum; `request_place` asks `allow_place` of every system after `place_reason` passes; `request_place` and `_advance_dig` call the new `_edited(e, x, y, old, now)` (loops `tile_edited`) after `set_fg` and before `_result` | the smallest change that lets placing need an item and digging give one, in order with EDIT_RESULT |
| `core/host/client_system.gd` | `allow_place(tile_id) -> bool` (default true), `placed(req, tile_id)` (no-op) | honest prediction |
| `core/host/client_world.gd` | `step()` predicts a place only if `_systems_allow_place(tile)`, then calls `placed(req, tile)` on each system | same |
| `core/rules/character.gd` | `sparks`, `inventory`, `equipment` are `Constellation`, `Inventory`, `Equipment`; `to_dict`/`from_dict` call theirs; `create` sets the constellation's salt | the placeholders replaced, as the contract said |
| `core/entity/move_stats.gd`, `body.gd`, `player_input.gd`, `player_controller.gd` | the spark abilities above, all off by default | Skyhook, Dash, Featherfall |
| `game/local_input.gd` | keys 1-4 call `select_hotbar(i)` and the placed tile follows the selection when the items system is live | the minimal hotbar mapping |
| `tools/trace_run.gd` | scenarios airjump, dash, glide | traces with sparks |

No change to `protocol.gd`, the endpoints, `net/bot_client.gd` (the bots place wood and the
kit has 30), `Presenter` or `view/`.

## Numbers

| What | Measured |
|---|---|
| Tests | 2041 checks, ALL PASS (1702 before; 339 new) |
| Smoke run (2 bots) | NET SMOKE PASS; items SYS 22 messages, 1015 bytes; host tick avg 217 us |
| `Items.ensure()` | loads 300+ rows once per process |

## Open issues

- **Tags waiting for readers.** Mole/dig_speed and Longarm/reach are tags: `TileEdit` and the
  host's dig still use `TileEdit.REACH` and tool power 1 (wiring them touches `world_host.gd`
  and `client_world.gd` on both sides; the integration pass should pass reach and dig power
  into `TileEdit.in_reach` / `DigProgress.update` from `items.tags(e)` and
  `ItemsClient.tags()`). Lantern/light, Owl/dim_sight, Dowser/ore_sense are for the view;
  Quickhand, Steady, Surefoot for combat; Silver Tongue, Hearthfriend, Beastfriend for
  trade, reputation and monsters. Featherfall slows the fall but fall damage does not exist.
- Dash has no key: double-tap works; `PlayerInput.dash` is there for whoever binds one.
- Magic items: 168 are inert text; partial ones apply their main number always-on
  (Boots of Speed's +30 ft is not a toggle, conditional extra damage is unconditional).
  Ammunition and spell scrolls are inert. No item charges.
- Rebuilding gear dresses the live combatant; if the rules track rebuilds combatants from
  scratch it must call `items.outfit(e)` after `make_combatant`.
- Bond progress is lost if the player leaves mid-bond (2 s, not worth saving).
- The first monster deaths will come from the combat/monsters tracks: `on_kill` is ready but
  nothing calls it yet; `rank_of` reads `e.meta.rank` / `e.look.rank` until monsters define ranks.
- Coin in a record is clamped to 65535 on the wire (a coin pile bigger than that would show
  short on the client; nothing makes one).

## After the integration pass

The seams this track left open were wired in [m2-integration.md](m2-integration.md); the public
surface it added here is listed in architecture.md, "M2 contracts / Integration".
