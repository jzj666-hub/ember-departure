# Project Rules

## Code Index (read first)
必读 `./CODEMAP.md` —— 实现任何功能前先检索,禁止重复实现已有能力。
- 「重复实现警告」表中的函数已被复制 3 份以上,不要再加第 N+1 份。
- 「高扇入服务层」的公开签名是契约,改前先看依赖方清单。
- 新脚本必须以 `##` 文档注释开头,否则不会进索引。
- 结构变动后重跑:`godot --headless --path . --script res://tools/gen_codemap.gd`

## Commenting Guidelines
- **Target Audience**: AI agents and LLMs only. Do NOT write comments for human programmers.
- **Style**: Extremely concise, telegram-style, and declaration-oriented.
- **Content**: Include only function/variable purposes, structural invariants, and pre/post-conditions.
- **Avoid**: Architectural justifications, design debates, tutorials, historical context, and wordy narratives.
