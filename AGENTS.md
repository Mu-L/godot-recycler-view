# Godot RecyclerView — notes for AI coding agents

This library is a GDExtension port of Android's RecyclerView: a virtualized list where only the
rows intersecting the viewport exist as nodes. It is not a Godot container, and most of its
failure modes are **silent** — no error, no warning, just "nothing renders" or "the view shows
stale data". Read this file before writing code against it.

If you are an agent working inside *another* project that uses this library, copy this file into
that project (or into your context) — the rules below are the ones that get missed.

---

## The mental model

Five things trip up code generation more than anything else:

1. **Callbacks are GDScript virtual methods, not signals.** Subclass and override methods with a
   leading underscore (`_create_item`, `_bind_item`, `_on_scrolled`, …). The RecyclerView itself
   emits no signals — there is no `item_clicked` to connect. Wire row interactions on the row
   control you instantiate (buttons, `gui_input`), the way the demos do.

2. **Items are `Control`s positioned by absolute rects, not by a container layout.** There is no
   measure/layout pass. Every item has a *main-axis extent* you supply; the cross axis comes from
   the viewport. Nothing sizes itself unless you turn on `auto_measure_items`.

3. **Class names are Android's, methods are Godot snake_case.** `RecyclerView`, `Adapter`,
   `ViewHolder`, `LinearLayoutManager` — but `set_adapter()`, `notify_item_inserted()`,
   `submit_list()`. Where the Android API used a listener interface, this port uses a virtual
   method (`ScrollListener._on_scrolled`, `DiffUtilItemCallback._are_items_the_same`, …).

4. **There are three ways to feed the list, and only one of them takes manual `notify_*` calls.**
   Picking the wrong one, or mixing them, is the single most common source of "the view won't
   update" reports. See the next section.

5. **A row is bound only after its item scene has run its ready pass.** The library mounts the
   control, and when the scene has `@onready` references to fill it waits for `ready` before
   calling `_bind_item` — so your `_bind_item` never writes into a half-built item and you should
   never `await control.ready` yourself. A control that *cannot* run its ready pass stays unbound
   until it can: a nested RecyclerView whose item was recycled off-tree is laid out with its
   scenes unreadied, so those rows fill when the item comes back on screen rather than at the
   moment you submit. Items built in code have no `@onready` state to wait for and bind straight
   away.

---

## Feeding the list: pick one pattern

`Adapter` (the base class) knows nothing about your data. It only counts and binds. How the list
learns that data changed depends on which subclass you build:

### Pattern A — plain `Adapter` + manual `notify_*`

You own the array, you tell the list exactly what changed. No diffing: the ops you send are the
ops applied.

```gdscript
class MyAdapter extends Adapter:
	var items: Array = []
	func _get_item_count() -> int: return items.size()
	func _create_item(_parent, _view_type) -> ViewHolder: ...
	func _bind_item(holder, position) -> void: ...

# on change:
items.append(x)
adapter.notify_item_inserted(items.size() - 1)
```

Use the narrowest op that describes the change (`notify_item_inserted` / `_removed` / `_moved` /
`_changed`, plus `_range_` variants for a run of them). Narrower ops mean better holder reuse and
correct animations. `notify_data_set_changed()` is the sledgehammer — it re-binds every visible
row and skips animations.

### Pattern B — `ListAdapter` + `submit_list()` — **do not call `notify_*`**

`ListAdapter` holds the list itself and diffs the old list against the new one, then dispatches
the resulting `notify_*` calls to the RecyclerView for you. Handing it a new array *is* the update
mechanism.

```gdscript
class MyAdapter extends ListAdapter:
	func _create_item(_parent, _view_type) -> ViewHolder: ...
	func _bind_item(holder, position) -> void:
		var item = get_item(position)          # read through the adapter, not a side array

adapter.set_diff_callback(MyDiff.new())        # required, or submit_list degrades to a full rebuild
adapter.submit_list(items.duplicate())         # the update: diff + dispatch, no manual notify
```

Calling `notify_*` on a `ListAdapter` is a bug even though the methods exist (they are inherited
from `Adapter`): the adapter's internal list and the RecyclerView's positions would disagree, and
the next `submit_list()` would diff against a list the view no longer matches. Change the data,
then submit.

`_on_current_list_changed(previous, current)` is the hook for reacting after a commit.

### Pattern C — `SortedList` + `SortedListCallback` — **do not call `notify_*`**

