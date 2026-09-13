# Tests that scene-based items are bound only after their ready pass.
#
# An item whose root comes from a .tscn often refreshes itself through
# @onready references (e.g. `@onready var label = $Label`). Binding the holder
# before its control enters the tree runs _bind_item against a not-yet-ready
# scene: the references are null and the item ends up empty. The RecyclerView
# must mount the control (running the ready pass) before calling _bind_item —
# never requiring the adapter author to `await ctrl.ready` manually.

extends GdUnitTestSuite

const ITEM_SCENE := preload("res://test_list_item.tscn")


# Binds through the item scene's refresh(), which touches an @onready Label.
class SceneAdapter extends Adapter:
	var items: Array[String] = []
	var created := 0
	var bound_inside_tree := true

	func _get_item_count() -> int:
		return items.size()

	func _create_item(parent: Control, view_type: int) -> ViewHolder:
		created += 1
		var vh := ViewHolder.new()
		vh.set_control(ITEM_SCENE.instantiate())
		return vh

	func _bind_item(holder: ViewHolder, position: int) -> void:
		var ctrl: TestListItem = holder.get_control()
		bound_inside_tree = bound_inside_tree and ctrl.is_inside_tree()
		ctrl.refresh(items[position])


func _make_setup(count := 5) -> Dictionary:
	get_window().size = Vector2i(1920, 1080)
	get_window().content_scale_size = Vector2i(1920, 1080)
	await get_tree().process_frame
	var rv := RecyclerView.new()
	rv.position = Vector2(0, 0)
	rv.set_size(Vector2(300, 300))
	rv.set_item_extent(60)
	rv.set_prefetch_enabled(true)
	# Mount before wiring the adapter: the first layout must run inside the
	# tree so first-mount binds wait for the item's ready pass. (An off-tree
	# RV lays out synchronously and binds immediately, as before — fine for
	# code-built items, wrong for scene items whose @onready refs need the
	# ready pass.)
	get_tree().root.add_child(rv)
	var adapter := SceneAdapter.new()
	for i in count:
		adapter.items.append("item %d" % i)
	rv.set_adapter(adapter)
	rv.set_layout(LinearLayoutManager.new())
	await get_tree().process_frame
	return { "rv": rv, "adapter": adapter }


func _label_text(rv: RecyclerView, position: int) -> String:
	for i in rv.get_child_holder_count():
		var holder := rv.get_child_holder_at(i)
		if holder.get_position() == position:
			return (holder.get_control().get_node("Label") as Label).text
	return ""


func _holder_at(rv: RecyclerView, position: int) -> ViewHolder:
	for i in rv.get_child_holder_count():
		if rv.get_child_holder_at(i).get_position() == position:
			return rv.get_child_holder_at(i)
	return null


func _make_off_tree_rv(adapter: Adapter, size := Vector2(300, 120), extent := 60) -> RecyclerView:
	# A RecyclerView that is not inside the tree: it still fills (build-time
	# layout, measuring), but its item scenes never run a ready pass.
	var rv := RecyclerView.new()
	rv.set_size(size)
	rv.set_item_extent(extent)
	rv.set_prefetch_enabled(false)
	rv.set_adapter(adapter)
	rv.set_layout(LinearLayoutManager.new())
	rv.request_layout()
	await get_tree().process_frame
	return rv


func test_first_layout_binds_scene_items_after_ready() -> void:
	var s := await _make_setup()
	var rv: RecyclerView = s.rv
	var adapter: SceneAdapter = s.adapter
	# _bind_item ran with the control inside the tree, so @onready refs were up.
	assert_that(adapter.bound_inside_tree).is_true()
	for i in 3:
		assert_that(_label_text(rv, i)).is_equal("item %d" % i)
	rv.free_items()
	rv.free()


func test_reused_holder_binds_again_after_ready() -> void:
	# Regression: a holder recycled by scrolling is re-used for a new position;
	# the re-bind must also run after the control re-enters the tree.
	var s := await _make_setup(20)
	var rv: RecyclerView = s.rv
	var adapter: SceneAdapter = s.adapter
	# Scroll past the first rows so the top holders recycle...
	rv.scroll_vertically(300)
	await get_tree().process_frame
	rv.scroll_vertically(-300)
	await get_tree().process_frame
	# ...and every visible row must still show its own content.
	for i in rv.get_child_holder_count():
		var pos: int = rv.get_child_holder_at(i).get_position()
		assert_that(_label_text(rv, pos)).is_equal("item %d" % pos)
	rv.free_items()
	rv.free()


