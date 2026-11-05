# Track: Interface (M2 wave 2)

Branch `ws/interface`. Everything the player sees and clicks for M2: the HUD, in-world
feedback, inventory and paper doll, level-up and Knack screens, the constellation, spells,
the character sheet, rest/downed/death prompts, and a scripted screenshot tour. Design:
[m2.md](../m2.md); the client surfaces it builds on: [rules.md](rules.md), [items.md](items.md),
[combat.md](combat.md).

UI and view code own no rules: every action is a request on a client system
(`RulesClient`, `ItemsClient`, `CombatClient`), validated on the host. Nothing in `core/` was
changed. The interface is built only by `ViewPresenter` (windowed clients); headless runs,
dedicated servers and bots use `LogPresenter` and never load it or a font.

## Files

| File | What |
|---|---|
| `game/ui/ui_theme.gd` | `UiTheme`: colours, fonts, StyleBoxes, the Theme, ink drawing helpers (bars, pips, stars, sweeps), UI scale |
| `game/ui/game_ui.gd` | `GameUi`: the root CanvasLayer (scaled virtual 1280x720), screen stack, input gating LocalInput asks, toasts, local deed tally |
| `game/ui/hud.gd` | `Hud`: vitals plate, XP and next reward, Hit Point Dice, slots, pending badge, conditions, clock and coin, action/bonus/reaction timers, hotbar, quick spells, toasts, banner, prompt, downed overlay, the night fade |
| `game/ui/context_prompts.gd` | `ContextPrompts`: what E does here (rest, sleep, kindle, revive, respawn) and the prompts |
| `game/ui/inventory_screen.gd` | `InventoryScreen`: paper doll with ten rings, 10 + 40 slots, crafting, bonding |
| `game/ui/choices_screen.gd`, `knack_card.gd` | `ChoicesScreen`, `KnackCard`: pending SRD choices, Knack cards, Epic Boon |
| `game/ui/constellation_screen.gd` | `ConstellationScreen`: stars, lines, empty slots, loose sparks, kindle/swap, sigil |
| `game/ui/spell_screen.gd` | `SpellScreen`: prepared spells, slots, quick-slot assignment, reasons |
| `game/ui/character_sheet.gd`, `sheet_model.gd` | `CharacterSheet`, `SheetModel` (numbers worked out on the client) |
| `game/ui/ui_screen.gd`, `tooltip_panel.gd` | screen base class, tooltip card |
| `game/ui/item_icons.gd` | `ItemIcons`: procedural icons (category, colour, rarity, cached textures) |
| `game/ui/item_text.gd` | `ItemText`: tooltip lines, affixes and tags in words, comparison, spark effects |
| `game/ui/choice_logic.gd`, `quick_slots.gd`, `input_logic.gd`, `nearby.gd`, `sigil_layout.gd`, `ui_copy.gd` | pure helpers (tested) and the copy |
| `game/ui/ui_tour.gd` | `UiTour`: the scripted screenshot tour |
| `view/fx/fx_view.gd` | `FxView`: in-world feedback root (projectiles, hit flash, sigil flash) |
| `view/fx/floating_numbers.gd`, `number_pool.gd` | pooled, capped damage/heal/miss/crit/save numbers |
| `view/fx/nameplates.gd` | nameplates with HP bars, rank frames and affixes |
| `view/fx/telegraphs.gd`, `telegraph.gdshader` | wind-up telegraphs and the aim preview |
| `view/fx/drops_view.gd`, `drop.gdshader` | loot on the ground as lit icon cards with glints |
| `tools/fetch_fonts.sh` | fetches the two OFL fonts into `assets/fonts/` (git-ignored); `tools/bootstrap.sh` runs it |
| `tests/test_interface.gd` | 115 checks |

Additive edits: `game/local_input.gd` (rewritten for the control scheme), `game/view_presenter.gd`
(makes `GameUi` and `FxView`, routes events, torch size from the `light` tag, zoom keys,
Ctrl+wheel), `game/chronicle_overlay.gd` (`set_margin`, toggle on L), `game/main.gd`
(`ui_tour=DIR`), `project.godot` (`[input]`), `.gitignore`, `tools/bootstrap.sh`.

