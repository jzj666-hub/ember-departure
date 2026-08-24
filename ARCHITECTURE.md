# 开发者文档 —— 架构、规模与精简建议

面向要动这份代码的人。README.md 讲的是「怎么用」，这份讲的是「里面是什么、为什么这么写、
现在多大、该不该瘦身」。

统计口径：2026-08-03，不含 `.godot/`（引擎缓存）。

---

## 一句话

这个项目现在是**一条资产管线，加上刚起步的一层游戏代码**。
管线解决的问题只有一个：*把从网上下的、骨骼命名互不相同的角色和动作，自动变成能互相通用的
Godot 资源*。游戏那边目前只有第三人称移动（走、跑、横移）和两个测试场景；
战斗、关卡、AI、UI 都还没有。

---

## 数据流：从「拖进文件夹」到「能播」

整条链路只有一个方向，没有回路：

```
你把文件丢进 assets/
        │
        ▼
① Godot 先按默认设置导入一次      ← 此时骨骼还是 mixamorig_/CC_Base_，动作和角色不通用
        │
        ▼
② 管线读模型，认骨架，把 BoneMap 写进 .import 文件
   （anim_pipeline.gd / character_pipeline.gd 的 configure()）
        │  角色还额外写：A-pose 修正开关、root_scale（身高归一到 character.cfg
        │  的 height，默认 1.75 m）
        ▼
③ Godot 按新的 .import 重新导入   ← 骨骼被改名成 Hips/Spine/LeftUpperArm，
        │                            骨架节点统一叫 GeneralSkeleton
        ▼
④ 收集动作 → AnimationLibrary .tres
   收集角色 → <id>.tscn 包装场景
   （build_all_libraries() / build_scenes()）
        │
        ▼
⑤ 运行时 character.gd 把动作库挂到 AnimationPlayer 上
```

**②③之间必须重启一次导入**，这是整条管线所有复杂度的来源：管线不能一趟做完，
必须「写配置 → 让引擎重跑 → 再收集结果」。所以才会有两个入口（编辑器插件 / 命令行脚本），
两边都是在编排这同一个三拍节奏。

**为什么这样做能省事**：第③步之后，角色和动作的骨骼名字完全一样了，
动作库和具体角色再无关系 —— 所以 `shared_animations.tres` 全项目只存一份，
不按角色复制。加第 10 个角色，动作那边零成本。

---

## 代码分三层

### 第一层：管线核心（971 行，占 42%）

| 文件 | 行数 | 职责 |
|---|---|---|
| `tools/anim_pipeline.gd` | 695 | 认骨架、写 .import、建动作库。**所有关于「这是什么骨架」的判断都在这里** |
| `tools/character_pipeline.gd` | 276 | 角色侧：身高归一、生成包装场景。骨架判断全部委托给上面那个 |

`anim_pipeline.gd` 里最值得知道的四件事：

1. **`detect_bone_map()` 是打分制**，不是前缀匹配。拿每份 BoneMap 去数「有多少根骨头
   真的存在」，取最高分，低于 12 根（`MIN_MATCHED_BONES`）判定为不认识。
   所以不带前缀的骨架也能认出来。
2. **`resolve_bone_map()` 会生成文件**。骨架带了没见过的命名空间（`mixamorig9_`）时，
   它现场派生一份 `.tres` 写到 `assets/retarget/generated/`。
   必须落成真文件，因为 `.import` 只能按路径引用 BoneMap。
3. **`probe()` 每调一次就实例化一次场景**，很慢，所以有个按 `.import` 修改时间做 key 的
   静态缓存（`_probe_cache`）。编辑器里文件系统一变就会触发扫描，没有这个缓存会卡。
4. **`SILHOUETTE_EXCLUDED` 是一份排除名单，不是白名单**。踩过的坑里最贵的一个，
   README 第 7 条有完整病历。

`character_pipeline.gd` 里最值得知道的一件事：

- **身高是 `character.cfg` 里的两个数，不是代码里的常量。**
  `root_scale` 永远等于 `height / measured_height`，`measured_height` 只在第一次
  配置这个角色（写 bone map 的那一趟）时量一次并存盘。这样改身高是纯算术，
  不碰测量，随时可以改。
  **测量只能发生在重定向之前**：`fix_silhouette` 掰 rest 姿势但不动顶点，
  之后骨架和网格不再是同一个形状，没有任何信息说明网格哪条轴是上。
  `configure()` 里那句 `if retargeted or skel_cfg.has("retarget/bone_map")`
  分的就是这条界：上面是「骨架的事，只做一次」，下面是「身高的事，随时可以重来」。

