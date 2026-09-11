extends Control

# 朴素实现 vs RecyclerView：同一份列表、同一个条目场景，只换渲染方式，
# 用同一块区域和同一套指标对比，直观感受"条目一多会怎样"。
#
# VBoxContainer 方案（朴素实现）把每一条都做成真实节点：
#   - 创建：一次性实例化全部条目，条目越多，点击后界面冻结越久；
#   - 滚动：每一帧都要排布并绘制全部节点，帧率随条目数下降；
#   - 常驻：条目全部留在场景树里，节点数 = 条目数 × 每个条目的子节点数。
# RecyclerView 只保留与视口相交的少数条目，创建和滚动都是常量开销——
# 切到 RecyclerView 模式时节点数会断崖式下降，且滚动帧率不受条目总数影响。
#
# 用法：上面两个下拉框分别选「条目数量」和「渲染方式」。
#   ① 切换数量时看「构建耗时」——VBoxContainer 要一次性建出所有条目，数量越大
#      界面冻结越久；RecyclerView 始终是十几毫秒，与总数无关。
#   ② 用滚轮滚动时看「FPS」——VBoxContainer 的帧率随条目总数下降：每次滚轮
#      事件都要在全部条目里做命中测试，条目越多越慢。RecyclerView 只保留可见的
#      那十几行，帧率不受总数影响。
#
# M2 Pro 实测（每个数据点独立进程、1600x900 视口、条目高 88）：
#   1 万条   构建 6.2 s / 12 万节点 / 1.9 GB   滚动 12 fps   |  RV 19 ms / 87 节点 / 满帧
#   5000 条  构建 2.5 s /  6 万节点 / 1.0 GB   滚动 24 fps   |  RV 17 ms / 87 节点 / 满帧
#   1000 条  构建 0.47 s / 1.2 万节点         滚动 58 fps   |  RV 16 ms / 87 节点 / 满帧
# 这里的条目刻意做得像一个真实卡片（面板 + 边距 + 横向容器 + 头像 + 标题/
# 副标题/进度条 + 时间/按钮，共 12 个节点），而不是一个光秃秃的 Label——
# 真实列表的条目大多长这样，节点越多、容器嵌套越深，VBoxContainer 的拐点
# 来得越早。

const ROW_SCENE := preload("res://naive_row.tscn")

@onready var count_option: OptionButton = %CountOption
@onready var mode_option: OptionButton = %ModeOption
@onready var stats_label: Label = %StatsLabel
@onready var scroll: ScrollContainer = %Scroll
@onready var list_box: VBoxContainer = %ListBox
@onready var recycler_view: RecyclerView = %RecyclerView

var _count := 100
var _naive_mode := true
var _build_ms := 0.0
var _list_nodes := 0
var _adapter: RowAdapter
var _building := false


class RowAdapter extends ListAdapter:
	const ROW_SCENE := preload("res://naive_row.tscn")

	# 一个条目就是一个真实卡片：面板 + 边距 + 横向容器 + 头像色块 + 文本列
	# （标题/副标题/进度条）+ 操作列（时间/按钮），共 12 个节点。
	static func apply_row_content(row: Control, index: int) -> void:
		(row.get_node(^"Card/Margin/Row/Body/Title") as Label).text = "Item %d" % index
		(row.get_node(^"Card/Margin/Row/Body/Progress") as ProgressBar).value = float(index % 100)
		(row.get_node(^"Card/Margin/Row/Actions/Time") as Label).text = "12:%02d" % (index % 60)
		(row.get_node(^"Card/Margin/Row/Avatar") as ColorRect).color = Color.from_hsv(
			fmod(index * 0.013, 1.0), 0.35, 0.55)

	func _get_item_extent(_position: int) -> int:
		return 88

	func _create_item(_parent: Control, _view_type: int) -> ViewHolder:
		var vh := ViewHolder.new()
		vh.set_control(ROW_SCENE.instantiate() as Control)
		return vh

	func _bind_item(holder: ViewHolder, position: int) -> void:
		apply_row_content(holder.get_control(), int(get_item(position)))


