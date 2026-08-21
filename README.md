# 灰烬:启程 — 角色与动作管线

Godot 4.7 项目。采用 ActorCore / AccuRig 自动绑定模型，通过重定向适配 Mixamo 与 Rigify 动作资产。

---

## 🎮 核心场景与运行

*   **主入口**：`scenes/main_menu.tscn` (按 **F5** 运行)。
*   **动作调试场景** (`scenes/anim_debug.tscn`)：同步播动作，检查骨骼重定向和高度比例。
*   **第三人称试玩场景**：操纵角色进行移动、攀爬及落地测试。
*   **武器测试场景**：调整武器握持偏移、stance 姿势、刃上残影，并调优连招时序行为树。
*   **人机操控与寻路测试场景** (`scenes/npc_test.tscn`)：搭方块、指挥人机寻路，或按 `E` 直接寄身操控它。

---

## 🕹️ 核心操作与输入逻辑

*   **常规移动**：`W/A/S/D`（S 倒走使用专门的倒放动作）。
*   **奔跑**：单按 `W` 时按住 `Shift`。
*   **蹲行**：按住 `Ctrl`。
*   **跳跃/攀爬**：按 `Space`。由探测器动态选择：前方有适高悬崖则攀爬，否则跳跃。
*   **刹停**：高速度撞墙触发 `run_to_stop` 动画。
*   **翻滚**：双击 `Shift`。
*   **武器攻击**：左键 `attack`，右键 / `Q` 重击（非沉浸时右键**单击**是重击、**按住**是转视角；沉浸模式下视角已经是自由的，右键直接就是重击），`E` 特殊，`X` 格挡。按键只有在武器配置里给它写了入口才有反应 —— 基线 `_default.json` 给了 `attack` 和 `heavy` 两个。
*   **武器测试场景的面板**：`J` 武器列表，`K` 武器配置，`B` 行为树（全屏节点图，点节点选中它），`L` 沉浸模式（全关面板 **并锁定鼠标**，移动鼠标直接转视角，不用按住右键；再按 `L`、或按 `J`/`K`/`B` 开任一面板即退出并交还光标）。
*   **刃上残影**：`K` 面板的「残影 / Trail」组。勾上「开启残影」，刃上会出现两个小球标出光源段的近端和远端，拖 `近端`/`远端` 让它们沿刃滑。颜色只设一个**色系** —— 点「余烬 / 霜蓝 / 虚空 / 血红 / 圣金 / 剧毒」任一预设，或自己拖 `色相` 和 `展宽`；亮芯、彩边、沿寿命的色相分离和收窄全部由算法推出来，上面那条色带就是它推出来的结果。`亮度` 超过 1 才会被 glow 拾取到（HDR 过曝）。`刃速` 是门限：低于它的帧不落点，所以起手抬刀不拖光、只有真正的斩击段亮。`光源` 大于 0 会在刃上挂一盏真的 `OmniLight3D`，照亮地面和角色。这一组跟着武器存进它自己的 JSON。
*   **人机测试场景的搭建视角**：默认是**第一人称自由飞行**（鼠标已锁定）。鼠标转视角，`WASD` 飞行，`空格`/`Ctrl` 升降，`Shift` 加速，`滚轮` 调飞行速度。屏幕中心有准星，指到的方块画黄色线框、将要放置的那一格画半透明蓝框 —— **落块必定落在预览那一格**。`左键` 放置，`右键` 拆除，`中键`（或 `Shift+左键`）指定人机目的地。按住 `Alt` 临时松开鼠标去点面板，松手自动收回。`E` 在搭建视角和寄身操控之间切换，`Tab` 换角色。
*   **人机寻路**：路线按角色**真实的物理能力**规划，阈值全部从 `PlayerController` 的导出参数推导而来，没有写死的常数 —— 跳跃顶点由 `jump_speed²/2g` 得出（约 1.13 m），爬升上限取 `climb_max_height`（2.2 m），站立净空取 `_stand_height`。所以 1 格和 2 格的台阶会爬，**3 格的墙会绕开**；桥洞下面照样能走过去。代价按**秒**计，绕 4 米比爬一次（1.5 s）便宜时它就绕。路线上不同的走法用颜色区分：绿=走，橙=爬，黄=跳，蓝=落差。目标够不到时会走到最近的可达点并在 HUD 说明。走着走着被挡住，会沿墙面切向绕出去，绕不出去就重算路径。
*   **解耦设计**：
    *   输入决策封装在 `CharacterIntent` 中，由 `IntentSource`（玩家为 `PlayerIntentSource`）每帧填充，控制器 `PlayerController` 仅读取 intent 并执行规则。

