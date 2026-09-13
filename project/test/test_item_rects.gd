# Tests that an item's rect is the rect the layout assigned — independent of
# when and where the assignment happened.
#
# A RecyclerView positions its items by absolute rect, but an item scene root is
# usually anchored (full-rect preset + grow BOTH, the editor default), so Godot
# still ties that rect to the parent's size. Anchor offsets are computed against
# the parent CanvasItem's size — and Godot reports an EMPTY parent area while
# the subtree is off-tree. A layout that runs there (a nested RecyclerView
# inside a recycled item, a detached RV) therefore stores absolute offsets, and
# the item inflates by exactly +parent size the moment the subtree enters a
# tree: it overlaps its neighbours until some in-tree layout happens to re-place
# it. The RecyclerView must own the rect outright.

extends GdUnitTestSuite


## The usual item scene root: full-rect anchors, growing both ways.
class AnchoredRow extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(148, 46)
		anchor_right = 1.0
		anchor_bottom = 1.0
		grow_horizontal = Control.GROW_DIRECTION_BOTH
		grow_vertical = Control.GROW_DIRECTION_BOTH


class RowAdapter extends Adapter:
	func _get_item_count() -> int:
		return 2

	func _get_item_extent(_position: int) -> int:
		return 148

	func _create_item(_parent: Control, _view_type: int) -> ViewHolder:
		var vh := ViewHolder.new()
		vh.control = AnchoredRow.new()
		return vh

	func _bind_item(_holder: ViewHolder, _position: int) -> void:
		pass


func _make_nested() -> Dictionary:
	# "card" = the outer RecyclerView's item; it gets recycled in and out of the
	# tree while the inner list keeps working.
	var card := Control.new()
	card.size = Vector2(1866, 57)
	get_tree().root.add_child(card)
	var inner := RecyclerView.new()
	inner.custom_minimum_size = Vector2(0, 57)
	inner.set_adapter(RowAdapter.new())
	var lm := LinearLayoutManager.new()
	lm.set_orientation(LinearLayoutManager.Orientation.HORIZONTAL)
	inner.set_layout(lm)
	card.add_child(inner)
	inner.set_size(Vector2(1866, 57))
	inner.request_layout()
	return { "card": card, "inner": inner }


func test_items_keep_their_rect_after_an_off_tree_layout() -> void:
	var s := _make_nested()
	var card: Control = s.card
	var inner: RecyclerView = s.inner
	await get_tree().process_frame
	assert_that(inner.get_child_holder_count()).is_equal(2)

	# The card is recycled: its subtree leaves the tree, while the inner list is
	# still driven (its adapter can be updated from a signal that reaches the
	# recycled card).
	get_tree().root.remove_child(card)
	inner.request_layout()
	await get_tree().process_frame

	# Back on screen, at its real size again.
	get_tree().root.add_child(card)
	inner.set_size(Vector2(1866, 57))
	await get_tree().process_frame
	await get_tree().process_frame

	for i in inner.get_child_holder_count():
		var holder: ViewHolder = inner.get_child_holder_at(i)
		var control: Control = holder.get_control()
		var slot := inner.get_decorated_item_rect(holder.get_position())
		assert_that(control.size).is_equal(Vector2(148, 57))
		assert_that(control.position).is_equal(slot.position)
	inner.free_items()
	inner.free()
	card.free()


func test_items_keep_their_rect_while_the_subtree_is_off_tree() -> void:
	# Detached layout is supported (build-time measuring, unit tests): the rects
	# it assigns must be the ones the item keeps, not something re-derived from
	# an empty parent area.
	var s := _make_nested()
	var card: Control = s.card
	var inner: RecyclerView = s.inner
	await get_tree().process_frame
	get_tree().root.remove_child(card)
	inner.request_layout()
	await get_tree().process_frame

	for i in inner.get_child_holder_count():
		var holder: ViewHolder = inner.get_child_holder_at(i)
		var control: Control = holder.get_control()
		var slot := inner.get_decorated_item_rect(holder.get_position())
		assert_that(control.position).is_equal(slot.position)
		assert_that(control.size).is_equal(slot.size)
	inner.free_items()
	inner.free()
	card.free()
