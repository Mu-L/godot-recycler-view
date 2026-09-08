extends VBoxContainer

@onready var rv: RecyclerView = %RecyclerView
@onready var send_button: Button = %SendButton

var _messages := []
var _adapter: ChatAdapter

class MsgDiff extends DiffUtilItemCallback:
	func _are_items_the_same(old_item: Variant, new_item: Variant) -> bool:
		var old: Msg = old_item
		var new: Msg = new_item
		return old._id == new._id
		
	func _are_contents_the_same(old_item: Variant, new_item: Variant) -> bool:
		var old: Msg = old_item
		var new: Msg = new_item
		return old._content == new._content

class Msg:
	static var _seq := 0
	
	var _id: int
	var _date: String
	var _content: String
	
	func _init(p_content: String) -> void:
		self._id = _seq; _seq += 1
		self._date = Time.get_time_string_from_system()
		self._content = p_content
		
	func display_content() -> String:
		return "%s[%d]: %s" % [_date, _id, _content]
		

class ChatAdapter extends ListAdapter:
	func _get_item_extent(_position: int) -> int:
		return 48
	
	func _create_item(_parent: Control, _view_type: int) -> ViewHolder:
		var vh := ViewHolder.new()
		var label := Label.new()
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vh.set_control(label)
		return vh
	
	func _bind_item(holder: ViewHolder, position: int) -> void:
		var msg: Msg = get_item(position)
		var label: Label = holder.get_control()
		label.text = msg.display_content()
		
		
func _ready() -> void:
	_adapter = ChatAdapter.new()
	_adapter.set_diff_callback(MsgDiff.new())
	var layout := LinearLayoutManager.new()
	layout.set_reverse_layout(true)
	rv.set_layout(layout)
	rv.set_adapter(_adapter)
	
	send_button.pressed.connect(_send)


func _send() -> void:
	_messages.push_front(Msg.new("新消息"))
	# submit_list 按引用持有传入的数组——之后不能再原地改动它,否则下一次
	# submit 时"旧列表"已被改掉,diff 拿不到真正的旧快照,更新会被静默丢弃
	# (与 Android ListAdapter 的契约一致)。_messages 是持续 push_front 的
	# 主数组,所以每次提交都传一份独立副本:
	_adapter.submit_list(_messages.duplicate())
	rv.smooth_scroll_to_position(0, 0.3)
		
