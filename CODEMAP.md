# CODEMAP — 灰烬:启程 代码索引

> **自动生成,请勿手工编辑本文件。** 重跑:
> `godot --headless --path . --script res://tools/gen_codemap.gd`
>
> 每行的「职责」列取自脚本自身开头的 `##` 文档注释 —— 想改描述就去改那个脚本的注释,
> 索引不会和代码漂移。

## 给 AI 代理的使用规则

**本文件非必读。** 默认用 grep 检索脚本开头的 `##` 职责注释(见 CLAUDE.md / GEMINI.md 的检索配方)。
仅当需要回答宏观结构问题(重复实现全貌、扇入排名、脚本总览)时才读本文件,且只读相关小节。
内容可能过期 —— 本文件仅在手动重跑生成器时更新。

## 统计

| 项 | 值 |
|---|---|
| 脚本数 | 117 |
| 总行数 | 45410 |
| 有 `##` 职责注释 | 114 / 117 |
| 有 `class_name` 全局名 | 60 / 117 |

## ⚠️ 重复实现警告

同名函数在 `scripts/` 下被复制了 3 份以上,**且彼此没有继承关系**。
写新场景/新模式时,不要再复制第 N+1 份 —— 先看这里,考虑抽公共实现。
抽成公共实现后,剩下的 ≤2 行转发函数不再计数,本表会自动变短。

| 函数 | 份数 | 分布 |
|---|---|---|
| `_build_hud` | **12** | scripts/chase_mode.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/weapon_trial.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/weapon_test.gd |
| `_build_ui` | **9** | scripts/anim_debug.gd, scripts/loading_screen.gd, scripts/main_menu.gd, scripts/manor/manor_merchant.gd, scripts/player_client/hero_select.gd, scripts/player_client/multiplayer_lobby.gd, scripts/player_client/title_screen.gd, scripts/skill_vfx_lab.gd, scripts/updater/update_dialog.gd |
| `_build_visual_helpers` | **6** | scripts/chase_mode.gd, scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd |
| `_build_player` | **5** | scripts/manor/manor_world.gd, scripts/player_client/weapon_trial.gd, scripts/playground.gd, scripts/skill_vfx_lab.gd, scripts/weapon_test.gd |
| `_clear_all_blocks` | **5** | scripts/chase_mode.gd, scripts/map_editor.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd |
| `_make_wire_cube` | **5** | scripts/chase_mode.gd, scripts/map_editor.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd |
| `setup` | **4** | scripts/network/snapshot_interpolator.gd, scripts/player/player_probes.gd, scripts/player_controller.gd, scripts/skills/skill_loadout.gd |
| `_spawn_character_visual` | **4** | scripts/chase_mode.gd, scripts/map_editor.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd |
| `_build_game_over_dialog` | **4** | scripts/chase_mode.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd |
| `reset` | **4** | scripts/ai/chase_perception.gd, scripts/ai/pvp_sword_ai.gd, scripts/player/anim_rig.gd, scripts/weapon_graph.gd |
| `_spawn_character` | **3** | scripts/player_client/weapon_trial.gd, scripts/playground.gd, scripts/weapon_test.gd |
| `cast_at` | **5** | scripts/skills/skill_hammer_beam.gd, scripts/skills/skill_sand.gd, scripts/skills/skill_skyfire.gd, scripts/skills/skill_sword_rain.gd, scripts/skills/skill_wall.gd |
| `_ensure_cached_resources` | **5** | scripts/skills/skill_hammer_beam.gd, scripts/skills/skill_slam.gd, scripts/skills/skill_skyfire.gd, scripts/skills/skill_sword_rain.gd, scripts/skills/skill_wind_barrage.gd |
| `build` | **3** | scripts/map_editor/editor_guide_dialog.gd, scripts/map_editor/editor_save_load_dialog.gd, scripts/player/anim_rig.gd |
| `_draw_path` | **3** | scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd |
| `_on_repath_requested` | **3** | scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd |
| `_build_npc` | **3** | scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd |
| `_apply_builder_orientation` | **3** | scripts/map_editor.gd, scripts/npc_test.gd, scripts/skill_vfx_lab.gd |
| `_build_cameras` | **3** | scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd |
| `_on_body_exited` | **3** | scripts/manor/manor_chair.gd, scripts/manor/manor_merchant.gd, scripts/manor/manor_teleporter.gd |
| `_on_body_entered` | **3** | scripts/manor/manor_chair.gd, scripts/manor/manor_merchant.gd, scripts/manor/manor_teleporter.gd |
| `_build_trigger` | **3** | scripts/manor/manor_chair.gd, scripts/manor/manor_merchant.gd, scripts/manor/manor_teleporter.gd |
| `_setup_vfx_pool` | **3** | scripts/dummy_target.gd, scripts/player_client/sword_pvp_game.gd, scripts/pvp_sword_sandbox.gd |
| `start` | **3** | scripts/dash_beam.gd, scripts/map_editor/editor_tutorial.gd, scripts/weapon_trail.gd |
| `_cast_crosshair` | **3** | scripts/chase_mode.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd |
| `_apply_commander_cam_orientation` | **3** | scripts/chase_mode.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd |
| `_toggle_commander_mode` | **3** | scripts/chase_mode.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd |
| `bind` | **3** | scripts/character_lod.gd, scripts/vfx/vfx_textures.gd, scripts/weapon_trail.gd |

