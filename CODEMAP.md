# CODEMAP — 灰烬:启程 代码索引

> **自动生成,请勿手工编辑本文件。** 重跑:
> `godot --headless --path . --script res://tools/gen_codemap.gd`
>
> 每行的「职责」列取自脚本自身开头的 `##` 文档注释 —— 想改描述就去改那个脚本的注释,
> 索引不会和代码漂移。

## 给 AI 代理的使用规则

1. **实现任何新功能前,先在本文件检索关键词。** 已存在的能力必须复用,禁止另起炉灶。
2. 「重复实现警告」一节列出了已经发生的重复。往这些函数里再加一份 = 明确错误。
3. 「高扇入服务层」的公开函数签名是契约。改签名前先看扇入清单,评估波及面。
4. 新建脚本必须写开头 `##` 文档注释,否则会出现在文末 TODO 里。

## 统计

| 项 | 值 |
|---|---|
| 脚本数 | 166 |
| 总行数 | 46569 |
| 有 `##` 职责注释 | 135 / 166 |
| 有 `class_name` 全局名 | 54 / 166 |

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
| `_create_9patch_style` | **4** | scripts/chase_mode.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/multiplayer_lobby.gd |
| `reset` | **4** | scripts/ai/chase_perception.gd, scripts/ai/pvp_sword_ai.gd, scripts/player/anim_rig.gd, scripts/weapon_graph.gd |
| `_build_game_over_dialog` | **4** | scripts/chase_mode.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd |
| `_spawn_character_visual` | **4** | scripts/chase_mode.gd, scripts/map_editor.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd |
| `setup` | **4** | scripts/network/snapshot_interpolator.gd, scripts/player_controller.gd, scripts/player/player_probes.gd, scripts/skills/skill_loadout.gd |
| `_setup_vfx_pool` | **3** | scripts/dummy_target.gd, scripts/player_client/sword_pvp_game.gd, scripts/pvp_sword_sandbox.gd |
| `_build_trigger` | **3** | scripts/manor/manor_chair.gd, scripts/manor/manor_merchant.gd, scripts/manor/manor_teleporter.gd |
| `_build_camera` | **3** | scripts/chase_mode.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd |
| `_apply_builder_orientation` | **3** | scripts/map_editor.gd, scripts/npc_test.gd, scripts/skill_vfx_lab.gd |
| `build` | **3** | scripts/map_editor/editor_guide_dialog.gd, scripts/map_editor/editor_save_load_dialog.gd, scripts/player/anim_rig.gd |
| `_build_cameras` | **3** | scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd |
| `_cast_crosshair` | **3** | scripts/chase_mode.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd |
| `_build_npc` | **3** | scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd |
| `bind` | **3** | scripts/character_lod.gd, scripts/vfx/vfx_textures.gd, scripts/weapon_trail.gd |
| `_on_body_entered` | **3** | scripts/manor/manor_chair.gd, scripts/manor/manor_merchant.gd, scripts/manor/manor_teleporter.gd |
| `_on_body_exited` | **3** | scripts/manor/manor_chair.gd, scripts/manor/manor_merchant.gd, scripts/manor/manor_teleporter.gd |
| `_on_repath_requested` | **3** | scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd |
| `_apply_commander_cam_orientation` | **3** | scripts/chase_mode.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd |
| `_drive_commander_camera` | **3** | scripts/chase_mode.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd |
| `_draw_path` | **3** | scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd |
| `_toggle_commander_mode` | **3** | scripts/chase_mode.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd |
| `_spawn_character` | **3** | scripts/player_client/weapon_trial.gd, scripts/playground.gd, scripts/weapon_test.gd |
| `start` | **3** | scripts/dash_beam.gd, scripts/map_editor/editor_tutorial.gd, scripts/weapon_trail.gd |

<details>
<summary>接口族(多态覆写,非重复 —— 点开查看)</summary>

