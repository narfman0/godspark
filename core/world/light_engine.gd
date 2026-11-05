## Per-tile light for rules (SRD Bright / Dim / Darkness) and for the view. Pure core: no nodes.
##
##   var light := LightEngine.new(world)
##   light.ensure_region(Rect2i(0, 0, 64, 64))   # lazy; level_at() also computes on demand
##   light.category_at(x, y) == LightEngine.Category.BRIGHT
##   light.add_light(id, 10.5, 40.2, LightEngine.TORCH)
##
## Two fields, one byte per tile each:
##   sky:   sunlight. Falls straight down every column until the first opaque tile (cells at
##          or above `sky_top(x)` hold SUN), then spreads sideways and down with falloff.
##   block: emissive tiles (TileDefs.emit) and carried lights.
## level = max(block, sky * sun). Changing `sun` recomputes nothing.
##
## Spreading is a Dijkstra flood over 8 neighbours: an orthogonal step costs STEP levels, a
## diagonal step DIAG (STEP * 1.4, so distances are octile, close to Euclidean). A
## diagonal step needs both orthogonal cells it squeezes between to be clear. Opaque tiles
## receive light and pass it on only to other opaque tiles, orthogonally, at SOLID_STEP per
## tile: never back out into open cells. So light never crosses a wall, but the view can show
## the first few tiles of rock under a lit surface or around a lit cave.
##
## Levels: a torch is DIM_MIN + 16 * STEP = 85. It reads BRIGHT (>= 45) within 8 tiles,
## DIM (>= 5) out to 16 tiles, DARK beyond. That is the SRD torch: 20 ft bright, 20 ft more
## dim, at 2.5 ft per tile. Sunlight uses the same scale, so cave mouths fade out over 16 tiles.
##
## Background walls do not affect light: a cell is sunlit when nothing opaque is above it
## (wall or not), and a covered cell gets only what spreads to it.
##
## Storage is one page per computed chunk (block then sky, a byte per tile), so only what
## has been looked at costs memory. Tiles are read through `world.light_fg`: on a sparse
## (client) world an unloaded cell is air above the world's sky_line and opaque below it,
## and pages of unloaded chunks with no loaded neighbour are freed.
class_name LightEngine
extends RefCounted

enum Category { DARK, DIM, BRIGHT }

const STEP := 5
const DIAG := 7
## Level lost per tile inside opaque tiles.
const SOLID_STEP := 22
const MAX := 125
const DIM_MIN := 5
const BRIGHT_MIN := 45
## A torch: bright 8 tiles (20 ft), dim to 16 tiles (40 ft).
const TORCH := 85
## Direct noon sunlight.
const SUN := 85
## Chunks are computed in batches of at most this many chunks per side.
const BATCH := 4

## light_changed(rect): levels in rect (tile units) may have changed. A change of `sun`
## reports the whole world.
signal light_changed(rect: Rect2i)

var world: TileWorld
## 0 night .. 1 noon. Scales the sky field when read.
var sun := 1.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if value != sun:
			sun = value
			light_changed.emit(Rect2i(0, 0, _w, _h))

## Bytes per field in a page.
const PAGE := K.CHUNK * K.CHUNK

var _w: int
var _h: int
var _cxn: int
## Per chunk: PAGE block bytes then PAGE sky bytes, or empty when not computed.
var _pages: Array[PackedByteArray] = []
var _zeros := PackedByteArray()
var _top := PackedInt32Array()   ## per column: lowest y that sees the sky, -1 = not scanned
var _done := PackedByteArray()   ## per chunk: 1 once computed
var _lights := {}                ## id -> Vector3i(x, y, strength)
## Deferred mode (the view's): whole-chunk changes are queued, and process() works through
## them and through cold chunks a budget at a time, so a frame never pays for more than one
## chunk's flood plus one update. Off (default): everything happens at once, as before.
var deferred := false
var _queue: Array[Vector2i] = []
var _queued := {}
var _reach := 0                  ## tiles a level can travel: ceil(strongest source / STEP)

