---
name: godot-recycler-view
description: Write or debug GDScript that uses the godot-recycler-view GDExtension — RecyclerView, Adapter, ListAdapter.submit_list, LinearLayoutManager, notify_item_* data updates, ItemTouchHelper/SnapHelper, item animations. Use when code instantiates RecyclerView / ViewHolder / Adapter / any layout manager, when a list renders nothing or keeps showing stale data with no error, or when the user mentions godot-recycler-view, RecyclerView, or a virtualized list in Godot.
---

# Using godot-recycler-view

A GDExtension port of Android's RecyclerView. Only the rows intersecting the viewport exist as
nodes. **Most failures in this API are silent** — no error, no warning, just "nothing renders" or
"the view shows stale data" — so check your code against the list below before debugging anything
else.

Full version of these notes: <https://github.com/iYouthy/godot-recycler-view/blob/main/AGENTS.md>

## The mental model

1. **Callbacks are GDScript virtual methods, not signals.** Subclass and override underscore
   methods (`_create_item`, `_bind_item`, `_on_scrolled`, …). The RecyclerView emits no signals —
   there is no `item_clicked` to connect. Row interactions belong on the row control itself.
2. **Items are `Control`s positioned by absolute rects; there is no measure/layout pass.** You
   supply each item's main-axis extent. Nothing sizes itself unless `auto_measure_items` is on.
   The list sets that rect itself and pins the item root's anchors to top-left, so anchors on the
   root are overwritten — size an item through its extent, never through the root's anchors.
3. **Android class names, Godot snake_case methods.** `RecyclerView` + `set_adapter()`,
   `notify_item_inserted()`, `submit_list()`. Android listener interfaces became virtual methods.
4. **Three ways to feed the list, and only one takes manual `notify_*`.** A plain `Adapter`:
   you call `notify_*`. A `ListAdapter`: `submit_list()` diffs and dispatches for you. A
   `SortedList`: it keeps items ordered and emits the ops; you forward its callback's `_on_*` to
   an adapter. Calling `notify_*` on the latter two is a bug, not an alternative.

5. **A row is bound only after its item scene has run its ready pass** — the library waits for
   `ready` before `_bind_item`, so never `await control.ready` yourself, and never read an item's
   labels right after `_create_item`. A nested RecyclerView whose item was recycled off-tree lays
   out with its scenes unreadied: those rows stay unbound and fill when the item is back on
   screen. Code-built items have no `@onready` state to wait for and bind immediately.

## Minimal working list

```gdscript
class MyAdapter extends Adapter:
	var items: Array = []

	func _get_item_count() -> int:             # required — the default is 0
		return items.size()

	func _create_item(_parent: Control, _view_type: int) -> ViewHolder:
		var vh := ViewHolder.new()
		vh.set_control(ROW_SCENE.instantiate())   # required — a holder with no control is blank
		return vh

	func _bind_item(holder: ViewHolder, position: int) -> void:
		(holder.get_control().get_node(^"Label") as Label).text = str(items[position])

func _ready() -> void:
	var rv := RecyclerView.new()
	rv.set_size(Vector2(400, 600))
	rv.set_item_extent(72)
	rv.set_adapter(MyAdapter.new())
	rv.set_layout(LinearLayoutManager.new())   # required — adapter alone renders nothing
	add_child(rv)
```

## Silent-failure checklist

1. **Layout manager missing.** `set_adapter()` without `set_layout()` renders nothing. The
   adapter is half of the pair, always.
2. **`ViewHolder` without a control.** `_create_item` must `vh.set_control(...)` a `Control`.
3. **Nodes built in `_bind_item`.** It runs on every recycle/reuse — create in `_create_item`,
   only write data in `_bind_item`.
4. **No extent.** Rows default to 64 px. Use `set_item_extent(px)`, override
   `_get_item_extent(pos)`, or enable `set_auto_measure_items(true)` (off by default) for
   content-sized rows. Note the trap: Godot clamps a `Control` up to its own minimum size, so a
   row taller than its extent renders taller than its slot and **overlaps the next row** — it is
   not clipped (extent 48 with 100 px content gives holders at y = 0, 48, 96, each 100 px tall).
5. **Updating data the wrong way for your adapter type.** A plain `Adapter` observes nothing: call
   `notify_item_inserted / _removed / _moved / _changed` (or the `_range_` forms) so it animates
   and reuses holders, or `notify_data_set_changed()` for a full rebuild with no animation. A
   `ListAdapter` and a `SortedList` dispatch their own ops — update them through `submit_list()`
   / `add()` and **never** call `notify_*` yourself: the view moves but their internal list does
   not. On a `ListAdapter` holding `[10, 20, 30]`, a manual `notify_item_removed(0)` renders
   `20, 30, 30` (a row lost, a row duplicated) until the next `submit_list()` repairs it.
