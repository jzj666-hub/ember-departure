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


static var _footstep_streams: Array[AudioStream] = []
static var _land_stream: AudioStream = null


static func create_footstep_sample(pitch_factor: float = 1.0, is_heavy: bool = false) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false

	var duration := 0.08 if not is_heavy else 0.13
	var sample_count := int(duration * 22050.0)
	var byte_array := PackedByteArray()
	byte_array.resize(sample_count * 2)

	var base_freq := (105.0 if not is_heavy else 70.0) * pitch_factor
	var decay := 50.0 if not is_heavy else 32.0

	for i in range(sample_count):
		var t := float(i) / 22050.0
		var env := exp(-decay * t)
		var body := sin(2.0 * PI * (base_freq - 25.0 * (t / duration)) * t) * 0.65
		var click := sin(2.0 * PI * (base_freq * 3.6) * t) * exp(-130.0 * t) * 0.35
		var noise := randf_range(-0.1, 0.1) * exp(-70.0 * t)
		var val := clampf((body + click + noise) * env, -1.0, 1.0)
		var val_int16 := int(round(val * 32767.0))
		byte_array.encode_s16(i * 2, val_int16)

	wav.data = byte_array
	return wav


static func _init_footstep_samples() -> void:
	if not _footstep_streams.is_empty():
		return

	for i in range(10):
		var p := "res://assets/voice/RPGsounds_Kenney/OGG/footstep%02d.ogg" % i
		if ResourceLoader.exists(p):
			var s := load(p) as AudioStream
			if s != null:
				_footstep_streams.append(s)

	if _footstep_streams.is_empty():
		_footstep_streams.append(create_footstep_sample(0.92))
		_footstep_streams.append(create_footstep_sample(1.00))
		_footstep_streams.append(create_footstep_sample(1.08))
		_footstep_streams.append(create_footstep_sample(1.16))

	var land_path := "res://assets/voice/RPGsounds_Kenney/OGG/cloth1.ogg"
	if ResourceLoader.exists(land_path):
		_land_stream = load(land_path) as AudioStream
	if _land_stream == null:
		_land_stream = create_footstep_sample(0.85, true)


static func play_footstep(volume_db: float = -12.0, pitch_scale: float = 1.0) -> void:
	_init_footstep_samples()
	if _footstep_streams.is_empty():
		return
	var stream := _footstep_streams[randi() % _footstep_streams.size()]
	play_sound(stream, volume_db, pitch_scale)


static func play_land_sound(volume_db: float = -6.0) -> void:
	_init_footstep_samples()
	if _land_stream != null:
		play_sound(_land_stream, volume_db, 0.9)


static func play_sound(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null or _player_pool.is_empty():
		return
	for p in _player_pool:
		if not is_instance_valid(p) or not p.is_inside_tree():
			continue
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch_scale
			p.play()
			return
	# All busy, preempt first valid
	for p in _player_pool:
		if is_instance_valid(p) and p.is_inside_tree():
			p.stop()
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch_scale
			p.play()
			return


static var _stream_cache: Dictionary = {}


static func preload_sound(path: String) -> void:
	if _stream_cache.has(path):
		return
	if ResourceLoader.exists(path):
		var s := load(path) as AudioStream
		if s != null:
			_stream_cache[path] = s


static func preload_sounds(paths: Array) -> void:
	for p in paths:
		preload_sound(str(p))


static func play_voice_file(file_path: String, volume_db: float = 0.0) -> void:
	var stream: AudioStream = _stream_cache.get(file_path, null)
	if stream == null:
		if not ResourceLoader.exists(file_path):
			return
		stream = load(file_path) as AudioStream
		if stream != null:
			_stream_cache[file_path] = stream
	if stream != null:
		play_sound(stream, volume_db)


static func play_sfx(file_path: String, volume_db: float = 0.0) -> void:
	play_voice_file(file_path, volume_db)


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