<details>
<summary>接口族(多态覆写,非重复 —— 点开查看)</summary>

| 函数 | 实现数 | 基类 |
|---|---|---|
| `cast` | 16 | `scripts/skills/skill_base.gd` |
| `get_params` | 15 | `scripts/skills/skill_base.gd` |
| `set_param` | 15 | `scripts/skills/skill_base.gd` |
| `replay` | 15 | `scripts/skills/skill_base.gd` |
| `build_config_panel` | 15 | `scripts/skills/skill_base.gd` |
| `preload_assets` | 15 | `scripts/skills/skill_base.gd` |
| `get_warmup_materials` | 14 | `scripts/skills/skill_base.gd` |
| `dispel_actor` | 8 | `scripts/skills/skill_base.gd` |
| `_build_characters` | 6 | `scripts/player_client/sword_pvp_game.gd` |
| `poll` | 5 | `scripts/intent_source.gd` |
| `find_path` | 3 | `scripts/nav_provider.gd` |
| `_check_blade_hits` | 3 | `scripts/player_client/sword_pvp_game.gd` |
| `_on_stats_changed` | 3 | `scripts/player_client/sword_pvp_game.gd` |

</details>

## 🔒 高扇入服务层(扇入 ≥ 5)

改这些脚本的**公开函数签名**会波及下列依赖方。改内部实现是安全的。

### `scripts/audio_manager.gd` — 扇入 29

Central audio dispatcher for game voiceovers and UI SFX.

公开 API:`init_pool`, `play_bgm`, `stop_bgm`, `set_bgm_volume`, `create_footstep_sample`, `get_random_footstep_stream`, `get_land_stream`, `play_footstep`, `play_land_sound`, `play_hit_sound`, `play_sound`, `preload_sound`, `preload_sounds`, `play_voice_file`, `play_sfx`, `play_countdown`, `play_go`, `play_game_over`, `play_lose`, `play_win`

被依赖:scripts/main_menu.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/map_editor/editor_tutorial.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/hero_select.gd, scripts/player_client/multiplayer_lobby.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/title_screen.gd, scripts/player_client/weapon_trial.gd, scripts/player_controller.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/skill_vfx_lab.gd, scripts/skills/skill_cleanse.gd, scripts/skills/skill_clone.gd, scripts/skills/skill_entangle.gd, scripts/skills/skill_grapple.gd, scripts/skills/skill_jump_buff.gd, scripts/skills/skill_mist.gd, scripts/skills/skill_sand.gd, scripts/skills/skill_slam.gd, scripts/skills/skill_stealth.gd, scripts/skills/skill_sword_rain.gd, scripts/skills/skill_teleport.gd, scripts/skills/skill_thunder.gd, scripts/skills/skill_wall.gd, scripts/skills/skill_wind_barrage.gd