| 函数 | 实现数 | 基类 |
|---|---|---|
| `cast` | 13 | `scripts/skills/skill_base.gd` |
| `get_params` | 12 | `scripts/skills/skill_base.gd` |
| `preload_assets` | 12 | `scripts/skills/skill_base.gd` |
| `build_config_panel` | 12 | `scripts/skills/skill_base.gd` |
| `replay` | 12 | `scripts/skills/skill_base.gd` |
| `set_param` | 12 | `scripts/skills/skill_base.gd` |
| `get_warmup_materials` | 11 | `scripts/skills/skill_base.gd` |
| `_build_characters` | 6 | `scripts/player_client/sword_pvp_game.gd` |
| `poll` | 5 | `scripts/intent_source.gd` |
| `_check_blade_hits` | 3 | `scripts/player_client/sword_pvp_game.gd` |
| `find_path` | 3 | `scripts/nav_provider.gd` |
| `_on_stats_changed` | 3 | `scripts/player_client/sword_pvp_game.gd` |

</details>

## 🔒 高扇入服务层(扇入 ≥ 5)

改这些脚本的**公开函数签名**会波及下列依赖方。改内部实现是安全的。

### `scripts/audio_manager.gd` — 扇入 27

Central audio dispatcher for game voiceovers and UI SFX.

公开 API:`init_pool`, `play_bgm`, `stop_bgm`, `set_bgm_volume`, `create_footstep_sample`, `get_random_footstep_stream`, `get_land_stream`, `play_footstep`, `play_land_sound`, `play_hit_sound`, `play_sound`, `preload_sound`, `preload_sounds`, `play_voice_file`, `play_sfx`, `play_countdown`, `play_go`, `play_game_over`, `play_lose`, `play_win`

被依赖:scripts/main_menu.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/map_editor/editor_tutorial.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/hero_select.gd, scripts/player_client/multiplayer_lobby.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/title_screen.gd, scripts/player_client/weapon_trial.gd, scripts/player_controller.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/skill_vfx_lab.gd, scripts/skills/skill_cleanse.gd, scripts/skills/skill_clone.gd, scripts/skills/skill_entangle.gd, scripts/skills/skill_grapple.gd, scripts/skills/skill_jump_buff.gd, scripts/skills/skill_mist.gd, scripts/skills/skill_sand.gd, scripts/skills/skill_slam.gd, scripts/skills/skill_stealth.gd, scripts/skills/skill_teleport.gd, scripts/skills/skill_wall.gd, tools/_probe_player_client.gd

### `tools/character_pipeline.gd` — 扇入 25

Turns a character export dropped into assets/characters/<id>/ into a ready

公开 API:`list_characters`, `read_settings`, `write_settings`, `find`, `configure_all`, `configure`, `root_scale_for`, `current_root_scale`, `build_scenes`, `build_scene`, `fix_character_materials`, `rig_report`

被依赖:addons/anim_pipeline/plugin.gd, scripts/anim_debug.gd, scripts/chase_mode.gd, scripts/dummy_target.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/hero_select.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/weapon_trial.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/skill_vfx_lab.gd, scripts/weapon_test.gd, tools/_probe_chair_anims.gd, tools/build_character_scenes.gd, tools/build_single_character.gd, tools/compare_rest.gd, tools/inspect_model.gd, tools/measure_scale.gd, tools/setup_character_imports.gd, tools/setup_single_character.gd

### `scripts/player_controller.gd` — 扇入 18

Character controller handling locomotion (WASD, sprint, crouch), gravity, jumps, rolls, ledges, and weapon graph states.

公开 API:`setup`, `drive`, `request_jump`, `request_roll`, `request_attack`, `request_button`, `view_yaw`, `get_head_position`, `get_head_front_position`, `is_moving`, `speed`, `state_name`, `play_stop_walk`, `sit_down`, `stand_up`, `is_sitting`, `apply_hit_reaction`, `set_weapon_graph`, `set_weapon_stance`, `set_weapon_locomotion`, `set_weapon_stance_clip`, `set_weapon_stance_filter`, `set_weapon_trail`, `weapon_stroke_count` …(共 32 个)

被依赖:scripts/chase_mode.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/weapon_trial.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/skill_vfx_lab.gd, scripts/weapon_test.gd, tools/_probe_chair_anims.gd, tools/_probe_landing_roll.gd, tools/_probe_manor_chairs_and_stop.gd, tools/_probe_movement_trial_tutorial.gd, tools/_probe_real_landing.gd

### `scripts/player_intent_source.gd` — 扇入 14

Keyboard/mouse input source for CharacterIntent, driven by KeybindManager.

公开 API:`button_for_mouse`, `poll`

被依赖:scripts/chase_mode.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/weapon_trial.gd, scripts/player_controller.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/skill_vfx_lab.gd, scripts/weapon_test.gd, tools/_probe_keybind_system.gd

