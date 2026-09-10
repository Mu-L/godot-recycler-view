# Tests for the GridLayoutManager port (rows, spans, virtualization).

extends GdUnitTestSuite


class CellAdapter extends Adapter:
	var count: int = 0
	var created: int = 0

	func _get_item_count() -> int:
		return count

	func _get_item_extent(position: int) -> int:
		return 60

	func _create_item(parent: Control, view_type: int) -> ViewHolder:
		created += 1
		var vh := ViewHolder.new()
		vh.set_control(Control.new())
		return vh

	func _bind_item(holder: ViewHolder, position: int) -> void:
		pass


class MixedCellAdapter extends Adapter:
	var count: int = 0
	var created: int = 0

	func _get_item_count() -> int:
		return count

	func _get_item_extent(position: int) -> int:
		return 80 if position == 0 else 40 + (position % 3) * 10

	func _create_item(parent: Control, view_type: int) -> ViewHolder:
		created += 1
		var vh := ViewHolder.new()
		vh.set_control(Control.new())
		return vh

	func _bind_item(holder: ViewHolder, position: int) -> void:
		pass


class HeaderLookup extends SpanSizeLookup:
	func _get_span_size(position: int) -> int:
		return 3 if position == 0 else 1


func test_grid_rows_and_columns() -> void:
	var rv := RecyclerView.new()
	rv.set_size(Vector2(360, 600))
	var adapter := CellAdapter.new()
	adapter.count = 10
	rv.set_item_extent(60)
	rv.set_adapter(adapter)
	var layout := GridLayoutManager.new()
	layout.set_span_count(3)
	rv.set_layout(layout)
	rv.request_layout()

	assert_that(layout.get_row_count()).is_equal(4)  # 10 items / 3 columns
	assert_that(layout.get_content_size(rv)).is_equal(240)  # 4 rows * 60
	assert_that(layout.get_item_row(0)).is_equal(0)
	assert_that(layout.get_item_row(2)).is_equal(0)
	assert_that(layout.get_item_row(3)).is_equal(1)
	assert_that(layout.get_item_row(9)).is_equal(3)
	assert_that(layout.get_item_column(0)).is_equal(0)
	assert_that(layout.get_item_column(1)).is_equal(1)
	assert_that(layout.get_item_column(2)).is_equal(2)
	assert_that(layout.get_item_column(3)).is_equal(0)

	# Cells tile a 3-column grid: 120 wide, 60 tall, at (col * 120, row * 60).
	for i in rv.get_child_holder_count():
		var h: ViewHolder = rv.get_child_holder_at(i)
		var c: Control = h.get_control()
		assert_that(int(c.size.x)).is_equal(120)
		assert_that(int(c.size.y)).is_equal(60)
		assert_that(int(c.position.x)).is_equal(layout.get_item_column(h.get_position()) * 120)
		assert_that(int(c.position.y)).is_equal(layout.get_item_row(h.get_position()) * 60)
	rv.free_items()
	rv.free()


func test_header_spans_full_row_and_row_height_is_max() -> void:
	var rv := RecyclerView.new()
	rv.set_size(Vector2(360, 600))
	var adapter := MixedCellAdapter.new()
	adapter.count = 10
	rv.set_item_extent(60)
	rv.set_adapter(adapter)
	var layout := GridLayoutManager.new()
	layout.set_span_count(3)
	layout.set_span_size_lookup(HeaderLookup.new())
	rv.set_layout(layout)
	rv.request_layout()

	# Position 0 is a full-row header: span 3, height 80, width = whole row.
	assert_that(layout.get_item_row(0)).is_equal(0)
	assert_that(layout.get_item_column(0)).is_equal(0)
	assert_that(layout.get_row_height(0)).is_equal(80)
	var h0: ViewHolder = rv.get_child_holder_at(0)
	var c0: Control = h0.get_control()
	assert_that(h0.get_position()).is_equal(0)
	assert_that(int(c0.size.x)).is_equal(360)
	assert_that(int(c0.size.y)).is_equal(80)

	# Row 1 (items 1..3, heights 50/60/40) takes the tallest cell's height.
	assert_that(layout.get_item_row(1)).is_equal(1)
	assert_that(layout.get_row_height(1)).is_equal(60)
	# Content = 80 + 3 rows of 60.
	assert_that(layout.get_content_size(rv)).is_equal(260)
	rv.free_items()
	rv.free()


func test_grid_scroll_virtualizes_without_overlap() -> void:
	var rv := RecyclerView.new()
	rv.set_size(Vector2(360, 600))
	var adapter := CellAdapter.new()
	adapter.count = 100
	rv.set_item_extent(60)
	# This test asserts creation stays bounded (virtualization); prefetch
	# deliberately pre-creates extra holders, so it is disabled here.
	rv.set_prefetch_enabled(false)
	rv.set_adapter(adapter)
	var layout := GridLayoutManager.new()
	layout.set_span_count(3)
	rv.set_layout(layout)
	rv.request_layout()

	for i in 40:
		rv.scroll_vertically(30)
		# Cells in the same row must not overlap horizontally.
		var by_row := {}
		for j in rv.get_child_holder_count():
			var h: ViewHolder = rv.get_child_holder_at(j)
			var c: Control = h.get_control()
			var row: int = layout.get_item_row(h.get_position())
			if not by_row.has(row):
				by_row[row] = []
			by_row[row].append([c.position.x, c.position.x + c.size.x])
		for row in by_row:
			var xs: Array = by_row[row]
			xs.sort()
			for k in range(1, xs.size()):
				assert_that(xs[k][0] >= xs[k - 1][1] - 0.5).is_true()

	# Virtualization keeps creation well below a full rebuild (100 items).
	assert_that(adapter.created).is_less(60)
	rv.free_items()
	rv.free()


