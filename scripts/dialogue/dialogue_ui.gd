extends CanvasLayer

const res_path = "res://assets/"
const dialogue_box_path = "res://assets/dialogue_box.png"

@onready var dialogue_engine: DialogueSystem

@export var speaker_label: Label
@export var text_label: RichTextLabel
@export var modal_shield: ColorRect
@export var _dialogue_box: TextureRect
@export var character_icon: TextureRect
@export var typing_speed: float = 0.03
var _is_typing: bool = false

func _ready() -> void:
	hide()
	dialogue_engine_setup()
	dialogue_ui_setup()

func dialogue_engine_setup():
	dialogue_engine = DialogueSystem.new()
	dialogue_engine.dialogue_started.connect(show)
	dialogue_engine.dialogue_line_displayed.connect(_on_line_received)
	dialogue_engine.dialogue_finished.connect(_hide)

func dialogue_ui_setup():
	# Connect the label's input signal directly via code
	text_label.gui_input.connect(_on_text_label_gui_input)
	text_label.fit_content = true
	text_label.custom_minimum_size = Vector2(800, 200)

func _on_line_received(speaker: String, text: String) -> void:
	_show()
	_dialogue_box.texture = load(dialogue_box_path)
	speaker_label.text = speaker
	text_label.text = text
	_update_icon()
	_type_out_text()

func _update_icon():
	if character_icon:
		character_icon.texture = null # Or set a placeholder image
	var texture_path = "res://assets/icons/%s.png" % speaker_label.text
	
	# 3. Safe Guard: Check if the image file actually exists before loading it
	if ResourceLoader.exists(texture_path):
		var new_texture = load(texture_path)
		character_icon.texture = new_texture

func _hide():
	modal_shield.hide()
	text_label.hide()
	speaker_label.hide()
	_dialogue_box.hide()
	if character_icon:
		character_icon.texture = null
	hide()

func _show():
	modal_shield.show()
	text_label.show()
	speaker_label.show()
	if _dialogue_box:
		_dialogue_box.show()
	show()

func _type_out_text() -> void:
	_is_typing = true
	text_label.visible_characters = 0
	while text_label.visible_characters < text_label.get_total_character_count():
		if not _is_typing: 
			break
		text_label.visible_characters += 1
	text_label.visible_characters = -1
	_is_typing = false

# --- THE CLICK DETECTOR ---
func _on_text_label_gui_input(event: InputEvent) -> void:
	# Check if the input event is a mouse click
	if event is InputEventMouseButton:
		# Target the left mouse button specifically, and only trigger when pressed down
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			handle_advance_request()

# --- THE KEYBOARD DETECTOR ---
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		handle_advance_request()

# --- UNIFIED ADVANCE LOGIC ---
func handle_advance_request() -> void:
	if _is_typing:
		# If it's typing out, skip the animation and show the whole line instantly
		_is_typing = false
	else:
		# If the line is already fully displayed, tell the engine to go to the next line
		dialogue_engine.advance_dialogue()

func start_dialogue(sequence):
	dialogue_engine.start_dialogue(sequence)