### 第二层：驱动层（193 行）

同一套核心，两个入口，做的事完全一样：

| 入口 | 文件 | 什么时候用 |
|---|---|---|
| 编辑器自动 | `addons/anim_pipeline/plugin.gd`（107 行） | 开着编辑器时丢文件进去，自动跑 |
| 命令行 | `tools/rebuild_assets.bat` + 4 个 ~20 行的 SceneTree 包装 | 不开编辑器时 |

插件用 `_working` 布尔量防止「重新导入 → 触发文件系统变化 → 又去配置」的自激循环。
命令行版把同一件事拆成 6 个独立进程（`--import` / 配置 / `--import` / 收集），
因为 headless 下没法在一个进程里让引擎重跑导入。

### 第三层：查看与诊断（653 行 + 452 行）

| 文件 | 行数 | 性质 |
|---|---|---|
| `scripts/anim_debug.gd` | 452 | 调试查看器：轨道相机 + 全代码手搓的 UI + 骨骼线框 |
| `tools/gen_bone_maps.gd` | 221 | **一次性**：把手写的骨骼名字典变成 `.tres`。加新骨架类型时才跑 |
| `tools/compare_rest.gd` | 177 | 诊断：逐骨对比各角色重定向后的 rest 和 profile 的差距。**体态对不齐时用这个** |
| `tools/build_debug_scene.gd` | 122 | **一次性**：生成 `scenes/anim_debug.tscn`（灯光、地面、相机架） |
| `tools/inspect_model.gd` | 116 | 诊断：dump 节点树、骨骼、rest pose、网格包围盒 |
| `tools/capture.gd` | 97 | 诊断：无编辑器截图到 `.captures/` |
| `tools/measure_scale.gd` | 46 | 诊断：核对 root_scale 算得对不对 |
| `tools/make_test_glb.gd` | 35 | 诊断：把 FBX 导成 GLB，测管线的 glTF 分支 |
| `tools/dump_profile.gd` | 16 | 诊断：打印 SkeletonProfileHumanoid 的骨骼名 |

### 游戏代码