### `scripts/follow_camera.gd` — 扇入 13

Third-person / First-person camera. Orbits/follows target.

公开 API:`frame_for`, `snap`, `toggle_first_person`, `set_first_person`

被依赖:scripts/chase_mode.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/weapon_trial.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/skill_vfx_lab.gd, scripts/weapon_test.gd

### `tools/anim_pipeline.gd` — 扇入 13

Shared logic for turning downloaded animation files into clips on a rig.

公开 API:`list_sources`, `source_dirs`, `list_all_sources`, `configure_all`, `configure`, `silhouette_filter`, `refresh_silhouette_settings`, `probe`, `detect_bone_map`, `map_prefix`, `resolve_bone_map`, `namespace_variant`, `arm_droop_degrees`, `source_bone_name`, `body_height`, `list_bones`, `character_library_path`, `build_all_libraries`, `build_library`, `clip_name_for`, `rig_report`, `first_of_class`

被依赖:addons/anim_pipeline/plugin.gd, scripts/character.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/hero_select.gd, scripts/player_client/title_screen.gd, tools/build_anim_library.gd, tools/build_single_character.gd, tools/character_pipeline.gd, tools/compare_rest.gd, tools/measure_scale.gd, tools/setup_anim_imports.gd, tools/setup_single_character.gd

### `scripts/world/world_builder.gd` — 扇入 12

Shared scene scaffolding: environment (sky/light/post) and ground (plane/grid/ring).

公开 API:`build_environment`, `build_ground`

被依赖:scripts/chase_mode.gd, scripts/manor/manor_world.gd, scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/weapon_trial.gd, scripts/playground.gd, scripts/pvp_sword_sandbox.gd, scripts/weapon_test.gd

### `scripts/map_data.gd` — 扇入 11

Map data model, JSON serialization, and file I/O manager.

公开 API:`serialize_map`, `create_default_map`, `save_map_to_file`, `load_map_from_file`, `list_available_maps`, `delete_user_map`

被依赖:scripts/chase_mode.gd, scripts/map_editor.gd, scripts/map_editor/editor_save_load_dialog.gd, scripts/network/network_manager.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/multiplayer_lobby.gd, scripts/player_client/sword_pvp_game.gd, scripts/player_client/title_screen.gd, scripts/pvp_sword_sandbox.gd, tools/_probe_map_editor.gd

### `scripts/nav_grid.gd` — 扇入 10

Voxel navigation grid + capability-derived A* for CharacterBody3D agents.

公开 API:`add_special_path`, `remove_special_path`, `clear_special_paths`, `set_special_paths`, `get_special_paths`, `get_special_path_between`, `set_bounds`, `set_capability_direct`, `set_block`, `clear_blocks`, `is_solid`, `is_standable`, `is_standable_at`, `stand_center`, `stand_foot`, `block_count`, `is_dirty`, `in_bounds`, `foot`, `cell_of`, `rebuild`, `cell_gap`, `standing_node`, `is_same_flat_platform` …(共 26 个)

被依赖:scripts/chase_mode.gd, scripts/map_editor.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, tools/_probe_chase_mode.gd, tools/_probe_gap_jump.gd, tools/_probe_map_editor.gd, tools/_probe_nav_provider.gd, tools/_probe_special_replay.gd, tools/_probe_standing_node.gd

### `scripts/npc_intent_source.gd` — 扇入 9

Standardized NPC intent source: follows a NavProvider plan, climbs what the

公开 API:`bind_nav_grid`, `set_path`, `set_plan`, `set_plan_result`, `direct_chase`, `clear_target`, `has_target`, `has_reached_target`, `plan_is_complete`, `get_target_position`, `get_path`, `get_path_index`, `obstructed_time`, `set_run`, `set_crouch`, `request_jump`, `request_roll`, `request_button`, `execute_sequence`, `stop_sequence`, `is_sequence_running`, `is_performing_jump_or_climb`, `get_sequence_status`, `poll`

被依赖:scripts/chase_mode.gd, scripts/map_editor.gd, scripts/navmesh_test.gd, scripts/npc_test.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, tools/_probe_chase_mode.gd, tools/_probe_npc_run.gd, tools/_probe_special_replay.gd

### `scripts/block_registry.gd` — 扇入 7