6. **`submit_list()` holds the array by reference** (mirrors Android's `AsyncListDiffer`).
   Mutating the array you submitted corrupts the diff and the next call silently does nothing:
   pass a snapshot — `adapter.submit_list(master.duplicate())`.
7. **Looking for signals.** There is nothing to `connect()`. Subclass instead, e.g.
   `rv.add_on_scroll_listener(MyListener.new())` with `ScrollListener._on_scrolled(dx, dy)`.
8. **Wrapping it in a `ScrollContainer`.** The RecyclerView scrolls itself; it needs a bounded
   size from its parent, or virtualizes nothing.
9. **Helper attach styles differ** — guessing from the method name gets it wrong:
   `rv.add_item_decoration(d)` · `rv.set_item_animator(a)` · `ItemTouchHelper` and `SnapHelper`
   both take `.attach_to_recycler_view(rv)` (after `helper.set_callback(cb)`).
10. **`reverse_layout` pins position 0 to the bottom** — it does not reverse the array. A chat
    list is reverse layout *plus* newest item at index 0.
11. **`ListAdapter` without `set_diff_callback()`** falls back to remove-all + insert-all: every
    row rebuilt, nothing animates. `_are_items_the_same` decides identity (same id → move/change),
    `_are_contents_the_same` decides whether a change op is emitted.
12. **RecyclerView left at zero size** lays out nothing — give it a container, anchors, or
    `set_size()`. It looks exactly like a broken adapter.

## API cheat sheet

| Goal | Call |
|---|---|
| Feed the list | `rv.set_adapter(a)` — **and** `rv.set_layout(lm)` |
| Row size | `rv.set_item_extent(px)` · `Adapter._get_item_extent(pos)` · `rv.set_auto_measure_items(true)` |
| Data changed (plain `Adapter`) | `adapter.notify_item_inserted/removed/moved/changed(pos[, count])`, `notify_item_range_*`, `notify_data_set_changed()` |
| Auto-diff | `class X extends ListAdapter` + `set_diff_callback(cb)` + `submit_list(arr.duplicate())` — never `notify_*` |
| Sorted container | `SortedList` + `SortedListCallback` (`set_callback`, `add`, `remove`, `update_item_at`, `index_of`, `begin/end_batched_updates`) — forward its `_on_*` to the adapter, never `notify_*` |
| Diff by hand | `DiffUtil.calculate_diff(cb, detect_moves)` → `dispatch_updates_to(sink)`; a `ListUpdateCallback` sink forwards to `adapter.notify_*`, `AdapterListUpdateCallback` is a ready-made one, `BatchingListUpdateCallback` coalesces |
| Observe data changes | `adapter.register_adapter_data_observer(obs)` + `AdapterDataObserver._on_item_range_inserted/…` |
| Stable ids | `adapter.set_has_stable_ids(true)` + `Adapter._get_item_id(pos)` |
| Partial rebind | payload from `DiffUtilItemCallback._get_change_payload(old, new)` → `Adapter._bind_item_with_payload(holder, pos, payload)` |
| Layouts | `LinearLayoutManager`, `GridLayoutManager` (+ `set_span_count`, `set_span_size_lookup`), `StaggeredGridLayoutManager`; `set_orientation(…HORIZONTAL)`, `set_reverse_layout(true)` |
| Scrolling | `rv.scroll_to_position(pos)`, `rv.smooth_scroll_to_position(pos, sec)`, `rv.get_scroll_offset()` |
| Lifecycle | `Adapter._on_view_attached/detached(holder)`, `_on_item_recycled(holder)`, `_on_failed_to_recycle_view(holder)` |
| Custom layout | subclass `LayoutManager`, override `_on_layout_children(rv, state)`, `_get_position_offset(pos)` |

Virtual methods (underscore-prefixed) are called by the C++ side — never call them yourself.
The public `notify_*` calls are the exception: those are how you report data changes.

## Reading the class reference

The class reference ships inside the extension, so in the Godot editor F1 on any of the 31 classes
shows signatures, members and descriptions. Outside the editor, the same XML lives in
`doc_classes/` in the repository.

When behaviour is unclear, prefer reading the demo scenes in the repository's `project/` folder
over inferring from a method name: this port follows Android's naming closely, but the call styles
above are exactly where it diverges.
