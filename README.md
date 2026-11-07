# Godspark

A co-op sidescrolling platformer set in a simulated world built on the SRD 5.2.1: a deep
Underdark, biomes with their own ecology, settlements that trade, raid and starve, and a
long road to godhood. Working title.

- Engine: Godot 4.7.1 (Forward+), GDScript.
- Status: M5, "Biomes and the shape of the overworld" (integrated, about to be played): the world
  is a climate journey from cold forest to hot desert through five biomes that look and feed
  differently, with ranges and rivers you cross on foot, on top of M4's living world. Next:
  lighting, then the Underdark's peoples. See [docs/m5.md](docs/m5.md), [docs/m4.md](docs/m4.md),
  [docs/m2.md](docs/m2.md), [docs/plan.md](docs/plan.md) and
  [docs/architecture.md](docs/architecture.md).

## What M5 added

- **A climate journey**: meadow, forest, mountain, desert and swamp lie cold to hot along a medium
  world of 8192 x 2560, each with its own ground, sky, dressing and parallax. It generates in
  about 25 s. A walk from end to end takes about 11 minutes.
- **Barriers**: every range has a pass and an under-route, every river a bridge or a ford. You never
  have to dig across, and roads, caravans and the sim's travel times all feel them.
- **Land that feeds differently**: food, timber, ore, stone, salt, reagents, game and water come from
  the biome. Salt is cheap in the desert and dear in the meadow, so caravans carry it over the
  pass, and raiders wait there for them. Shops sell all of it.
- **Monsters that belong**: each biome hunts its own, and a lair's name follows what comes out of it.
- **Combat you can read**: swings on real clips, the arc you will hit, a highlight on your target,
  hit, crit and miss you can tell apart, and a dodge roll on V.
- **The map**: regions, ranges, rivers and crossings, named. Other players and people show their
  weapons as soon as you see them.

## What M4 added

- **A world you can walk**: every site reachable on foot. W climbs stairs, ladders and ropes;
  S held drops through walkways; ropes you buy or make anchor where you click and unroll
  downward. Digging gives plain rubble you can place again.
- **Places**: towns built by the sim's tier, with roads between them and deep roads below. They
  grow, and fall to ruin, when no one is looking.
- **People**: townsfolk on their daily round, guards from the real garrison, caravans with
  wagons, raiders and patrols, all from the sim's own numbers. A fight you watch is fought in
  real time and written back; one you don't is resolved by the sim as before.
- **Dealings**: talk (E) to anyone who talks; rumours are real events with places on your map.
  Shops and smiths sell what the town has at its prices. Quests come from what is happening:
  message, bounty, escort, defend, relief, recover, and for patrons hunts and sieges.
- **Standing**: each faction remembers. It moves prices, who attacks you and what patrons give.
  Killing friendly or neutral people costs standing and pays nothing.
- **Rooms**: a keeper's paid room is a place you can respawn, and a bed while you stay near it.

## What M2 added

- **Characters**: fighter, rogue, wizard or cleric (`class=` when you first join); levels 1-100
  where every fifth is an SRD class level and the levels between give spark slots, Vigor and
  Knacks (picked from what you did: deeds). XP from kills you took part in, shared with the
  players nearby; a guard's kill pays a quarter if you were in the fight, nothing if you watched.
- **Combat**: real-time; every swing and spell is an SRD roll made on the host once the hit
  physically connects. Monsters wind up visibly before they strike. Downed at 0 HP: death
  saves every 4 s, a friend holds E to get you up (a healing spell or potion does too); dead,
  you wake at your bed or the nearest shrine with nothing lost.
- **Monsters**: SRD stat blocks with brains, ranks (minion, elite, champion, boss) and
  affixes, spawned off-screen around you by a director: small, minion-heavy packs by day near
  the settlement you start at, harder ones further out, at night and deeper down. Sim lairs
  become real creatures when you arrive.
- **Items**: an inventory and hotbar (what you dig is what you can place), a paper doll with
  ten rings, SRD magic items (attunement items bond at a campfire, no limit), ordinary gear
  with materials and affixes, loot on the ground.
- **Sparks**: found on elites and champions; kindle them at a shrine for movement and utility
  (run, jump, air jumps, dash, glide, dig speed and reach, light, swing speed ...). They never
  change attack rolls, AC, DCs or damage dice.
- **Rests**: hold E at a campfire for a short rest on Hit Point Dice; sleep in a bed for a long
  rest (the night passes when every living player is in bed).

```bash
git clone --recurse-submodules <this repo>
godot --headless --import
godot --headless -s res://tools/run_tests.gd     # prints ALL PASS
```

## Running it

```bash
tools/bootstrap.sh          # optional: fetch the art (about 57 MB, git-ignored); runs without it
godot                       # host a new world and play it (listen server on port 24650)
godot -- join=HOST[:PORT] name=ann          # join someone's game
godot -- offline gen=dev seed=7             # single-player, no network port
godot --headless -- dedicated port=24650 world=/path/to/world   # a server with no local player
```