### `tools/character_pipeline.gd` — 扇入 24

Turns a character export dropped into assets/characters/<id>/ into a ready

公开 API:`list_characters`, `read_settings`, `write_settings`, `find`, `configure_all`, `configure`, `root_scale_for`, `current_root_scale`, `build_scenes`, `build_scene`, `fix_character_materials`, `rig_report`

被依赖:addons/anim_pipeline/plugin.gd, scripts/anim_debug.gd, scripts/chase_mode.gd, scripts/dummy_target.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/hero_select.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/weapon_trial.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/skill_vfx_lab.gd, scripts/weapon_test.gd, tools/build_character_scenes.gd, tools/build_single_character.gd, tools/compare_rest.gd, tools/inspect_model.gd, tools/measure_scale.gd, tools/setup_character_imports.gd, tools/setup_single_character.gd

### `tools/anim_pipeline.gd` — 扇入 16

Shared logic for turning downloaded animation files into clips on a rig.

公开 API:`list_sources`, `source_dirs`, `list_all_sources`, `configure_all`, `configure`, `silhouette_filter`, `refresh_silhouette_settings`, `probe`, `detect_bone_map`, `map_prefix`, `resolve_bone_map`, `namespace_variant`, `arm_droop_degrees`, `source_bone_name`, `body_height`, `list_bones`, `character_library_path`, `build_all_libraries`, `build_library`, `clip_name_for`, `rig_report`, `first_of_class`

被依赖:addons/anim_pipeline/plugin.gd, scripts/character.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/hero_select.gd, scripts/player_client/title_screen.gd, scripts/skills/skill_clone.gd, scripts/skills/skill_jump_buff.gd, scripts/skills/skill_thunder.gd, tools/build_anim_library.gd, tools/build_single_character.gd, tools/character_pipeline.gd, tools/compare_rest.gd, tools/measure_scale.gd, tools/setup_anim_imports.gd, tools/setup_single_character.gd

### `scripts/follow_camera.gd` — 扇入 14

Third-person / First-person camera. Orbits/follows target.

公开 API:`frame_for`, `snap`, `toggle_first_person`, `set_first_person`

被依赖:scripts/chase_mode.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/weapon_trial.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/skill_vfx_lab.gd, scripts/weapon_test.gd, scripts/world/commander_cam.gd

### `scripts/player_controller.gd` — 扇入 13

Character controller handling locomotion (WASD, sprint, crouch), gravity, jumps, rolls, ledges, and weapon graph states.

公开 API:`apply_movement_profile`, `setup`, `drive`, `request_jump`, `request_roll`, `request_attack`, `request_button`, `view_yaw`, `get_head_position`, `get_head_front_position`, `is_moving`, `speed`, `state_name`, `play_stop_walk`, `sit_down`, `stand_up`, `is_sitting`, `apply_hit_reaction`, `set_weapon_graph`, `set_weapon_stance`, `set_weapon_locomotion`, `set_weapon_stance_clip`, `set_weapon_stance_filter`, `set_weapon_trail` …(共 35 个)

被依赖:scripts/chase_mode.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/weapon_trial.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/skill_vfx_lab.gd, scripts/weapon_test.gd

### `scripts/player_intent_source.gd` — 扇入 13

Keyboard/mouse input source for CharacterIntent, driven by KeybindManager.

公开 API:`button_for_mouse`, `poll`

被依赖:scripts/chase_mode.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/weapon_trial.gd, scripts/player_controller.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/skill_vfx_lab.gd, scripts/weapon_test.gd

### `scripts/world/world_builder.gd` — 扇入 12

Shared scene scaffolding: environment (sky/light/post) and ground (plane/grid/ring).

公开 API:`build_environment`, `build_ground`

被依赖:scripts/chase_mode.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/weapon_trial.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/weapon_test.gd

### `scripts/map_data.gd` — 扇入 10

Map data model, JSON serialization, and file I/O manager.

公开 API:`serialize_map`, `create_default_map`, `save_map_to_file`, `load_map_from_file`, `list_available_maps`, `delete_user_map`

