# Closing the Loop — execute, reconcile, issues

The advisor's job doesn't end at the plan. This file covers the three follow-through flows: dispatching an executor and reviewing its work (`execute`), keeping the plan backlog alive (`reconcile`), and publishing plans where work gets picked up (`--issues`).

The founding rule survives unchanged: **the advisor never edits source code.** In `execute`, a *separate executor subagent* edits only the plan's approved paths in the current checkout; the advisor dispatches, reviews, and renders a verdict. Improve never creates a worktree and never stages, commits, merges, pushes, switches branches, or stashes.

---

## `execute <plan>` — dispatch and review

### Preconditions (check all before dispatching)

- The repo is a git repository (safe drift, scope, and dirty-state checks require it). If not: stop and say so.
- The plan file exists and its dependencies show DONE in `plans/README.md`. If not: stop, name the missing dependency.
- Run the plan's drift check yourself. If in-scope files changed since `Planned at`, reconcile the plan first (see below) — don't hand a stale plan to an executor.
- Run `git status --short -- <in-scope paths>`. If any in-scope path is modified, staged, or untracked, stop and ask the user to resolve the overlap; never stash or overwrite it.

### Dispatch

Do not create a worktree. Resolve the canonical absolute path of the current checkout and bind the executor to it. Before dispatch, snapshot enough state to distinguish the executor's changes from the user's existing work:

- `git status --short` for the complete checkout.
- The unstaged tracked patch (`git diff --binary`) and staged patch (`git diff --cached --binary`) separately.
- The path and content hash of every pre-existing untracked file.
- The output of `git status --porcelain=v1 -- plans/README.md`. Any nonempty entry — staged, unstaged, or untracked (`??`) — means the index is user-owned dirty state and must not be created, overwritten, or updated during this execution.

Unrelated dirty state may remain, but it belongs to the user. The executor must not modify, delete, stage, or otherwise normalize any pre-existing change. If the plan overlaps dirty paths, do not dispatch.

Choose **one** executor by the work the plan still requires:

- `implementer` — default for a complete, mechanical plan with explicit files, code shape, tests, and verification gates.
- `developer` — use when the plan is bounded but execution still needs normal engineering judgment, coordination across related modules, or adaptation among established repository patterns.
- `specialist` — only when successful execution inherently requires deep reasoning about architecture, algorithms, concurrency, distributed systems, performance, or subtle cross-system behavior. Prefer refining an ambiguous plan before escalating.
- Never use `researcher`, `reviewer`, or `expert` as the editing executor. Do not override the selected custom agent's globally configured model or reasoning settings.

Spawn the selected agent with ownership of only the plan's in-scope files. Pass the canonical checkout path explicitly. Require every shell/tool call to set that path as its working directory and every edit to target an approved in-scope path beneath it; inherited current-directory state is never sufficient. Tell it that other agents and user edits may be active and it must not revert or alter their work.

The subagent prompt must contain:

1. **The full plan file text, inlined.** Subagents do not inherit the advisor's context. Never assume they have read the plan merely because it exists in the checkout.
2. The executor preamble:

> You are the executor for the implementation plan below. Follow it step by
> step. Run every verification command and confirm the expected result before
> moving on. Touch only the files listed as in scope. If any STOP condition
> occurs, stop immediately and report. Do not improvise around obstacles.
> Override the plan's git workflow: do not create a worktree, switch branches,
> stash, stage, commit, merge, push, or open a PR. Leave approved edits
> unstaged in the current checkout for the user to review. Also SKIP the plan's
> instruction to update `plans/README.md` — your reviewer maintains the index.
> Run a verification command only when it is demonstrably non-mutating to the
> checkout and user data, or every possible write target is a clean path in the
> plan's approved scope. Before an install, formatter, build, code generator,
> migration, or write-capable test, STOP and report the command and its exact
> possible write paths so the user can explicitly authorize it. Do not infer
> that a command is safe merely because its usual outputs are ignored by Git.
> Before reporting, audit every claim in
> your report against an actual tool result from this session — only report
> what you can point to evidence for; if a verification failed or was
> skipped, say so plainly. Work only in the supplied checkout and approved
> in-scope paths, and do not revert or overwrite existing changes. Before any edit,
> run `git rev-parse --show-toplevel` from the explicitly supplied working
> directory and STOP if the result is not the supplied canonical checkout
> path. Set that working directory on every command and use only absolute file
> paths from the plan's in-scope list for edits. When finished, reply with exactly the report
> format below.

3. The report format:

```
STATUS: COMPLETE | STOPPED
STEPS: per step — done/skipped + verification command result
STOPPED BECAUSE: (only if STOPPED) which STOP condition, what was observed
FILES CHANGED: list
NOTES: anything the reviewer should know (deviations, surprises, judgment calls)
```

### Review (the advisor's real job here)

Review like a tech lead reviewing a PR against the spec — never fix anything yourself:

1. **Re-run safe done criteria** in the current checkout. Don't trust the executor's report, but apply the same command-safety boundary as the executor. Run a criterion only if it is demonstrably non-mutating to the checkout and user data or all possible writes are confined to clean, approved paths. Otherwise obtain explicit user approval for the exact command and write scope; if an essential criterion remains unauthorized, render BLOCK rather than silently treating it as passed.
2. **Scope and index compliance**: compare the post-execution status, unstaged patch, staged patch, and untracked-file hashes with the pre-dispatch snapshot. Every new content change must be inside the plan's in-scope list. The staged patch must be byte-for-byte unchanged: newly staging a change or unstaging a pre-existing change fails review even when the path is in scope. Any executor-caused content change outside scope also fails review, full stop.
3. **Read the full diff.** Judge it against "Why this matters" (does it solve the actual problem?) and the repo conventions named in the plan (does it look like the rest of the codebase?).
4. **Audit the new tests.** Executors game criteria — a test that asserts nothing meaningful passes `pnpm test` and proves nothing. Read what the tests assert.
5. **Independent review when warranted.** For meaningful changes, spawn a fresh-context `reviewer` against the current checkout. Give it the plan, base revision, canonical checkout path, pre-dispatch snapshot, and executor diff; ask only for substantive correctness, regression, security, concurrency, edge-case, and test-coverage findings. Explicitly require read-only review: no file edits, fixes, formatting, installs, staging, commits, branch changes, stashing, or other Git mutations. Require every command to use the supplied checkout as its working directory. Verify its findings yourself. For a trivial mechanical change, skip this when the independent pass would add no useful confidence.
6. **User-work integrity**: verify that every pre-existing tracked patch and untracked-file hash is unchanged outside the plan's scope. Investigate any delta before rendering a verdict; never clean, reset, or otherwise alter the checkout to make the snapshots match.

### Verdict

**Documented deviations are judged on merit, not reflex-blocked.** "Do not improvise" exists to stop silent drift; an executor that hits a real obstacle (e.g. the plan's approach breaks existing test mocks), adapts minimally, and explains it in NOTES has done the right thing. Approve it if the adaptation serves the plan's intent and stays in scope; treat *undocumented* deviations as review failures.

| Verdict | When | Action |
|---|---|---|
| **APPROVE** | Criteria pass, scope clean, quality holds | If `plans/README.md` was clean before dispatch, update its status to DONE; if it was already dirty, leave it untouched and report the recommended status change to the user. Present the diff summary and anything from NOTES. Leave all source edits unstaged. **Staging, committing, pushing, opening a PR, or otherwise publishing the change requires a separate explicit user request.** |
| **REVISE** | Fixable gaps | Send a follow-up task to the same executor with specific, actionable feedback ("criterion 3 fails: X; the error handling in `api.ts:90` swallows the error — use the Result pattern per the plan"). **Max 2 revision rounds**, then BLOCK. |
| **BLOCK** | STOP condition hit, scope violated unrecoverably, or revisions exhausted | If `plans/README.md` was clean before dispatch, mark it BLOCKED with the reason; if it was already dirty, leave it untouched and report the recommended status change. Refine or rewrite the plan only where doing so cannot overwrite pre-existing dirty plan files. Tell the user what happened and what changed or remains to be updated. |

Plan-authorized file edits are the narrow exception to Improve's normal read-only rule. Verification remains non-mutating unless the user separately authorizes a specific command and its exact write scope. Gitignored output is not inherently disposable or safe to overwrite.

---

## `reconcile` — keep `plans/` alive

Process what happened since the last session. Read `plans/README.md` and every plan file, then per status:

- **DONE** — spot-check that the done criteria still hold on the current HEAD (cheap ones only). Mark verified in the index. Don't delete plan files — they're the record.
- **BLOCKED** — read the reason. Investigate the underlying obstacle in the codebase. Either rewrite the plan around it (new number if the approach changed fundamentally, in-place refresh otherwise) or mark REJECTED with one line of rationale.
- **IN PROGRESS** (stale) — flag it to the user; an executor probably died mid-run. Inspect the current checkout against the plan and recorded status without cleaning or reverting anything.
- **TODO** — run the drift check. If drifted: re-verify the finding still exists (it may have been fixed in passing), then refresh the "Current state" excerpts and `Planned at` SHA. If the finding is gone, mark REJECTED ("fixed independently").

Finish with a short report: what's verified done, what was refreshed, what's rejected, and what's executable right now.

---

## `--issues` — publish plans as GitHub issues

Modifier on any planning invocation (`$improve --issues`, `$improve security --issues`). The flag is the user's authorization to create issues — never create them without it.

1. Preflight: `gh auth status` succeeds and the repo has a GitHub remote. If either fails, write the plan files as normal and say why issues were skipped.
2. Visibility check: `gh repo view --json visibility`. If the repo is **public**, warn the user that issues are publicly visible and get explicit confirmation before publishing any plan that describes a security vulnerability, credential location, or other sensitive finding.
3. Show the list of titles about to become issues; confirm once if interactive.
4. Per plan: `gh issue create --title "<plan title>" --body-file <plan file>`. Labels: `improve` plus the category — apply only if the labels exist or can be created without erroring; skip labels rather than fail.
5. Record each issue URL in the plan's Status block (`- **Issue**: <url>`) and the index.

The plan file remains the source of truth; the issue is distribution. The self-containment rule pays off here — the issue body needs no edits to make sense to whoever (or whatever) picks it up.