Options (after `--`): `gen=dev|small|medium|large` (default `medium`, 8192 x 2560, which takes
about half a minute behind a loading screen) and `seed=N` pick a new world;
`world=DIR` is where it is saved and loaded (default `user://worlds/<gen>`; a saved world there
is loaded instead of generating one); `gen=test` is the small flat test world; `name=X`;
`port=N`; `class=fighter|rogue|wizard|cleric` for a new character; `cheats` (debug keys and
DEBUG messages); `spawns=0|1` turns the spawn director off or on; `pack=goblin-warrior` (or
`SLUG:RANK`, `raiders:bandit`, comma-separated) spawns ranked packs near you; `xp=N`
multiplies kill XP; `sleep=HOURS` advances the world clock at start; `timeout=S`; `shot=PATH.png
shot_after=S` saves a screenshot and quits; `ui_tour=DIR` (with `offline cheats`, under
`tools/soft_godot.sh`) drives the interface through its screens and saves a picture of each. `game/main.gd` lists them all. The world, the
clock, the world history and the players are saved on exit.

## Controls

Terraria-like: the selected hotbar item decides what the left mouse button does. Hotbar slot 1 is the
attack slot: a new character starts with it selected and empty (it shows the wielded weapon,
which lives on the paper doll), so a left click fights; the kit's torches, campfire, potions,
bed, two ropes and supplies are on slots 2-7, and loot never lands in slot 1. Digging gives
plain rubble (ore gives ore to sell), which you can place again to bridge or block; camp gear,
walkways, stairs, ladders and rope are made from supplies. A hint above the hotbar
("Left click: use what is selected. F: always attack. Right click: dig.") fades after your
first attack.
**Digging moved from the left to the right mouse button.**

| Action | Keys |
|---|---|
| Move left / right | A / D, or Left / Right |
| Climb up / down (ladders, ropes, walls) | W / S, or Up / Down |
| Take a staircase up from its foot or where it crosses your walkway (running on stays level; once on the stairs you keep to them) | Hold W as you reach it |
| Hang a rope: select it and click a cell beside rock or under a walkway; it unrolls down to the floor (30 tiles at most). Click the rope again with a rope selected, or dig it, to take it back | Left mouse button |
| Drop through a walkway (or stairs, a ladder top) to what is below: hold S a moment (a brush does nothing; after climbing down onto a walkway, press S again), or S + Jump at once | S |
| Jump (hold for higher) | Space |
| Use the selected hotbar item toward the mouse: a weapon (or an empty slot) attacks and keeps attacking while held, a block places, a potion is drunk | Left mouse button |
| Dig the tile under the mouse (hold) | **Right mouse button** |
| Attack with your weapon, whatever is selected (hold) | F |
| Dodge roll: about two tiles the way you face, under blows, a cooldown of a second; it cancels a wind-up, but not a swing that has landed | V |
| Pick a hotbar slot | 1-9, 0; Ctrl + mouse wheel; mouse wheel over the hotbar; click a slot |
| Zoom | Mouse wheel; = and - |
| Interact: talk to the person beside you (the prompt over their head says who); hold at a campfire to rest, sleep in a bed, kindle at a shrine, hold by a downed friend to haul them up, wake after dying | E |
| Hang a rope from the hotbar: select it, click where it should hang; climb it with W and S | 1-0, Left mouse, W / S |
| In a conversation: answer by number; farewell | 1-9; 0 or Esc |
| Quick spells: hold to aim (areas show where they land), let go to cast | Q, R, T, G |
| Dash (with the Dash spark) | Shift, or tap a direction twice |
| Inventory and paper doll | Tab or I |
| Character sheet | C |
| Constellation | K |
| Spells (assign Q R T G) | B |
| Choices waiting (level-ups, Knacks) | U |
| World map | M |
| Work (the quest log) | J |
| Standing and patrons | P |
| The controls card | F1 or H |
| Show or hide the world-history log | L |
| Close the top screen | Esc |
| Debug, host only: one game hour / one game day passes | F6 / F7 |

Pickup is automatic. Screens never pause the game (it is co-op): the world runs behind them
and the movement keys still work, but clicks on (or around) a screen never dig or attack.

In the inventory: click to pick up and click to put down (or drag); Shift-click wears a piece
of gear (or takes it off); right-click drinks, wears or bonds (bonding needs a campfire near);
click outside the panel to drop what you hold. Ten ring slots, five under each hand.

A game day lasts 20 real minutes. You carry a torch (the Lantern spark widens it); caves are
dark without one.

## Talking, trading and work

