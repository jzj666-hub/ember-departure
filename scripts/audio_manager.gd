class_name AudioManager
extends Node
## Central audio dispatcher for game voiceovers and UI SFX.

const DEFAULT_BGM_PATH := "res://assets/voice/background/song_of_the_sea.ogg"

static var _player_pool: Array[AudioStreamPlayer] = []
static var _root_node: Node = null
static var _bgm_player: AudioStreamPlayer = null


static func init_pool(root: Node, pool_size: int = 6) -> void:
	_root_node = root
	_player_pool.clear()
	for i in range(pool_size):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		root.add_child(p)
		_player_pool.append(p)

	if _bgm_player == null or not is_instance_valid(_bgm_player):
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.name = "BGMPlayer"
		_bgm_player.bus = "Master"

	if _bgm_player.get_parent() != null and _bgm_player.get_parent() != root:
		_bgm_player.get_parent().remove_child(_bgm_player)
	if _bgm_player.get_parent() == null:
		root.add_child(_bgm_player)


static func play_bgm(file_path: String = DEFAULT_BGM_PATH, volume_db: float = -6.0, loop: bool = true) -> void:
	if not ResourceLoader.exists(file_path):
		return
	var stream := load(file_path) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop

	if _bgm_player == null or not is_instance_valid(_bgm_player):
		_bgm_player = AudioStreamPlayer.new()
		_bgm_player.name = "BGMPlayer"
		_bgm_player.bus = "Master"

	if _bgm_player.get_parent() == null and _root_node != null and is_instance_valid(_root_node):
		_root_node.add_child(_bgm_player)

	if _bgm_player.playing and _bgm_player.stream == stream:
		return

	_bgm_player.stream = stream
	_bgm_player.volume_db = volume_db
	if _bgm_player.is_inside_tree():
		_bgm_player.play()


static func stop_bgm() -> void:
	if _bgm_player != null and is_instance_valid(_bgm_player):
		_bgm_player.stop()


static func set_bgm_volume(volume_db: float) -> void:
	if _bgm_player != null and is_instance_valid(_bgm_player):
		_bgm_player.volume_db = volume_db


static func play_sound(stream: AudioStream, volume_db: float = 0.0) -> void:
	if stream == null or _player_pool.is_empty():
		return
	for p in _player_pool:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return
	# All busy, preempt first
	var p0 := _player_pool[0]
	p0.stop()
	p0.stream = stream
	p0.volume_db = volume_db
	p0.play()


static func play_voice_file(file_path: String, volume_db: float = 0.0) -> void:
	if not ResourceLoader.exists(file_path):
		return
	var stream := load(file_path) as AudioStream
	if stream != null:
		play_sound(stream, volume_db)


static func play_countdown(number: int, male: bool = true) -> void:
	if number < 1 or number > 10:
		return
	var gender := "Male" if male else "Female"
	var path := "res://assets/voice/Voiceover Pack/%s/%d.ogg" % [gender, number]
	play_voice_file(path, 1.0)


static func play_go(male: bool = true) -> void:
	var gender := "Male" if male else "Female"
	var path := "res://assets/voice/Voiceover Pack/%s/go.ogg" % gender
	play_voice_file(path, 2.0)


static func play_game_over(male: bool = true) -> void:
	var gender := "Male" if male else "Female"
	var path := "res://assets/voice/Voiceover Pack/%s/game_over.ogg" % gender
	play_voice_file(path, 2.0)


static func play_lose(male: bool = true) -> void:
	var gender := "Male" if male else "Female"
	var path := "res://assets/voice/Voiceover Pack/%s/you_lose.ogg" % gender
	play_voice_file(path, 2.0)


static func play_win(male: bool = true) -> void:
	var gender := "Male" if male else "Female"
	var path := "res://assets/voice/Voiceover Pack/%s/you_win.ogg" % gender
	play_voice_file(path, 2.0)
