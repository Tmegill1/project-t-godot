extends SceneTree

func _initialize() -> void:
	var files := _discover("res://test")
	var checks := 0
	var failing_assertions := 0
	var failing_tests := 0

	for path in files:
		var script: GDScript = load(path)
		for method in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			var case: TestCase = script.new()
			case.call(test_name)
			checks += case.check_count()
			var fails := case.failures()
			if not fails.is_empty():
				failing_tests += 1
				failing_assertions += fails.size()
				printerr("FAIL %s::%s" % [path.get_file(), test_name])
				for f in fails:
					printerr("    " + f)

	print("%d checks across %d files | %d failing assertions in %d tests" % [
		checks, files.size(), failing_assertions, failing_tests])
	quit(1 if failing_assertions > 0 else 0)

func _discover(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_discover(full))
		elif entry.begins_with("test_") and entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found