---

## 🛠️ 资产管线与添加说明

管线自动化工具支持全自动角色重定向、高度归一化和动作库构建。

### 1. 添加角色
1. 在 `assets/characters/` 下新建以角色 id 命名的文件夹（如 `assets/characters/bandit/`）。
2. 将导出的 `.fbx`、`.json` 及 `textures/` 丢入其中。
3. 打开 Godot 编辑器或运行 `tools/rebuild_assets.bat` 自动生成包装场景 `<id>.tscn`。
4. 如需定制身高，编辑文件夹下的 `character.cfg`（设置 `height`）。

### 2. 添加动作
1. 共享动作放入 `assets/animations/source/`。
2. 角色专属动作放入 `assets/characters/<id>/animations/`。
3. 运行管线，动作将自动重定向至 `SkeletonProfileHumanoid` 并生成动作库。

---

## 💻 命令行测试工具

*   **完整构建管线**：运行 `tools/rebuild_assets.bat`。
*   **武器连招时序规则测试**：`godot --headless --script tools/_probe_weapon_graph.gd`
*   **武器场景交互测试**：`godot --headless --script tools/_probe_weapon_scene.gd`
*   **持械站姿分层测试**：`godot --headless --script tools/_probe_stance.gd`
*   **原始身高比例测量**：`godot --headless --path . --script tools/measure_scale.gd`
*   **角色绑定姿势差异比对**：`godot --headless --path . --script tools/compare_rest.gd`
*   **寻路规则回归**：`godot --headless --path . --script res://tools/_probe_nav_grid.gd` —— 纯逻辑，验证爬升/落差上限、体素化（桥洞）、头顶净空、禁止穿角、不可达回退，外加重建与搜索耗时。
*   **人机寻路实跑**：`godot --headless --path . --script res://tools/_probe_npc_nav.gd` —— 真跑场景，验证人机能翻过可爬的墙、穿过隧道、绕出 L 形凹角、被封死时如实上报。
*   **角色分层渲染**：`godot --headless --path . --script res://tools/_probe_character_lod.gd` —— 距离分档与粘滞、各档往网格和混合器写了什么、隐档姿势是否真冻结、关掉之后是否原样还原。

---

## 📂 项目结构目录

*   `addons/anim_pipeline/`：重定向和资源管线编辑器插件。
*   `assets/characters/<id>/`：角色源文件、生成场景 `.tscn` 及专属动作库。
*   `assets/animations/source/`：共享动作源文件。
*   `assets/combat_tools/configs/`：武器 JSON 配置，`_default.json` 为连招及握持基线。
*   `assets/retarget/`：骨骼重定向映射 `.tres` 模版。
*   `scripts/character.gd`：角色组件逻辑入口，不被管线覆盖。
*   `scripts/player_controller.gd`：Locomotion、状态机与运行时 AnimationTree 构建/驱动。
*   `scripts/character_lod.gd`：角色分层渲染。按相机距离和是否在画面里分四档，远处交给引擎剔除、关阴影、降动画推进频率。
*   `scripts/nav_grid.gd`：体素寻路图，通行规则全部由 `PlayerController` 的能力参数推导。
*   `scripts/npc_intent_source.gd`：bot 的决策源，跟随寻路计划并处理攀爬、绕障与卡死重算。
*   `scripts/weapon_config.gd`：武器 JSON 配置读写、合并继承与规范修复。
*   `scripts/weapon_graph.gd`：武器动作连招行为树运行时（解耦纯逻辑）。