被依赖:scripts/chase_mode.gd, scripts/map_editor.gd, scripts/map_editor/editor_save_load_dialog.gd, scripts/network/network_manager.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/multiplayer_lobby.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/title_screen.gd, scripts/pvp_sword_sandbox.gd

### `scripts/block_registry.gd` — 扇入 6

Block type definition registry and multi-cell geometry instance factory.

公开 API:`init_registry`, `register_type`, `get_type`, `list_types`, `create_body`

被依赖:scripts/chase_mode.gd, scripts/map_editor.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd, scripts/pvp_sword_sandbox.gd

### `scripts/npc_intent_source.gd` — 扇入 6

Standardized NPC intent source: follows a NavProvider plan, climbs what the

公开 API:`bind_nav_grid`, `set_path`, `set_plan`, `set_plan_result`, `direct_chase`, `clear_target`, `has_target`, `has_reached_target`, `plan_is_complete`, `get_target_position`, `get_path`, `get_path_index`, `obstructed_time`, `set_run`, `set_crouch`, `request_jump`, `request_roll`, `request_button`, `execute_sequence`, `stop_sequence`, `is_sequence_running`, `is_performing_jump_or_climb`, `get_sequence_status`, `poll`

被依赖:scripts/chase_mode.gd, scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd

### `scripts/keybind_manager.gd` — 扇入 5

Global keybinding and input redirection manager.

公开 API:`get_instance`, `get_all_bindings`, `get_binding`, `set_binding`, `reset_to_defaults`, `save_to_disk`, `load_from_disk`, `action_label`, `set_action_trigger_mode`, `binding_key_only_text`, `binding_display_text`, `binding_short_action_text`, `get_action_for_mouse_button`

被依赖:scripts/keybind_remap_panel.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/weapon_trial.gd, scripts/player_intent_source.gd

### `scripts/skills/skill_registry.gd` — 扇入 5

Central registry of all available skills.

公开 API:`init_registry`, `dispel_all_debuffs`, `reset_all_state`, `register_skill`, `get_skill`, `get_all_skills`, `get_first_skill_id`, `warmup_all_shaders`

被依赖:scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/skill_vfx_lab.gd, scripts/skills/skill_cleanse.gd, scripts/skills/skill_loadout.gd

## 全量索引

扇入 = 有多少脚本 preload 它;扇出 = 它 preload 了多少脚本。

### `addons/anim_pipeline/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `plugin.gd` | 132 | — | 0 | 2 | Watches the asset folders so downloaded content needs no manual work: drop a |