func _init(w: TileWorld) -> void:
	world = w
	_w = w.width
	_h = w.height
	_cxn = w.chunks_x
	_pages.resize(w.chunks_x * w.chunks_y)
	_zeros.resize(K.CHUNK)
	_top.resize(_w)
	_top.fill(-1)
	_done.resize(w.chunks_x * w.chunks_y)
	var strongest := SUN
	for e in TileDefs.emit:
		strongest = maxi(strongest, emit_level(e))
	_reach = ceili(float(strongest) / STEP)
	world.tile_changed.connect(_on_tile_changed)
	world.chunk_changed.connect(_on_chunk_changed)

## Light level for a tile's `emit` value (0-15): emit 15 is a torch.
static func emit_level(emit: int) -> int:
	return 0 if emit <= 0 else mini(MAX, DIM_MIN + (emit + 1) * STEP)

## Strength for a light that sheds bright light for half of `total_ft` and dim light for the
## rest (torch 40, lantern 60, the Light cantrip 40, a candle 10).
static func strength_for_ft(total_ft: float) -> int:
	return mini(MAX, DIM_MIN + roundi(K.ft(total_ft)) * STEP)

static func category_of(level: int) -> Category:
	if level >= BRIGHT_MIN:
		return Category.BRIGHT
	if level >= DIM_MIN:
		return Category.DIM
	return Category.DARK

func level_at(x: int, y: int) -> int:
	if not world.in_bounds(x, y):
		return int(SUN * sun + 0.5) if y >= _h and x >= 0 and x < _w else 0
	if _done[(x >> 5) + (y >> 5) * world.chunks_x] == 0:
		ensure_region(Rect2i(x, y, 1, 1))
	return maxi(_cell(x, y, 0), int(_cell(x, y, PAGE) * sun + 0.5))

func category_at(x: int, y: int) -> Category:
	return category_of(level_at(x, y))

## The raw fields, for the view (sky is unscaled by sun). Ensure the region first.
func block_at(x: int, y: int) -> int:
	return _cell(x, y, 0) if world.in_bounds(x, y) else 0

func sky_at(x: int, y: int) -> int:
	if world.in_bounds(x, y):
		return _cell(x, y, PAGE)
	return SUN if y >= _h and x >= 0 and x < _w else 0

## Stored value of one field (off 0 block, PAGE sky) at an in-bounds cell; 0 if not computed.
func _cell(x: int, y: int, off: int) -> int:
	var p := _pages[(x >> 5) + (y >> 5) * _cxn]
	return 0 if p.is_empty() else p[(x & 31) + ((y & 31) << 5) + off]

## Chunks with a light page (memory: 2 KB each).
func page_count() -> int:
	var n := 0
	for p in _pages:
		if not p.is_empty():
			n += 1
	return n

## One byte per tile of `rect`, rows bottom to top, for an R8 texture. sky = true gives the
## unscaled sky field, false the block field. Outside the world reads 0 (sky: SUN above it).
## Does not compute anything: call ensure_region(rect) first.
func region_bytes(rect: Rect2i, sky: bool) -> PackedByteArray:
	var off := PAGE if sky else 0
	var x0 := clampi(rect.position.x, 0, _w)
	var x1 := clampi(rect.end.x, 0, _w)
	var left := PackedByteArray()
	left.resize(x0 - rect.position.x)
	var right := PackedByteArray()
	right.resize(rect.end.x - x1)
	var blank := PackedByteArray()
	blank.resize(rect.size.x)
	var above := blank
	if sky:
		above = blank.duplicate()
		above.fill(0)
		for x in range(x0, x1):
			above[x - rect.position.x] = SUN
	var out := PackedByteArray()
	for r in rect.size.y:
		var y := rect.position.y + r
		if y < 0 or x1 <= x0:
			out.append_array(blank)
		elif y >= _h:
			out.append_array(above)
		else:
			out.append_array(left)
			var x := x0
			var row := (y >> 5) * _cxn
			var base := ((y & 31) << 5) + off
			while x < x1:
				var e := mini(x1, ((x >> 5) + 1) << 5)
				var p := _pages[(x >> 5) + row]
				if p.is_empty():
					out.append_array(_zeros.slice(0, e - x))
				else:
					out.append_array(p.slice(base + (x & 31), base + (x & 31) + e - x))
				x = e
			out.append_array(right)
	return out

