extends RefCounted
## The host owns persistence, the remap modal, and returning to its previous menu.
## No pointer capture, fullscreen, InputMap changes, or raw-input capture here.

const ACTIONS := ["interact", "torch", "knock", "hud", "pause", "back"]
const ACTION_NAMES := {
	"interact": "Действие", "torch": "Фонарь", "knock": "Постучать",
	"hud": "Памятка (удерживать)", "pause": "Пауза", "back": "Назад",
}

static func build(pad: Node, on_back: Callable, on_save: Callable, on_remap: Callable) -> Control:
	var model = pad.get("model")
	var haptics = pad.get("haptics")
	var scroll := ScrollContainer.new()
	scroll.name = "PadSettings"
	# Shrink flags keep the viewport bounded even in an expanding parent VBox.
	scroll.custom_minimum_size = Vector2(636, 300)
	scroll.size = Vector2(636, 300)
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.focus_mode = Control.FOCUS_NONE
	scroll.process_mode = Node.PROCESS_MODE_ALWAYS
	scroll.get_v_scroll_bar().focus_mode = Control.FOCUS_NONE

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 10)
	scroll.add_child(margin)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	margin.add_child(body)
	var focusables: Array[Control] = []
	var focus_rows: Array[Control] = []
	var sliders: Dictionary = {}
	var remap_buttons: Dictionary = {}
	_add_note(body, "Геймпад: левый стик / крестовина выбирают строку; ← / → меняют значение. LB / RB переходят между пунктами.")

	for spec in [
		["move_deadzone", "Мёртвая зона ходьбы", 0.05, 0.40, 0.01, "%.2f"],
		["look_deadzone", "Мёртвая зона обзора", 0.05, 0.40, 0.01, "%.2f"],
		["look_speed", "Чувствительность обзора", 0.5, 5.0, 0.1, "%.1f"],
	]:
		var property: String = spec[0]
		var changed := func(value: float) -> void:
			model.set(property, value)
			_save(on_save)
		sliders[property] = _slider(body, focusables, focus_rows, spec[1], spec[2], spec[3], spec[4], float(model.get(property)), spec[5], changed)

	var invert := _checkbox(body, focusables, focus_rows, "Инвертировать обзор по вертикали", bool(model.invert_y))
	invert.name = "InvertY"
	invert.toggled.connect(func(value: bool) -> void:
		model.invert_y = value
		_save(on_save)
	)
	var vibration := _checkbox(body, focusables, focus_rows, "Вибрация", bool(haptics.enabled))
	vibration.name = "Vibration"
	var intensity := _slider(body, focusables, focus_rows, "Сила вибрации", 0.0, 100.0, 5.0, float(haptics.intensity) * 100.0, "%.0f%%", func(value: float) -> void:
		haptics.stop_all()
		haptics.configure(bool(haptics.enabled), value / 100.0)
		_save(on_save)
	)
	intensity.name = "VibrationIntensity"
	var status := _add_note(body, "")
	status.name = "VibrationStatus"
	var refresh_status := func() -> void:
		if is_instance_valid(pad):
			status.text = _haptics_status(pad)
	vibration.toggled.connect(func(value: bool) -> void:
		haptics.stop_all()
		haptics.configure(value, float(haptics.intensity))
		refresh_status.call()
		_save(on_save)
	)
	intensity.value_changed.connect(func(_value: float) -> void: refresh_status.call())
	var test := _button(body, focusables, focus_rows, "Проверить вибрацию")
	test.name = "TestVibration"
	test.pressed.connect(func() -> void:
		haptics.pulse(int(model.active_device), "test")
		refresh_status.call()
	)
	# The browser promise completes later. Poll only this visible screen, never
	# infer actual motor movement from an API completion or a connected pad.
	var timer := Timer.new()
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if scroll.is_visible_in_tree():
			refresh_status.call()
			_refresh_bindings(model, remap_buttons)
	)
	scroll.add_child(timer)
	refresh_status.call()

	_add_note(body, "Назначения ниже действуют в игре. В меню схема постоянна: A / Cross — выбрать, B / Circle — назад, Start / Options — пауза или возврат.")
	for action in ACTIONS:
		var button := _button(body, focusables, focus_rows, "")
		button.name = "Remap_" + action
		remap_buttons[action] = button
		button.pressed.connect(func() -> void:
			if on_remap.is_valid():
				on_remap.call(action)
		)
	_refresh_bindings(model, remap_buttons)

	var reset := _button(body, focusables, focus_rows, "Сбросить настройки геймпада")
	reset.name = "ResetPadSettings"
	reset.pressed.connect(func() -> void:
		var active_device: int = model.active_device
		model.set_profile("caretaker")
		model.move_axes = Vector2i(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
		model.look_axes = Vector2i(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
		model.move_deadzone = 0.20
		model.look_deadzone = 0.16
		model.look_exponent = 1.5
		model.look_speed = 2.4
		model.trigger_threshold = 0.55
		model.invert_y = false
		model.set_device(active_device)
		haptics.stop_all()
		haptics.configure(true, 0.55)
		for property in sliders:
			_sync_slider(sliders[property], float(model.get(property)))
		_sync_slider(intensity, 55.0)
		invert.set_pressed_no_signal(false)
		vibration.set_pressed_no_signal(true)
		_refresh_bindings(model, remap_buttons)
		refresh_status.call()
		_save(on_save)
	)
	var back := _button(body, focusables, focus_rows, "Назад")
	back.name = "BackFromPadSettings"
	back.pressed.connect(func() -> void:
		haptics.stop_all()
		if on_back.is_valid():
			on_back.call()
	)
	_wire_focus(scroll, focusables, focus_rows)
	return scroll


static func _add_note(body: VBoxContainer, message: String) -> Label:
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 16)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(label)
	return label


static func _slider(body: VBoxContainer, focusables: Array[Control], rows: Array[Control], title: String, minimum: float, maximum: float, increment: float, initial: float, format: String, changed: Callable) -> HSlider:
	# Caption, value, and slider share a row. Focusing upward from the bottom
	# cannot scroll away the caption as it would with a separate preceding label.
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 48
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	var caption := Label.new()
	caption.text = title
	caption.custom_minimum_size.x = 224
	caption.add_theme_font_size_override("font_size", 16)
	row.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = increment
	slider.value = initial
	slider.custom_minimum_size = Vector2(160, 44)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.tooltip_text = title
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 56
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 16)
	row.add_child(value_label)
	slider.set_meta("value_label", value_label)
	slider.set_meta("value_format", format)
	_sync_slider(slider, initial)
	slider.value_changed.connect(func(value: float) -> void:
		value_label.text = format % value
		changed.call(value)
	)
	focusables.append(slider)
	rows.append(row)
	return slider