### `scripts/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `anim_debug.gd` | 537 | — | 0 | 1 | Character and Animation debug inspector scene. |
| `audio_manager.gd` | 255 | AudioManager | 29 | 0 | Central audio dispatcher for game voiceovers and UI SFX. |
| `block_registry.gd` | 199 | BlockRegistry | 6 | 0 | Block type definition registry and multi-cell geometry instance factory. |
| `character.gd` | 201 | Character | 0 | 1 | Root Node3D for character, wrapping instanced model scene. |
| `character_intent.gd` | 51 | CharacterIntent | 0 | 0 | Decoupled character input intent state. Recycled in-place every physics frame. |
| `character_lod.gd` | 330 | CharacterLOD | 0 | 0 | Per-character compute tier, picked from camera distance and on-screen state. |
| `chase_mode.gd` | 1105 | — | 0 | 11 | 1v1 Pursuit / Chase Mode controller. |
| `dash_beam.gd` | 161 | DashBeam | 0 | 0 | 3D character ghost afterimages with energy particle shatter dissipation. |
| `dash_fade.gd` | 72 | DashFade | 1 | 0 | Whole-character opacity with smoothstep easing for dash dissolve/fade. |
| `dummy_target.gd` | 568 | DummyTarget | 2 | 2 | Stationary hit target: HP readout, reaction clips, impact VFX. |
| `equipment_manager.gd` | 94 | EquipmentManager | 4 | 0 | PlayerController component managing equipping, unequipping, and applying ItemData behaviors. |
| `follow_camera.gd` | 172 | FollowCamera | 14 | 0 | Third-person / First-person camera. Orbits/follows target. |
| `game_settings.gd` | 152 | GameSettings | 1 | 0 | Global graphics, performance, and gameplay configuration manager. |
| `handheld_item.gd` | 194 | HandheldItem | 0 | 0 | Node representing an item instantiated on a bone attachment socket. |
| `intent_source.gd` | 8 | IntentSource | 0 | 0 | Base class for character decision/input sources (AI bot, keyboard, network, etc.). |
| `item_data.gd` | 35 | ItemData | 0 | 0 | Configuration resource for a handheld item. |
| `keybind_manager.gd` | 213 | KeybindManager | 5 | 0 | Global keybinding and input redirection manager. |
| `keybind_remap_panel.gd` | 332 | KeybindRemapPanel | 2 | 1 | Combat and locomotion input remapping UI panel. |
| `loading_screen.gd` | 179 | — | 0 | 0 | Asynchronous loading screen with smooth progress bar and dynamic gameplay hints. |
| `main_menu.gd` | 370 | — | 1 | 2 | Project Mode Selection Gateway (Player Client vs Developer Sandbox). |
| `map_data.gd` | 157 | MapData | 10 | 0 | Map data model, JSON serialization, and file I/O manager. |
| `map_editor.gd` | 1698 | MapEditor | 1 | 14 | Map editor controller supporting multi-cell block building, save/load/new map, |
| `nav_grid.gd` | 804 | NavGrid | 4 | 0 | Voxel navigation grid + capability-derived A* for CharacterBody3D agents. |
| `nav_mesh_provider.gd` | 177 | NavMeshProvider | 1 | 0 | NavProvider backed by NavigationServer3D, for continuous maps: terrain, roads, |
| `nav_provider.gd` | 281 | NavProvider | 0 | 0 | Base class for navigation backends: voxel grid, navmesh, etc. |
| `navmesh_test.gd` | 471 | — | 0 | 6 | Continuous-map navigation test: NPC pathfinds over a baked NavigationMesh with |
| `npc_intent_source.gd` | 1291 | NPCIntentSource | 6 | 0 | Standardized NPC intent source: follows a NavProvider plan, climbs what the |
| `npc_test.gd` | 856 | — | 0 | 6 | Scene controller for NPC possession, first-person voxel building, and |
| `player_controller.gd` | 1571 | PlayerController | 13 | 2 | Character controller handling locomotion (WASD, sprint, crouch), gravity, jumps, rolls, ledges, and weapon graph states. |
| `player_intent_source.gd` | 123 | PlayerIntentSource | 13 | 1 | Keyboard/mouse input source for CharacterIntent, driven by KeybindManager. |
| `playground.gd` | 696 | — | 1 | 6 | Half-width of the floor, in metres. |
| `profile_manager.gd` | 220 | — | 1 | 0 | Player profile persistence and avatar manager. |
| `pvp_sword_sandbox.gd` | 826 | — | 0 | 11 | Developer Sandbox for NPC Sword PVP. |
| `scene_loader.gd` | 25 | SceneLoader | 0 | 0 | Global scene transition and asynchronous threaded loading controller. |
| `settings_dialog.gd` | 373 | SettingsDialog | 2 | 1 | Visual, performance, atmosphere, and gameplay configuration UI dialog. |
| `skill_vfx_lab.gd` | 1341 | — | 0 | 9 | Interactive Skill and VFX Sandbox Inspector. |
| `special_path_recorder.gd` | 281 | SpecialPathRecorder | 2 | 0 | Full-trajectory recorder: captures ground run-up + airborne + landing from |
| `trail_palette.gd` | 111 | TrailPalette | 0 | 0 | Derives a whole trail colour set from one hue family. Stateless, all static. |
| `weapon_config.gd` | 555 | WeaponConfig | 1 | 0 | Reads, writes, and normalizes per-weapon JSON configurations. |
| `weapon_graph.gd` | 181 | WeaponGraph | 1 | 0 | Runtime weapon behavior graph managing active nodes, edges (trigger windows), and input buffers. |
| `weapon_graph_editor.gd` | 895 | WeaponGraphEditor | 0 | 0 | UI Editor panel for managing a weapon's JSON config dictionary. Emits `changed` signal on edits. |
| `weapon_test.gd` | 1390 | — | 0 | 7 | Interactive weapon tuning and configuration tester scene. |
| `weapon_trail.gd` | 513 | WeaponTrail | 0 | 0 | Blade afterimage: a three-rail ribbon, its sparks, and an optional light. |

