extends CanvasLayer

@onready var speaker_label: Label = $Background/SpeakerLabel
@onready var text_label: RichTextLabel = $Background/DialogueText
@onready var dialogue_engine: DialogueSystem = $DialogueEngine

@export var typing_speed: float = 0.03
var _is_typing: bool = false

func _ready() -> void:
	hide()
	dialogue_engine.dialogue_started.connect(show)
	dialogue_engine.dialogue_line_displayed.connect(_on_line_received)
	dialogue_engine.dialogue_finished.connect(_hide)
	
	# Connect the label's input signal directly via code
	text_label.gui_input.connect(_on_text_label_gui_input)

func _on_line_received(speaker: String, text: String) -> void:
	speaker_label.text = speaker
	text_label.text = text
	_type_out_text()

func _hide():
	text_label.hide()
	speaker_label.hide()
	hide()

func _type_out_text() -> void:
	_is_typing = true
	text_label.visible_characters = 0
	while text_label.visible_characters < text_label.get_total_character_count():
		if not _is_typing: 
			break
		text_label.visible_characters += 1
		await get_tree().create_timer(typing_speed).timeout
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