`SortedList` is a container that keeps items ordered by your comparator and emits the right
insert/remove/move/change events as they are added, updated or removed. It is the tool for a list
whose order is derived (leaderboards, priority queues, anything sorted by a score).

```gdscript
class MyCallback extends SortedListCallback:
	var adapter: Adapter
	func _compare(a, b) -> int: return a.score - b.score          # sort order (required)
	func _are_items_the_same(a, b) -> bool: return a.id == b.id   # identity (required)
	func _are_contents_the_same(a, b) -> bool: return a.score == b.score
	# forward what the list decided:
	func _on_inserted(position: int, count: int) -> void:
		adapter.notify_item_range_inserted(position, count)
	func _on_removed(position: int, count: int) -> void:
		adapter.notify_item_range_removed(position, count)
	func _on_moved(from_position: int, to_position: int) -> void:
		adapter.notify_item_moved(from_position, to_position)
	func _on_changed(position: int, count: int) -> void:
		adapter.notify_item_range_changed(position, count, null)

var sorted := SortedList.new()
sorted.set_callback(cb)
sorted.add(item)              # lands at its sorted position; cb._on_inserted fires
sorted.remove(item)
sorted.update_item_at(index, new_item)
sorted.begin_batched_updates()   # coalesce many changes into fewer notifications
sorted.end_batched_updates()
```

`SortedList` is **not** an `Adapter` — it is the data source. You still write an `Adapter` whose
`_get_item_count()` returns `sorted.size()` and whose `_bind_item()` reads `sorted.get(position)`.
The callback's `_on_*` methods are where you forward to that adapter. Since the sorted list
already computed the change, you forward rather than invent.

---

## A minimal working list

```gdscript
extends Control

const ROW_SCENE := preload("res://row.tscn")

class MyAdapter extends Adapter:
	var items: Array = []

	func _get_item_count() -> int:            # REQUIRED — without it the count is 0
		return items.size()

	func _create_item(_parent: Control, _view_type: int) -> ViewHolder:
		var vh := ViewHolder.new()
		vh.set_control(ROW_SCENE.instantiate())   # REQUIRED — a holder with no control renders nothing
		return vh

	func _bind_item(holder: ViewHolder, position: int) -> void:
		var row: Control = holder.get_control()
		(row.get_node(^"Label") as Label).text = str(items[position])

func _ready() -> void:
	var rv := RecyclerView.new()
	rv.set_size(Vector2(400, 600))            # or let a container size it
	rv.set_item_extent(72)                    # main-axis size of every row
	rv.set_adapter(MyAdapter.new())
	rv.set_layout(LinearLayoutManager.new())  # REQUIRED — adapter alone renders nothing
	add_child(rv)
```

---

## Mistakes that fail silently

Each of these produces no error message. Check your code against this list.

### 1. Setting an adapter without a layout manager

`layout_children()` returns immediately when either is missing, so the list stays empty.

```gdscript
rv.set_adapter(MyAdapter.new())                    # WRONG — nothing renders
rv.set_adapter(MyAdapter.new())
rv.set_layout(LinearLayoutManager.new())           # RIGHT
```

### 2. A `ViewHolder` without a control

```gdscript
func _create_item(parent, view_type):              # WRONG — rows are blank
	return ViewHolder.new()

func _create_item(parent, view_type):              # RIGHT
	var vh := ViewHolder.new()
	vh.set_control(ROW_SCENE.instantiate())
	return vh
```

### 3. Building nodes in `_bind_item`

`_bind_item` runs every time a recycled holder is reused — creating nodes there duplicates them
on every scroll. `_create_item` builds once per holder; `_bind_item` only writes data into what
already exists.

### 4. Assuming a measure pass will size rows

Without an extent, every row uses the RecyclerView's default (64 px). Set it globally with
`set_item_extent()`, per position by overriding `Adapter._get_item_extent(position)`, or turn on
`set_auto_measure_items(true)` and let each row be measured from its own control (Android's
`wrap_content`).

The trap: rows are **laid out** at the extent you gave, but Godot clamps a `Control`'s size up to
its own combined minimum size. A row whose content is taller than its extent therefore renders
taller than its slot and **overlaps the next row** — it is not clipped, and nothing warns you.
Measured: with `extent = 48` and a row whose minimum height is 100, the holders land at y = 0, 48,
96 … while each is 100 px tall; with `auto_measure_items` on they land at 0, 100, 200 and match.
`auto_measure_items` is off by default, so set an extent that actually matches your content or
turn it on.