### `scripts/ai/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `chase_perception.gd` | 162 | ChasePerception | 0 | 0 | What one agent knows about its opponent: line of sight, hearing, a decaying |
| `pvp_sword_ai.gd` | 266 | PvpSwordAi | 2 | 0 | Autonomous combat AI intent source: delivers precise target tracking, forward pursuit, combos, and clean spacing. |

### `scripts/combat/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `pvp_combat_manager.gd` | 90 | PvpCombatManager | 2 | 0 | Shared combat formulas, stat tuning values, and roll mitigation logic for PVP duel modes. |

### `scripts/config/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `chase_profile.gd` | 19 | ChaseProfile | 0 | 0 | Difficulty knobs for one chase encounter. Shared by chase_mode / chase_game / chase_multiplayer. |
| `movement_profile.gd` | 149 | MovementProfile | 0 | 0 | Tunable locomotion/jump/climb/land/roll/dash values for one character archetype. |

### `scripts/manor/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `manor_chair.gd` | 127 | ManorChair | 1 | 0 | Interactive chair/bench node enabling player and NPC sitting interaction with forward seat offset. |
| `manor_merchant.gd` | 521 | ManorMerchant | 1 | 0 | **⚠ 缺注释** |
| `manor_npc_wander.gd` | 105 | ManorNpcWander | 1 | 0 | Autonomous wander intent source constrained to an anchor radius with stop_walking transitions. |
| `manor_teleporter.gd` | 118 | ManorTeleporter | 1 | 0 | **⚠ 缺注释** |
| `manor_world.gd` | 994 | — | 0 | 10 | **⚠ 缺注释** |

### `scripts/map_editor/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `editor_guide_dialog.gd` | 290 | — | 1 | 0 | Static 4-page "special operations" guide book modal for MapEditor. |
| `editor_save_load_dialog.gd` | 147 | — | 1 | 1 | Save / Load map modal for MapEditor. |
| `editor_tutorial.gd` | 487 | — | 1 | 2 | Interactive 8-step onboarding quest for MapEditor. |

### `scripts/network/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `network_manager.gd` | 415 | — | 0 | 1 | Network Manager for 1v1 LAN/P2P pursuit chase mode. |
| `snapshot_interpolator.gd` | 131 | SnapshotInterpolator | 2 | 0 | Jitter buffer and snapshot interpolator for smoothing network remote entity transforms and animations. |

### `scripts/player/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `anim_rig.gd` | 743 | CharacterAnimRig | 0 | 0 | The runtime AnimationTree of one character: clip preparation, tree construction, layer playback. |
| `player_probes.gd` | 226 | PlayerProbes | 0 | 0 | Everything PlayerController asks the world before it commits to a move: |
| `player_vfx.gd` | 216 | PlayerVfx | 0 | 0 | What a lunge looks like, and what the blade leaves behind. |
| `player_weapons.gd` | 117 | PlayerWeapons | 0 | 0 | What the equipped weapon changes: the behaviour graph, and the animation the |

### `scripts/player_client/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `chase_game.gd` | 1478 | — | 0 | 18 | User client dedicated 1v1 Pursuit game scene. |
| `chase_multiplayer.gd` | 1296 | — | 0 | 19 | 1v1 LAN Multiplayer Pursuit Match Controller. |
| `hero_select.gd` | 610 | — | 0 | 3 | Dynamic 3D Hero selection stage with 360-degree orbit drag and multiplayer sync. |
| `multiplayer_lobby.gd` | 861 | — | 0 | 3 | Multiplayer LAN Lobby UI & Room Waiting Chamber. |
| `skill_draw_panel.gd` | 142 | SkillDrawPanel | 2 | 0 | Slot-machine reveal for the drawn skill. Purely cosmetic: the result is decided by SkillLoadout.roll(). |
| `sword_pvp_game.gd` | 745 | — | 0 | 11 | Player Client dedicated 1v1 Sword PVP Duel scene. |
| `sword_pvp_multiplayer.gd` | 428 | — | 0 | 1 | LAN 1v1 sword duel. Extends the AI duel scene: reuses arena, HUD, floaters, game-over flow. |
| `title_screen.gd` | 1196 | — | 0 | 8 | User-facing game client title screen. |
| `weapon_trial.gd` | 578 | — | 0 | 12 | Player client weapon trial and combo sandbox. |

