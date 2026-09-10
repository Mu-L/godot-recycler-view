extends VBoxContainer

# 响应式网格 demo:窗口（或容器）越宽，一行容纳的 item 越多。
#
# GridLayoutManager 的 span_count（列数）支持运行时变更：set_span_count()
# 会重建行模型，下一次布局把已挂载的 item 重新排到新的行/列上（holder 复用，
# 不是整体重建）。库不会自己猜列数——"一行放几个"是业务决策，所以这里演示
# 使用侧需要的接线：监听 RecyclerView 的 resized 信号，按视口宽度算出列数，
# 变了才 set_span_count + request_layout。事件驱动，不做轮询。
#
# 拖动窗口边缘改宽度即可看到列数变化。
#
# 注意列数跟随的是 RecyclerView 的**逻辑视口宽度**：项目开了 stretch
# （viewport + expand），逻辑宽度在窗口宽高比超过设计比例时才会增长，
# 所以把窗口拖宽就能看到列数上涨。若项目用固定视口或 keep 比例，逻辑宽度
# 恒定，列数自然不变——那是 stretch 设置的语义，不是列表的问题。
#
# 一个容器布局的坑：InfoLabel 必须开自动换行（autowrap_mode），否则它那行长文本的
# 最小宽度会成为整个 VBoxContainer 的最小宽度，容器再也不会窄到让列数降下来——
# 响应式布局会在缩窗口时卡住。任何放在列表上方的长文本 Label 都有这个问题。

const ITEM_SCENE := preload("res://grid_item.tscn")

# 每个 item 的目标宽度。实际宽度 = 视口宽度 / 列数：格子均分视口（与 Android
# 的 GridLayoutManager 一致，item 会被拉伸填满格子），所以实际值略大于目标值。
const TARGET_ITEM_WIDTH := 160

@onready var recycler_view: RecyclerView = %RecyclerView
@onready var info_label: Label = %InfoLabel

var _adapter: CellAdapter
var _layout: GridLayoutManager


class CellAdapter extends Adapter:
	var count: int = 60
	var created: int = 0

	func _get_item_count() -> int:
		return count

	func _get_item_extent(_position: int) -> int:
		return 60

	func _create_item(_parent: Control, _view_type: int) -> ViewHolder:
		created += 1
		var vh := ViewHolder.new()
		vh.set_control(ITEM_SCENE.instantiate() as Control)
		return vh

	func _bind_item(holder: ViewHolder, position: int) -> void:
		var item: Control = holder.get_control()
		(item.get_node("Label") as Label).text = str(position)
		(item.get_node("Color") as ColorRect).color = Color.from_hsv(
			fmod(position * 0.06, 1.0), 0.45, 0.62)


func _ready() -> void:
	_adapter = CellAdapter.new()
	_layout = GridLayoutManager.new()
	recycler_view.set_item_extent(60)
	recycler_view.set_adapter(_adapter)
	recycler_view.set_layout(_layout)
	# 响应式接线：宽度一变就重算列数并重排。
	recycler_view.resized.connect(_update_span_count)
	_update_span_count()


func _update_span_count() -> void:
	var width := int(recycler_view.size.x)
	var cols := maxi(1, width / TARGET_ITEM_WIDTH)
	if cols != _layout.get_span_count():
		_layout.set_span_count(cols)
		# set_span_count 只把行模型标记为脏；要本帧看到重排，需要主动请求
		# 一次布局（resized 通知里的那次布局用的是旧列数）。
		recycler_view.request_layout()
	_update_info(width, cols)


func _update_info(width: int, cols: int) -> void:
	info_label.text = "拖动窗口边缘改变宽度 —— 视口 %d px，每行 %d 个（目标 item 宽度 %d px，实际 %d px）｜ 共 %d 项" % [
		width, cols, TARGET_ITEM_WIDTH, width / cols, _adapter.count,
	]