### 5. Calling `notify_*` on a `ListAdapter` or `SortedList`

See "Feeding the list" above. Both dispatch their own ops; a manual `notify_*` moves the view
without moving the list they hold, so the two disagree until the next managed update repairs it.
Measured on a `ListAdapter` holding `[10, 20, 30]`: a manual `notify_item_removed(0)` leaves the
view rendering `20, 30, 30` — one row lost and one duplicated, because the layout then fills
position 2 from the adapter's unchanged list. (A manual `notify_item_inserted` past the end is
simply ignored, which is why this goes unnoticed until a removal.) Either use a plain `Adapter`
with `notify_*`, or use the managed subclass and only mutate through it.

### 6. Mutating the array you gave `submit_list()`

`ListAdapter` keeps that array by reference, mirroring Android's `AsyncListDiffer`. Mutating it
afterwards corrupts the diff's "previous list", and the next `submit_list` silently does nothing.

```gdscript
adapter.submit_list(master)                        # WRONG if you keep mutating `master`
master.push_front(new_item)                        # the adapter's previous list is now this

adapter.submit_list(master.duplicate())            # RIGHT — submit a snapshot
```

### 7. Expecting signals

There is nothing to `connect()` on the list or the adapter. Subclass instead:

```gdscript
rv.scrolled.connect(...)                           # WRONG — no such signal

class MyListener extends ScrollListener:
	func _on_scrolled(dx: int, dy: int) -> void:
		pass
rv.add_on_scroll_listener(MyListener.new())        # RIGHT
```

Row-local interactions (buttons, taps) belong on the row control from `_create_item`. To observe
data changes without subclassing the adapter, register an `AdapterDataObserver` with
`adapter.register_adapter_data_observer(obs)`.

### 8. Wrapping the RecyclerView in a ScrollContainer

The RecyclerView scrolls itself. Put it directly under a container that gives it a bounded size
(`size_flags_vertical = SIZE_EXPAND_FILL` in a VBoxContainer, anchors, an explicit `set_size`).
Inside a `ScrollContainer` it gets unbounded height and virtualizes nothing.

### 9. Attaching helpers the wrong way

These are three different call styles; guessing from the method name gets it wrong:

```gdscript
rv.add_item_decoration(MyDivider.new())            # decoration   → add_item_decoration
rv.set_item_animator(DefaultItemAnimator.new())    # animator     → set_item_animator

var helper := ItemTouchHelper.new()                # touch helper → attach_to_recycler_view
helper.set_callback(MyCallback.new())
helper.attach_to_recycler_view(rv)

var snap := LinearSnapHelper.new()                 # snap helper  → attach_to_recycler_view
snap.attach_to_recycler_view(rv)
```

### 10. Misreading `reverse_layout`

`set_reverse_layout(true)` pins **position 0 to the bottom** of the viewport; it does not reverse
the array. A chat list is therefore reverse layout + newest item at index 0 (insert at the front),
not "append and hope".

### 11. Creating a `ListAdapter` without a diff callback

Without one, `submit_list()` falls back to remove-all + insert-all: every row is rebuilt and
nothing animates. Supply the comparator:

```gdscript
class MyDiff extends DiffUtilItemCallback:
	func _are_items_the_same(a: Variant, b: Variant) -> bool:
		return a.id == b.id              # identity: same id → move/change, not remove+insert
	func _are_contents_the_same(a: Variant, b: Variant) -> bool:
		return a.text == b.text          # equality: false → a change op is emitted

adapter.set_diff_callback(MyDiff.new())
```

### 12. Leaving the RecyclerView at zero size

It is a `Control`: place it in a container that gives it a real size, or call `set_size()`. A
zero-height RecyclerView lays out nothing, which looks identical to a broken adapter.

---

## API cheat sheet

**Feeding the list**

| Goal | Call |
|---|---|
| Plain adapter | `class X extends Adapter` + `set_adapter(a)` **and** `set_layout(lm)` |
| Manual updates | `adapter.notify_item_inserted/removed/moved/changed(pos[, count])`, `notify_item_range_*`, `notify_data_set_changed()` |
| Auto-diff | `class X extends ListAdapter` + `set_diff_callback(cb)` + `submit_list(arr.duplicate())` — **never** `notify_*` |
| Sorted container | `SortedList` + `SortedListCallback` (`set_callback`, `add`, `remove`, `update_item_at`, `index_of`, `begin/end_batched_updates`) — forward its `_on_*` to the adapter, **never** `notify_*` yourself |
| Stable ids | `adapter.set_has_stable_ids(true)` + `Adapter._get_item_id(pos)` |
| Partial rebind | payload from `DiffUtilItemCallback._get_change_payload(old, new)` → `Adapter._bind_item_with_payload(holder, pos, payload)` |
| Observe data changes | `adapter.register_adapter_data_observer(obs)` with `AdapterDataObserver._on_item_range_inserted/…` |