| 文件 | 职责 |
|---|---|
| `scripts/character.gd` | 管线交付的接口：找到 AnimationPlayer 和 Skeleton3D，挂动作库，`play()` / `resolve()` / `clip_names()` / `has_clip()`，外加 `body_height` 和手部插槽 |
| `scripts/main_menu.gd` | 主菜单，测试场景的入口 |
| `scripts/playground.gd` | 第三人称试玩场景：环境、地面、几何体、生成角色、HUD |
| `scripts/player_controller.gd` | 走 / 跑 / 横移 / 蹲行 / 撞墙刹停 / 跳跃 / 攀爬 / **跨小台阶** / 下落 / 三段落地 / 翻滚 / 持械站姿 / 图驱动的攻击。**只剩状态机和身体**，其余四层各自成文件（见下），互相不认识，只经过控制器 |
| `scripts/player/anim_rig.gd` | `CharacterAnimRig`：运行时那两层 AnimationTree、clip 预处理（`flatten()` / 反向烘焙 / 测速）、动作层与挥击层的播放和每帧参数。**所有 clip 名字和 `parameters/...` 路径只在这里出现**。加动作 clip、改混合树、换过滤器都改这一个文件 |
| `scripts/player/player_probes.gd` | `PlayerProbes`：动之前问世界的那些问题 —— 找 ledge、跨台阶、落点预测（`predict_impact()`）、翻滚落地有没有地。纯查询，只有 `try_step_up()` 会写位置。阈值全部从 body 上读，不自带常量 |
| `scripts/player/player_vfx.gd` | `PlayerVfx`：冲刺的光束 / 淡出（`DashVfx` 枚举住在这里）和刀刃残影的生命周期。控制器只说「开始 / 走一帧 / 收」 |
| `scripts/player/player_weapons.gd` | `PlayerWeapons`：`WeaponGraph` 的归属，加上装备接口（把武器的 clip 装进挥击槽、换站姿 clip / 过滤器 / 移动极点）。依赖单向：它认识 rig，rig 不认识武器 |
| `scripts/character_intent.gd` | 一帧的「这个角色想干什么」，纯数据。战斗按键槽的名字表在这里 |
| `scripts/intent_source.gd` | 这些决定从哪来的基类。玩家、bot、录像、剧情各写一份 |
| `scripts/player_intent_source.gd` | 键鼠那一份。双击 Shift 的判定在这里（那是输入设备的性质，不是角色的），物理键 → 战斗槽的绑定表也在这里 |
| `scripts/npc_intent_source.gd` | bot 那一份：跟随 `NavProvider` 计划、到墙脚发起攀爬、被挡住时沿墙切向绕行、卡死重算，外加脚本化任务序列。**攀爬高度、到达半径这些阈值全部从被驱动的 body 上读**，不写死。**只认接口不认后端**，全文没有 `NavGrid` 字样 |
| `scripts/nav_provider.gd` | 寻路后端的基类，`IntentSource` 的同型物。契约六件：`find_path` / `is_path_valid` / `capability` / `stand_center` / `stand_foot` / `is_standable_at`，外加 `changed` 信号。`Move` 枚举和 `Capability`（连同 `JUMP_CLEAR` / `LIP_CLEAR` / `MAX_GAP_DROP` / `MAX_DROP`）住在这里 —— 它们是**身体**的性质，不是格子的。`find_path` 返回的是**世界坐标 + 每段怎么走**，所以换后端不用动执行器。守着它的是 `tools/_probe_nav_provider.gd` |
| `scripts/nav_grid.gd` | `NavProvider` 的体素实现。每格 1 m，每列可以有多个可站立面（桥洞、悬挑）。**通行规则全部由 `PlayerController` 的导出参数推导**：跳跃顶点由 `jump_speed²/2g` 算，爬升上限取 `climb_max_height`，站立净空取 `_stand_height`；代价单位是**秒**，所以「绕 4 米」和「爬一次 1.5 秒」可以直接比。`NO_CELL` 和格子语义留在这一层，方格模式的场景（`chase_mode` / `map_editor` / `npc_test` / `chase_game` / `chase_multiplayer` / `special_path_recorder`）直接用它，不走接口。纯逻辑不持有场景节点，可 headless 测 |
| `scripts/nav_mesh_provider.gd` | `NavProvider` 的连续实现，包 `NavigationServer3D`。给地形、路面、导入的建筑网格用。三件事和体素那份不同，都是**故意**的：①区域内全是 `Move.WALK`，多边形走廊没有「跨过了沟」这个概念，纵向通行只存在于手工布的 `NavigationLink3D`；②`stand_center()` 是恒等——连续地面没有格子中心可对齐；③查询靠「离网格多远」，所以水平和垂直**分开判**（垂直放宽到 3 m，否则上坡会被 `_void_between()` 读成悬崖）。还有一个 `_densify()`：把爬升超过体感台阶高度的腿切碎，否则执行器会把斜坡当台阶去爬。守着它的是 `tools/_probe_nav_mesh.gd` |
| `scripts/navmesh_test.gd` | 连续地图演示场景：斜坡 + 旋转的墙 + 圆柱，**没有任何方块**。烘焙时 `cell_height` 是关键参数——它决定烘出来的面比真实碰撞面高多少，而这个偏移会直接叠到每条腿的 dy 上，粗了会让 NPC 在平地上起跳。0.05 够用 |
| `scripts/npc_test.gd` | 人机测试场景：第一人称自由飞行搭建视角 + 准星 + 目标格高亮/放置预览，方块增删同步进 NavGrid，指挥人机寻路 |
| `scripts/follow_camera.gd` | 第三人称相机：站立自由看，移动锁背后 |
| `scripts/character_lod.gd` | 角色分层渲染。按相机距离分四档（近/中/远/隐），远处交给引擎的 `visibility_range` 剔除、关 `cast_shadow`、压 `lod_bias`，动画混合器改成手动推进并降频；离屏再单独降一档算力但**不动阴影**。挂载点只有一个：`PlayerController.setup()`。**只碰渲染和姿势求值，不碰 `_physics_process`、寻路和联网**，所以换档永远改不了玩法。headless 默认关闭 |

**武器那一层**（配置、行为树、编辑器）：