Block type definition registry and multi-cell geometry instance factory.

公开 API:`init_registry`, `register_type`, `get_type`, `list_types`, `create_body`

被依赖:scripts/chase_mode.gd, scripts/map_editor.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/sword_pvp_game.gd, scripts/pvp_sword_sandbox.gd, tools/_probe_map_editor.gd

### `scripts/keybind_manager.gd` — 扇入 6

Global keybinding and input redirection manager.

公开 API:`get_instance`, `get_all_bindings`, `get_binding`, `set_binding`, `reset_to_defaults`, `save_to_disk`, `load_from_disk`, `action_label`, `set_action_trigger_mode`, `binding_key_only_text`, `binding_display_text`, `binding_short_action_text`, `get_action_for_mouse_button`

被依赖:scripts/keybind_remap_panel.gd, scripts/player_client/chase_game.gd, scripts/player_client/chase_multiplayer.gd, scripts/player_client/weapon_trial.gd, scripts/player_intent_source.gd, tools/_probe_keybind_system.gd

### `scripts/skills/skill_registry.gd` — 扇入 5

Central registry of all available skills.

公开 API:`init_registry`, `dispel_all_debuffs`, `register_skill`, `get_skill`, `get_all_skills`, `get_first_skill_id`, `warmup_all_shaders`

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
| `audio_manager.gd` | 255 | AudioManager | 27 | 0 | Central audio dispatcher for game voiceovers and UI SFX. |
| `block_registry.gd` | 199 | BlockRegistry | 7 | 0 | Block type definition registry and multi-cell geometry instance factory. |
| `character_intent.gd` | 51 | CharacterIntent | 2 | 0 | Decoupled character input intent state. Recycled in-place every physics frame. |
| `character_lod.gd` | 330 | CharacterLOD | 0 | 0 | Per-character compute tier, picked from camera distance and on-screen state. |
| `character.gd` | 201 | Character | 0 | 1 | Root Node3D for character, wrapping instanced model scene. |
| `chase_mode.gd` | 1170 | — | 2 | 9 | 1v1 Pursuit / Chase Mode controller. |
| `dash_beam.gd` | 161 | DashBeam | 0 | 0 | 3D character ghost afterimages with energy particle shatter dissipation. |
| `dash_fade.gd` | 72 | DashFade | 1 | 0 | Whole-character opacity with smoothstep easing for dash dissolve/fade. |
| `dummy_target.gd` | 568 | DummyTarget | 2 | 2 | Stationary hit target: HP readout, reaction clips, impact VFX. |
| `equipment_manager.gd` | 94 | EquipmentManager | 4 | 0 | PlayerController component managing equipping, unequipping, and applying ItemData behaviors. |
| `follow_camera.gd` | 172 | FollowCamera | 13 | 0 | Third-person / First-person camera. Orbits/follows target. |
| `handheld_item.gd` | 194 | HandheldItem | 1 | 0 | Node representing an item instantiated on a bone attachment socket. |
| `intent_source.gd` | 8 | IntentSource | 0 | 0 | Base class for character decision/input sources (AI bot, keyboard, network, etc.). |
| `item_data.gd` | 35 | ItemData | 0 | 0 | Configuration resource for a handheld item. |
| `keybind_manager.gd` | 213 | KeybindManager | 6 | 0 | Global keybinding and input redirection manager. |
| `keybind_remap_panel.gd` | 332 | KeybindRemapPanel | 3 | 1 | Combat and locomotion input remapping UI panel. |
| `loading_screen.gd` | 179 | — | 0 | 0 | Asynchronous loading screen with smooth progress bar and dynamic gameplay hints. |
| `main_menu.gd` | 332 | — | 2 | 1 | Project Mode Selection Gateway (Player Client vs Developer Sandbox). |
| `map_data.gd` | 157 | MapData | 11 | 0 | Map data model, JSON serialization, and file I/O manager. |
| `map_editor.gd` | 1698 | MapEditor | 4 | 14 | Map editor controller supporting multi-cell block building, save/load/new map, |
| `nav_grid.gd` | 804 | NavGrid | 10 | 0 | Voxel navigation grid + capability-derived A* for CharacterBody3D agents. |
| `nav_mesh_provider.gd` | 177 | NavMeshProvider | 1 | 0 | NavProvider backed by NavigationServer3D, for continuous maps: terrain, roads, |
| `nav_provider.gd` | 281 | NavProvider | 1 | 0 | Base class for navigation backends: voxel grid, navmesh, etc. |
| `navmesh_test.gd` | 471 | — | 0 | 6 | Continuous-map navigation test: NPC pathfinds over a baked NavigationMesh with |
| `npc_intent_source.gd` | 1291 | NPCIntentSource | 9 | 0 | Standardized NPC intent source: follows a NavProvider plan, climbs what the |
| `npc_test.gd` | 856 | — | 0 | 6 | Scene controller for NPC possession, first-person voxel building, and |
| `player_controller.gd` | 1540 | PlayerController | 18 | 2 | Character controller handling locomotion (WASD, sprint, crouch), gravity, jumps, rolls, ledges, and weapon graph states. |
| `player_intent_source.gd` | 121 | PlayerIntentSource | 14 | 1 | Keyboard/mouse input source for CharacterIntent, driven by KeybindManager. |
| `playground.gd` | 696 | — | 3 | 6 | Half-width of the floor, in metres. |
| `profile_manager.gd` | 220 | — | 2 | 0 | Player profile persistence and avatar manager. |
| `pvp_sword_sandbox.gd` | 826 | — | 0 | 11 | Developer Sandbox for NPC Sword PVP. |
| `scene_loader.gd` | 25 | SceneLoader | 1 | 0 | Global scene transition and asynchronous threaded loading controller. |
| `skill_vfx_lab.gd` | 1321 | — | 0 | 9 | Interactive Skill and VFX Sandbox Inspector. |
| `special_path_recorder.gd` | 281 | SpecialPathRecorder | 4 | 0 | Full-trajectory recorder: captures ground run-up + airborne + landing from |
| `trail_palette.gd` | 111 | TrailPalette | 0 | 0 | Derives a whole trail colour set from one hue family. Stateless, all static. |
| `weapon_config.gd` | 555 | WeaponConfig | 2 | 0 | Reads, writes, and normalizes per-weapon JSON configurations. |
| `weapon_graph_editor.gd` | 895 | WeaponGraphEditor | 0 | 0 | UI Editor panel for managing a weapon's JSON config dictionary. Emits `changed` signal on edits. |
| `weapon_graph.gd` | 164 | WeaponGraph | 1 | 0 | Runtime weapon behavior graph managing active nodes, edges (trigger windows), and input buffers. |
| `weapon_test.gd` | 1390 | — | 0 | 7 | Interactive weapon tuning and configuration tester scene. |
| `weapon_trail.gd` | 494 | WeaponTrail | 0 | 0 | Blade afterimage: a three-rail ribbon, its sparks, and an optional light. |

