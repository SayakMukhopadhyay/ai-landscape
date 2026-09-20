# AI Landscape

My version-controlled personal AI setup for Codex. It currently contains custom agents and the Improve skill, with room to add more shared skills and configuration over time.

The repository is the source of truth. A bootstrap script connects its contents to the personal Codex configuration directory with Windows directory junctions, so edits are immediately available to Codex while remaining tracked in Git.

## Included setup

- `agents/` contains the personal `researcher`, `implementer`, `developer`, `reviewer`, `specialist`, and `expert` agents.
- `skills/` contains personal Codex skills, currently Improve.
- `scripts/Connect-CodexSetup.ps1` connects the repository-owned directories to the corresponding personal Codex paths.

## Connect to Codex on Windows

Close Codex, then run the bootstrap script from a separate PowerShell window. Codex can keep the existing agent directory open while it is running, which prevents Windows from replacing that directory with a junction.

```powershell
.\scripts\Connect-CodexSetup.ps1
```

It creates these junctions:

```text
%USERPROFILE%\.agents\skills   -> <repository>\skills
%CODEX_HOME%\agents            -> <repository>\agents
# or %USERPROFILE%\.codex\agents when CODEX_HOME is unset
```

When `CODEX_HOME` is not set, the script uses `%USERPROFILE%\.codex` for the agents junction. Running it again against the correct junctions is a no-op. If a destination already exists and is not the expected junction, the script stops without changing it; remove or relocate that path yourself before rerunning the script.

