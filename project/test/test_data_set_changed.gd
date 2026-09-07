# Tests for the full data-set change path (notify_data_set_changed).
#
# A full data-set change invalidates every position: there is no incremental op
# marking the retained children, so the next layout must re-bind the kept
# holders. Regression: a holder at a still-valid position used to keep its
# stale binding (e.g. data [a0, a1, a2] replaced by [a0, a2] showed a0, a1).

extends GdUnitTestSuite


class PlainAdapter extends Adapter:
	var items: Array = []

	func _get_item_count() -> int:
		return items.size()

	func _create_item(parent: Control, view_type: int) -> ViewHolder:
		var vh := ViewHolder.new()
		var label := Label.new()
		label.set_size(Vector2(200, 40))
		vh.set_control(label)
		return vh

	func _bind_item(holder: ViewHolder, position: int) -> void:
		(holder.get_control() as Label).text = str(items[position])


class ListAdapterImpl extends ListAdapter:
	# No diff callback: submit_list falls back to remove-all + insert-all,
	# mirroring the fallback path (like the app that reported the bug).

	func _create_item(parent: Control, view_type: int) -> ViewHolder:
		var vh := ViewHolder.new()
		var label := Label.new()
		label.set_size(Vector2(200, 40))
		vh.set_control(label)
		return vh

	func _bind_item(holder: ViewHolder, position: int) -> void:
		(holder.get_control() as Label).text = str(get_item(position))


func _make_setup(adapter: Adapter) -> Dictionary:
	get_window().size = Vector2i(1920, 1080)
	get_window().content_scale_size = Vector2i(1920, 1080)
	await get_tree().process_frame
	var rv := RecyclerView.new()
	rv.position = Vector2(0, 0)
	rv.set_size(Vector2(200, 600))
	rv.set_item_extent(40)
	rv.set_adapter(adapter)
	rv.set_layout(LinearLayoutManager.new())
	rv.request_layout()
	get_tree().root.add_child(rv)
	await get_tree().process_frame
	return { "rv": rv, "adapter": adapter }


func _text(rv: RecyclerView, pos: int) -> String:
	for i in rv.get_child_holder_count():
		var h = rv.get_child_holder_at(i)
		if h.get_position() == pos:
			return (h.get_control() as Label).text
	return ""


func _visible_texts(rv: RecyclerView) -> Array:
	var out := []
	for i in rv.get_child_holder_count():
		out.append((rv.get_child_holder_at(i).get_control() as Label).text)
	return out


func test_data_set_changed_rebinds_retained_children() -> void:
	# Content at a retained position changed and the count shrank: the kept
	# holder must be re-bound, not left showing its old data.
	var adapter := PlainAdapter.new()
	adapter.items = ["a0", "a1", "a2"]
	var s := await _make_setup(adapter)
	var rv: RecyclerView = s.rv
	assert_that(_visible_texts(rv)).contains_exactly(["a0", "a1", "a2"])

	adapter.items = ["a0", "a2"]  # "a1" removed; position 1 now holds "a2"
	adapter.notify_data_set_changed()
	await get_tree().process_frame
	assert_that(rv.get_child_holder_count()).is_equal(2)
	assert_that(_visible_texts(rv)).contains_exactly(["a0", "a2"])
	rv.free_items()
	rv.free()


func test_data_set_changed_same_count_rebinds_every_retained_row() -> void:
	# Same item count, every row's content replaced: no row may keep its old
	# binding just because its position is still valid.
	var adapter := PlainAdapter.new()
	adapter.items = ["a0", "a1", "a2"]
	var s := await _make_setup(adapter)
	var rv: RecyclerView = s.rv
	assert_that(_visible_texts(rv)).contains_exactly(["a0", "a1", "a2"])

	adapter.items = ["b0", "b1", "b2"]
	adapter.notify_data_set_changed()
	await get_tree().process_frame
	assert_that(_visible_texts(rv)).contains_exactly(["b0", "b1", "b2"])
	rv.free_items()
	rv.free()


func test_submit_list_then_notify_data_set_changed_shows_new_list() -> void:
	# submit_list() followed by notify_data_set_changed() (the pattern used by
	# the game that reported the bug): the extra full-data-set change must not
	# undo the submit — the retained rows still refresh to the new list.
	var adapter := ListAdapterImpl.new()
	var s := await _make_setup(adapter)
	var rv: RecyclerView = s.rv
	adapter.submit_list(["a0", "a1", "a2"])
	await get_tree().process_frame
	assert_that(_visible_texts(rv)).contains_exactly(["a0", "a1", "a2"])

	adapter.submit_list(["a0", "a2"])  # middle item removed
	adapter.notify_data_set_changed()
	await get_tree().process_frame
	assert_that(rv.get_child_holder_count()).is_equal(2)
	assert_that(_visible_texts(rv)).contains_exactly(["a0", "a2"])
	rv.free_items()
	rv.free()