### `scripts/ai/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `chase_perception.gd` | 162 | ChasePerception | 0 | 0 | What one agent knows about its opponent: line of sight, hearing, a decaying |
| `pvp_sword_ai.gd` | 165 | PvpSwordAi | 2 | 0 | Autonomous combat AI intent source: delivers precise target tracking, forward pursuit, combos, and clean spacing. |

### `scripts/combat/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `pvp_combat_manager.gd` | 90 | PvpCombatManager | 3 | 0 | Shared combat formulas, stat tuning values, and roll mitigation logic for PVP duel modes. |

### `scripts/manor/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `manor_chair.gd` | 127 | ManorChair | 2 | 0 | Interactive chair/bench node enabling player and NPC sitting interaction with forward seat offset. |
| `manor_merchant.gd` | 521 | ManorMerchant | 2 | 0 | **⚠ 缺注释** |
| `manor_npc_wander.gd` | 105 | ManorNpcWander | 3 | 0 | Autonomous wander intent source constrained to an anchor radius with stop_walking transitions. |
| `manor_teleporter.gd` | 118 | ManorTeleporter | 2 | 0 | **⚠ 缺注释** |
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
| `player_weapons.gd` | 113 | PlayerWeapons | 0 | 0 | What the equipped weapon changes: the behaviour graph, and the animation the |