| 文件 | 职责 |
|---|---|
| `scripts/weapon_config.gd` | **格式的权威定义**。JSON 读写、继承合并、`normalise()` 修复。全静态，无状态 |
| `scripts/weapon_graph.gd` | 行为树运行时：现在播哪个节点，下一次按键把它变成什么。**不碰 AnimationTree** |
| `scripts/weapon_graph_editor.gd` | 场景内的编辑面板：全屏，左边是画出来的节点图（`NodeMap` 内部类，`_draw()` 手绘：框、按触发键上色的箭头、每个节点自己的时间轴带取消窗口），右边是选中节点的表单。只认一个 Dictionary，对外只发 `changed` 信号 |
| `scripts/weapon_test.gd` | 武器测试场景：世界 + 角色 + 三块面板 |
| `scripts/item_data.gd` | 运行时交接用的数据：模型、握姿、站姿、图 |
| `scripts/equipment_manager.gd` | 挂到插槽上、把站姿和图推给控制器。`equip_by_id()` 自动读盘 |
| `scripts/handheld_item.gd` | 把模型重锚成「握把在原点、刃朝 +Y」，再应用握姿 |
| `scripts/dash_beam.gd` | 冲刺特效之一：沿冲刺路径拉一条发光带（`ImmediateMesh` 两片交叉三角带），冲完自己淡掉自己释放。**不烘蒙皮**，headless 也能跑 |
| `scripts/dash_fade.gd` | 冲刺特效之二：角色淡出淡回。走 `GeometryInstance3D.transparency`，不碰 `material_override`，所以贴图材质全保住 |
| `scripts/trail_palette.gd` | 残影配色算法。全静态无状态。输入只有 `(色相, 展宽, 亮度, 寿命)`，输出芯色 / 两侧边色 / 渐变带 / 光源色。**"只设色系、其余自动"的全部实现都在这一个文件里** |
| `scripts/weapon_trail.gd` | 残影运行时：每帧采两个刃上锚点进环形缓冲，重建三排顶点的 `ImmediateMesh` 带，外加粒子和可选 `OmniLight3D`。挂在世界空间，顶点是全局坐标，自己 seal 自己释放 |

这一层的分层原则是**依赖单向**：`weapon_config` ← `weapon_graph` ← `player_controller`。
配置层不认识控制器，运行时层不认识 AnimationTree。所以那些时序规则能被
`tools/_probe_weapon_graph.gd` 在一秒内不开场景全部测掉。

`character.gd` 里那句 `skeleton.reset_bone_poses()` 不是可选的，见 README 踩过的坑第 9 条。
但 `player_controller.gd` 故意绕开它做淡入淡出，理由见同一条的例外段。

**这一层最值得知道的八件事**（前四条在 README 踩过的坑 10~13 条里有完整病历）：

1. **骨架朝 +Z**，不是 Godot 惯例的 −Z。所有转向集中在 `PlayerController` 一处。
2. **动作分原地和带位移两种**，混合树里只能放原地的 ——
   带位移的几个 clip 在 setup 时把横向位移烘掉了，整棵树不用 root motion。
   （常开 `root_motion_track` 会让角色失去胯部起伏而飘起来，而一棵树只有一个。）
   攀爬那两段连**竖直**位移也一起烘掉（`Flatten.ALL`）：台子多高是几何决定的，
   clip 不知道，留着它自己那 2 m 上升，人会停在台子上方一米。
3. **混合树里没法倒放 clip**，两种官方写法都静默失效。要倒放得自己烘
   （`gen/` 库）；站姿后退干脆用了真正倒着拍的 `standing_torch_walk_back`。
4. **混合空间必须开 `SYNC_MODE_CYCLIC_MUTABLE`**，否则不等长的 clip 会按拍频
   周期性地漂移 —— 斜着走每 4.6 秒「发癫」一次。
5. **动作层是一个 Transition，输入 0 是下面那整棵树。** 「什么都不做」当成一个
   状态，淡出就是白送的。输入 0 必须 `set_input_reset(0, false)`，
   整个节点必须 `sync = true`，两条都是静默出错型。
6. **三段落地 clip 都是「先掉两米再落地」。** 必须提前起播，提前量见
   `land_*_lead`，量法见 `tools/_probe_landing.gd`。落地那一刻才播 = 模型弹到天上。
7. **输入不在控制器里。** 控制器只读 `CharacterIntent`，谁填的它不管。
   加 bot 就是加一个 `IntentSource`，一行控制器代码都不用改。
8. **持械站姿是「静止时才全权接管」的一层。** 过滤混合（`weapon_stance`）只够到
   `Spine` 子树，够不着腿 —— 所以持械的**站姿由混合空间的 `idle` 极点顶替**
   （`set_weapon_locomotion()`），下半身才跟着变。而站姿层的权重不是常数：
   `_drive_animation()` 按 `_blend` 的模长把它从静止的 1.0 衰减到走起来的 0，
   否则跑步时手臂会被一张站姿定死。武器要带自己的走/跑动作就填
   `stance.walk_clip` / `run_clip`，留空则沿用空手的 `walk` / `sprint`。
   规则由 `tools/_probe_stance.gd` 守着。

场景是**代码建的**，`.tscn` 里只有一个挂着脚本的根节点。
这是刻意的：`anim_debug.tscn` 和它的生成器已经对不上了（见下面 E），
一份来源比两份好。

---

## 当前规模