**Diffing by hand** (full control, what `diff_demo` does)

| Goal | Call |
|---|---|
| Diff two lists | `class X extends DiffUtilCallback` (position-based: `_get_old_list_size`, `_get_new_list_size`, `_are_items_the_same(old_pos, new_pos)`, `_are_contents_the_same`) |
| Run it | `DiffUtil.calculate_diff(cb, detect_moves)` → `DiffResult` |
| Apply it | `result.dispatch_updates_to(sink)` where the sink is a `ListUpdateCallback` (`_on_inserted/_on_removed/_on_moved/_on_changed`) forwarding to `adapter.notify_*`; `AdapterListUpdateCallback.set_adapter(a)` is a ready-made sink |
| Coalesce ops | wrap the sink in a `BatchingListUpdateCallback` + `dispatch_last_event()` |
| Position mapping | `result.convert_old_position_to_new(pos)`, `convert_new_position_to_old(pos)` |

**Layout, scrolling, interaction**

| Goal | Call |
|---|---|
| Row size | `rv.set_item_extent(px)` · `Adapter._get_item_extent(pos)` · `rv.set_auto_measure_items(true)` |
| Layouts | `LinearLayoutManager`, `GridLayoutManager` (+ `set_span_count`, `set_span_size_lookup`, `SpanSizeLookup._get_span_size(pos)`), `StaggeredGridLayoutManager`; `set_orientation(…HORIZONTAL)`, `set_reverse_layout(true)` |
| Scrolling | `rv.scroll_to_position(pos)`, `rv.smooth_scroll_to_position(pos, sec)`, `rv.get_scroll_offset()`, `rv.get_scroll_state()` |
| Row chrome | `rv.add_item_decoration(dec)` (`ItemDecoration._get_item_offsets(pos, parent)`, `_on_draw(parent)`), `rv.set_item_animator(anim)` (`DefaultItemAnimator`, or subclass `ItemAnimator` for `_animate_add/remove/move/change`) |
| Gestures | `ItemTouchHelper` + `ItemTouchHelperCallback` (`_get_movement_flags`, `_is_long_press_drag_enabled`, `_is_item_view_swipe_enabled`, `_on_swiped`, …) → `attach_to_recycler_view(rv)` |
| Snapping | `LinearSnapHelper` / `PagerSnapHelper` → `attach_to_recycler_view(rv)` |
| Scroll events | `rv.add_on_scroll_listener(listener)` with `ScrollListener._on_scrolled(dx, dy)` / `_on_scroll_state_changed(state)` |
| Lifecycle hooks | `Adapter._on_view_attached/detached(holder)`, `_on_item_recycled(holder)`, `_on_failed_to_recycle_view(holder)` |
| Custom layout | subclass `LayoutManager`, override `_on_layout_children(rv, state)`, `_get_position_offset(pos)`, `_get_item_rect(rv, pos)`, … (see `custom_layout_demo`) |

Virtual methods (underscore-prefixed) are called by the C++ side — never call them yourself.
The public `notify_*` calls are the exception: those are how you report data changes, and only
when you are the one owning the data (Pattern A).

---

## Where to look next

- `docs/en/guides/` — feature walkthroughs with runnable code (quick_start, data_updates,
  layout_managers, animations, touch_interaction, scroll_bars, multi_view_types,
  reverse_and_nested).
- `project/` — a complete Godot project with 22 demo scenes; each one is a working example of a
  single feature (`diff_demo` for manual `DiffUtil`, `list_adapter_demo` for `submit_list`,
  `custom_layout_demo` for a scripted layout manager). The class reference is compiled into the
  extension, so the editor shows it on F1.
- `doc_classes/*.xml` — the same reference as plain XML, if you need signatures without the editor.

If something is not covered here, prefer reading a demo scene over inferring behaviour from the
method name: this port follows Android's naming closely, but the call styles above are where it
diverges.