Walk up to a townsperson, keeper, merchant, smith, priest or guard (or a caravan's escort):
the prompt over their head says "E: talk to <name>". Marks over heads say who sells (a coin),
who smiths (an anvil), who has work today (a red diamond), who waits for work you have done (a
green tick) and who speaks for your patron (a plum star). E opens the conversation in a panel
low on the screen; the world keeps running. Answer with the buttons or the number keys (they
do not switch hotbar slots while you talk); 0 or Esc says farewell. Walking off, a fight or
the person leaving ends it, and the panel says why.

- **News**: real history, each a note with the place named and a "mark on map" box.
- **Shops and smiths**: their goods with stock and what you pay, your pack with what they pay;
  click buys or sells the amount set by the nudge, Shift-click the whole stack. A line says
  why prices are what they are (plenty, scarcity, your standing, your Bond, your patron) and
  the town's purse says why a poor town pays little. Esc goes back to the talk.
- **Work** (J): on offer, under way, and done; accept from the conversation, hand in to the
  town that gave it, abandon (it says what that costs). Pin one to the HUD for a pointer.
- **Map** (M): the places you have seen or heard of, the roads between them, the pinned work;
  drag, wheel, Home. **Standing** (P): every people you know, your standing with them, how
  their guards take you, and patronage (tiers at 25, 50 and 75 bring gifts).

What a town sells, and at what price, comes from its stocks in the world simulation; selling
ore you dug or trade goods you carried pays the local price, gear about a quarter of its
value. Work comes from what is going on (a lair on the roads, a hungry town, a caravan
leaving, raiders on the way). See [docs/tracks/deals.md](docs/tracks/deals.md) and
[docs/tracks/m4-interface.md](docs/tracks/m4-interface.md).

## Screens

- **HUD**: hit points, level and class level, experience with a mark for what the next level
  gives, Hit Point Dice, spell slots, action / bonus / reaction timers, the hotbar, quick
  spells, conditions, coin, the clock, toasts, and a badge when choices wait.
- **In the world**: damage, healing, misses, crits and saves float up; monsters' wind-ups show
  as inked shapes; nameplates with hit points (elite, champion and boss frames); loot lies on
  the ground as glinting cards.
- **Inventory** (Tab), **character sheet** (C), **constellation** (K: your sparks as stars;
  kindle at a shrine), **spells** (B), **choices** (U: class-level picks and Knack cards).
- **The living world**: the dialogue panel, the shop, work (J), the map (M), standing (P), the
  controls card (F1 or H); a place's banner as you enter it; plates over caravans and raiders;
  the pinned work on the HUD with a pointer; buttons for the screens under the clock.

`tools/fetch_fonts.sh` (run by `tools/bootstrap.sh`) fetches the two OFL fonts the interface
uses; without them it falls back to the engine font.

## Known limits

- Nobody had played M2 before this build: combat feel, wind-up dodging at real latency, the
  revive hold, inventory dragging and spell aiming want a human's judgement.
- About two thirds of SRD magic items and spells are text only or refused; no opportunity
  attacks, two-weapon fighting, grapples, Action Surge or monster spellcasting yet.
- XP pacing is modelled, not played: about 3 minutes a level early, 20 at level 50, an hour in
  the 90s, 40 hours to 100, from measured spawn rates and assumed fight lengths
  ([docs/tracks/m4-integration.md](docs/tracks/m4-integration.md)). Quest coin and XP are first guesses.
- Escort work needs a caravan already leaving (the sim plans them every 5 days); goods taken
  home by raiders go into their town's stock, with no quest to win them back there.
- Caves: worldgen joins every cave region to the rest with steps, bridges, ladders and ropes
  (docs/tracks/traversal.md), but about a quarter of cave spots 40 tiles apart still defeat a
  monster's path follower, and a few deep sites are only reachable the long way round.
- Species and background are labels only; Epic Boons, tool and language Knacks and Bonds are
  recorded but not used yet.

## Tests

```bash
godot --headless -s res://tools/run_tests.gd     # prints ALL PASS
tools/net_smoke.sh                               # two bots and a dedicated host over ENet
WORLD="gen=dev seed=3" HOST_WAIT=3 tools/net_smoke.sh   # the same on a generated world
ALL=1 tools/net_smoke.sh   # the M2 story with the director on: fight, XP, rests, downed, revive
tools/soft_godot.sh --resolution 1280x720 -- offline cheats class=fighter gen=dev seed=3 \
    world=/tmp/x ui_tour=/tmp/shots     # screenshots of every screen and an M2 slice
```

Balance tools (headless): `tools/arena.gd` (a build against a ranked pack), `tools/spawn_sim.gd`
(what the director spawns, kill rates), `tools/loot_sim.gd`, `tools/xp_pacing.gd`,
`tools/cave_nav.gd`. Places: `tools/soft_godot.sh -s res://tools/place_shot.gd -- out=/tmp/town.png
seed=4 site=0 [sun=0]` (a settlement, or `route=N` for a road bridge); `tools/worldmap.gd` draws
streets, buildings and route paths.

Rules come from [godot-srd-addon](https://github.com/narfman0/godot-srd-addon), vendored as
a submodule and symlinked at `addons/srd`.

This work includes material from the System Reference Document 5.2.1 ("SRD 5.2.1") by
Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is
licensed under the Creative Commons Attribution 4.0 International License, available at
https://creativecommons.org/licenses/by/4.0/legalcode.