## The control scheme

| Action | Input |
|---|---|
| Move, climb, jump | A/D, W/S, Space (unchanged) |
| Use the selected hotbar item toward the cursor | Left mouse: a weapon or empty slot attacks (hold to keep attacking), a block places, a potion is drunk |
| Dig the tile under the cursor (hold) | **Right mouse** (was left) |
| Attack with the wielded weapon whatever is selected | F (hold) |
| Hotbar slot | 1-0; Ctrl+wheel; wheel over the hotbar; click a slot |
| Zoom | Mouse wheel; = and - (keypad + and -) |
| Interact | E: hold at a campfire to rest, sleep in a bed, kindle at a shrine (opens the constellation), hold near a downed ally to revive, respawn when dead. Pickup is automatic |
| Quick spells | Q, R, T, G: hold to aim (areas show their shape), release to cast |
| Dash (Dash spark) | Shift, or double-tap a direction |
| Inventory / character / constellation / spells / choices | Tab or I / C / K / B / U |
| Chronicle log | L (was C) |
| Close the top screen | Esc |

Routing: `LocalInput` takes mouse buttons only from `_unhandled_input`, so a click any
Control takes (screens, the hotbar, buttons) never digs or attacks; while any screen is open a
full-screen catcher takes every click (a click outside a screen drops the held item in the
inventory, else closes it), and held buttons are released. Movement keys keep working with
screens open; only a focused text field takes them (`InputLogic.movement_allowed`). Dash is
ignored while a screen is open (Shift-click in the inventory would otherwise dash).

## The theme

`UiTheme` holds the colours (ink, parchment, night sky, vermilion HP, gold XP and coin, teal
slots, plum magic, rarity accents), the StyleBoxes (parchment panels with an ink border and a
hard offset "print" shadow, a night panel for the stars), sizes for a virtual 1280x720, and ink
drawing helpers. Fonts: **IM Fell English SC** (titles; Igino Marini) and **Patrick Hand**
(body and HUD; Patrick Wagesreiter), both SIL OFL 1.1, fetched from Google Fonts' GitHub by
`tools/fetch_fonts.sh` with their licence texts; without them the engine font is used. The UI
root is scaled by `min(w/1280, h/720)` (1.5 at 1920x1080), so layouts are written once.

## What each screen reads and calls

| Screen | Reads | Calls |
|---|---|---|
| HUD | `cw.hp/max_hp`, `cw.hours()`, `rules.sheet` (level, xp, class, hit dice, pending), `combat.status` (timers, slots, concentration), `combat.spells`, `items.hotbar()/selected()/coin()/sigil()`, CONDITION events | `items.select_hotbar` |
| Toasts | `items.drop_removed` (+ cached `drop_added` items), `items.note`, `rules.notice`, `rules.xp_gained`, rest events | - |
| Banner | `rules.leveled` | - |
| Prompts / E | `rules.sheet.resting/rest_ready`, `rules.downed`, `rules.rest_event`, tiles near the body in `cw.world` | `rest_short`, `rest_long`, `stand`, `revive`, `revive_stop`, `respawn` |
| Inventory | `items.item(i)`, `equipment`, `bonding`, `Items.recipes()`, campfire near | `move`, `use`, `unequip`, `drop`, `bond`, `craft` |
| Choices | `rules.choices`, `rules.pending_keys()`, SRD text, `Knacks.def` | `answer`, `pick_knack` |
| Constellation | `items.constellation` (kindled with grid spots, slots), loose sparks, shrine near | `kindle`, `swap_spark` |
| Spells | `combat.spells`, `combat.status` | quick-slot assignment (local, `user://ui.cfg`); casting via LocalInput `cc.cast` |
| Character | `rules.sheet`, `items.equipment`, `cw.stats` through `SheetModel` | - |
| FX | combat events, `cw.remotes`, `items.drops`, monsters client `monster_info` if present, `look.rank` | - |

## Accessors added to client systems

None. Nothing in `core/` changed. What the mirrors lack, and how the UI copes:

- **Deeds are not on the wire** (`rules.sheet` has no `deeds`). The sheet and the Knack cards
  read `sheet.deeds` if it ever appears; until then `GameUi.tally` counts this client's own
  digs, places and kills since joining, labelled as such. Wanted: `deeds` in CHAR (or a DEEDS
  message) from `RulesSystem.sheet`.
- **The answered build is not mirrored** (feats, fighting style, chosen skills). `SheetModel`
  makes a stand-in Character with the class defaults and auto answers, dresses it in the
  mirrored gear and sets the host's ability scores; AC, attacks, saves and skills can differ
  from the host's where a choice differs (Defense style, chosen skills). Wanted: the build's
  choices or the derived numbers (AC, attack bonus, save and skill bonuses) in CHAR.
- **Temporary hit points** are not mirrored (VITALS carries hp and max only), so the HP bar
  shows none.
- **Cast refusals are not sent**: `CombatSystem` keeps `last_refusal` on the host. The quick
  slots grey out from what the client knows (no slot, busy, bonus/reaction spent, unsupported)
  and a cast `cc.cast` itself refuses becomes a toast; a host refusal is silent. Wanted: a
  NOTE-like message from combat.
- **Monster look is not on the wire**: ENT_ADD carries name and kind, not `look` (slug, rank).
  Remote monsters therefore draw as primitives (an M2-base limitation), and `look.rank` is
  only read for local looks; ranks and affixes come from the monsters client's
  `monster_info(id, info)` signal when that system exists (the tour stands in for it).

## The tour

```bash
tools/soft_godot.sh --resolution 1280x720 -- offline cheats class=wizard gen=dev seed=3 \
    world=/tmp/x ui_tour=/tmp/claude-1000/godspark-ui timeout=220
```

`UiTour` (offline host, `cheats`) waits for the world, then: HUD; gives rings, magic items,
affixed gear and sparks (host_call) and wears six rings and a cloak through the client;
inventory with a tooltip; levels 4 (banner, Knack cards) and 15 (ASI half-made); a shrine,
kindles four sparks, constellation with a star hovered; the sigil flash; spells and an area
aim preview; the character sheet; three goblins with the reference brain (two get champion
and elite info as the monsters client would send) and a loot pile, fighting through the
combat client: telegraph, numbers, nameplates; downed (death saves), dead (respawn prompt);
a campfire (E held through `Input.action_press`) and the rest ring; a bed and the night
passing. It prints `TOUR shot <path>` for each picture and a frame-cost line for the fight.

## Measured

| What | Number |
|---|---|
| Tests | 2673 checks, ALL PASS (2558 before; +115 `test_interface.gd`) |
| Smoke | `tools/net_smoke.sh`, `FIGHT=1 SPAWN=goblin-warrior:2`, `RULES=1`: NET SMOKE PASS |
| Icon raster | about 6 ms per (category, colour) the first time, cached after |
| Frame cost in the tour's fight (3 goblins, numbers, plates, telegraphs, drops; CPU Vulkan under Xvfb, 1280x720, 96 fps) | interface (GameUi + HUD) avg 74 us, max 321 us; FX avg 78 us, max 440 us (1467 frames) |

## Known rough edges

- Remote monsters are primitives with our nameplates (look not on the wire, see above).
- The bed "still awake" prompt is fed by BED_WAIT; the tour has one player so it photographs
  the night passing instead (the prompt logic is tested headless).
- Deed counts are this session's only (above). Knack cards fall back to "for digging stone"
  style hints when nothing was counted.
- SheetModel numbers are an approximation where the host's answered choices differ from the
  defaults (above); the sheet says so in its footer.
- Ring layout: five rings under each hand; with the doll at 330 px wide the labels are 11 px.
- Nameplates step upward to avoid overlapping; a tight pack of ten still stacks tall.
- Floating numbers are 2D labels projected each frame (crisp, styled), not Label3D.
- The sigil flash fires on a dash start or an air jump; Featherfall and passive sparks do not
  flash.
- Quick-slot assignments live in `user://ui.cfg` per character name, not on the host.
- Not looked at at 1920x1080 (Xvfb here is 1280x720); the root scales by 1.5 there.