**代码**（2026-08-04 重新统计）

| | |
|---|---|
| GDScript 总量 | **3,605 行 / 21 个文件** |
| 管线核心 | 1,265 行（35%）`anim_pipeline` + `character_pipeline` |
| 调试查看器 | 460 行（13%） |
| 一次性 & 诊断工具 | 837 行（23%） |
| 驱动/胶水 | 286 行（8%） |
| **游戏代码** | **870 行（24%）** menu + playground + controller + camera + character |
| README.md | 300 行 |

**资产**

| | |
|---|---|
| 角色 | 4 个（`hero` ~ `hero_3`，都是 AccuRig 导出） |
| 动作源文件 | 13 个（11 个 Mixamo FBX + 1 个 Godot 官方 GLB 包 + 1 个 CC 骨架 FBX） |
| 产出的动作剪辑 | **60 个**（大头是那个 GLB 包） |
| 支持的骨架类型 | 3 种（CC/AccuRig、Mixamo、Rigify DEF）+ 自动派生的命名空间变体 |
| 磁盘占用 | 47.7 MB，其中 `shared_animations.tres` 单文件 9.8 MB |

**这个规模意味着什么**：管线部分已经做完了。它处理了 3 种骨架、2 种文件格式、
命名空间变体、A-pose、单位换算、多网格身高测量、单动作 vs 打包动作命名 ——
这些是真实世界的资产会带来的**全部**常见麻烦。第 5 个角色和第 61 个动作不会再增加复杂度。

---

## 该不该精简？

**结论：不需要重构，但有大约 200 行是纯冗余，值得清掉。**

2,328 行对它做的事来说不算多。真正的问题不是「太大」，是**分布**：
97.5% 的代码在服务一条已经做完的管线，游戏本身还没开始。
所以下面的建议按「花多少时间换多少收益」排，别为了瘦身而瘦身。

### A. 直接删，零风险 —— **已完成（2026-08-03）**

| 目标 | 处理 | 为什么 |
|---|---|---|
| `assets/retarget/rigify_to_humanoid.tres` | 已删 | 孤儿。`AnimPipeline.BONE_MAPS` 里列的是 `rigify_def_to_humanoid.tres`，`gen_bone_maps.gd:211` 也只生成后者，全项目 0 个 `.import` 引用它。内容和在用的那份逐字节相同（只差一个 sub-resource id），且文件头没有 `uid=`，也无法被按 uid 引用 |
| `tools/_check_prefix.gd.uid`<br>`tools/list_rig.gd.uid` | 已删 | 对应的 `.gd` 早已不存在，`.uid` 残留 |
| `anyrouter.bat` | 已移到上一级目录 | 是启动 Claude CLI 的代理脚本，和这个 Godot 项目无关。没删掉是因为它还能用，只是不该躺在项目里 |

### B. 真正的重复代码，值得合并（半天，省 ~150 行）

这是唯一一处「同一段逻辑写了两遍」，而且两边都在长：

| 重复对 | 行数 | 重合度 |
|---|---|---|
| `AnimPipeline.configure()`<br>`CharacterPipeline.configure()` | 72 + 100 | 约 60 行**逐字相同**：silhouette 刷新 → probe → 骨架空检查 → 已重定向检查 → `PATH:` key → 已配置守卫 → detect → resolve → 清理旧 key → 写 bone_map → A-pose 判断。<br>差异只有：角色多写身高和多模型警告，动作多写 `trimming=false` |
| `AnimPipeline.rig_report()`<br>`CharacterPipeline.rig_report()` | 39 + 41 | 约 35 行结构相同，差异只是「按文件名报」还是「按角色 id 报」，以及角色多打一个导入身高 |

建议：抽一个 `AnimPipeline._configure_rig(cfg, res_path, probed) -> {changed, message, skel_cfg}`
做公共部分，两边各自在返回后追加自己那几行。`rig_report()` 同理抽一个 `_describe_rig()`。

**注意**：合并 `configure()` 时那个「已配置就返回」的守卫必须留在公共部分里 ——
现在它不再兼管 `root_scale`（身高走 `character.cfg`，见前面），但它仍然是
「骨架只判断一次」的唯一保障。角色那边还多一个分支：守卫命中之后要接着跑
`_apply_height()`，别在合并时把它吃掉。

### C. 小重复，顺手改（各 15 分钟）

- ~~**裸名解析**在 `capture.gd` 里自带了一份~~ —— 已收进 `Character.resolve()`，
  `capture.gd` 改用它了。
