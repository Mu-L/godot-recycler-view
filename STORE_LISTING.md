# Godot RecyclerView

### Android's RecyclerView, ported to Godot 4 as a GDExtension.

Godot's built-in `ItemList` and `Tree` can't render rich custom rows, and stacking rows in a
`VBoxContainer` stops working once the list gets long: every row is a real node, and you pay for
them when the list is built and again on every scroll. On an M2 Pro, a 10,000-row `VBoxContainer`
of card-shaped rows (avatar, title, subtitle, progress bar, button) takes 6.2 seconds to create,
holds 120,000 nodes in about 1.9 GB, and scrolls at 12 fps — each wheel event has to hit-test all
of them. The `naive_list_demo` in the repository lets you reproduce those numbers: pick an item
count, switch between the container and the RecyclerView, and watch the counters.

RecyclerView keeps only the rows that intersect the viewport in the tree. The same 10,000-row
list is 87 nodes, builds in 19 ms, and scrolls at 60 fps.

Adapters, view holders, layout managers, the recycled pool, item animations, `ItemTouchHelper`,
`SnapHelper`, `DiffUtil` and the scroll bar all come from `androidx.recyclerview`, so the names
and the mental model carry over. Everything is driven from GDScript.

```gdscript
class MyAdapter extends Adapter:
    var items: Array = []
    func _get_item_count() -> int:
        return items.size()
    func _create_item(parent: Control, view_type: int) -> ViewHolder:
        var vh := ViewHolder.new()
        vh.set_control(ROW_SCENE.instantiate())      # any Control: scene, container, RichTextLabel
        return vh
    func _bind_item(holder: ViewHolder, position: int) -> void:
        var row := holder.get_control() as MyRow     # the script on your row scene
        row.refresh(items[position])

var rv := RecyclerView.new()
rv.set_item_extent(72)
rv.set_adapter(MyAdapter.new())
rv.set_layout(LinearLayoutManager.new())             # or Grid / StaggeredGrid
add_child(rv)
```

## What's in it

The list itself:

- Viewport virtualization with clipping, prefetch, and three levels of view reuse (changed scrap,
  position-bound view cache, per-type recycled pool).
- `Adapter` and `ListAdapter`. Subclass one and implement `_create_item`, `_bind_item` and
  `_get_item_count`; `ListAdapter.submit_list()` diffs for you.
- `LinearLayoutManager`, `GridLayoutManager` (with `SpanSizeLookup` for full-width headers) and
  `StaggeredGridLayoutManager`. Vertical or horizontal, `reverse_layout` for chat lists, and a
  `span_count` you can change while the grid is on screen.
- Rows can have different extents and view types, or you can turn on `auto_measure_items` and let
  each row measure itself (Android's `wrap_content`; a `SIZE_EXPAND` root fills the viewport like
  `match_parent`). A `RichTextLabel` with `fit_content` works without extra setup.

Data updates:

- `notify_item_inserted` / `removed` / `moved` / `changed`, queued and applied at frame end, so you
  can call them in any order.
- `DiffUtil` with stable ids, plus payload updates that rebind only the child control that changed
  instead of the whole row.

Interaction and effects:

- `DefaultItemAnimator` fades, slides and moves rows on insert, remove, move and change.
- `ItemTouchHelper` for long-press drag-to-reorder and swipe-to-dismiss.
- `LinearSnapHelper` (center snap) and `PagerSnapHelper` (one page per fling).
- Scroll bars built on Godot's `ScrollBar`, with `Overlay` / `Inset` / `Reserve` / `Never` modes,
  auto-fade when idle, and theming from the editor.
- `ItemDecoration` for per-item insets and custom drawing.
- `ScrollListener` for scroll deltas and `IDLE` / `DRAGGING` / `SETTLING` transitions, plus inertial
  fling, nested RecyclerViews, `scroll_to_position` and `smooth_scroll_to_position`.

