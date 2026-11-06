## Shown while a new world generates on its thread (game/main.gd): the name of what is being
## made and a bar, so a 30-second wait doesn't look frozen.
class_name LoadingScreen
extends CanvasLayer

## What each worldgen stage reads as. Stages not listed keep the last line.
const LINES := {
	"biomes": "Laying out the climate",
	"surface": "Raising the land",
	"layers": "Laying down rock and soil",
	"caves": "Hollowing the caves",
	"caverns": "Opening the deep places",
	"deep_road": "Cutting the deep road",
	"portal": "Finding the way down",
	"ruins": "Burying the old ruins",
	"ores": "Seeding the ore",
	"sites": "Choosing where people live",
	"places": "Raising the towns",
	"roads": "Laying the roads",
	"passages": "Opening the ways through",
	"dressing": "Growing the last of it",
}

## Rough share of a medium world's time each stage takes (measured; the rest are quick), so
## the bar moves with the wait and not with the stage count.
const WEIGHT := {"layers": 1.0, "caves": 4.0, "cave_steps": 2.0, "places": 0.5, "roads": 0.5, "passages": 25.0}

var _line: Label
var _bar: ProgressBar
var _text := "Beginning"
var _shown := -1
var _t := 0.0

func _ready() -> void:
	layer = 100
	var back := ColorRect.new()
	back.color = UiTheme.NIGHT_DEEP
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.custom_minimum_size = Vector2(520, 0)
	box.position = -Vector2(260, 60)
	box.add_theme_constant_override("separation", 14)
	back.add_child(box)
	var title := UiTheme.label("A new world", UiTheme.TITLE, UiTheme.STARLIGHT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_line = UiTheme.label(_text, UiTheme.BODY, UiTheme.TEXT_LIGHT)
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_line)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(520, 14)
	_bar.max_value = 1.0
	box.add_child(_bar)

## A last line while the host starts.
func show_line(text: String) -> void:
	_shown = WorldGen.STAGES.size()
	_bar.value = 1.0
	_line.text = text

func _process(delta: float) -> void:
	_t += delta
	_bar.modulate.a = 0.8 + 0.2 * sin(_t * 3.0)        # alive, even through the long stage
	var i := WorldGen.stage_index
	if i <= _shown or i >= WorldGen.STAGES.size():
		return
	_shown = i
	var done := 0.0
	var total := 0.0
	for k in WorldGen.STAGES.size():
		var w := float(WEIGHT.get(String(WorldGen.STAGES[k][0]), 0.05))
		total += w
		if k < i:
			done += w
	_bar.value = done / total
	_text = LINES.get(String(WorldGen.STAGES[i][0]), _text)
	_line.text = _text