## Lowest y in column x that sees open sky (nothing opaque at or above it).
func sky_top(x: int) -> int:
	if x < 0 or x >= _w:
		return _h
	if _top[x] < 0:
		_top[x] = _scan_top(x, _h - 1)
	return _top[x]

func add_light(id: int, x: float, y: float, strength: int) -> void:
	strength = clampi(strength, 0, MAX)
	var l := Vector3i(floori(x), floori(y), strength)
	if _lights.get(id) == l:
		return
	var old: Variant = _lights.get(id)
	_lights[id] = l
	_reach = maxi(_reach, ceili(float(strength) / STEP))
	var box := _around(Vector2i(l.x, l.y))
	if old != null:
		box = box.merge(_around(Vector2i(old.x, old.y)))
	_update(box, true, false)

func move_light(id: int, x: float, y: float) -> void:
	if not _lights.has(id):
		return
	var l: Vector3i = _lights[id]
	if Vector2i(floori(x), floori(y)) == Vector2i(l.x, l.y):
		return
	add_light(id, x, y, l.z)

func remove_light(id: int) -> void:
	if not _lights.has(id):
		return
	var l: Vector3i = _lights[id]
	_lights.erase(id)
	_update(_around(Vector2i(l.x, l.y)), true, false)

func has_light(id: int) -> bool:
	return _lights.has(id)

## Compute every not-yet-computed chunk that rect touches.
func ensure_region(rect: Rect2i) -> void:
	rect = rect.intersection(Rect2i(0, 0, _w, _h))
	if rect.size.x <= 0 or rect.size.y <= 0:
		return
	var c0 := Vector2i(rect.position.x >> 5, rect.position.y >> 5)
	var c1 := Vector2i((rect.end.x - 1) >> 5, (rect.end.y - 1) >> 5)
	var by := c0.y
	while by <= c1.y:
		var bx := c0.x
		while bx <= c1.x:
			_ensure_batch(Rect2i(bx, by, mini(BATCH, c1.x - bx + 1), mini(BATCH, c1.y - by + 1)))
			bx += BATCH
		by += BATCH

func is_computed(cx: int, cy: int) -> bool:
	return _done[cx + cy * world.chunks_x] != 0

## Queued chunk changes not yet applied (deferred mode).
func backlog() -> int:
	return _queue.size()

## Deferred mode: apply queued chunk changes, then compute cold chunks of `want` nearest its
## centre first, until `budget_us` is spent (at least one unit of work is done). A unit is
## one chunk computed from cold or one queued chunk change. True when nothing is left.
func process(budget_us: int, want := Rect2i()) -> bool:
	var t0 := Time.get_ticks_usec()
	var first := true
	while first or Time.get_ticks_usec() - t0 < budget_us:
		first = false
		if not _queue.is_empty():
			var c: Vector2i = _queue[0]
			var need := Rect2i(c * K.CHUNK, Vector2i(K.CHUNK, K.CHUNK)).grow(_reach + 1)
			var cold := _cold_in(need, need.get_center()) if _any_computed(need) else Vector2i(-1, -1)
			if cold.x >= 0:
				_ensure_batch(Rect2i(cold, Vector2i.ONE))
				continue
			_queue.pop_front()
			_queued.erase(c)
			_chunk_changed_now(c.x, c.y)
			continue
		if want.has_area():
			var cold := _cold_in(want, want.get_center())
			if cold.x >= 0:
				_ensure_batch(Rect2i(cold, Vector2i.ONE))
				continue
		return true
	return _queue.is_empty() and (not want.has_area() or _cold_in(want, want.get_center()).x < 0)

## The not-yet-computed chunk of rect nearest to `at` (tiles), or (-1, -1).
func _cold_in(rect: Rect2i, at: Vector2i) -> Vector2i:
	rect = rect.intersection(Rect2i(0, 0, _w, _h))
	if not rect.has_area():
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for cy in range(rect.position.y >> 5, ((rect.end.y - 1) >> 5) + 1):
		for cx in range(rect.position.x >> 5, ((rect.end.x - 1) >> 5) + 1):
			if _done[cx + cy * _cxn] != 0:
				continue
			var d := (Vector2i(cx * K.CHUNK + 16, cy * K.CHUNK + 16) - at).length_squared()
			if d < best_d:
				best_d = d
				best = Vector2i(cx, cy)
	return best