func _ready() -> void:
	recycler_view.set_item_extent(88)
	recycler_view.set_layout(LinearLayoutManager.new())
	for n in [100, 500, 1000, 2000, 5000, 10000]:
		count_option.add_item(str(n))
	count_option.selected = 0
	count_option.item_selected.connect(func(_i: int) -> void: _on_count_changed())
	mode_option.add_item("VBoxContainer（朴素实现）")
	mode_option.add_item("RecyclerView（本库）")
	mode_option.selected = 0
	mode_option.item_selected.connect(func(_i: int) -> void: _on_mode_changed())
	_rebuild()


func _on_count_changed() -> void:
	_count = int(count_option.get_item_text(count_option.selected))
	_rebuild()


func _on_mode_changed() -> void:
	_naive_mode = mode_option.selected == 0
	_rebuild()


func _process(_delta: float) -> void:
	_update_stats()


func _rebuild() -> void:
	if _building:
		return
	_building = true
	_update_stats()
	# 先清掉上一批条目并等它们真正释放（queue_free 在帧末生效）。清理不计入
	# 构建耗时，也不会和新一批同时在树上——否则节点数会虚高。
	if _naive_mode:
		_clear_recycler()
	_clear_naive()
	await get_tree().process_frame

	var t0 := Time.get_ticks_usec()
	if _naive_mode:
		scroll.visible = true
		recycler_view.visible = false
		_build_naive()
	else:
		scroll.visible = false
		recycler_view.visible = true
		_build_recycler()
	# 真正让用户感到"卡"的是这一段：实例化 + 入树 + 随后那一帧的排布与绘制。
	# 等到帧末再记时，测到的才是界面的冻结时长。
	await get_tree().process_frame
	_build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	_building = false
	_update_stats()


func _build_naive() -> void:
	for i in _count:
		var row := ROW_SCENE.instantiate() as Control
		RowAdapter.apply_row_content(row, i)
		list_box.add_child(row)


func _build_recycler() -> void:
	_adapter = RowAdapter.new()
	var items: Array = []
	for i in _count:
		items.append(i)
	_adapter.submit_list(items)
	recycler_view.set_adapter(_adapter)


func _clear_naive() -> void:
	# queue_free only: removing thousands of children one by one is O(n²) and
	# would dominate the very measurement this demo is about. The nodes leave
	# the tree at frame end, and _rebuild waits for that before building anew.
	for child in list_box.get_children():
		child.queue_free()


func _clear_recycler() -> void:
	_adapter = null
	recycler_view.set_adapter(null)
	recycler_view.free_items()


func _count_nodes(node: Node) -> int:
	var total := 1
	for child in node.get_children():
		total += _count_nodes(child)
	return total


# 列表当前的节点数。朴素模式每一行的节点数固定（数一行再乘行数即可，递归
# 几万个节点会拖慢测量本身）；RecyclerView 只挂可见的少数条目，递归开销可以
# 忽略，而且滚动时挂载数会变，需要实时数。
func _list_node_count() -> int:
	if _naive_mode:
		var rows := list_box.get_child_count()
		if rows == 0:
			return 1
		return 1 + rows * _count_nodes(list_box.get_child(0))
	return _count_nodes(recycler_view)


func _update_stats() -> void:
	if _building:
		stats_label.text = "正在构建 %d 条……" % _count
		return
	_list_nodes = _list_node_count()
	var fps := Engine.get_frames_per_second()
	stats_label.text = "FPS %d   |   帧时间 %.1f ms   |   本列表节点数 %d   |   场景节点总数 %d   |   上次构建耗时 %.0f ms" % [
		fps, 1000.0 / maxf(float(fps), 1.0), _list_nodes,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), _build_ms,
	]
