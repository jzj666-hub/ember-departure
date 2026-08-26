# CLAUDE.md

## Codebase Navigation

Do NOT bulk-read index files. Grep on demand — every script opens with a `##` docstring stating its
responsibility, so search finds it. Every new script MUST open with such a line; it is the search hook.

Recipes (ripgrep):
- capability by keyword: `rg -n "^##.*<keyword>" scripts/`
- list all responsibilities in a subtree: `rg -n "^##" scripts/<dir>/`
- fan-in of a type: `rg -n "\b<ClassName>\b" scripts/` or `rg -n "<script_path>" scripts/`
- existing impls of a function: `rg -n "func <name>" scripts/`

Before adding a helper that sounds generic (`_build_hud`, `_build_ui`, `_make_wire_cube`,
`_spawn_character`, `setup`, `reset`, …), grep `func <name>` first — several already exist in
multiple copies. Reuse or ask; do not add copy N+1.

`CODEMAP.md` is an on-demand generated report (full script table, duplicate-impl counts, fan-in
ranking), NOT required reading. Consult it only when a broad structural question needs it.
Regenerate manually when wanted: `godot --headless --path . --script res://tools/gen_codemap.gd`

## Comment & Doc Style (mandatory, all files)

Audience: AI agents / LLMs only. Never write comments for human programmers.

Style: extremely concise, telegram-style, declaration-oriented.

Include only:
- function / variable purpose
- structural invariants
- pre-conditions / post-conditions

Exclude: architectural justification, design debate, tutorial, historical context, changelog notes, wordy narrative.

Examples:
```
// GOOD
// dash(): applies impulse along facing. Pre: stamina>=DASH_COST. Post: state=DASHING, stamina-=DASH_COST.
// hitboxes[]: active only during frames [startup, startup+active). Invariant: len == len(hurtboxes).

// BAD
// We chose an impulse here instead of velocity-set because it composes better with
// gravity, and historically the velocity-set version caused the player to feel floaty...
```