func test_scroll_into_prefetched_rows_keeps_content() -> void:
	# Prefetch creates fresh holders before they scroll into view; those too
	# must be bound only after the mount (they have never been ready before).
	var s := await _make_setup(30)
	var rv: RecyclerView = s.rv
	# Drag far enough that prefetched rows enter the viewport.
	for i in 20:
		rv.scroll_vertically(15)
		await get_tree().process_frame
	for i in rv.get_child_holder_count():
		var pos: int = rv.get_child_holder_at(i).get_position()
		assert_that(_label_text(rv, pos)).is_equal("item %d" % pos)
	rv.free_items()
	rv.free()


# Adapter whose items bind fit_content wrapped text (the pattern behind the
# quack-under-pressure report). Regression contract: the first bind must see
# the slot's width, so width-sensitive content shapes honestly — never at the
# scene's stale width, which inflates the minimum past the slot extent and
# leaves the item oversized until the next scroll.
#
# Note on environments: Godot runs an item scene's ready pass at the end of
# the frame when the mount happens inside a queue flush (this test env), so
# the deferred bind there already runs after the mount layout sized the item
# — that path was never broken. The broken path is the synchronous bind (the
# ready pass already ran at add_child), where the bind precedes the mount
# layout; that env is covered by the real-game driver (quack-under-pressure),
# and this test pins the same contract (width at bind + slot size) for
# whichever path the suite runs on.
class WrappedTextAdapter extends Adapter:
	var items: Array = []
	var extent := 100
	var width_at_bind: float = -1.0

	func _get_item_count() -> int:
		return items.size()

	func _get_item_extent(_position: int) -> int:
		return extent

	func _create_item(parent: Control, view_type: int) -> ViewHolder:
		var vh := ViewHolder.new()
		var root := VBoxContainer.new()
		root.custom_minimum_size = Vector2(0, extent)
		var label := RichTextLabel.new()
		label.fit_content = true
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(label)
		vh.set_control(root)
		return vh

	func _bind_item(holder: ViewHolder, position: int) -> void:
		var root: VBoxContainer = holder.get_control()
		width_at_bind = root.size.x
		(root.get_child(0) as RichTextLabel).text = (
				"a long line of words that wraps onto several lines when shaped "
				+ "at a narrow width but stays within the extent at three hundred pixels")


# Regression: a scene item first mounted while its RecyclerView is off-tree must
# not be bound there. The control cannot run its ready pass until it enters a
# tree, so _bind_item would write through @onready references that are still
# null (the reported crash: "Invalid assignment ... on a base object of type
# 'Nil'" from the item's own refresh()). The bind waits for the ready signal and
# lands when the RecyclerView enters the tree.
func test_off_tree_mount_defers_scene_bind_until_ready() -> void:
	var adapter := SceneAdapter.new()
	for i in 4:
		adapter.items.append("item %d" % i)
	var rv := await _make_off_tree_rv(adapter, Vector2(300, 120), 60)
	assert_that(rv.get_child_holder_count()).is_greater(0)
	for i in rv.get_child_holder_count():
		# Mounted, but deliberately not bound: nothing to bind into yet.
		assert_that(rv.get_child_holder_at(i).is_bound()).is_false()
	assert_that(adapter.created).is_greater(0)

	get_tree().root.add_child(rv)
	await get_tree().process_frame
	await get_tree().process_frame
	# The ready pass ran on the way in, so every visible row is bound and filled.
	assert_that(adapter.bound_inside_tree).is_true()
	for i in rv.get_child_holder_count():
		var pos: int = rv.get_child_holder_at(i).get_position()
		assert_that(_label_text(rv, pos)).is_equal("item %d" % pos)
	rv.free_items()
	rv.free()


