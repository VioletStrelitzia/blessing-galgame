extends Node

enum Bus {
	MASTER,
	MUSIC,
	SFX,
	VOICE
}

const MUSIC_BUS_NAME = "Music"
const SFX_BUS_NAME = "SFX"
const VOICE_BUS_NAME = "Voice"

@onready var music_manager: MusicAudioPlayerManager = $MusicManager
@onready var sfx_manager: SFXAudioPlayerManager = $SFXManager
@onready var voice_manager: VoiceAudioPlayerManager = $VoiceManager


func _ready() -> void:
	music_manager.set_bus(MUSIC_BUS_NAME)
	sfx_manager.set_bus(SFX_BUS_NAME)
	voice_manager.set_bus(VOICE_BUS_NAME)
	GalLogger.info("加载完成")


func play_music(
	audio: AudioStream,
	offset: float = 0,
	fade_out_duration: float = 1.0,
	fade_in_duration: float = 1.0,
	loop: bool = true
):
	music_manager.play(audio, offset, fade_out_duration, fade_in_duration, loop)


func play_voice(audio: AudioStream, offset: float = 0):
	voice_manager.play(audio, offset)


func pause_music():
	music_manager.pause()


func resume_music() -> void:
	music_manager.resume()


func stop_music(fade_out_duration: float = 1.0):
	music_manager.stop(fade_out_duration)


func pause_voice():
	voice_manager.pause()


func resume_voice() -> void:
	voice_manager.resume()


func stop_voice():
	voice_manager.stop()


func play_sfx(audio: AudioStream, offset: float = 0):
	sfx_manager.play(audio, offset)


func set_volume(bus_index: Bus, volume_linear: float):
	var db = linear_to_db(volume_linear)
	AudioServer.set_bus_volume_db(bus_index, db)