- **轨道绑定计数**仍写了两遍：`anim_debug.gd:186 _binding_line()` 和
  `capture.gd:71 _report_binding()`，同一套「数有多少轨道找得到骨头」，
  一个返回字符串一个直接 print。抽到 `AnimPipeline` 里返回 `{bound, total, unbound}`。
- **`inspect_model.gd` 自带 `_find_all()` 和 `_global_rest()`**，
  和 `AnimPipeline.first_of_class()` / `_global_rest()` 重复。
  `compare_rest.gd` 也自带一份 `_global_rest()`，同一个问题。

### D. 不要动

- **`anim_pipeline.gd` 里的长注释**。它的注释密度极高（695 行里相当一部分是注释），
  看着像可以删，但那些注释记录的是**已经踩过、并且看不出来的坑** ——
  脚趾枢轴、重定向之后就量不到身高、`.import` 的 key 是节点路径不是节点名。
  删掉注释省不下多少行，但下一个人会把坑重踩一遍。这是这个项目最贵的资产。
- **两套入口（插件 + bat）**。看着冗余，实际上是两个不同场景：编辑器开着 / 没开。
  合并不掉，因为 headless 下无法在单进程里重跑导入。
- **诊断工具（653 行）**。它们互相不依赖，也不参与主流程，留着不产生维护成本，
  下次遇到怪骨架时能省几个小时。真嫌乱就整体挪到 `tools/diagnostics/`。

### E. 真正该关心的，不是精简

- **`scenes/anim_debug.tscn` 已经和它的生成器对不上了。**
  `build_debug_scene.gd` 生成的 `Ground` 是单位变换，
  checked-in 的那份带着 `Transform3D(..., 0, -0.083, -2.02)`（有点倾斜和偏移）。
  README 说这个文件「自动生成、不要手改」，但它已经被手改过。
  现在跑一次 `build_debug_scene.gd` 会静默把这个改动抹掉。
  **要么承认它是手写文件从生成器名单里划掉，要么把改动写回生成器。**
- **`shared_animations.tres` 是 9.8 MB 的生成物，没进 `.gitignore`。**
  每次重建动作库都会产生一次 10 MB 级别的 diff。
  它是完全可从源文件重建的 —— 除非要出包，否则可以忽略掉。
- **管线做完了，游戏刚开了个头。** 移动那一层已经有了（`playground` / `player_controller`
  / `follow_camera` / `character_intent` / `intent_source` / `player_intent_source`）：
  走、跑、横移、蹲行、撞墙刹停、BlendSpace2D 混合、第三人称相机、碰撞，
  以及跳跃、攀爬（探测决定跳还是爬）、走下平台自动下落、按落差分三档的落地、双击翻滚，
  和一层「谁来做决定」的接口（bot 接这里）。
  武器那一层也有了：握姿、持械站姿、连招图，以及一个把它们存成文件的场景。
  接下来缺的是转身动作（库里有 `left_turn` 没接）、
  **伤害与受击**（`hit_chest` 在库里，行为树只管播哪个动作、什么时候能接下一个，
  判定框还没有）、把武器接进 `playground`、以及一个真正的关卡。
  在这些之前花时间瘦身管线，收益仍然是负的。
- **试玩场景是代码建的，没有生成器。** 这是上面那条 `anim_debug.tscn` 漂移问题的
  解法：`playground.tscn` 里只有一个挂脚本的根节点，世界在 `_ready()` 里建。
  想改布局改 `playground.gd`，没有第二份可以对不上。

---

## 加东西的时候改哪里