func test_span_count_change_rebuilds_rows() -> void:
	var rv := RecyclerView.new()
	rv.set_size(Vector2(360, 600))
	var adapter := CellAdapter.new()
	adapter.count = 10
	rv.set_item_extent(60)
	rv.set_adapter(adapter)
	var layout := GridLayoutManager.new()
	layout.set_span_count(3)
	rv.set_layout(layout)
	rv.request_layout()
	assert_that(layout.get_row_count()).is_equal(4)

	layout.set_span_count(5)
	rv.request_layout()
	# 10 items in 5 columns -> 2 rows.
	assert_that(layout.get_row_count()).is_equal(2)
	assert_that(layout.get_item_row(5)).is_equal(1)
	rv.free_items()
	rv.free()


func _holder_rect(rv: RecyclerView, position: int) -> Rect2:
	for i in rv.get_child_holder_count():
		var h: ViewHolder = rv.get_child_holder_at(i)
		if h.get_position() == position:
			var c: Control = h.get_control()
			return Rect2(c.position, c.size)
	return Rect2()


func _prepare_responsive_rv(width: float) -> Dictionary:
	get_window().size = Vector2i(1920, 1080)
	get_window().content_scale_size = Vector2i(1920, 1080)
	await get_tree().process_frame
	var rv := RecyclerView.new()
	rv.set_size(Vector2(width, 300))
	var adapter := CellAdapter.new()
	adapter.count = 12
	rv.set_item_extent(60)
	rv.set_adapter(adapter)
	var layout := GridLayoutManager.new()
	layout.set_span_count(2)
	rv.set_layout(layout)
	get_tree().root.add_child(rv)
	rv.request_layout()
	await get_tree().process_frame
	return { "rv": rv, "adapter": adapter, "layout": layout }


func test_span_count_change_reflows_mounted_children() -> void:
	# A live grid re-flows when span_count changes: the already-mounted holders
	# keep their identity but every row/column assignment is recomputed.
	var s := await _prepare_responsive_rv(360.0)
	var rv: RecyclerView = s.rv
	var layout: GridLayoutManager = s.layout

	# 2 columns of 180: row 0 holds positions 0 and 1.
	assert_that(_holder_rect(rv, 0)).is_equal(Rect2(0, 0, 180, 60))
	assert_that(_holder_rect(rv, 1)).is_equal(Rect2(180, 0, 180, 60))
	assert_that(_holder_rect(rv, 2)).is_equal(Rect2(0, 60, 180, 60))

	# The viewport grows and the app re-computes the column count from it.
	rv.set_size(Vector2(540, 300))
	layout.set_span_count(3)
	rv.request_layout()
	await get_tree().process_frame

	# Same 12 items, now 4 rows of 3 — mounted holders re-flowed in place.
	assert_that(layout.get_row_count()).is_equal(4)
	assert_that(_holder_rect(rv, 0)).is_equal(Rect2(0, 0, 180, 60))
	assert_that(_holder_rect(rv, 1)).is_equal(Rect2(180, 0, 180, 60))
	assert_that(_holder_rect(rv, 2)).is_equal(Rect2(360, 0, 180, 60))
	assert_that(_holder_rect(rv, 3)).is_equal(Rect2(0, 60, 180, 60))
	assert_that(_holder_rect(rv, 11)).is_equal(Rect2(360, 180, 180, 60))
	rv.free_items()
	rv.free()


func _desired_item_width() -> int:
	# The width an item wants; the grid stretches it to viewport/span_count.
	return 150


func test_resize_signal_drives_span_count_responsively() -> void:
	# The responsive wiring an app writes once: recompute the column count from
	# the viewport width on every resize, and re-layout only when it changed.
	var s := await _prepare_responsive_rv(360.0)
	var rv: RecyclerView = s.rv
	var layout: GridLayoutManager = s.layout
	var changes: Array[int] = []
	rv.resized.connect(func() -> void:
		var cols: int = maxi(1, int(rv.size.x / float(_desired_item_width())))
		if cols != layout.get_span_count():
			layout.set_span_count(cols)
			changes.append(cols)
			rv.request_layout())

	# 360 -> 2 columns; 540 -> 3; 780 -> 5; back to 360 -> 2.
	for width in [540.0, 780.0, 360.0]:
		rv.set_size(Vector2(width, 300))
		await get_tree().process_frame

	assert_that(changes).contains_exactly([3, 5, 2])
	assert_that(layout.get_span_count()).is_equal(2)
	assert_that(layout.get_row_count()).is_equal(6)
	# 360 / 2 = 180 per cell, and the re-flow is live again after the shrink.
	assert_that(_holder_rect(rv, 1)).is_equal(Rect2(180, 0, 180, 60))
	rv.free_items()
	rv.free()
