# CLAUDE.md

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
