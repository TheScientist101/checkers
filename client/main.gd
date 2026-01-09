extends Control

var url := "known-leela-checkers-46031859.koyeb.app"

var access_token : String
var uuid : String

var default_size := Vector2(1152,648)

@onready var sign_up = $LoginThings/CenterContainer/SignUp
@onready var sign_up_HTTP := $LoginThings/CenterContainer/SignUp/SignUpHTTPRequest
@onready var sign_up_first_name := $LoginThings/CenterContainer/SignUp/VBoxContainer/FirstNameEdit
@onready var sign_up_last_name := $LoginThings/CenterContainer/SignUp/VBoxContainer/LastNameEdit
@onready var sign_up_email := $LoginThings/CenterContainer/SignUp/VBoxContainer/EmailEdit
@onready var sign_up_password := $LoginThings/CenterContainer/SignUp/VBoxContainer/PasswordEdit
@onready var sign_up_confirm_password := $LoginThings/CenterContainer/SignUp/VBoxContainer/ConfirmPasswordEdit
@onready var sign_up_button := $LoginThings/CenterContainer/SignUp/VBoxContainer/SignUpButton
@onready var sign_up_back_button := $LoginThings/CenterContainer/SignUp/VBoxContainer/BackButton
@onready var sign_up_feedback := $LoginThings/CenterContainer/SignUp/VBoxContainer/FeedbackLabel

@onready var log_in = $LoginThings/CenterContainer/LogIn
@onready var log_in_HTTP := $LoginThings/CenterContainer/LogIn/LogInHTTPRequest
@onready var log_in_email := $LoginThings/CenterContainer/LogIn/VBoxContainer/EmailEdit
@onready var log_in_password := $LoginThings/CenterContainer/LogIn/VBoxContainer/PasswordEdit
@onready var log_in_button := $LoginThings/CenterContainer/LogIn/VBoxContainer/LogInButton
@onready var log_in_sign_up_button := $LoginThings/CenterContainer/LogIn/VBoxContainer/SignUpInsteadButton
@onready var log_in_feedback := $LoginThings/CenterContainer/LogIn/VBoxContainer/FeedbackLabel

func _ready():
	sign_up_HTTP.request_completed.connect(_on_sign_up_request_completed)
	log_in_HTTP.request_completed.connect(_on_log_in_request_completed)

func _process(_delta: float) -> void:
	var window_size := Vector2(DisplayServer.window_get_size())
	var new_ratio = max(min(window_size.x/default_size.x, window_size.y/default_size.y), 1)
	scale.x = new_ratio
	scale.y = new_ratio
	position.x = -size.x * ((scale.x/2)-0.5)
	position.y = -size.y * ((scale.y/2)-0.5)

func _on_sign_up_button_pressed() -> void:
	sign_up_feedback.text = ""
	
	if sign_up_password.text == sign_up_confirm_password.text:
		disable_buttons(true)
		
		var dict = {
			"first_name" = sign_up_first_name.text,
			"last_name" = sign_up_last_name.text,
			"password" = sign_up_password.text,
			"email" = sign_up_email.text
		}
		var json := JSON.stringify(dict)
		sign_up_HTTP.request("https://" + url + "/register", PackedStringArray(), HTTPClient.METHOD_POST, json)
	else:
		sign_up_feedback.text = "Password does not match confirm password"

func _on_log_in_button_pressed() -> void:
	log_in_feedback.text = ""
	
	disable_buttons(true)
	
	var dict = {
		"password" = log_in_password.text,
		"email" = log_in_email.text
	}
	var json := JSON.stringify(dict)
	log_in_HTTP.request("https://" + url + "/login", PackedStringArray(), HTTPClient.METHOD_POST, json)

func _on_log_in_request_completed(_result, _response_code, _headers, body) -> void:
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if json == null:
		log_in_feedback.text = "Connection error"
		disable_buttons(false)
	
	else:
		if json["success"]:
			access_token = json["access_token"]
			uuid = json["uuid"]
			start_game()
		else:
			log_in_feedback.text = json["error"]["message"]
			disable_buttons(false)
	
func _on_sign_up_request_completed(_result, _response_code, _headers, body) -> void:
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if json == null:
		sign_up_feedback.text = "Connection error"
		disable_buttons(false)
	else:
		if json["success"]:
			sign_up_feedback.text = "Check your email for verification, then log in"
		else:
			sign_up_feedback.text = json["error"]["message"]
			
		disable_buttons(false)

func disable_buttons(state: bool) -> void:
	sign_up_button.disabled = state
	sign_up_back_button.disabled = state
	log_in_button.disabled = state
	log_in_sign_up_button.disabled = state

func _on_sign_up_instead_button_pressed() -> void:
	log_in.visible = false
	sign_up.visible = true

func _on_back_button_pressed() -> void:
	log_in.visible = true
	sign_up.visible = false

func start_game() -> void:
	$LoginThings.visible = false
	$CenterContainer2/GameThings/SubViewportContainer/SubViewport/Game.start(access_token, log_in_email.text, url, uuid)
