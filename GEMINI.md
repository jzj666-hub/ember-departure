# Project Rules

## Codebase Navigation & Access Restrictions
- 不要整体读索引文件。按需 grep —— 每个脚本开头都有 `##` 职责注释,搜索即可命中。
- 新脚本必须以 `##` 注释开头,它是检索抓手。
- **严禁擅自扫描或递归读取 `assets/` 目录**。除非用户明确要求访问指定资产文件。
- 按能力找脚本:`Select-String -Path "scripts\*\*.gd" -Pattern "^##.*<关键词>"`
- 查已有实现:`Select-String -Path "scripts\*\*.gd" -Pattern "func <name>"`

新增通用名辅助函数前(`_build_hud`/`_build_ui`/`_make_wire_cube`/`_spawn_character`/`setup`/`reset` 等),
先查已有实现 —— 已有多份副本,复用或询问,不要再加第 N+1 份。

`CODEMAP.md` 是按需生成的报告,**非必读**。仅在需要回答宏观结构问题时查阅。

## Skill Architecture & Development
- **技能完全解耦独立**：技能模块置于 `scripts/skills/skill_<name>.gd`，保持自包含与高内聚，不横向耦合非必要系统或外部沙盒。
- **用户自测原则**：实际运行测试由用户完成，Agent 编写/重构代码后无需自行编写额外测试脚手架或运行多余测试脚本。

## Commenting Guidelines
- **Target Audience**: AI agents and LLMs only. Do NOT write comments for human programmers.
- **Style**: Extremely concise, telegram-style, and declaration-oriented.
- **Content**: Include only function/variable purposes, structural invariants, and pre/post-conditions.
- **Avoid**: Architectural justifications, design debates, tutorials, historical context, and wordy narratives.