### `scripts/player_client/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `chase_game.gd` | 1542 | — | 2 | 16 | User client dedicated 1v1 Pursuit game scene. |
| `chase_multiplayer.gd` | 1360 | — | 0 | 17 | 1v1 LAN Multiplayer Pursuit Match Controller. |
| `hero_select.gd` | 610 | — | 0 | 3 | Dynamic 3D Hero selection stage with 360-degree orbit drag and multiplayer sync. |
| `multiplayer_lobby.gd` | 873 | — | 0 | 2 | Multiplayer LAN Lobby UI & Room Waiting Chamber. |
| `skill_draw_panel.gd` | 142 | SkillDrawPanel | 2 | 0 | Slot-machine reveal for the drawn skill. Purely cosmetic: the result is decided by SkillLoadout.roll(). |
| `sword_pvp_game.gd` | 745 | — | 0 | 11 | Player Client dedicated 1v1 Sword PVP Duel scene. |
| `sword_pvp_multiplayer.gd` | 428 | — | 0 | 1 | LAN 1v1 sword duel. Extends the AI duel scene: reuses arena, HUD, floaters, game-over flow. |
| `title_screen.gd` | 1148 | — | 4 | 7 | User-facing game client title screen. |
| `weapon_trial.gd` | 578 | — | 1 | 12 | Player client weapon trial and combo sandbox. |

### `scripts/skills/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `skill_aim.gd` | 177 | SkillAim | 2 | 0 | Ground-target aim controller for skills that expose cast_at(). Extracted from the VFX lab flow: |
| `skill_base.gd` | 49 | — | 1 | 0 | Abstract base class for all playable and VFX sandbox skills. |
| `skill_cleanse.gd` | 308 | — | 1 | 2 | Skill 11: Holy Cleanse (✨ 圣洁净化). |
| `skill_clone.gd` | 336 | — | 2 | 1 | 分身 (Mirror Clone): summon a physically identical clone in place. |
| `skill_entangle.gd` | 513 | — | 1 | 1 | Realistic Bioluminescent Thorny Vine Entanglement Skill. |
| `skill_grapple.gd` | 543 | — | 1 | 1 | Grapple: forward thick hook. Extend → latch → retract+pull. Hit = model capsule vs hook width. |
| `skill_jump_buff.gd` | 276 | — | 1 | 1 | Skill 10: Jump Buff (🦘 弹跳增益). |
| `skill_loadout.gd` | 211 | SkillLoadout | 2 | 1 | One fighter's skill slot: role-filtered random draw, cooldown clock, cast entry points. |
| `skill_mist.gd` | 508 | — | 1 | 1 | Skill 8: Mist Obscurity (昏暗/迷雾障眼). |
| `skill_registry.gd` | 114 | — | 5 | 12 | Central registry of all available skills. |
| `skill_sand.gd` | 359 | — | 1 | 1 | 深沙 (Deep Sand): ground-targeted quicksand zone. |
| `skill_slam.gd` | 570 | — | 1 | 1 | Skill 9: Ground Slam (裂地崩击). |
| `skill_stealth.gd` | 306 | — | 2 | 1 | Stealth / Optical Camouflage Skill. |
| `skill_teleport.gd` | 318 | — | 1 | 2 | Cyberpunk Flash Teleport Skill (Supersonic Mach Dash). |
| `skill_wall.gd` | 344 | — | 1 | 1 | 焰气之痕 (Flame Wall): place a wall of fire perpendicular to the aim line. |

### `scripts/updater/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `update_dialog.gd` | 339 | UpdateDialog | 1 | 0 | In-game update prompt modal dialog with animations and direct Git synchronization. |
| `updater.gd` | 123 | Updater | 1 | 0 | Version checker and in-app Git synchronization runner. |

### `scripts/vfx/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `cyber_ghost_effect.gd` | 88 | CyberGhostEffect | 1 | 0 | Cyberpunk hologram afterimage spawner. |
| `vfx_textures.gd` | 64 | VfxTextures | 0 | 0 | Central lookup for the VFX texture library under assets/VFX_assets/. |

### `scripts/world/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `env_preset.gd` | 55 | EnvPreset | 1 | 0 | Sky + post-processing + directional light settings for one scene's look. |
| `ground_preset.gd` | 29 | GroundPreset | 1 | 0 | Ground plane + line grid + decorative ring appearance for one scene. |
| `world_builder.gd` | 180 | WorldBuilder | 12 | 2 | Shared scene scaffolding: environment (sky/light/post) and ground (plane/grid/ring). |

### `tools/`