| 想做什么 | 改哪 |
|---|---|
| 支持新骨架（UE、Ready Player Me…） | 在 `gen_bone_maps.gd` 加一份字典 → 跑一次 → 把 `.tres` 加进 `AnimPipeline.BONE_MAPS`。**其他一行都不用改** |
| 只是命名空间不同的同款骨架 | 什么都不用做，`resolve_bone_map()` 自己派生 |
| 改某个角色的身高 | 该角色文件夹里的 `character.cfg`，改 `height`，跑一次管线。动作库不用动 |
| 改默认身高 | `CharacterPipeline.TARGET_HEIGHT_M`。只影响还没生成 `character.cfg` 的新角色 |
| 让某个角色重新测量身高 | 把 `character.cfg` 的 `measured_height` 改成 0，跑**两遍**管线 |
| 给角色加游戏逻辑 | `scripts/character.gd`，管线不会覆盖它 |
| 加动作后处理（根运动提取、循环点） | `AnimPipeline._harvest()`（`:653`），每个 clip 都经过这里 |
| 换调试场景的灯光/地面 | 先解决上面 E 里的漂移问题，否则改了会被抹掉 |
| **加一个新的角色动作** | `CharacterAnimRig.ACTIONS` 加一行（名字 / clip / 烘哪几轴 / 循不循环），树和 TimeScale 自动生出来；再加一个 `State` 和它的 `_drive_*()` |
| **配一把武器的握姿 / 站姿 / 连招** | 不改代码。进武器测试场景调，按 `S` 存到 `assets/combat_tools/configs/<武器名>.json`。站姿那三个下拉分别是静止 / 走 / 跑，后两个留空就沿用空手动作。面板用 `J`/`K`/`B` 开关，`L` 全关 |
| **往武器配置面板加一组设置** | `weapon_test.gd` 的 `_build_tuner()` 里加一句 `_fold(body, "标题", true)`，内容塞进它返回的 box。面板本身会滚，不用挪别的东西 |
| **加一个战斗按键槽**（比如 `dodge`） | `CharacterIntent.BUTTONS` 加一项 → `PlayerIntentSource.KEY_BUTTONS` 绑个键。配置里立刻能选，bot 走 `request_button("dodge")` |
| **给武器配置加一个字段**（比如判定框） | `WeaponConfig.defaults()` 加默认值 → `normalise()` 里补一行校验 → 消费方去读。老文件缺这个字段会自动被补上，不用迁移 |
| **让一招能边打边走** | 该节点把「锁移动」关掉。腿会回到 locomotion，上半身归挥击层，控制器按走速给移动（`attack_turn` 控转身快慢） |
| **让一招带冲刺** | 该节点填 `dash_distance`（米，上限 12）。快慢是控制器的 `dash_speed`（全局，默认 6 m/s），时间由 距离/速度 推出来，节点里没有自己的时钟。动作全程正常播，冲刺跑在它**里面**；冲不完的距离会被动作长度截掉，想冲更远就调 `dash_speed`。特效由 `dash_vfx` 选（无 / 光束 / 淡出淡回），武器测试面板「冲刺」组里能实时切 |
| **给一把武器配残影** | 不改代码。武器测试场景 `K` 面板的「残影」组，存在武器自己的 JSON 的 `trail` 块里。`base`/`tip` 是**沿刃长的归一化比例**不是米 —— `HandheldItem` 已经把每把武器重锚成「握把在原点、刃朝 +Y」，所以同一对数字换武器、改 `item_scale`、翻转 grip 全都自动跟着走。颜色只填 `hue` + `hue_spread`，其余由 `TrailPalette` 推。想让某一招不出残影就把该节点的 `trail` 关掉；想只在斩击那几帧出就填该节点的 `trail_window`（秒，`[0,0]` 是全程） |
| **调残影观感** | 立体感和渐变全在 `TrailPalette` 的五条常量里（`CORE_SAT_*` / `EDGE_*` / `CORE_ALPHA_GAIN` / `TAIL_WIDTH`），改那里对所有武器一起生效。**注意顶点色是 8 位、会在 1 处截断**：`energy` 不能走顶点色，它走 `WeaponTrail._refresh_material()` 里的 `albedo_color`。还有 `energy > 1` 要看得见就必须开 `Environment.glow_enabled`，两个场景的 `_build_environment()` 里都有 |
| **正式场景里装备武器** | `EquipmentManager.equip_by_id("Abyss Blade")`，配置自动从盘上读 |
| **调跨台阶的高度** | `PlayerController.step_max_height`（默认 0.4）。**三个数必须对齐**：烘焙的 `agent_max_climb` ≤ 它 ≤ `climb_min_height`。网格按 `agent_max_climb` 规划路线，身体按 `step_max_height` 执行，高于 `climb_min_height` 才轮到攀爬 —— 网格承诺得比身体能做的多，NPC 就会走进路缘石里再也出不来（那正是加这条规则之前的症状）。改完跑 `tools/_probe_step_up.gd` |
| **接 bot / 录像 / 联机** | 写一个 `IntentSource` 子类，赋给 `PlayerController.intent_source`。或者设成 `null`，直接调 `drive()` / `request_jump()` / `request_roll()` / `request_button()` |
| **加一种地图 / 寻路后端**（连续地形、navmesh） | 写一个 `NavProvider` 子类，`bind_nav_grid()` 给 NPC。执行器一行都不用改 —— 它只读 `find_path()` 返回的世界坐标和 `moves`。**参照实现见 `nav_mesh_provider.gd`**，那里记了三个踩过的坑：烘焙 `cell_height` 太粗会让 NPC 在平地起跳、垂直容差太紧会把上坡读成悬崖、路点太疏会被当成台阶去爬。两个还没解的：navmesh 上 `moves` 没有天然来源，跳跃段要靠 `NavigationLink3D` 手工标；`special_paths` 现在按 `Vector3i` 对索引，迁过去要改成按 link id。方格那套照旧走 `NavGrid`，两者互不影响 |
| **改假人**（武器测试场景 `F1`） | 血量 / 受击胶囊 / 韧性 / 特效寿命都是 `DummyTarget` 的常量。**受击 clip 名必须是动画库的 key（snake_case，如 `hit_chest`），不是 `.tres` 里的 `resource_name`（`Hit_Chest`）** —— 写错了 `resolve()` 返回空，身体会一直停在 rest pose 上。反应分三档：轻打 `hit_head`/`hit_chest`，韧性（`KNOCKDOWN_POISE`，按伤害累积、按 `POISE_RECOVERY` 回复）打破才播倒地 `hit_knockback`，倒地必须接起身 `lay_to_idle`，否则人会瞬间弹起来。所有转场都要给 `Character.play()` 传 blend 时间。**加新反应 clip 前先跑 `tools/_probe_reactions.gd`** 看它对髋高做了什么 —— 库里 `hit_knockback` 是倒地不是踉跄 |
| **改假人的判定** | `weapon_test._check_dummy_hit()`：刀刃两个 anchor 连成的线段（加 `BLADE_PAD` 厚度）vs 假人胶囊，**按接触上升沿计数，不是按 stroke** —— 一个 clip 里劈三下就该判三次。另外补测了上一帧刀尖到这一帧刀尖的扫掠段，防止快刀一帧跨过胶囊。改完跑 `tools/_probe_dummy.gd` |
| **换掉某段落地 clip** | 换完跑 `tools/_probe_landing.gd`，把新的 `t(min)` 填进对应的 `land_*_lead` |
| 改试玩场景里能爬 / 能摔的几何体 | `playground.gd` 的 `_build_parkour()` |
| **调角色分层渲染的档位** | `CharacterLOD` 的导出参数：`near_end` / `mid_end` / `cull_end` 是档界（米），`mid_hz` / `far_hz` 是各档动画推进频率，`shadow_tier` 是最后一个还投影的档，`offscreen_tier` 是离屏降到哪一档。改完跑 `tools/_probe_character_lod.gd` |
| **给某个不走 `PlayerController` 的角色也分档** | `CharacterLOD.attach(visual)`，第二个参数留空就自己找 AnimationTree / AnimationPlayer。重复调用只会 rescan，不会挂第二个 |
| **临时全关分层渲染做对比** | `CharacterLOD.set_enabled(false)`，会把每个角色恢复成 `attach()` 时的样子。单个角色钉死某一档用 `lod.forced = CharacterLOD.Tier.FAR` |

