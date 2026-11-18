extends SceneTree
## Helper, not a suite. Cuts Robin out of the portrait for the standee figure.
## Run: --headless --path . -s tests/standee_cut_tool.gd -- --check=<png path>
## The background turns transparent, the outline stays, and the picture is cropped to what is left.

const SOURCE := "res://assets/portraits/robin.png"
const TARGET := "res://assets/characters/standees/robin.png"
## The floor band colour (#19161f). Everything from its top row down is cleared first.
const FLOOR := Color8(0x19, 0x16, 0x1f)
## Pixels darker than this (largest channel, 0-255) are outline. The fill stops there.
const OUTLINE_MAX := 28
## The bright green ground for the check picture.
const CHECK_GROUND := Color(0.0, 1.0, 0.0)


func _initialize() -> void:
	var check_path := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--check="): check_path = arg.trim_prefix("--check=")
	var image := Image.load_from_file(ProjectSettings.globalize_path(SOURCE))
	image.convert(Image.FORMAT_RGBA8)
	var floor_top := find_floor_top(image)
	print("floor band top row: %d" % floor_top)
	# The hips line: clear the floor band and everything below it.
	for y in range(floor_top, image.get_height()):
		for x in image.get_width():
			image.set_pixel(x, y, Color(0, 0, 0, 0))
	flood_background(image, floor_top)
	var bounds := image.get_used_rect()
	print("cut bounds: x %d, y %d, width %d, height %d" % [bounds.position.x, bounds.position.y,
		bounds.size.x, bounds.size.y])
	var cut := image.get_region(bounds)
	var error := cut.save_png(ProjectSettings.globalize_path(TARGET))
	print("saved %s: %s" % [TARGET, error_string(error)])
	if check_path != "": save_check(cut, check_path)
	quit(0 if error == OK else 1)


## The top row of the floor band, read down the left edge from the bottom.
func find_floor_top(image: Image) -> int:
	var y := image.get_height() - 1
	while y > 0 and close_to(image.get_pixel(2, y - 1), FLOOR):
		y -= 1
	return y


func close_to(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.05


func is_outline(color: Color) -> bool:
	return maxi(maxi(color.r8, color.g8), color.b8) < OUTLINE_MAX


## Flood fill from the top, left and right edges above the floor, through pixels that are not outline-dark.
## The cut row is not a seed: it runs through the skirt and the satchel, so the fill would leak inside.
func flood_background(image: Image, floor_top: int) -> void:
	var width := image.get_width()
	var seen := PackedByteArray()
	seen.resize(width * floor_top)
	var queue := PackedInt32Array()
	for x in width:
		queue.append(x)
	for y in floor_top:
		queue.append(y * width)
		queue.append(y * width + width - 1)
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		if seen[index] == 1: continue
		seen[index] = 1
		var x := index % width
		var y := int(float(index) / float(width))
		if is_outline(image.get_pixel(x, y)): continue
		image.set_pixel(x, y, Color(0, 0, 0, 0))
		if x > 0: queue.append(index - 1)
		if x < width - 1: queue.append(index + 1)
		if y > 0: queue.append(index - width)
		if y < floor_top - 1: queue.append(index + width)


## The cut-out on bright green, so holes and leftovers are easy to see.
func save_check(cut: Image, path: String) -> void:
	var check := Image.create(cut.get_width(), cut.get_height(), false, Image.FORMAT_RGBA8)
	check.fill(CHECK_GROUND)
	check.blend_rect(cut, Rect2i(Vector2i.ZERO, cut.get_size()), Vector2i.ZERO)
	print("check picture: %s" % error_string(check.save_png(path)))