| 脚本 | 行 | class_name | 扇入 | 扇出 | 职责 |
|---|---|---|---|---|---|
| `_match_hero4_textures.gd` | 39 | — | 0 | 0 | Dumps mesh details and UVs to a JSON for matching textures. |
| `_probe_alpha.gd` | 11 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_anim_lengths.gd` | 12 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_arrays.gd` | 27 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_asset_import.gd` | 39 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_audio_system.gd` | 64 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_chair_anims.gd` | 23 | — | 0 | 2 | **⚠ 缺注释** |
| `_probe_chair_mesh.gd` | 27 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_character_lod.gd` | 233 | — | 0 | 0 | Checks the character render/compute tier system: the distance banding and its |
| `_probe_chase_9patch_hud.gd` | 122 | — | 0 | 2 | Test probe for 9-patch frame textures on Chase Game HUD panels |
| `_probe_chase_mode.gd` | 175 | — | 0 | 3 | Headless probe for 1v1 Chase Mode rules and subsystems. |
| `_probe_col_gen.gd` | 24 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_dash.gd` | 61 | — | 0 | 0 | Throwaway: drives the weapon test scene headless, fires the Ax's lunge node |
| `_probe_fbx_scales.gd` | 30 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_gap_jump.gd` | 286 | — | 0 | 1 | Throwaway: does the gap-jump edge rule match the arc the engine actually flies? |
| `_probe_gap_run.gd` | 150 | — | 0 | 0 | Throwaway: drive the real body across real voids, over and over. |
| `_probe_grass_mesh.gd` | 13 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_hero4_meshes.gd` | 69 | — | 0 | 0 | Inspects hero_4 sub-meshes, materials, vertex bones, UVs. |
| `_probe_house_tree.gd` | 13 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_indoor_wall.gd` | 54 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_inspect_render.gd` | 34 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_interactive_tutorial.gd` | 148 | — | 0 | 2 | Probe test suite for Map Studio Onboarding: Ask Modal & Full 6-Step Interactive Tutorial State Machine. |
| `_probe_keybind_system.gd` | 168 | — | 0 | 4 | Automated probe and validation test suite for KeybindManager and PlayerIntentSource remapping. |
| `_probe_landing_roll.gd` | 41 | — | 0 | 1 | **⚠ 缺注释** |
| `_probe_manor_chairs_and_stop.gd` | 105 | — | 0 | 3 | Comprehensive probe test for manor chairs, sitting interactions, billboard removal, and NPC stop_walking behavior. |
| `_probe_manor_npcs.gd` | 60 | — | 0 | 1 | Probe testing manor NPC loading and wandering behavior. |
| `_probe_manor.gd` | 103 | — | 0 | 3 | **⚠ 缺注释** |
| `_probe_map_editor_guide.gd` | 124 | — | 0 | 1 | Probe test suite for MapEditor B-key panels toggle, multi-page tutorial guide, and input invariants. |
| `_probe_map_editor.gd` | 208 | — | 0 | 5 | Headless test probe for Map Editor subsystems: BlockRegistry, MapData, SpecialPathRecorder, and NavGrid special paths. |
| `_probe_mm_buffer.gd` | 32 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_mm_direct.gd` | 14 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_mm_order.gd` | 24 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_mm.gd` | 23 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_movement_trial_tutorial.gd` | 154 | — | 0 | 2 | Headless probe testing the Movement Sandbox Third-Person Trial & Interactive Tutorial flow. |
| `_probe_nav_grid.gd` | 186 | — | 0 | 0 | Throwaway: does the navigation graph agree with the controller's real limits? |
| `_probe_nav_mesh.gd` | 160 | — | 0 | 0 | Drives the continuous-map scene end to end: bake a NavigationMesh, route an |
| `_probe_nav_provider.gd` | 144 | — | 0 | 2 | Contract probe: NavGrid satisfies NavProvider, and the world-space wrappers |
| `_probe_npc_nav.gd` | 308 | — | 0 | 0 | Throwaway: drive the real scene and see whether the body actually gets there. |
| `_probe_npc_run.gd` | 24 | — | 0 | 2 | **⚠ 缺注释** |
| `_probe_orig_grass_mat.gd` | 19 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_player_client.gd` | 120 | — | 0 | 3 | Headless probe for User Client title screen, chase game, and audio dispatcher. |
| `_probe_pvp_sword.gd` | 144 | — | 0 | 1 | Automated verification for NPC Sword PVP Combat, Roll Halving, Dev Sandbox, and Player Client. |
| `_probe_reactions.gd` | 56 | — | 0 | 0 | Throwaway: what the reaction clips actually do to the body. Hip height over |
| `_probe_real_landing.gd` | 39 | — | 0 | 1 | **⚠ 缺注释** |
| `_probe_scene_loader_and_weapon_trial.gd` | 137 | — | 0 | 4 | Test probe for Global SceneLoader progress transitions and Player Client Weapon Trial Armory & Combo system. |
| `_probe_shaders.gd` | 13 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_skill_mist.gd` | 88 | — | 0 | 0 | Test suite for SkillMist (Skill 8). |
| `_probe_skill_preload.gd` | 41 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_skill_slam.gd` | 63 | — | 0 | 0 | Test suite for SkillSlam (Skill 9). |
| `_probe_special_replay.gd` | 393 | — | 0 | 3 | Throwaway: does a recorded special path reach the executor, and does the |
| `_probe_standing_node.gd` | 31 | — | 0 | 1 | **⚠ 缺注释** |
| `_probe_step_up.gd` | 88 | — | 0 | 0 | Guards the step-up rule against the dead zone it was written to close. |
| `_probe_stop_walk_decel.gd` | 51 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_textures.gd` | 11 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_title_bg_and_sandbox_hud.gd` | 139 | — | 0 | 3 | Test probe for Main Gateway Video Background, Player Client 3D Animation Background, and Movement Sandbox HUD. |
| `_probe_updater.gd` | 47 | — | 0 | 2 | Probe script to test Updater logic and UpdateDialog UI instantiation. |
| `_probe_uvs_detailed.gd` | 30 | — | 0 | 0 | **⚠ 缺注释** |
| `_probe_vfx_textures.gd` | 131 | — | 0 | 0 | Diagnoses why the VFX textures do not show up. |
| `_probe_weapon_trail.gd` | 318 | — | 0 | 1 | Throwaway: checks the blade trail's config clamps, its palette, its anchor |
| `anim_pipeline.gd` | 959 | AnimPipeline | 13 | 0 | Shared logic for turning downloaded animation files into clips on a rig. |
| `build_anim_library.gd` | 25 | — | 0 | 1 | CLI step 2: collect clips into AnimationLibrary resources - the shared library |
| `build_character_scenes.gd` | 27 | — | 0 | 1 | CLI step: generate assets/characters/<id>/<id>.tscn for every character. |
| `build_debug_scene.gd` | 141 | — | 0 | 0 | Generates scenes/anim_debug.tscn: lighting, ground and an orbit camera rig, |
| `build_single_character.gd` | 44 | — | 0 | 2 | CLI step: build a single character's animation library (if any) and wrapper scene (.tscn). |
| `capture.gd` | 108 | — | 0 | 0 | Renders stills of the debug scene so a retarget can be checked without |
| `character_pipeline.gd` | 588 | CharacterPipeline | 25 | 1 | Turns a character export dropped into assets/characters/<id>/ into a ready |
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
- `tools/_probe_alpha.gd`
- `tools/_probe_anim_lengths.gd`
- `tools/_probe_arrays.gd`
- `tools/_probe_asset_import.gd`
- `tools/_probe_audio_system.gd`
- `tools/_probe_chair_anims.gd`
- `tools/_probe_chair_mesh.gd`
- `tools/_probe_col_gen.gd`
- `tools/_probe_fbx_scales.gd`
- `tools/_probe_grass_mesh.gd`
- `tools/_probe_house_tree.gd`
- `tools/_probe_indoor_wall.gd`
- `tools/_probe_inspect_render.gd`
- `tools/_probe_landing_roll.gd`
- `tools/_probe_manor.gd`
- `tools/_probe_mm_buffer.gd`
- `tools/_probe_mm_direct.gd`
- `tools/_probe_mm_order.gd`
- `tools/_probe_mm.gd`
- `tools/_probe_npc_run.gd`
- `tools/_probe_orig_grass_mat.gd`
- `tools/_probe_real_landing.gd`
- `tools/_probe_shaders.gd`
- `tools/_probe_skill_preload.gd`
- `tools/_probe_standing_node.gd`
- `tools/_probe_stop_walk_decel.gd`
- `tools/_probe_textures.gd`
- `tools/_probe_uvs_detailed.gd`