func _any_computed(rect: Rect2i) -> bool:
	rect = rect.intersection(Rect2i(0, 0, _w, _h))
	if not rect.has_area():
		return false
	for cy in range(rect.position.y >> 5, ((rect.end.y - 1) >> 5) + 1):
		for cx in range(rect.position.x >> 5, ((rect.end.x - 1) >> 5) + 1):
			if _done[cx + cy * _cxn] != 0:
				return true
	return false

## Forget everything (a whole new world was loaded into the same TileWorld).
func reset() -> void:
	_queue.clear()
	_queued.clear()
	for i in _pages.size():
		_pages[i] = PackedByteArray()
	_top.fill(-1)
	_done.fill(0)
	light_changed.emit(Rect2i(0, 0, _w, _h))

# --- internals ---------------------------------------------------------------------------

func _around(p: Vector2i) -> Rect2i:
	return Rect2i(p.x - _reach, p.y - _reach, _reach * 2 + 1, _reach * 2 + 1)

func _scan_top(x: int, from_y: int) -> int:
	var y := from_y
	var opaque := TileDefs.opaque
	var line := world.sky_line[x] if x < world.sky_line.size() else _h
	while y >= 0:
		if world.sparse and not world.is_loaded(x, y):
			if y <= line:
				return y + 1
			y = maxi(line + 1, (y >> 5) << 5) - 1   # skip the unloaded air in this chunk
			continue
		if opaque[world.light_fg(x, y)] != 0:
			return y + 1
		y -= 1
	return 0

func _ensure_batch(chunks: Rect2i) -> void:
	var cxn := world.chunks_x
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for cy in range(chunks.position.y, chunks.end.y):
		for cx in range(chunks.position.x, chunks.end.x):
			if _done[cx + cy * cxn] == 0:
				lo = Vector2i(mini(lo.x, cx), mini(lo.y, cy))
				hi = Vector2i(maxi(hi.x, cx), maxi(hi.y, cy))
	if hi.x < 0:
		return
	var inner := Rect2i(lo * K.CHUNK, (hi - lo + Vector2i.ONE) * K.CHUNK)
	var box := inner.grow(_reach).intersection(Rect2i(0, 0, _w, _h))
	var blk := _flood(box, false)
	var sky := _flood(box, true)
	for cy in range(lo.y, hi.y + 1):
		for cx in range(lo.x, hi.x + 1):
			if _done[cx + cy * cxn] != 0:
				continue
			_write(box, blk, sky, Rect2i(cx * K.CHUNK, cy * K.CHUNK, K.CHUNK, K.CHUNK), true, true)
			_done[cx + cy * cxn] = 1
	light_changed.emit(inner)

## Recompute box after a change inside it. Cells outside box are unaffected, because the
## change is at least _reach tiles from them.
func _update(box: Rect2i, block: bool, sky: bool) -> void:
	box = box.intersection(Rect2i(0, 0, _w, _h))
	if box.size.x <= 0 or box.size.y <= 0:
		return
	var any := false
	for cy in range(box.position.y >> 5, ((box.end.y - 1) >> 5) + 1):
		for cx in range(box.position.x >> 5, ((box.end.x - 1) >> 5) + 1):
			if _done[cx + cy * world.chunks_x] != 0:
				any = true
	if not any:
		return  # nobody has looked here yet; ensure_region will see the new state
	# The frame around box seeds the flood, so it has to be computed already.
	ensure_region(box.grow(1))
	var blk := _flood(box, false) if block else PackedByteArray()
	var skf := _flood(box, true) if sky else PackedByteArray()
	_write(box, blk, skf, box, block, sky)
	light_changed.emit(box)

