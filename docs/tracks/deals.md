# Track: Deals (M4 wave 2)

Branch `ws/deals`. Talk, trade, quests and patrons with the sim's people: rumours are real
chronicle events with places, shops and smiths sell what the settlement has at its prices,
work comes from what is happening, patrons reward standing. Design: [m4.md](../m4.md)
("Dealings", "Standing"); contract: [architecture.md](../architecture.md), "M4 contracts /
Deals".

## What was built

| File | What |
|---|---|
| `core/deals/deals.gd` | `Deals`: data access, hash-seeded picks (`h`, `rng`, `pick`, `weighted`), `day(sim)`, `where(sim, from, to)` (direction and distance in words), `at_site` (inside a place's rect), `site_named`, `neighbours`, `routes_of`, `lairs_on_routes`, `fill` |
| `core/deals/deals_talk.gd` | `DealsTalk`: `situation`, `line`, `rumours`, `rumour` |
| `core/deals/deals_shop.gd` | `DealsShop`: `shelves`, `rack`, `piece`, `buy_mult` / `sell_mult`, `sell_each`, `good_of` |
| `core/deals/deals_quests.gd` | `DealsQuests`: `offers`, `check`, `still_valid`, `target_pos` |
| `core/deals/deals_patron.gd` | `DealsPatron`: `tier`, `gift` |
| `core/deals/deals_system.gd` | `DealsSystem` (HostSystem.DEALS = 6): conversations, shops, services, quests, patrons, saving, cheats |
| `core/deals/deals_codec.gd`, `deals_client.gd` | SYS messages (JSON payloads) and the client mirror |
| `data/deals/lines.json`, `prices.json`, `quests.json` | what people say and know; prices, shelves, racks, services, patrons; quest kinds |
| `game/ui/deals_stopgap.gd` | **stopgap** keyboard UI until the Interface track's screens |
| `tools/deals_day.gd` | three days of one town's dealings while the world moves |
| `tests/test_deals.gd` | 152 checks |

## Talk

A player asks to talk (`TALK_TO {e}`). The host checks: the entity has meta `talk` (Life's
townsfolk, keepers, smiths, merchants, priests, guards, caravan escorts and drovers), body
centres within 5 tiles, line of sight (`HitShapes.line_to` from the player's eye), neither in
combat (`combat.in_combat` on both), the player not downed, and `life.stance != HOSTILE`
(standing at or below -40 with the faction, or a grudge). The answer is a conversation:
`{open, id, name, role, site, faction, line, view, options}`. The world does not pause.
Every 15 ticks the host re-checks (7 tiles, no sight check): walking away (`far`), the person
leaving or dying (`gone`), a fight (`fight`) or turning hostile (`hostile`) ends it with a
closing line.

**Lines** (`data/deals/lines.json`): a greeting by role, then the town's situation (or the
hour when nothing is happening), and one time in three a word of the culture. Chosen by a hash
of (world seed, person, game day, hour band: morning 5-11, day 11-17, evening 17-21, night),
so a person says the same thing within an hour band. Situations, most pressing first:
`besieged` (`besieged_by`), `raided` (`last_raided` within 30 days, or a raid, repelled raid,
monster raid, apex wrath or sack on the town in the chronicle), `war` (the faction is at war:
`{foe}`), `hungry` (`hungry > 0` or food at twice its base price), `caravan_due` (a caravan
travelling here: `{dest}` is where from), `prosperous` (wealth >= 2 a head, morale >= 0.6),
else `quiet`.

**Options** by role at a settlement: everyone `rumours`; merchant `shop` (a market or store
stands, or the world has no places); smith `smith` (a smithy); anyone who gives work today
`quests`; keeper `bed` (a tavern); priest `heal` (a shrine); keeper and priest `patron` (tier
1 or more with the faction); `turn_in:<qid>` for the player's open work given here; `bye`.
Party people (escorts, drovers) have `rumours` and `bye`; their rumours are about their home.

**Rumours** (`DealsTalk.rumours`): chronicle events of the last 60 game days whose names
(`site, lair, to, from, vfrom, rfrom, pfrom, a, b, army, faction, rfaction, dfaction, old,
route, places`) touch the town: its name, its faction, its neighbours (adjacent by any route)
and their factions, the routes out of it, the lairs on them. Filtered by what the role knows
(`knows`): a guard roads, raids and lairs; a merchant prices, famines and caravans; a priest
the sick and the dead; a keeper everything (`*`); townsfolk the big things; escorts and drovers
the road. Newest first, 5 for keepers, 4 for guards and merchants, 3 for others. Each:
`{id (chronicle index), text (sim.describe), kind, t, site, dir, dist, tiles}`; `site` is
the first name field that resolves to a site (settlements and lairs as they are, then names
Deals has seen, for fallen places), else for a route the far end of that route from here;
`dir` is east/west (with above/below when the height differs a lot), `dist` close by / a short
walk / a fair walk / a long walk / far away. Hearing one adds it to the player's known list
(saved, at most 120, mirrored in RUMOUR).

## Shops (data/deals/prices.json)

**The store** (merchant, a market or store): each shelf row the tier carries
(`shelves`: supplies, torches, rope, campfire from timber; healing potions from luxuries in
villages and up; trade goods `trade:food/timber/ore/tools/luxuries`). How many: what the stock
spares above `keep` (0.6) of the town's own target, divided by `units` per item, capped by
`max`. Price each: trade goods the sim's local price (`SimEconomy.price`) times units; other
rows their list value (row `value` or `Items.value`) times the good's local price over its
base; then times `buy_markup` (1.25).

**The smith** (smithy): a rack per settlement per game day from a hash of (world seed, site,
day, piece): pieces by tier (2 / 4 / 7 / 10) times an ore factor (stock over target,
0.25-1.25) and a tools factor (0.5-1.1), never more than the ore stock covers at 1 ore a
piece; no ore at all: one crude copper piece of scrap. Kinds from the culture (`kinds`:
dwarves warhammers, axes, picks, heavy armour and shields; elves bows, scimitars, rapiers and
light armour; halflings slings, daggers and light armour; drow hand crossbows; orcs greataxes
and hide ...). Each piece is `ItemGen.roll` (affixes at the tier's level hint), its +N magic
removed, its quality from the tier's weights (hamlet crude/common, village up to fine, town up
to masterwork 5%, city fine 40% and masterwork 15%), one step up when wealth per head >= 3,
down under 0.5; material by tier (copper, iron; silver in towns with >= 40 ore; mithral only in
dwarf, elf, drow and goliath cities); common and crude pieces keep no affix, fine one,
masterwork two. Price: `Items.value` times the ore price factor (0.75-1.5) times the markup.
Sold pieces are recorded per site per day (saved); a new day is a new rack.

**Buying** (`BUY {l, n}`, in an open shop): needs coin and room; `WorldSim.player_trade(sid,
good, -units * n, -price)` takes the goods out of the stock and adds the coin to the wealth (a
smith piece takes its ore); the player pays. **Selling** (`SELL {s, n}`): trade goods and ore
(rows with `good`: ore:copper 0.25 ore units, iron 0.5, silver 2) at the local price times
`sell_trade` (0.85), so a town with plenty pays less; gear and magic items at `sell_gear`
(0.25) of value; other things `sell_other` (0.3); rubble, tiles, coin and sparks are
`worthless`. One sale never takes more than `wealth_cap` (0.25) of the town's wealth (`poor`);
trade goods and ore enter the stock, the coin leaves the wealth. This is how finding ore pays.

**Modifiers** (on the buy price; the sell price by the inverse): standing x 0.002 a point (100:
-20%, -40: +8%), a Bond with the people -5%, Silver Tongue (`price_mult` tag) -5/10/15%, each
patron tier -5%; buy never below 0.6, sell never above 1.3.

**Services**: `bed` (keeper, tavern): 2 / 3 / 5 / 8 coin by tier, free for a patron of the
faction; sets the respawn point through `RulesSystem.set_bed(e, cell, inn = true)` at the
tavern's keeper anchor (no night passes; it is a respawn point). `heal` (priest, shrine): all
missing hit points through `rules.heal`, 1 coin each, at least 5. The coin goes to the town.

## Quests (data/deals/quests.json)

Offers are made once per settlement per game day, from the sim as it stands when anyone first
asks, with choices hashed from (world seed, site, day); the list is kept for the day (saved),
so every player sees the same work that day. An offer whose thing has gone (the lair, the
party) drops out. Taken offers are one shared instance: others who accept join the party.
At most 4 ordinary offers, in this order, plus patron work.

| Kind | Giver | Made when | Done when | Time | On the way |
|---|---|---|---|---|---|
| bounty | guard | a lair hunts a route out of town, the town holds a grievance, or the nearest lair within 900 tiles | `n` of its creatures (half, at least 2; all if 3 or fewer) died while a party member was within 90 tiles of the lair: ready, turn in at the town | 8 d | lair gone otherwise: **beaten** (25% of coin and standing) |
| escort | merchant | an outbound caravan of the town on its first leg, < 35% along | it reaches its destination (the sim turns it home) with at least half its members and a party member within 60 tiles of it for half the checks: done where it arrives | 2 d | caravan gone: failed. Accepting **holds** it (`SimParty.held`) until a party member is within 40 tiles or 3 game hours pass |
| recover | merchant | an ambush on the town's caravans (won by the raiders) in 30 days, and a raid party from the raiders' home still abroad with cargo | `n` of that good as trade items handed in (Life drops a laden raider's share as `trade:<good>`) | 10 d | |
| relief | priest, else keeper | the town is hungry | `n` food (half the population, 20-300) handed in as `trade:food`; it enters the stock; pays its local value x 1.1 | 12 d | |
| defend | guard | a raid or army travelling to this town | a `raid` (thrown back) or `raid_repelled` line for the town after accepting, with a party member at the town: done; raid won: failed | 2 d | no one there: beaten; the party gone without a line: lapsed |
| message | keeper | the town has neighbours | a party member inside the target site's place (rect + 8), then turn in | 6 d | |
| hunt (patron) | keeper, priest | an apex lair within 900 tiles | the whole lair killed by the party | 14 d | beaten 25% |
| siege (patron) | keeper, priest | a town of the faction is besieged | the siege ends with the town still the faction's, a party member having been there | 6 d | town lost: failed |

Every quest: id `q<site>.<day>.<kind>`, `title`, `why` (a line built from the event), `goal`,
`due`, `target` (the sim entity: lair, party, site, good, n), `reward` `{coin, standing, xp,
item}`, `state` (offered, active, ready, done, failed, lapsed, beaten, abandoned), `players`
(names), `progress {have, need, text}`, `giver`. Coin: base + per x size of the job, never more
than 20% of the town's wealth (checked again at payment). Payment goes to every party member
within 135 tiles of where it ends: the coin (split) out of the town's wealth through
`player_trade`, standing (`life.add_standing`), XP (`rules.award_xp(..., "quest")`), deeds
`quest` and `quest:<kind>` (`rules.add_deed`), and when `item` (hashed chance per kind) a
smith-made piece from the giver town, a quality step up, scaled to the player's level.
Abandoning (`ABANDON`): escorts -4 and defence -3 standing; the last to leave ends it.
Expiry: **lapsed**, no penalty. Validity as the sim moves: the giver town gone or changed
hands lapses everything; a lair cleared by an NPC expedition is beaten; checks run every
second on the host thread.

Saved: the world keeps open quests (and ended ones for 30 game days, so offline members see
the outcome), today's offers, the smiths' sold pieces and seen names (`save_world`); each
player keeps their rumours, their log of ended quests and the patron gifts given
(`save_player`).

## Patrons (prices.json `patron`)

Tiers at standing 25 / 50 / 75 with a faction. A Bond with its people (Knacks: `people:
<culture>`) raises standing to Life's `bond_floor` (30), which is the first tier. A patron is
the keeper or priest of any of its settlements (option `patron`). Each tier's gift once
(recorded per player and faction): tier 1 a made-to-order piece from that town's smith
(the player's wielded kind, a quality step above the best on today's rack, the player's level
for affixes; mithral possible in a dwarf, elf, drow or goliath city); tier 2 an uncommon and
tier 3 a rare SRD magic item from the pools (by slug; only items whose mods work or partly
work), with the reason in the text. Benefits: -5% prices per tier, a free bed; from tier 2 the
patron work (hunt, siege) when the sim has an apex lair or a siege. Falling under 25 suspends
it all (PATRON says `suspended`); gifts stay given.

## Messages (DealsCodec, SYS system 6, JSON payloads like Life's)

| Kind | Dir | Payload |
|---|---|---|
| TALK 1 | h->c | `{open, id, name, role, site, faction, line, view, options: [{id, label}], rumours?, new?, offers?}` or `{open: false, why, line}` |
| SHOP 2 | h->c | `{open, kind (store / smith), site, town, listings: [{id, item, n, price}], sell: {"<slot>": price}, wealth}` or `{open: false}` |
| QUESTS 3 | h->c | `{quests: [quest view]}` the whole log (open quests with `where` [x, y] and `target_site`, then ended snapshots) |
| RUMOUR 4 | h->c | `{rumours: [rumour], all}` newly heard, or the full list on join |
| PATRON 5 | h->c | `{patrons: {faction: {tier, standing, given, suspended, name}}}` when it changes |
| NOTE 6 | h->c | `{op, ok, word}` the answer to every request but LEAVE |
| TALK_TO 64 / CHOOSE 65 / LEAVE 66 / BUY 67 / SELL 68 / SERVICE 69 / ACCEPT 70 / ABANDON 71 / TURN_IN 72 | c->h | `{e}` / `{o}` / `{}` / `{l, n}` / `{s, n}` / `{id}` / `{q}` / `{q}` / `{q}` |
| CHEAT 79 | c->h | `{op: goto, role}` / `{op: coin, n}` / `{op: give, base, n}` / `{op: standing, faction, n}` / `{op: complete, q}` / `{op: report}` (host `cheats`) |

Refusal words: far, no_sight, no_one, no_talk, fight, down, hostile, not_talking, no_option,
not_shopping, no_listing, none_left, coin, full, bad_index, empty, worthless, poor, no_service,
no_rules, full_hp, no_quest, already, not_here, gone, missing, not_ready, no_cheats, unknown.
A shop's traffic in the smoke: a few hundred bytes per message.

## The client surface (for the Interface track)

```gdscript
var dc := cw.system(HostSystem.DEALS) as DealsClient
signal talk_changed(conversation: Dictionary)   # {} when closed (dc.closed: {why, line})
signal shop_changed(shop: Dictionary)           # {} when closed
signal quests_changed(quests: Array)
signal rumour_heard(rumours: Array)             # the new ones (all on join)
signal patron_changed(patrons: Dictionary)
signal note(op: int, ok: bool, word: String)    # DealsCodec.Msg op
dc.conversation; dc.shop; dc.quests; dc.rumours; dc.patrons
dc.talking(); dc.shopping(); dc.quests_in("active" | "done" | "failed" | "lapsed" | "beaten" | "abandoned")
dc.map_marks()                                  # rumours with a site id, for the map
dc.talk(entity_id); dc.choose(option_id); dc.leave()
dc.buy(listing_id, n); dc.sell(inventory_slot, n); dc.service("bed" | "heal")
dc.accept(quest_id); dc.abandon(quest_id); dc.turn_in(quest_id)
```

Who can be talked to: `LifeClient.person(id).talk`; names and roles there too. Item names:
`ItemGen.name(item)`; values `Items.value`. A conversation's `view` is main, rumours, shop,
smith, quests or patron; `offers` (quests view) carry title, why, goal, giver, reward, state.
Prices in SHOP are what this player pays (modifiers applied); `sell` maps inventory slots to
what the town pays each. Quest `where` is the target's tile position; `target_site` its site.

**The stopgap** (`game/ui/deals_stopgap.gd`, since replaced by the M4 Interface track's
screens, [m4-interface.md](m4-interface.md); it also added the ATLAS message): the context prompt shows
"E: talk to <name>, <role>" within 4 tiles; E opens the talk; a parchment panel (top left)
and the log list the options by number: 1-9 choose; in a shop 1-9 buy one, Shift+1-9 sell one
of the n-th sellable stack, Ctrl+1-9 the whole stack; in work 1-9 accept; 0 or Esc back or
leave. Its three call sites: `GameUi.attach` (makes it), `GameUi._unhandled_input` (keys),
`ContextPrompts.tick` (the prompt).

## Hooks added in other tracks

| Where | What | Why |
|---|---|---|
| `core/sim/world_sim.gd` | `player_trade(sid, good, n, coin) -> bool`, `hold_party(pid, on) -> bool`, stat `player_trades` | purchases, sales, deliveries and rewards enter the settlement's books (refused if any stock or the wealth would go negative); an escort holds its caravan |
| `core/sim/sim_party.gd` | `held` (saved only when true) | the hold survives a save |
| `core/sim/sim_conflict.gd` | `tick_parties` skips `held` parties as it skips `frozen` | a held caravan neither moves nor runs timers |
| `core/rules/rules_system.gd` | `set_bed(e, cell, inn := true)`; `respawn_point` accepts an inn bed whose cell (and the one above) is open; sleeping in a real bed clears `bed_inn` | a paid room is a respawn point without a bed tile |
| `core/rules/character.gd` | `bed_inn` (saved as `bed_inn` when true) | |
| `data/items/base.json` | rows `trade:food`, `trade:timber`, `trade:ore`, `trade:tools`, `trade:luxuries` (kind material, `trade`, `good`, stack 999, value = the good's base price, weight 1/4/4/3/1, not placeable); `good` and `units` on `ore:copper` (0.25), `ore:iron` (0.5), `ore:silver` (2) | goods to buy, sell and carry; Life now drops a laden raider's cargo as these rows instead of coin |
| `game/ui/game_ui.gd`, `context_prompts.gd` | the stopgap's three call sites | E to talk |
| `game/main.gd` | `HOSTSTATS deals:` line | smokes |
| `net/bot_client.gd`, `tools/net_smoke.sh` | `deals=1` scenario, `DEALS=1` variant | the smoke |

No change to Life, Items' code, Monsters, Places, the protocol or the endpoints.

## Determinism

Lines, racks, offers and gifts come from hashes of (world seed, ids, day); nothing in Deals
calls the sim's generator or the host's dice, and reading never writes the sim. Test
(`_wander`): two hosts, same seed; on one a player with standing 100 everywhere tours the
towns for a game week, talking to everyone who talks and opening every rumour, shop, smith and
work list (599 talks, 918 views, 1198 offers seen) without buying: `sim.rng.state` and
`to_dict()` identical to the host where nobody dealt.

## Measured

- Tests: 3624 checks, ALL PASS (3472 before; 152 in `test_deals.gd`).
- Smokes: plain, `FIGHT=1 SPAWN=goblin-warrior:2`, `RULES=1`, `SPAWNS=1 WORLD="gen=dev seed=3"
  SEE=`, `ALL=1`, `LIFE=1`, `DEALS=1`: NET SMOKE PASS. DEALS: bot1 talks to the merchant, buys a
  rope (3 coin), sells 6 iron ore (12 coin), takes "Word to Umberwood Den" from the keeper,
  completes it (cheat), turns it in (+11 coin, +2 standing); host and client DEALSCHECK agree
  (`coin=220 rope=3 ore=0 quest=done standing=2`) and the rejoin brings it all back.
- `tools/deals_day.gd -- seed=5`: a round of 4 buys and 2 sales moves the town's books
  exactly (wealth +150, food -40, timber -7, ore +14) and the audit stays clean a week on.

## Deviations from the brief and architecture.md

- Payloads are JSON (as Life's), not byte layouts: low rate, dictionaries of item records.
- Roles: no new Life roles. "Guard captain" is any guard, "elder" the keeper; the patron is a
  keeper or priest at any of the faction's settlements (the hall/shrine building is not
  required for patronage, only for services).
- Escort offers need a caravan already leaving (on its first leg, < 35%): the sim plans
  caravans only every 5 days, so this work is rare in a given town on a given day. The hold
  starts at acceptance, not before.
- Recover only for a raid party still abroad with cargo; goods back at the raiders' camp are
  in that town's stock (no quest yet).
- Defend: a raid that arrives at once (the sim's own arrival while players watch) is fought by
  Life; the quest only exists while the raid is still on the road.
- A paid bed is a respawn point only (the night passes in real bed tiles, as before).
- Patron work: a hunt is offered and taken in a test (an apex lair forced); its completion
  and the siege kind are not exercised end to end.

## Open issues

- The stopgap panel is plain text; the Interface track builds the dialogue, shop, quest log,
  map marks and patron screens on `DealsClient`.
- Rumours in a young world are few (60-day window, events must touch the town); the window
  and `TELL` counts are guesses.
- Quest XP and coin numbers are first guesses; nothing balances them against loot yet.
- Torches, ropes and other tile items are worthless to sell back (kind tile).
- A smith piece taken by a buyer takes 1 ore; the sim's ore use for tools is unchanged, so a
  busy smith drains ore faster than the sim alone would.
- The escort's "most of its cargo" is checked as "most of its people" (cargo is sold on
  arrival before Deals looks).
- Not judged by a human: the lines' tone, the prices' feel, whether the work is worth doing.
