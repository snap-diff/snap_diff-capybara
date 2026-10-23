# Architecture Decision Records (ADR)

An Architecture Decision Record (ADR) captures an important architecture decision along with its context and consequences.

## Conventions

- Directory: `adr`
- Naming:
  - Use date-prefixed files: `YYYY-MM-DD-choose-database.md`
  - If the repo already uses slug-only names, keep that: `choose-database.md`
- Status values: `proposed`, `accepted`, `rejected`, `deprecated`, `superseded`

## Workflow

- Create a new ADR as `proposed`.
- Discuss and iterate.
- When the team commits: mark it `accepted` (or `rejected`).
- If replaced later: create a new ADR and mark the old one `superseded` with a link.

## ADRs

- [Adopt architecture decision records](2026-10-23-adopt-architecture-decision-records.md) (accepted, 2026-10-23)
- [Review PR screenshots on a sign-in review page backed by a self-hosted GitHub App and Worker](2026-10-23-review-screenshots-on-a-sign-in-page.md) (proposed, 2026-10-23)
- [Ship review setup as a gem executable](2026-10-23-ship-review-setup-as-a-gem-executable.md) (proposed, 2026-10-23)