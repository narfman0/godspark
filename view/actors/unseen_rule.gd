## How a creature combat marks Invisible (SRD: "you can't be seen") is drawn for this client: the
## Hide of a roper or cloaker waiting in the dark, the Invisibility spell. Combat's rules are the
## host's (CombatSight.can_see); this decides only the picture, from what the client knows.
##
##   UnseenRule.show(invisible, own, player, sees)   # SEEN, FAINT or GONE
##
## You keep sight of yourself, and of the other players: they are the party, and a co-op game where
## a friend vanishes is only confusing. What the own senses pierce (own effects sees_invisible: a
## spell that shows the invisible) shows faint. Everything else is gone: the body, its shadow, its
## plate and its target ring, so nothing gives a lurker away before it springs.
class_name UnseenRule
extends RefCounted

enum Show { SEEN, FAINT, GONE }

## Own effect ids (EFFECT events' what) that show the invisible.
const SEES := ["see-invisibility", "true-seeing"]
## ActorBody transparency while FAINT.
const FAINT_ALPHA := 0.65

static func show(invisible: bool, own: bool, player: bool, sees: bool) -> Show:
	if not invisible:
		return Show.SEEN
	return Show.FAINT if own or player or sees else Show.GONE

## Do these own effects (ids, a concentration: prefix ignored) show the invisible?
static func sees_invisible(effects: Array) -> bool:
	for e: String in effects:
		if e.trim_prefix("concentration:") in SEES:
			return true
	return false
