# Tests for responsive_grid_demo: the scene derives the grid's column count from
# the viewport width on every RecyclerView resize and re-flows the mounted items
# when it changes (set_span_count + request_layout — event-driven, no polling).
# Covers the demo's own wiring, not just the layout manager.

extends GdUnitTestSuite


func _columns_for(demo: Control, layout: GridLayoutManager, width: float) -> int:
	# The demo root is a container: resizing it (not the RV, which the container
	# stretches) is what a window resize does to the scene.
	demo.set_size(Vector2(width, 400))
	await get_tree().process_frame
	return layout.get_span_count()


func test_demo_columns_follow_the_viewport_width() -> void:
	get_window().size = Vector2i(1920, 1080)
	get_window().content_scale_size = Vector2i(1920, 1080)
	await get_tree().process_frame

	var demo: Control = load("res://responsive_grid_demo.tscn").instantiate()
	get_tree().root.add_child(demo)
	await get_tree().process_frame
	var rv: RecyclerView = demo.get_node("%RecyclerView")
	var layout: GridLayoutManager = rv.get_layout()
	assert_that(layout).is_not_null()

	# 160px target width: 720 -> 4 columns, 640 -> 4, 480 -> 3, 160 -> 1.
	assert_that(await _columns_for(demo, layout, 720.0)).is_equal(4)
	assert_that(await _columns_for(demo, layout, 640.0)).is_equal(4)
	assert_that(await _columns_for(demo, layout, 480.0)).is_equal(3)
	assert_that(await _columns_for(demo, layout, 160.0)).is_equal(1)
	# Never zero, even when the width is degenerate.
	assert_that(await _columns_for(demo, layout, 0.0)).is_equal(1)

	demo.free()


func test_demo_reflows_items_when_the_column_count_changes() -> void:
	get_window().size = Vector2i(1920, 1080)
	get_window().content_scale_size = Vector2i(1920, 1080)
	await get_tree().process_frame

	var demo: Control = load("res://responsive_grid_demo.tscn").instantiate()
	get_tree().root.add_child(demo)
	await get_tree().process_frame
	var rv: RecyclerView = demo.get_node("%RecyclerView")
	var layout: GridLayoutManager = rv.get_layout()

	demo.set_size(Vector2(640, 400))
	await get_tree().process_frame
	assert_that(layout.get_span_count()).is_equal(4)
	# 640 / 4 = 160 per cell: position 4 opens the second row at x = 0.
	var cell := _cell_rect(rv, 4)
	assert_that(cell.position.x).is_equal(0.0)
	assert_that(cell.position.y).is_equal(60.0)
	assert_that(cell.size.x).is_equal(160.0)

	# Narrower: 3 columns, so position 4 moves into the second row, col 1.
	demo.set_size(Vector2(480, 400))
	await get_tree().process_frame
	assert_that(layout.get_span_count()).is_equal(3)
	cell = _cell_rect(rv, 4)
	assert_that(cell.position.x).is_equal(160.0)
	assert_that(cell.position.y).is_equal(60.0)
	assert_that(cell.size.x).is_equal(160.0)

	demo.free()


func _cell_rect(rv: RecyclerView, position: int) -> Rect2:
	for i in rv.get_child_holder_count():
		var h: ViewHolder = rv.get_child_holder_at(i)
		if h.get_position() == position:
			var c: Control = h.get_control()
			return Rect2(c.position, c.size)
	return Rect2()
