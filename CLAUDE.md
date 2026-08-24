# CLAUDE.md

## Before Writing Any New Code (mandatory)

Read `CODEMAP.md` first — it indexes every script: path, lines, `class_name`, fan-in/fan-out, one-line responsibility.

- Search it for the capability you are about to build. If it exists, reuse it. Do not re-implement.
- 「重复实现警告」 table = functions already copy-pasted 3+ times with no inheritance relation. Adding copy N+1 is an error; extract a shared implementation instead.
- 「高扇入服务层」 = load-bearing public signatures. Read the dependent list before changing one.
- Every new script MUST open with a `##` docstring line. That line is its CODEMAP entry; without it the script is invisible to search.

Regenerate after adding/removing/renaming scripts:
`godot --headless --path . --script res://tools/gen_codemap.gd`

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