static func _sync_slider(slider: HSlider, value: float) -> void:
	slider.set_value_no_signal(value)
	var label: Label = slider.get_meta("value_label")
	label.text = str(slider.get_meta("value_format")) % slider.value


static func _checkbox(body: VBoxContainer, focusables: Array[Control], rows: Array[Control], title: String, initial: bool) -> CheckBox:
	var check := CheckBox.new()
	check.text = title
	check.button_pressed = initial
	check.custom_minimum_size.y = 44
	check.add_theme_font_size_override("font_size", 17)
	body.add_child(check)
	focusables.append(check)
	rows.append(check)
	return check


static func _button(body: VBoxContainer, focusables: Array[Control], rows: Array[Control], title: String) -> Button:
	var button := Button.new()
	button.text = title
	button.clip_text = true
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 17)
	body.add_child(button)
	focusables.append(button)
	rows.append(button)
	return button


static func _wire_focus(scroll: ScrollContainer, controls: Array[Control], rows: Array[Control]) -> void:
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	outline.border_color = Color(0.98, 0.83, 0.47)
	outline.set_border_width_all(2)
	outline.set_corner_radius_all(4)
	for index in controls.size():
		var control := controls[index]
		var previous := controls[posmod(index - 1, controls.size())]
		var next := controls[(index + 1) % controls.size()]
		var row := rows[index]
		control.focus_mode = Control.FOCUS_ALL
		control.add_theme_stylebox_override("focus", outline)
		control.focus_neighbor_top = control.get_path_to(previous)
		control.focus_neighbor_bottom = control.get_path_to(next)
		control.focus_previous = control.get_path_to(previous)
		control.focus_next = control.get_path_to(next)
		control.focus_neighbor_left = NodePath(".")
		control.focus_neighbor_right = NodePath(".")
		control.focus_entered.connect(func() -> void:
			# Container sorting/follow_focus can run after focus_entered. Defer
			# the whole-row request so neither direction hides its caption.
			scroll.call_deferred("ensure_control_visible", row)
		)
	# The host may override initial focus. Wait until the detached UI has been
	# mounted; do not steal focus when it is constructed as a hidden screen.
	scroll.ready.connect(func() -> void:
		if scroll.is_visible_in_tree():
			controls[0].call_deferred("grab_focus")
	)


static func _refresh_bindings(model: RefCounted, buttons: Dictionary) -> void:
	for action in buttons:
		var button: Button = buttons[action]
		button.text = "%s: %s" % [ACTION_NAMES[action], model.call("binding_label", action)]
		button.tooltip_text = button.text


static func _haptics_status(pad: Node) -> String:
	var model = pad.get("model")
	var haptics = pad.get("haptics")
	if not haptics.enabled:
		return "Вибрация выключена. Управление геймпадом работает без неё."
	if float(haptics.intensity) <= 0.0:
		return "Сила вибрации 0%: эффекты выключены."
	if int(model.active_device) < 0:
		return "Контроллер не обнаружен. Подключите его и нажмите кнопку."
	var capability: Dictionary = haptics.status(int(model.active_device))
	var reason := str(capability.get("reason", "unknown"))
	if reason == "no-controller":
		return "Контроллер не обнаружен. Подключите его и нажмите кнопку."
	if not bool(capability.get("available", false)):
		var detail := "Вибрация недоступна в этом браузере или подключении."
		if reason == "web-bridge-unavailable":
			detail = "WEB-интерфейс вибрации недоступен в этой сборке."
		elif reason in ["permissions-policy-blocked", "insecure-context"]:
			detail = "Браузер ограничил доступ к вибрации."
		elif reason == "haptics-rejected":
			detail = "Браузер отклонил запрос вибрации."
		return detail + " Управление геймпадом остаётся доступным."
	var result := str(capability.get("lastResult", "not-tested"))
	if result.begins_with("rejected:"):
		return "Браузер отклонил запрос вибрации. Отклик контроллера не подтверждён."
	match result:
		"api-complete":
			return "Браузер принял запрос. Это не подтверждает работу моторов: проверьте отклик на контроллере."
		"requested":
			return "Запрос вибрации отправлен. Проверьте ощущение на контроллере."
		"preempted", "not-completed", "unknown-result":
			return "Запрос не подтверждён или прерван. Ощущение вибрации не проверено."
		_:
			return "Браузер поддерживает запрос вибрации. Нажмите «Проверить» и проверьте отклик."


static func _save(callback: Callable) -> void:
	if callback.is_valid():
		callback.call()