func _write(box: Rect2i, blk: PackedByteArray, sky: PackedByteArray, area: Rect2i, wb: bool, ws: bool) -> void:
	var gw := box.size.x + 4
	for cy in range(area.position.y >> 5, ((area.end.y - 1) >> 5) + 1):
		for cx in range(area.position.x >> 5, ((area.end.x - 1) >> 5) + 1):
			var xa := maxi(area.position.x, cx << 5)
			var xb := mini(area.end.x, (cx + 1) << 5)
			var ya := maxi(area.position.y, cy << 5)
			var yb := mini(area.end.y, (cy + 1) << 5)
			var ci := cx + cy * _cxn
			var p := _pages[ci]
			if p.is_empty():
				p.resize(PAGE * 2)
			var n := xb - xa
			for y in range(ya, yb):
				var g := (xa - box.position.x + 2) + (y - box.position.y + 2) * gw
				var i := (xa & 31) + ((y & 31) << 5)
				if wb:
					for k in n:
						p[i + k] = blk[g + k]
				if ws:
					for k in n:
						p[PAGE + i + k] = sky[g + k]
			_pages[ci] = p

## Flood one field over box. The grid is box grown by 2: the outer ring is a barrier, the
## next ring (the frame) is seeded from the stored field, so a small box continues the light
## around it exactly. Returns levels for the whole grid.
func _flood(box: Rect2i, sky: bool) -> PackedByteArray:
	var gx := box.position.x - 2
	var gy := box.position.y - 2
	var gw := box.size.x + 4
	var gh := box.size.y + 4
	var n := gw * gh
	var op := PackedByteArray()
	op.resize(n)
	var lv := PackedByteArray()
	lv.resize(n)
	var buckets: Array = []
	buckets.resize(MAX + 1)
	for l in MAX + 1:
		buckets[l] = []
	var opaque := TileDefs.opaque
	var emit := TileDefs.emit
	var off := PAGE if sky else 0
	for j in gh:
		var y := gy + j
		for k in gw:
			var i := k + j * gw
			if j == 0 or k == 0 or j == gh - 1 or k == gw - 1:
				op[i] = 2
				continue
			var x := gx + k
			var src := 0
			if x < 0 or x >= _w or y < 0:
				op[i] = 1
				continue
			if y >= _h:
				if sky:
					src = SUN
			else:
				var id := world.light_fg(x, y)
				var e := emit[id]
				if e > 0:
					if not sky:
						src = emit_level(e)
				elif opaque[id] != 0:
					op[i] = 1
				if sky and op[i] == 0 and y >= sky_top(x):
					src = SUN
				if j == 1 or k == 1 or j == gh - 2 or k == gw - 2:
					src = maxi(src, _cell(x, y, off))
			if src > 0:
				lv[i] = src
				buckets[src].append(i)
	if not sky:
		for l: Vector3i in _lights.values():
			var k := l.x - gx
			var j := l.y - gy
			if k < 1 or j < 1 or k >= gw - 1 or j >= gh - 1 or l.z <= 0:
				continue
			var i := k + j * gw
			if op[i] == 1 or l.z <= lv[i]:
				continue
			lv[i] = l.z
			buckets[l.z].append(i)
	for l in range(MAX, 0, -1):
		var b: Array = buckets[l]
		if b.is_empty():
			continue
		var o := l - STEP
		var d := l - DIAG
		var so := l - SOLID_STEP
		var ob: Array = buckets[o] if o > 0 else []
		var db: Array = buckets[d] if d > 0 else []
		var sb: Array = buckets[so] if so > 0 else []
		for i: int in b:
			if lv[i] != l:
				continue
			if op[i] != 0:
				# Inside rock: only on to other rock, slowly.
				if so <= 0:
					continue
				for m: int in [i - 1, i + 1, i - gw, i + gw]:
					if op[m] == 1 and lv[m] < so:
						lv[m] = so
						sb.append(m)
				continue
			if o <= 0:
				continue
			var nl := i - 1
			var nr := i + 1
			var nd := i - gw
			var nu := i + gw
			var cl := op[nl] == 0
			var cr := op[nr] == 0
			var cd := op[nd] == 0
			var cu := op[nu] == 0
			if op[nl] < 2 and lv[nl] < o:
				lv[nl] = o
				ob.append(nl)
			if op[nr] < 2 and lv[nr] < o:
				lv[nr] = o
				ob.append(nr)
			if op[nd] < 2 and lv[nd] < o:
				lv[nd] = o
				ob.append(nd)
			if op[nu] < 2 and lv[nu] < o:
				lv[nu] = o
				ob.append(nu)
			if d <= 0:
				continue
			var m: int
			if cl and cd:
				m = nd - 1
				if op[m] < 2 and lv[m] < d:
					lv[m] = d
					db.append(m)
			if cr and cd:
				m = nd + 1
				if op[m] < 2 and lv[m] < d:
					lv[m] = d
					db.append(m)
			if cl and cu:
				m = nu - 1
				if op[m] < 2 and lv[m] < d:
					lv[m] = d
					db.append(m)
			if cr and cu:
				m = nu + 1
				if op[m] < 2 and lv[m] < d:
					lv[m] = d
					db.append(m)
	return lv