### `scripts/skills/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `skill_aim.gd` | 177 | SkillAim | 2 | 0 | Ground-target aim controller for skills that expose cast_at(). Extracted from the VFX lab flow: |
| `skill_base.gd` | 56 | — | 1 | 0 | Abstract base class for all playable and VFX sandbox skills. |
| `skill_cleanse.gd` | 453 | — | 1 | 2 | 创世天启·广域圣洁神圣净域 (Grand Celestial Holy Cleanse Sanctuary). |
| `skill_clone.gd` | 398 | — | 2 | 2 | 分身·深渊黑煞浓雾幻象 (Dense Shadow Phantom Clone). |
| `skill_entangle.gd` | 628 | — | 1 | 1 | 幽冥死沼·深渊黑绿毒藤宏大向心缠绕 (Grand Dark Toxic Vine Cataclysm Entanglement). |
| `skill_grapple.gd` | 549 | — | 1 | 1 | Grapple: forward thick hook. Extend → latch → retract+pull. Hit = model capsule vs hook width. |
| `skill_hammer_beam.gd` | 716 | — | 1 | 1 | Skill 16: Hammer Beam / 天锤引雷 (高能光束·锤式轰击). 抡锤定格 0.6s + 2s 混色高能光束；skill_frozen 静止门控。 |
| `skill_jump_buff.gd` | 507 | — | 1 | 2 | 技能十：蟾宫折桂 (Osmanthus of the Moon Palace / Jump & Agility Buff). |
| `skill_loadout.gd` | 211 | SkillLoadout | 2 | 1 | One fighter's skill slot: role-filtered random draw, cooldown clock, cast entry points. |
| `skill_mist.gd` | 457 | — | 1 | 1 | 昏暗·无明夜 (Mist Obscurity / Abyssal Darkness Domain). |
| `skill_registry.gd` | 131 | — | 5 | 15 | Central registry of all available skills. |
| `skill_sand.gd` | 359 | — | 1 | 1 | 深沙 (Deep Sand): ground-targeted quicksand zone. |
| `skill_skyfire.gd` | 962 | — | 1 | 1 | Skill 15: Skyfire Fall / 天火坠落 (九霄焚陨·连珠天陨). 全程序化噪声火焰零贴图；RigidBody3D 拟真碎石。 |
| `skill_slam.gd` | 701 | — | 1 | 1 | Skill 9: Ground Slam (裂地崩击). |
| `skill_stealth.gd` | 316 | — | 2 | 1 | 光学迷彩·多点消融潜行 (Multi-Point Dissolve Optical Stealth). |
| `skill_sword_rain.gd` | 1232 | — | 1 | 1 | Skill 14: Sword Rain / 万剑归宗 (太乙剑阵·御剑飞霄·天降剑雨). |
| `skill_teleport.gd` | 386 | — | 1 | 2 | 空间跃迁·超音速破风突进 (Supersonic Spatial Dash). |
| `skill_thunder.gd` | 675 | — | 1 | 2 | Skill 12: Thunder Smite (天雷神裁). |
| `skill_wall.gd` | 552 | — | 1 | 1 | 孽血业火·十方核爆喷火血莲壮观火屏 (Spectacular Blood-Lotus Atomic Flame Barrier). |
| `skill_wind_barrage.gd` | 552 | — | 1 | 1 | Skill 13: Spatial Cleave / 裂空千刃 (弧形风刃·3D多维异面斩击). |

### `scripts/ui/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `hud_kit.gd` | 24 | HudKit | 4 | 0 | Pure UI construction helpers shared across HUDs. No scene state, all static. |

