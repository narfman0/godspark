# Track: Interface (M4 wave 2)

Branch `ws/m4-interface`, cut from main 0253399. The living world on screen: talking to people,
shops and smiths, quests, a world map, standing and patrons, places and parties in the world,
controls and help, and a scripted tour. It extends the M2 interface ([interface.md](interface.md):
theme, screen stack, input routing, toasts) and replaces the Deals stopgap. Design:
[m4.md](../m4.md); the client surfaces: [deals.md](deals.md), [life.md](life.md),
[places.md](places.md).

UI and view own no rules: every action is a `DealsClient` request validated on the host. The
interface is built only by `ViewPresenter` (windowed clients); dedicated servers, bots and
headless runs never load it or a font.

## Files

| File | What |
|---|---|
| `game/ui/deals_ui.gd` | `DealsUi`: who E talks to, the dialogue panel, number keys, words for every Deals answer, rumours and map marks, quest outcomes and the hand-in celebration, standing toasts and history, patron tier banners, place banners on arrival, the pinned quest |
| `game/ui/dialogue_panel.gd` | `DialoguePanel`: the conversation, anchored low |
| `game/ui/people_marks.gd` | `PeopleMarks`: marks over people, the talk prompt over the nearest, name plates on hover, party plates (one canvas) |
| `game/ui/shop_screen.gd` | `ShopScreen`: the two-sided trade screen |
| `game/ui/quest_log.gd`, `quest_tracker.gd` | `QuestLogScreen` (J) and `QuestTracker` (HUD) |
| `game/ui/world_map.gd` | `WorldMapScreen` (M) |
| `game/ui/standing_screen.gd` | `StandingScreen` (P) |
| `game/ui/help_screen.gd`, `controls.gd` | `HelpScreen` (F1 or H) and `Controls`, the control scheme in one place |
| `game/ui/emblems.gd` | `Emblems`: portraits (role icon on faction colour), marks, map emblems (settlement by culture and tier, lair, ruin, portal) |
| `game/ui/deals_logic.gd`, `map_logic.gd` | pure helpers (tested): words, prices, quests, standing, bearings; map layout, discovery, polylines |
| `game/ui/world_tour.gd` | `WorldTour extends UiTour`: the living-world tour |
| `tests/test_m4_interface.gd` | 130 checks |

Removed: `game/ui/deals_stopgap.gd`. Edited (additive): `game_ui.gd` (DealsUi, PeopleMarks,
the new screens and keys, `number_keys_taken`, Esc leaves a conversation, the host's arrival
note folded into the banner), `hud.gd` (tracker, screen buttons, place banner, coin changes,
talk hint), `context_prompts.gd`, `input_logic.gd` (`hotbar_keys_allowed`), `ui_copy.gd` (Deals
refusals, closing words), `game/local_input.gd` (number keys skip the hotbar while the dialogue
takes them; no movement code touched), `game/chronicle_overlay.gd` (`set_quiet` while
talking), `game/main.gd` (`world_tour=DIR`), `view/fx/nameplates.gd` (calm Life people get the
interface's plate instead), `project.godot` (`quest_log` J, `world_map` M, `standing` P,
`help` F1 and H), `README.md`.

## Screens and keys

| Screen | Key | Reads | Calls |
|---|---|---|---|
| Talk prompt, marks, plates | (E talks) | `lc.people`, `cw.remotes`, `dc.quests`, `dc.sites[..].work`, `dc.patrons`, FX plates' combat activity | `dc.talk(id)` |
| Dialogue (low, not a screen: the world keeps its clicks outside it) | 1-9, 0, Esc | `dc.conversation` (line, view, options, rumours, new, offers), `dc.sites` (town), `lc.factions` | `dc.choose`, `dc.accept`, `dc.leave` |
| Shop / smith | opens with the shop; Esc back | `dc.shop` (listings, sell, wealth), `dc.sites` (state, pop, culture, faction), `lc.standing`, `rules.sheet.bonds`, `dc.patrons`, `items` | `dc.buy(l, n)`, `dc.sell(s, n)`, `dc.service` |
| Quest log | J | `dc.quests`, `dc.conversation.offers`, `dc.sim_hour()`, META sites | `dc.accept`, `dc.abandon`, `choose("turn_in:")` |
| Tracker (HUD) | pin in the log | the pinned quest, `where` / `target_site` / META | - |
| World map | M | META (surface, bands, sites), `dc.sites`, `dc.routes`, `dc.seen`, `dc.rumours`, `dc.quests`, `lc.people` in view, `cw.remotes` (players) | - |
| Standing | P | `lc.factions`, `lc.standing`, `dc.patrons`, `dc.sites`, DealsUi history | - |
| Controls card | F1 or H | `Controls.GROUPS` | - |
| Place banner (HUD) | on entering | META sites, `dc.sites` | - |
| Screen buttons (HUD, under the clock) | click | `DealsUi.fresh_marks` (Map pulses) | `gu.toggle` |