func _on_tile_changed(x: int, y: int, layer: int, old: int, now: int) -> void:
	if layer != TileWorld.Layer.FG:
		return
	var was_op := TileDefs.opaque[old] != 0 and TileDefs.emit[old] == 0
	var is_op := TileDefs.opaque[now] != 0 and TileDefs.emit[now] == 0
	var emit_changed := TileDefs.emit[old] != TileDefs.emit[now]
	if was_op == is_op and not emit_changed:
		return
	var p := Vector2i(x, y)
	if was_op == is_op:
		_update(_around(p), true, false)
		return
	# The direct-sun span of this column changes between y and the next opaque tile below.
	# Fix the column top first, so any chunk computed during the updates sees the new sky.
	var lo := y
	if _top[x] >= 0:
		var top := _top[x]
		if is_op and y >= top:
			_top[x] = y + 1
			lo = top
		elif not is_op and y == top - 1:
			_top[x] = _scan_top(x, y)
			lo = _top[x]
	else:
		var t := sky_top(x)
		if not is_op and t <= y:
			lo = t
		elif is_op and t == y + 1:
			lo = _scan_top(x, y - 1)
	var span := Rect2i(x, lo, 1, y - lo + 1)
	_update(_around(p), true, false)
	_update(span.grow(_reach), false, true)

func _on_chunk_changed(cx: int, cy: int) -> void:
	if deferred:
		var c := Vector2i(cx, cy)
		if not _queued.has(c):
			_queued[c] = true
			_queue.append(c)
		return
	_chunk_changed_now(cx, cy)

func _chunk_changed_now(cx: int, cy: int) -> void:
	# Whole chunk rewritten (arrived, dropped, loaded): recompute everything it can reach.
	# Direct sun changes only between each column's old and new sky top, so the sun update
	# spans from the lowest of those up to the chunk. A column nobody has scanned has no
	# computed light depending on it and is left for later.
	var r := Rect2i(cx * K.CHUNK, cy * K.CHUNK, K.CHUNK, K.CHUNK)
	var lo := r.position.y
	for x in range(r.position.x, r.end.x):
		var old := _top[x]
		if old < 0:
			continue
		_top[x] = _scan_top(x, _h - 1)
		if _top[x] != old:
			lo = mini(lo, mini(old, _top[x]))
	_update(r.grow(_reach), true, false)
	_update(Rect2i(r.position.x, lo, K.CHUNK, r.end.y - lo).grow(_reach), false, true)
	if world.sparse and not world.has_chunk(cx, cy):
		_trim_around(cx, cy)

## Free the pages of unloaded chunks near (cx, cy) that have no loaded neighbour.
func _trim_around(cx: int, cy: int) -> void:
	for qy in range(cy - 1, cy + 2):
		for qx in range(cx - 1, cx + 2):
			if qx < 0 or qy < 0 or qx >= _cxn or qy >= world.chunks_y or world.has_chunk(qx, qy):
				continue
			var near := false
			for ny in range(qy - 1, qy + 2):
				for nx in range(qx - 1, qx + 2):
					if world.has_chunk(nx, ny):
						near = true
			if not near:
				_pages[qx + qy * _cxn] = PackedByteArray()
				_done[qx + qy * _cxn] = 0
