# ADR 0001: Screenshot Preparation Plugins (Deferred)

Date: 2026-04-14
Status: Deferred

## Context

We added more pre-capture steps for stable screenshots, including:
- DOM normalization CSS
- Font readiness waits
- Animation disabling
- Caret hiding
- Custom CSS and JS injections

The number of knobs and prep steps is growing. A plugin pipeline could make
ordering explicit and allow app-level extensions without monkey-patching.

## Decision

Defer a plugin system for now.

We will keep the simple `configure_consistency` API plus existing flags as
aliases. This provides a single entry point and keeps complexity low.

## Consequences

Benefits:
- Minimal code and API surface
- Easy onboarding for new users

Costs:
- Prep order is still encoded in `Screenshoter`
- Extensibility is limited to CSS/JS injections and flags

## Revisit Criteria

Re-open this decision when:
- We need more than one custom preparation step per app
- We add two or more new prep steps beyond CSS/JS injection
- Prep ordering or conditional logic becomes hard to reason about

## Next Refactoring Ideas

If revisited, implement a lightweight pipeline:
- `plugins` list with callables
- Context object with `inject_css`, `inject_js`, `wait_for_fonts`, and `session`
- Built-in plugins for existing steps, mapped from current flags