### `scripts/updater/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `update_dialog.gd` | 339 | UpdateDialog | 0 | 0 | In-game update prompt modal dialog with animations and direct Git synchronization. |
| `updater.gd` | 123 | Updater | 0 | 0 | Version checker and in-app Git synchronization runner. |

### `scripts/vfx/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `cyber_ghost_effect.gd` | 88 | CyberGhostEffect | 1 | 0 | Cyberpunk hologram afterimage spawner. |
| `vfx_textures.gd` | 66 | VfxTextures | 0 | 0 | Central lookup for the VFX texture library under assets/VFX_assets/. |

### `scripts/world/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `commander_cam.gd` | 91 | CommanderCam | 3 | 1 | Free-fly spectator ("commander") camera shared by chase_mode / chase_game / chase_multiplayer. |
| `env_preset.gd` | 55 | EnvPreset | 1 | 0 | Sky + post-processing + directional light settings for one scene's look. |
| `ground_preset.gd` | 29 | GroundPreset | 1 | 0 | Ground plane + line grid + decorative ring appearance for one scene. |
| `world_builder.gd` | 180 | WorldBuilder | 12 | 2 | Shared scene scaffolding: environment (sky/light/post) and ground (plane/grid/ring). |

### `tools/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `_match_hero4_textures.gd` | 39 | — | 0 | 0 | Dumps mesh details and UVs to a JSON for matching textures. |
| `anim_pipeline.gd` | 959 | AnimPipeline | 16 | 0 | Shared logic for turning downloaded animation files into clips on a rig. |
| `build_anim_library.gd` | 25 | — | 0 | 1 | CLI step 2: collect clips into AnimationLibrary resources - the shared library |
| `build_character_scenes.gd` | 27 | — | 0 | 1 | CLI step: generate assets/characters/<id>/<id>.tscn for every character. |
| `build_debug_scene.gd` | 141 | — | 0 | 0 | Generates scenes/anim_debug.tscn: lighting, ground and an orbit camera rig, |
| `build_single_character.gd` | 44 | — | 0 | 2 | CLI step: build a single character's animation library (if any) and wrapper scene (.tscn). |
| `capture.gd` | 108 | — | 0 | 0 | Renders stills of the debug scene so a retarget can be checked without |
| `character_pipeline.gd` | 588 | CharacterPipeline | 24 | 1 | Turns a character export dropped into assets/characters/<id>/ into a ready |
| `compare_rest.gd` | 206 | — | 0 | 2 | Read-only diagnostic: compares every character's retargeted rest pose against |
| `dump_profile.gd` | 18 | — | 0 | 0 | Dumps SkeletonProfileHumanoid bone names + reference pose, so bone maps can |
| `gen_bone_maps.gd` | 311 | — | 0 | 0 | Generates BoneMap resources that map each known source rig onto |
| `gen_codemap.gd` | 428 | — | 0 | 0 | Generates CODEMAP.md — repo-wide script index used by AI agents as a lookup standard. |
| `inspect_model.gd` | 137 | — | 0 | 1 | Headless inspector: dumps node tree, skeleton, rest pose and mesh bounds |
| `make_test_glb.gd` | 41 | — | 0 | 0 | Exports an imported animation scene back out as .glb, to test the pipeline |
| `measure_scale.gd` | 57 | — | 0 | 2 | Reports what height every character is set to, what it was measured at, and |
| `setup_anim_imports.gd` | 28 | — | 0 | 1 | CLI step 1: detect each animation's rig and write the matching BoneMap into |
| `setup_character_imports.gd` | 30 | — | 0 | 1 | CLI step: detect each character's rig and write its BoneMap, A-pose fix and |
| `setup_single_character.gd` | 35 | — | 0 | 2 | CLI step: configure a single character's .import file and its private animations. |

## TODO — 缺少 `##` 职责注释

这些脚本对 AI 检索不可见,补一行 `##` 注释即可。

- `scripts/manor/manor_merchant.gd`
- `scripts/manor/manor_teleporter.gd`
- `scripts/manor/manor_world.gd`