Start a new Codex session after changing agent definitions. Codex loads personal custom-agent TOML files from `~/.codex/agents/` for newly created sessions, as described in the [official OpenAI documentation](https://developers.openai.com/es-419/docs/agent-configuration/subagents#app-custom-agents).

## Improve

Improve is a Codex agent skill that audits any codebase and writes implementation plans for the configured custom agents to execute.

The idea: use your most capable model for the part where intelligence compounds — understanding the codebase, judging what's worth doing, writing the spec — and hand execution to cheaper models. The skill never implements anything itself. The plan is the product.

```
you          →  $improve                    (advisor plans and vets)
plans/       →  001-fix-n-plus-one.md       (self-contained specs)
custom agent →  implements, tests, reviews  (role-routed, cost-aware)
```

This personal adaptation is tuned for Codex with the custom `researcher`, `implementer`, `developer`, `reviewer`, `specialist`, and `expert` agents configured globally. It is maintained for local use rather than packaged or published for installation. Each agent's model and reasoning choices live in its repository-owned TOML file; the skill routes by role. The plans it writes are plain markdown, so any agent or human can still pick them up.

Based on [shadcn/improve](https://github.com/shadcn/improve), with the Codex and agent-routing adaptation maintained by Sayak Mukhopadhyay.

### Usage

```
$improve                        full audit → prioritized findings → plans
$improve quick                  cheap pass: hotspots, top findings only
$improve deep                   exhaustive: every package, every category
$improve security               focused audit (also: perf, tests, bugs, ...)
$improve branch                 audit only what the current branch changes
$improve next                   feature suggestions — where to take the project
$improve plan <description>     skip the audit, spec one thing
$improve review-plan <file>     critique and tighten an existing plan
$improve execute <plan>         dispatch a role-matched executor, review its work
$improve reconcile              refresh the backlog: verify, unblock, retire
$improve ... --issues           also publish plans as GitHub issues
```

### How to use

A typical first run, start to finish:

1. Open Codex in the repo and run `$improve` (or `$improve quick` to keep it cheap).
2. It maps the repo, audits it, and comes back with a findings table. Reply with the ones you want planned — "plan 1, 3 and 5".
3. Plans land in `plans/` — one file each, plus an index with the recommended order. Read them; they're meant to be reviewed.
4. Hand a plan to any agent ("implement plans/001-*.md"), or let the skill run it: `$improve execute 001`. It chooses `implementer` for mechanical work or `developer` for work requiring normal engineering judgment. Only work that inherently needs deep technical reasoning can escalate to `specialist`, after refining the plan where possible. Execution stays in the current checkout, leaves edits unstaged, and preserves unrelated dirty work while the advisor reviews the diff against the plan.
5. Next session, run `$improve reconcile` to clean up the backlog: verify what landed, refresh what drifted, unblock what got stuck.

Before a PR, `$improve branch` does the same thing scoped to just what your branch changes.

### Example

A run against [shadcn/ui](https://github.com/shadcn-ui/ui) came back with findings like:

```
| # | Finding                                        | Category  | Effort | Confidence |
|---|------------------------------------------------|-----------|--------|------------|
| 1 | shadow-config duplicated in search.ts/view.ts, | tech-debt | M      | HIGH       |
|   | copies already drifted (TODO at search.ts:31)  |           |        |            |
| 2 | O(n²) icon migration (migrate-icons.ts:168)    | perf      | S      | HIGH       |
```

…and rejected a few, with reasons recorded so they don't come back next run:

```
- [SEC-01] https_proxy env var "SSRF": by-design — standard proxy convention,
  every CLI honors it. Not a finding.
```

Picking #1 produced [this plan](./examples/001-extract-shadow-config-resolution.md) — current code excerpted, exact steps, the repo's own test/lint commands as verification gates, and STOP conditions for when reality doesn't match.

### How it works

**Recon.** Maps the repo: stack, conventions, and the exact build/test/lint commands — these become verification gates in every plan. It also ingests intent and design docs when present — ADRs (`docs/adr/`), PRDs, `CONTEXT.md`, `DESIGN.md`, `PRODUCT.md` — so decided tradeoffs aren't re-flagged as findings, direction suggestions stay grounded in stated product intent, and plans speak the repo's own vocabulary. Composes with any repo that already maintains these docs.

**Audit.** Fans out parallel read-only `researcher` agents across nine categories: correctness, security, performance, test coverage, tech debt, dependencies & migrations, DX, docs, and direction (feature suggestions — every one must cite evidence from the repo itself, no generic idea-slop). Difficult targeted questions can escalate to `specialist` or, exceptionally, read-only `expert`. Every finding carries `file:line` evidence, impact, effort, and confidence.

**Vet.** Subagents over-report, so the advisor re-reads every cited location itself before showing you anything — false positives get dropped, wrong attributions get corrected, rejections get recorded.

**Prioritize.** Findings land in a table ordered by leverage (impact ÷ effort, weighted by confidence). You pick what becomes plans.

**Plan.** One file per selected finding, written into `plans/` with an index, priority order, and dependency graph.

### What makes the plans executable

Plans are written for the weakest plausible executor — a model that has never seen the advisor session and may be much smaller. Three properties carry that:

- **Self-contained.** All context is inlined: exact file paths, current-state code excerpts, repo conventions with an exemplar file, verified commands. No "as discussed above."
- **Verification gates.** Every step ends with a command and its expected output. Done criteria are machine-checkable. The executor never has to judge whether it succeeded.
- **Hard boundaries.** Explicit out-of-scope lists, and STOP conditions — "if X, stop and report" — instead of letting a small model improvise when reality doesn't match the plan.

Each plan also stamps the git commit it was written against, so executors run a mechanical drift check before touching anything.

### Closing the loop

Plans aren't fire-and-forget:

- **`execute <plan>`** works in the current checkout, routes a complete plan to `implementer` or a judgment-heavy bounded plan to `developer`, and escalates to `specialist` only when execution inherently requires deep technical reasoning and plan refinement cannot remove that need. It refuses overlapping dirty paths, snapshots unrelated user changes, leaves source edits unstaged, and independently uses `reviewer` when the change warrants it. Verification is limited to non-mutating commands; installs, builds, formatters, codegen, migrations, or write-capable tests require explicit approval for their exact write scope. The advisor checks scope and reads the diff against intent before approving, revising, or blocking.
- **`reconcile`** processes what happened since: verifies DONE plans still hold, investigates BLOCKED ones and rewrites around the obstacle, refreshes drifted plans, retires findings that got fixed independently.
- **`--issues`** publishes plans as GitHub issues — same self-contained body, so any agent or human can pick them up where work already lives.

### Hard rules

- Never modifies source code itself. The only direct writes go to `plans/`; `execute` delegates approved source edits in the current checkout and leaves them unstaged for you to review.
- Outside explicit `execute`, it runs read-only analysis only. During `execute`, file edits are limited to the plan's clean, approved paths; potentially mutating verification commands require separate explicit approval for their exact write scope.
- Never reproduces secret values. Locations and credential types only, rotation always recommended.
- Asked to implement? It declines and points at the plan (or offers `execute`).

## License

[MIT](./LICENSE.md). Original work © 2026 shadcn; Codex adaptation © 2026 Sayak Mukhopadhyay.
