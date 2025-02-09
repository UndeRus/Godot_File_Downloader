#------------------------------------------------------------------------------
#-- Copyright (c) 2021 Lyaaaaaaaaaaaaaaa
#--
#-- Author : Lyaaaaaaaaaaaaaaa
#--
#-- Implementation Notes:
#--  - You can use this class as a node by directly using it in a scene or in a
#--      script by instancing the class.
#--
#-- Anticipated changes:
#--
#--  - Get rid of the _process function and let the user manually call get_stats
#--      (which would call _update_stats) on purpose instead of spaming the 
#--      stats_updated signal.
#--  - Delete the blind mode (seriously it's useless)
#--
#-- Changelog:
#--  - 15/09/2021 Lyaaaaa
#--    - Created the file.
#--
#--  - 23/09/2021 Lyaaaaa
#--    - Implemented the file.
#--
#--  - 30/09/2021 Lyaaaaa
#--    - file_urls is now of PoolStringArray type.
#--
#--  - 04/10/2021 Lyaaaaa
#--    - Updated _calculate_percentage to control if it successfully opened the
#--        file before calling .get_len on it. 
#--    - _downloaded_percent is now a float to avoid warning because I converted
#--        float to int.
#--    - **It is no longer a class** as it was making duplication with the plugin.gd
#--        which declared this script as a subtype of HTTPRequest named FileDownloader.
#--        This way seems to be more 'plugin' like.
#--
#--  - 08/10/2021 Lyaaaaa
#--    - Removed the _on_file_downloaded handler as it was pretty useless
#--        and creating errors. Its code is now inside _download_next_file.
#--    - Removed the connect statement from _init which was connecting to
#--        _on_file_downloaded.
#--    - The "downloads_started" signal is now emited inside _send_get_request
#--        if there is no error.
#--    - _download_next_file is now called inside _on_request_completed if the
#--        request was a GET one.
#--
#--  - 11/10/2021 Lyaaaaa
#--    - Changed the default value of save_path to user://cache/
#--
#--  - 10/11/2021 Lyaaaaa
#--    - Added blind_mode var.
#--    - Updated _update_stats and _on_request_completed to control change their
#--        behavior depending of blind_mode.
#--    - Updated start_download to allow setting up the blind_mode from parameter.
#--
#--  - 23/12/2021 Lyaaaaa
#--    - Fixed the 2go limitation by declaring _file_size as a float.
#--    - Updated _calculate_percentage to remove a now useless conversion to float.
#--    - Updated _on_request_completed to replace the weird if and size.right by
#--        size.replace. _file_size = size.to_int() becomes _file_size = size.to_float().
#--
#--  - 25/12/2021 Lyaaaaa
#--    - Added _downloads_done function.
#--    - Updated _on_file_downloaded and _download_next_file to call _downloads_done.
#--    - The last downloaded file is now closed.
#--
#--  - 18/04/2022 Lyaaaaa
#--    - Added a _reset method to re-use the downloader after it had been used.
#--    - Updated _downloads_done to call _reset.
#------------------------------------------------------------------------------
extends HTTPRequest

signal downloads_started
signal file_downloaded
signal downloads_finished
signal stats_updated

@export var blind_mode: bool   = false
@export var save_path: String = "user://cache/"
@export var file_urls: PackedStringArray

var _current_url       : String
var _current_url_index : int = 0

var _file : FileAccess
var _file_name : String
var _file_size : float

var _headers   : Array = []

var _downloaded_percent : float = 0
var _downloaded_size    : float = 0

var _last_method : int
var _ssl         : bool = false


func _init() -> void:
	set_process(false)
	connect("request_completed", Callable(self, "_on_request_completed"))


func _ready() -> void:
	set_process(false)


func _process(_delta) -> void:
	_update_stats()


func start_download(p_urls       : PackedStringArray = [],
					p_save_path  : String          = "",
					p_blind_mode : bool            = false) -> void:
	_create_directory()
	if p_urls.is_empty() == false:
		file_urls = p_urls
	
	if p_save_path != "":
		save_path = p_save_path
	
	blind_mode = p_blind_mode
	
	_download_next_file()


func get_stats() -> Dictionary:
	var dictionnary : Dictionary
	dictionnary = {"downloaded_size"    : _downloaded_size,
				   "downloaded_percent" : _downloaded_percent,
				   "file_name"          : _file_name,
				   "file_size"          : _file_size}
	return dictionnary
	

func _reset() -> void:
	_current_url = ""
	_current_url_index = 0
	_downloaded_percent = 0
	_downloaded_size = 0


func _downloads_done() -> void:
	set_process(false)
	_update_stats()
	_file.close()
	emit_signal("downloads_finished")
	_reset()
	

func _send_head_request() -> void:
	# The HEAD method only gets the head and not the body. Therefore, doesn't
	#   download the file.
	request(_current_url, _headers, HTTPClient.METHOD_HEAD)
	_last_method = HTTPClient.METHOD_HEAD
	
	
func _send_get_request() -> void:
	var error = request(_current_url, _headers, HTTPClient.METHOD_GET)
	if error == OK:
		emit_signal("downloads_started")
		_last_method = HTTPClient.METHOD_GET
		set_process(true)
	
	elif error == ERR_INVALID_PARAMETER:
		print("Given string isn't a valid url ")
	elif error == ERR_CANT_CONNECT:
		print("Can't connect to host")
	

func _update_stats() -> void:
	if blind_mode == false:
		_calculate_percentage()
		emit_signal("stats_updated",
					_downloaded_size,
					_downloaded_percent,
					_file_name,
					_file_size)


func _calculate_percentage() -> void:
	var error : int
	_file = FileAccess.open(save_path + _file_name, FileAccess.READ)

	if _file != null:
		_downloaded_size    = _file.get_length()
		_downloaded_percent = (_downloaded_size / _file_size) *100


func _create_directory() -> void:
	var directory = DirAccess.open("user://")
	
	if directory.dir_exists(save_path) == false:
		directory.make_dir(save_path)

	directory.change_dir(save_path)


func _download_next_file() -> void:
	if _current_url_index < file_urls.size():
		_current_url  = file_urls[_current_url_index]
		_file_name    = _current_url.get_file()
		download_file = save_path + _file_name
		_send_head_request()
		_current_url_index += 1  
	else:
		_downloads_done()


func _extract_regex_from_header(p_regex  : String,
								p_header : String) -> String:
	var regex = RegEx.new()
	regex.compile(p_regex)
	
	var result = regex.search(p_header)
	return result.get_string()


func _on_request_completed(p_result,
						   _p_response_code,
						   p_headers,
						   _p_body) -> void:
	if p_result == RESULT_SUCCESS:
		if _last_method == HTTPClient.METHOD_HEAD and blind_mode == false:
			var regex = "(?i)content-length: [0-9]*"
			var size  = _extract_regex_from_header(regex, ' '.join(p_headers))
			size = size.replace("Content-Length: ", "")
			_file_size = size.to_float()
			_send_get_request()
			
		elif _last_method == HTTPClient.METHOD_HEAD and blind_mode == true:
			_send_get_request()
			
		elif _last_method == HTTPClient.METHOD_GET:
			emit_signal("file_downloaded")
			_download_next_file()
	else:
		print("HTTP Request error: ", p_result)


func _on_file_downloaded() -> void:
	_current_url_index += 1
	
	if _current_url_index < file_urls.size():
		_download_next_file()
	
	else:
		_downloads_done()