Documentation and demos:

- The class reference is compiled into the extension. 31 classes show up in the editor, so F1 on
  `RecyclerView` or `GridLayoutManager` gives you the signatures and descriptions.
- 22 demo scenes in the bundled project: a 10k list, masonry, chat, drag-and-drop, snapping, a
  custom layout, responsive grids. Open the project and press F5.
- Guides in English and Chinese.
- 240+ GDScript tests (gdUnit4) and 130+ C++ tests covering the algorithm layer that doesn't need
  the engine.

## Platforms

Prebuilt binaries for Linux (x86_64, x86_32, arm64, arm32), Windows (x86_64, x86_32, arm64), macOS
(universal), Android (arm64, arm32, x86_64, x86_32), iOS (arm64) and Web (wasm32), in debug and
release, single and double precision. You can also build it yourself with one `scons` command.

## Getting started

Copy the extension into your project — the `.gdextension` file uses relative paths, so the folder
can go anywhere — then:

1. Subclass `Adapter` and implement `_create_item`, `_bind_item` and `_get_item_count`.
2. Create a `RecyclerView`, give it an item extent, your adapter and a layout manager.
3. Call `notify_item_*` when the data changes, or use `ListAdapter.submit_list()` and let it diff.

The `project/` folder is a complete Godot project with every demo scene in it. The
[guides](https://github.com/iYouthy/godot-recycler-view/tree/main/docs) walk through each feature
with runnable code.

## Requirements

Godot 4.3 or newer (the project itself targets 4.7; the in-editor class docs need 4.3+). The
prebuilt binaries have no other dependencies. Building from source needs SCons and a C++17
compiler.

## License

MIT. A port of Android RecyclerView (`androidx.recyclerview`, Apache-2.0), with the upstream
attribution kept.

---
---

# 中文介绍（可选，如需在描述中附中文说明）

## Godot RecyclerView

### Android 的 RecyclerView，移植到 Godot 4 的 GDExtension。

Godot 自带的 `ItemList` 和 `Tree` 渲染不了复杂的自定义条目，用 `VBoxContainer` 堆又堆不长：
每行都是真实节点，列表建出来要付一次代价，之后每次滚动还要再付一次。M2 Pro 上做一个一万行的
卡片列表（头像、标题、副标题、进度条、按钮），创建要 6.2 秒，12 万个节点占约 1.9 GB 内存，滚动只有
12fps——每收到一次滚轮事件，都要在这上万个控件里做一遍命中测试。仓库里的 `naive_list_demo` 可以复现
这些数字：选条目数量，在容器和 RecyclerView 之间切换，盯着统计栏看就行。

RecyclerView 只把与视口相交的那几行留在场景树里。同一份一万行的列表，87 个节点，19 毫秒建好，
滚动 60fps。

适配器、ViewHolder、布局管理器、回收池、条目动画、`ItemTouchHelper`、`SnapHelper`、`DiffUtil` 和
滚动条都来自 `androidx.recyclerview`，名字和思路都可以照搬，用 GDScript 驱动。

```gdscript
class MyAdapter extends Adapter:
    var items: Array = []
    func _get_item_count() -> int:
        return items.size()
    func _create_item(parent: Control, view_type: int) -> ViewHolder:
        var vh := ViewHolder.new()
        vh.set_control(ROW_SCENE.instantiate())      # 任意 Control：场景、容器、RichTextLabel
        return vh
    func _bind_item(holder: ViewHolder, position: int) -> void:
        var row := holder.get_control() as MyRow     # 你的行场景上的脚本
        row.refresh(items[position])

var rv := RecyclerView.new()
rv.set_item_extent(72)
rv.set_adapter(MyAdapter.new())
rv.set_layout(LinearLayoutManager.new())             # 或 Grid / StaggeredGrid
add_child(rv)
```

## 有什么

列表本身：

- 视口虚拟化，带裁剪、预取和三级视图复用（变化暂存 / 位置绑定的视图缓存 / 按类型回收池）。
- `Adapter` 和 `ListAdapter`。继承之后实现 `_create_item`、`_bind_item` 和 `_get_item_count`；
  `ListAdapter.submit_list()` 会自动 diff。
- `LinearLayoutManager`、`GridLayoutManager`（配合 `SpanSizeLookup` 可以做通栏标题）和
  `StaggeredGridLayoutManager`。横竖两个方向都支持，聊天列表用 `reverse_layout`，网格的列数
  可以在运行时改。
- 条目可以有不同的长度和视图类型，也可以打开 `auto_measure_items` 让条目自己决定高度（对应
  Android 的 `wrap_content`；根节点用 `SIZE_EXPAND` 就填满视口，相当于 `match_parent`）。带
  `fit_content` 的 `RichTextLabel` 不需要额外处理。

数据更新：

- `notify_item_inserted` / `removed` / `moved` / `changed`，统一排队到帧末应用，调用顺序随意。
- `DiffUtil` 支持稳定 id；payload 局部更新只重绑变化的那个子控件，不重建整行。

交互和效果：

- `DefaultItemAnimator`：插入、移除、移动、变化时的淡入淡出和滑动。
- `ItemTouchHelper`：长按拖拽排序、滑动删除。
- `LinearSnapHelper`（居中吸附）和 `PagerSnapHelper`（一次一页）。
- 滚动条基于 Godot 的 `ScrollBar`，有 `Overlay` / `Inset` / `Reserve` / `Never` 四种模式，空闲
  自动淡出，可以直接在编辑器里改主题。
- `ItemDecoration`：条目内边距和自绘分隔线。
- `ScrollListener`：滚动增量和 `IDLE` / `DRAGGING` / `SETTLING` 状态；另外还有惯性滑动、嵌套
  RecyclerView、`scroll_to_position` 和 `smooth_scroll_to_position`。

文档和示例：

- 类参考编译在扩展里，31 个类会出现在编辑器中，在 `RecyclerView` 或 `GridLayoutManager` 上按 F1
  就能看到签名和说明。
- 工程里带了 22 个 demo 场景：万条列表、瀑布流、聊天、拖拽、吸附、自定义布局、响应式网格等等。
  打开工程按 F5 就能跑。
- 中英文教程各一套。
- 240+ 个 GDScript 测试（gdUnit4），130+ 个 C++ 测试（覆盖不依赖引擎的算法层）。

## 平台

预编译好的二进制覆盖 Linux（x86_64、x86_32、arm64、arm32）、Windows（x86_64、x86_32、arm64）、
macOS（universal）、Android（arm64、arm32、x86_64、x86_32）、iOS（arm64）和 Web（wasm32），调试版和
发布版、单精度和双精度都有。也可以用一条 `scons` 命令自己编译。

## 开始使用

把扩展拷进项目即可（`.gdextension` 里用的是相对路径，放哪个目录都行），然后：

1. 继承 `Adapter`，实现 `_create_item`、`_bind_item` 和 `_get_item_count`。
2. 创建 `RecyclerView`，设置条目长度、适配器和布局管理器。
3. 数据变化时调用 `notify_item_*`，或者改用 `ListAdapter.submit_list()` 让它自动 diff。

`project/` 是一个完整的 Godot 工程，所有 demo 场景都在里面。每个功能的详细用法见
[教程]（https：//github.com/iYouthy/godot-recycler-view/tree/main/docs）。

## 环境要求

Godot 4.3 或更高（工程本身以 4.7 为目标；编辑器内的类文档需要 4.3+）。预编译二进制没有其他依赖。
从源码编译需要 SCons 和一个 C++17 编译器。

## 许可证

MIT。移植自 Android RecyclerView（`androidx.recyclerview`，Apache-2.0），保留了上游署名。