## 别碰的四条线

1. `AnimPipeline.body_height()` 只能用在**重定向之前**的模型上 —— 之后骨架被
   `fix_silhouette` 掰成 T-pose 而网格没动，两者形状不再一致，排名法失效。
   函数里有个 `RETARGETED_SKELETON` 的挡板，别拆。
2. `AnimPipeline.SILHOUETTE_EXCLUDED` 里的 `LeftFoot`/`RightFoot` —— 只留脚趾没用，
   要压平脚趾的是脚踝那根骨头。
3. `.import` 里的 skeleton key 必须是 `PATH:<节点路径>` —— 写成节点名 Godot 会**静默忽略**，
   一切看着正常但轨道绑不上。
4. 武器动作槽是**启动时一次性预留**的（`CharacterAnimRig.WEAPON_SLOTS`），装备时只往
   槽里写 clip。别改成按需增删 —— 改 `AnimationNodeTransition.input_count` 会重建全部
   输入，把正在播的姿势打回原点，于是每次拔刀角色都会抖一下。上限的代价就是从这来的。
   槽在**挥击层**（`swing`）上，不在动作层上：动作层整份替换姿势，那对跳跃是对的、对
   出招是错的 —— 一个允许移动的招必须把腿留给 locomotion，否则人会贴着地平移。哪半边
   归挥击层是 `swing_blend` 过滤器的事，按节点在 `_begin_weapon_action()` 里选一次，
   不逐帧改（中途换过滤器会让腿从一个姿势瞬跳到另一个）。

**另外：不要手改 `.import`。** 它是解析格式，一处改坏 Godot 会静默把整份参数重置成
默认值 —— 包括把 `fbx/importer` 从 ufbx(0) 换成需要外部程序的 FBX2glTF(1)，
然后导入直接失败。要重新测量走 `measured_height = 0`。
