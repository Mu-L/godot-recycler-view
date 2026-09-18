# Guards doc_classes/*.xml against the classes the extension actually registers.
#
# The XML is hand-written and the build only consumes it one way (XML → compiled
# blob), so nothing has ever checked that it still describes the code. A renamed
# method, a property whose accessors changed, a deleted constant or a [method …]
# that points nowhere all shipped silently. This test makes drift fail CI.
#
# It checks that every documented name resolves and that every documented
# property default matches the value the class actually starts with — the two
# things a machine can settle. Prose still needs a human: this cannot tell that
# a sentence describes behaviour the port never implemented.

extends GdUnitTestSuite

# Per-class method-name sets, filled on demand by _has_method().
var _method_names: Dictionary = {}


func _doc_dir() -> String:
	# doc_classes/ sits beside the Godot project, not inside it, so res:// cannot
	# reach it. Resolve it from the project directory instead.
	return ProjectSettings.globalize_path("res://").path_join("..").path_join("doc_classes").simplify_path()


func _doc_files() -> PackedStringArray:
	var files := PackedStringArray()
	var dir := DirAccess.open(_doc_dir())
	if dir == null:
		return files
	for f in dir.get_files():
		if f.ends_with(".xml"):
			files.append(f)
	return files


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _all_matches(text: String, pattern: String) -> Array:
	var re := RegEx.new()
	re.compile(pattern)
	var out: Array = []
	for m in re.search_all(text):
		out.append(m)
	return out


# Reads one attribute out of a single XML tag. Anchored on a leading space so
# `name` cannot match inside another attribute's value.
func _attr(tag: String, key: String) -> String:
	var hits := _all_matches(tag, ' %s="([^"]*)"' % key)
	return hits[0].get_string(1) if not hits.is_empty() else ""


func _has_property(cls: String, prop: String) -> bool:
	for entry in ClassDB.class_get_property_list(cls, false):
		if entry.get("name", "") == prop:
			return true
	return false


# ClassDB.class_has_method() does not report GDVIRTUAL methods, and most of this
# library's script-facing surface is virtuals (_bind_item, _on_scrolled, …), so
# it would flag every one of them as missing. class_get_method_list() does
# include them (flagged METHOD_FLAG_VIRTUAL), and with no_inheritance = false it
# also resolves unqualified references to a base class's method.
func _has_method(cls: String, name: String) -> bool:
	if not _method_names.has(cls):
		var names := {}
		for entry in ClassDB.class_get_method_list(cls, false):
			names[entry.name] = true
		_method_names[cls] = names
	return _method_names[cls].has(name)


# The XML stores a default as text; render the engine's value the same way.
func _default_as_text(value: Variant) -> String:
	match typeof(value):
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			return String.num(value)
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value)
		_:
			return str(value)


func test_doc_classes_describe_registered_classes() -> void:
	var files := _doc_files()
	assert_that(files.size()).override_failure_message(
		"找不到 doc_classes: %s" % _doc_dir()
	).is_greater(0)

	var problems: Array[String] = []

	for file in files:
		var path := _doc_dir().path_join(file)
		var text := _read(path)

		# The class itself. The <class> tag carries xmlns/inherits before name,
		# so read the attribute rather than pattern-matching the tag's shape.
		var class_hits := _all_matches(text, "<class [^>]*>")
		if class_hits.is_empty():
			problems.append("%s: 没有 <class ...>" % file)
			continue
		var cls := _attr(class_hits[0].get_string(0), "name")
		if cls.is_empty():
			problems.append("%s: <class> 没有 name 属性" % file)
			continue
		if not ClassDB.class_exists(cls):
			problems.append("%s: 类 %s 未注册" % [file, cls])
			continue

		# Methods, including the virtuals bound via GDVIRTUAL_BIND.
		for m in _all_matches(text, '<method name="([^"]+)"'):
			var name: String = m.get_string(1)
			if not _has_method(cls, name):
				problems.append("%s: [method %s.%s] 不存在" % [file, cls, name])

		# Properties: their accessors must exist, and — the check that catches
		# the drift a names-only pass misses — the documented default has to
		# match the value the class actually starts with.
		for m in _all_matches(text, "<member [^>]*>"):
			var tag: String = m.get_string(0)
			var prop := _attr(tag, "name")
			var setter := _attr(tag, "setter")
			var getter := _attr(tag, "getter")
			var declared := _attr(tag, "default")
			if prop.is_empty():
				continue
			if not _has_property(cls, prop):
				problems.append("%s: [member %s.%s] 不是该类的属性" % [file, cls, prop])
				continue
			if not setter.is_empty() and not _has_method(cls, setter):
				problems.append("%s: 属性 %s 的 setter %s 不存在" % [file, prop, setter])
			if not getter.is_empty() and not _has_method(cls, getter):
				problems.append("%s: 属性 %s 的 getter %s 不存在" % [file, prop, getter])
			if declared.is_empty():
				continue
			var actual := _default_as_text(ClassDB.class_get_property_default_value(cls, prop))
			if actual != declared:
				problems.append("%s: 属性 %s 的默认值文档写的是 %s,实际是 %s"
					% [file, prop, declared, actual])

		for m in _all_matches(text, '<constant name="([^"]+)"'):
			var name: String = m.get_string(1)
			if not ClassDB.class_has_integer_constant(cls, name):
				problems.append("%s: [constant %s.%s] 不存在" % [file, cls, name])

		for m in _all_matches(text, '<signal name="([^"]+)"'):
			var name: String = m.get_string(1)
			if not ClassDB.class_has_signal(cls, name):
				problems.append("%s: [signal %s.%s] 不存在" % [file, cls, name])

		# Cross-references inside `<description>` prose. These are what the
		# editor turns into links; a broken one renders as literal text and
		# nothing warns.
		for m in _all_matches(text, r'\[method ([A-Za-z_][A-Za-z0-9_]*)(?:\.([A-Za-z_][A-Za-z0-9_]*))?\]'):
			var owner: String = m.get_string(1)
			var member: String = m.get_string(2)
			if member.is_empty():
				# Unqualified: must resolve on this class or an ancestor.
				if not _has_method(cls, owner):
					problems.append("%s: [method %s] 在本类及其基类上都找不到" % [file, owner])
			elif not _has_method(owner, member):
				problems.append("%s: [method %s.%s] 不存在" % [file, owner, member])

		for m in _all_matches(text, r'\[member ([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\]'):
			var owner: String = m.get_string(1)
			var prop: String = m.get_string(2)
			if not _has_property(owner, prop):
				problems.append("%s: [member %s.%s] 不存在" % [file, owner, prop])

	if not problems.is_empty():
		print("doc_classes 与代码不一致(%d 处):" % problems.size())
		for p in problems:
			print("  - ", p)
	assert_that(problems).override_failure_message(
		"doc_classes 有 %d 处指向不存在的 API,详见上方输出" % problems.size()
	).is_empty()