# The reported case, one level deeper: the items of a RecyclerView that lives
# inside another RecyclerView's item are filled while that outer item is off-tree
# (recycled into the cache/pool, where its signals still reach it). The inner
# items then have no ready pass either — they must defer like any other.
func test_nested_rv_filled_off_tree_defers_inner_bind() -> void:
	var outer := OuterAdapter.new()
	for i in 3:
		outer.items.append(i)
	var outer_rv := await _make_off_tree_rv(outer, Vector2(300, 150), 150)
	assert_that(outer_rv.get_child_holder_count()).is_greater(0)

	var item: NestedItem = _holder_at(outer_rv, 0).get_control()
	var inner: RecyclerView = item.inner_rv
	# Off-tree containers do not sort their children, so the inner RV has no size
	# of its own yet: give it one, as the outer item's layout would.
	inner.set_size(Vector2(280, 100))
	inner.set_item_extent(50)
	inner.set_prefetch_enabled(false)
	inner.set_adapter(item.inner_adapter)
	inner.set_layout(LinearLayoutManager.new())
	item.inner_adapter.items = ["a", "b"]
	inner.request_layout()
	await get_tree().process_frame
	# Inner rows are mounted off-tree but not bound: their scene has no ready
	# pass yet, so writing through @onready would crash the item.
	assert_that(inner.get_child_holder_count()).is_greater(0)
	for i in inner.get_child_holder_count():
		assert_that(inner.get_child_holder_at(i).is_bound()).is_false()

	get_tree().root.add_child(outer_rv)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_that(item.label.text).is_equal("outer 0")
	# Inner and outer ready passes both ran; the deferred binds filled the rows.
	assert_that(_label_text(inner, 0)).is_equal("leaf a")
	assert_that(_label_text(inner, 1)).is_equal("leaf b")
	outer_rv.free_items()
	outer_rv.free()


# Item whose control carries its own RecyclerView, the shape behind the report.
class NestedItem extends VBoxContainer:
	@onready var label: Label = $Label
	var inner_rv: RecyclerView
	var inner_adapter := InnerAdapter.new()

	func _init() -> void:
		custom_minimum_size = Vector2(0, 150)
		var l := Label.new()
		l.name = "Label"
		add_child(l)
		inner_rv = RecyclerView.new()
		inner_rv.name = "InnerRV"
		inner_rv.custom_minimum_size = Vector2(0, 100)
		add_child(inner_rv)


class InnerAdapter extends Adapter:
	var items: Array = []

	func _get_item_count() -> int:
		return items.size()

	func _get_item_extent(_position: int) -> int:
		return 50

	func _create_item(_parent: Control, _view_type: int) -> ViewHolder:
		var vh := ViewHolder.new()
		vh.set_control(ITEM_SCENE.instantiate())
		return vh

	func _bind_item(holder: ViewHolder, position: int) -> void:
		(holder.get_control() as TestListItem).refresh("leaf %s" % items[position])


class OuterAdapter extends Adapter:
	var items: Array = []

	func _get_item_count() -> int:
		return items.size()

	func _get_item_extent(_position: int) -> int:
		return 150

	func _create_item(_parent: Control, _view_type: int) -> ViewHolder:
		var vh := ViewHolder.new()
		vh.set_control(NestedItem.new())
		return vh

	func _bind_item(holder: ViewHolder, position: int) -> void:
		var item: NestedItem = holder.get_control()
		item.label.text = "outer %d" % position


func test_fresh_mount_binds_at_slot_width_and_holds_slot() -> void:
	# The first bind shapes the item's content: it must happen at the slot's
	# width (the RV presets the subtree's cross size before the bind), and
	# the mounted item must hold its slot size from the first frames.
	get_window().size = Vector2i(1920, 1080)
	get_window().content_scale_size = Vector2i(1920, 1080)
	await get_tree().process_frame
	var rv := RecyclerView.new()
	rv.position = Vector2(0, 0)
	rv.set_size(Vector2(300, 300))
	var adapter := WrappedTextAdapter.new()
	adapter.items = ["a"]
	get_tree().root.add_child(rv)
	rv.set_adapter(adapter)
	rv.set_layout(LinearLayoutManager.new())
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_that(adapter.width_at_bind).is_equal(300.0)
	for i in rv.get_child_holder_count():
		var c: Control = rv.get_child_holder_at(i).get_control()
		assert_that(c.size).is_equal(Vector2(300, 100))
	rv.free_items()
	rv.free()