Number keys: while the dialogue shows, `GameUi.number_keys_taken()` is true; `LocalInput` skips
the hotbar keys (`InputLogic.hotbar_keys_allowed`), `DealsUi.input` maps 1-9 to the shown
options (a handed-in quest's stale option is hidden) and 0 to farewell. Movement keys still
work. Clicks on the dialogue never reach the world (`mouse_over_ui`); the shop, log, map,
standing and help are stacked screens (the catcher takes every click).

Closing: the host's reasons become a word and its line ("Out of earshot. You walked off
mid-sentence.", "A fight!", "They left", "Hostile"). Rumours: a toast and the Map button pulses
with the count of new places until the map opens. Hand-in: the "Done!" banner and a toast with
the reward (coin paid, standing, XP, and the smith's piece when there is one; XP and standing
also toast on their own). Endings the player did not cause (beaten, failed, lapsed, made ready
by someone else) arrive as a note. Standing: a toast for moves of 3 or more or a change of
band; a banner on reaching or losing a patron tier.

## Wire and mirror additions (outside game/ and view/)

| Where | What | Size |
|---|---|---|
| `core/deals/deals_codec.gd`, `deals_system.gd` | SYS Deals `ATLAS` (7), h->c JSON: on join `{t, sites, routes, seen, all}`; every 5 s to all players `{t, sites}` only when a digest of the list changes (population counted in tens); once a second, to one player, `{t, seen: [new ids]}` when they first stand at a site | dev world (seed 3, 2048x1024, day 60, 17 sites, 8 routes): 5440 B on join, a site refresh 1583 B; the loopback test world (1024x512, 11 sites, 5 routes): 3560 B (1349 B after zstd), a site refresh 909 B; a seen message ~25 B |
| | site: `{id, kind, name, culture, tier, pop, faction, state: DealsTalk.situation, work: [giver roles with ordinary offers today]}` for settlements (work only within 120 tiles of a player), `{id, kind, name, lair, apex}` for lairs, `{id, kind, ruin, name}` otherwise (a fallen town's name from Deals' `names`) | |
| | route: `{id, a, b, kind, name, path}`, `path` every 8th feet cell of `Places.route_path` plus the last | |
| | `DealsSystem.work_roles(sid)`: reads the day's offers when someone has asked, else previews `DealsQuests.offers` (pure) without keeping them, so the first real ask still makes the day's list (the determinism tests in test_deals stay green; an earlier version that cached them broke three) | |
| | discovery: `DealsSystem.seen` (player id -> site ids stood at, `Deals.at_site` margin 8 for settlements, 4 otherwise), saved in `save_player` as `seen` (an array of ids) | a few bytes a site |
| `core/deals/deals_client.gd` | `sites`, `routes`, `seen`, `sim_t`, `clock_h`, `atlas_changed(fresh)`, `sim_hour()`, `site_name(sid)` | |
| `core/life/life_system.gd`, `life_codec.gd` | PEOPLE: a party member's info also carries `party` (caravan, raid, ...), `home` and `dest` (site ids, as at spawn) | ~30 B a party member, once |

Nothing else in `core/` changed; no protocol change (SYS payloads only). META is unchanged: it
carries sites but not routes, places or names, and those come in ATLAS.

Discovery = sites stood at (`dc.seen`, saved on the host with the player in Deals) plus sites
named in heard rumours (`dc.rumours`, already saved by Deals) plus quest sites and targets
(`dc.quests`). The map draws nothing else, and parties only while their people are in view.

## The tour

```bash
tools/bootstrap.sh            # once: models and fonts
tools/soft_godot.sh --resolution 1280x720 -- offline cheats class=fighter gen=dev seed=3 sleep=1440 \
    world=/tmp/claude-1000/m4ui-world world_tour=/tmp/claude-1000/godspark-m4ui timeout=460
```

`sleep=1440` ages the world 60 days so there is news. Beats (`TOUR shot` per picture, 22):
01 arrival banner, 02 talk prompt over the merchant, 03 dialogue, 04 the keeper's rumours, 05
shop, 06 a rope bought and ore sold (coin moving), 07 the smith's rack with a tooltip compared
to what is worn, 08 work on offer, 09 the log, 10 the tracker, 11 the map, 12 zoomed with a
place card, 13 a caravan with its plate (Life's `cheat_party`), 14 raiders coming
(`schedule("raid")`), 15-16 the raid met by the guards, 17 the hand-in option, 18 handed in, 19
patron tier 1 (Deals' standing cheat), 20 the gift, 21 standing, 22 the controls card. Scene
setting goes through Deals' and Life's cheats or `host_call` (teleports beside people); the
player's actions through `DealsClient`.

## Measured

| What | Number |
|---|---|
| Tests | 3754 checks, ALL PASS (3624 before; 130 in `test_m4_interface.gd`) |
| Smokes | plain, `FIGHT=1 SPAWN=goblin-warrior:2`, `RULES=1`, `SPAWNS=1 WORLD="gen=dev seed=3" SEE=`, `LIFE=1`, `DEALS=1`, `ALL=1`: NET SMOKE PASS (each first try) |
| ATLAS, dev world seed 3 at day 60 | 5440 B JSON on join (17 sites, 8 routes), 1583 B for a site refresh |
| Tour | 22 shots in /tmp/claude-1000/godspark-m4ui/, about 3 minutes under soft_godot |

## Known rough edges

- The dialogue's portrait is a role icon on the faction's colour; people's looks are not used.
- `work` marks come from a preview of the day's offers until someone asks; a town whose state
  changes before the first ask can show a mark for work that is then not offered (or miss one).
- A party plate's "bound for" is the destination at spawn; a caravan that turns home keeps it.
- The talk prompt is drawn over the person, not in the HUD's prompt box; off screen, nothing.
- The map's "known roads" need both ends known; a road you walked to an unheard place is not
  drawn until you reach it. Party markers on the map are the people in view only.
- Rumour "mark on map" choices live in memory (not saved); all are marked on join.
- Standing history is this session's (Life does not mirror past reasons).
- Escort `where` updates only when QUESTS is resent; the tracker's pointer to a moving caravan
  lags between updates.
- Not looked at at 1920x1080; the root scales by 1.5 there.
- What only a human with a mouse can judge: hover and drag on the map, Shift-click and the
  nudge in the shop, whether the marks over heads read at a glance in a crowd, the dialogue's
  place on screen in a fight, and whether the copy's tone lands.
