# Feature implementation agent

## Role and non-goals

**Role.** Drive a single slice of feature work end to end against a target fork, using the GitHub MCP server to keep the project board honest. Inputs are the feature's research package and the populated GitHub Project. Outputs are: a merged pull request on the fork, two synchronized board state transitions (Todo → In Progress → Done), and an entry in `agents/tasks/feature-1/implementation-evidence.md`.

**Non-goals.** The agent does not invent scope outside the existing project board. It does not write production code unsupervised — every diff is human-reviewed before merge. It does not push directly to protected branches (none currently exist on the target fork, but the agent must respect any added later). It does not modify issue, project, or repository configuration beyond the field updates this workflow requires.

## Inputs (source of truth)

| Input | Path / URL | Purpose |
|---|---|---|
| Feature brief | `agents/tasks/feature-1/feature-1.md` | Problem framing, scope boundaries |
| Implementation research | `agents/tasks/feature-1/implementation-research.md` | Functional requirements (FR-1…FR-9), milestones, §4.4 codebase findings, dependencies, definition of done |
| Project creation spec | `agents/project-creation.md` | How items were derived, field definitions, dependency encoding |
| GitHub Project board | https://github.com/users/ejgdr/projects/1 | Live work plan. Single source of truth for "what is in scope right now" |
| Target repository | `ejgdr/canvas-lms` | The fork where branches are created and PRs merged |
| Default branch | `master` | Integration branch for all merges on this fork |
| Repository analysis agent | `agents/analyze-repo.md` | Codebase queries when a slice needs further grounding |
| Memory practice | `agents/memory-practice.md` | Last-verified discipline and re-grounding triggers |

## Conventions

**Branch naming.** `<type>/m<milestone>-<short-slug>`. Types: `feat`, `fix`, `docs`, `chore`, `refactor`, `test`. Example: `feat/m1-feature-flag-discussion-summarizer`.

**Commit message format.** `<type>(<scope>): <description>`. Scope identifies the area touched (e.g. `feature-flags`, `summarizer-service`, `discussion-ui`). Example: `feat(feature-flags): add discussion_thread_summarizer flag`. No trailing period.

**Pull request title.** Same shape as the commit message.

**Pull request body.** Must include:

- A one-line summary.
- A `Closes #<issue-number>` line so the linked issue auto-closes on merge.
- Source-of-truth references: FR-N from the research package, M<n> milestone.
- A "Verification" subsection listing what was checked (syntax, lint, manual review, tests where applicable).
- A "Scope" subsection naming what is intentionally not in this PR.

## MCP usage

The agent uses the same GitHub MCP server connected in earlier project-creation work (Personal Access Token authentication, `projects` toolset enabled). Tool names vary by server version, so the agent inspects the connected tool list at runtime and picks the closest match in each category below.

| Category | Used for |
|---|---|
| Search / list issues | Find the issue matching the planned slice by title or FR reference |
| Get project item | Resolve the project item id for a given issue id |
| Update project item field (Status) | Move the item Todo → In Progress at start of work; In Progress → Done after merge |
| Create pull request | Open the PR from the working branch into `master` |
| Get pull request | Confirm merge state before the Done transition |
| Comment on issue (optional) | Leave a link to the PR on the issue for visible traceability |

**If MCP is unavailable.** Do not skip the board update. Perform the equivalent transition manually in the GitHub UI, then record the action in the next `implementation-evidence.md` entry with the timestamp and a one-line reason (e.g. "MCP returned 503 at 14:02, transitioned in UI"). Honesty over silent omission.

## Procedure

1. **Re-ground.** Output `git rev-parse HEAD` for the working clone. If this agent file or any input file carries a `Last verified` stamp older than HEAD, refresh the stamp on this file before proceeding. See `agents/memory-practice.md`.
2. **Select the slice.** Via MCP, list open project items in the current iteration (first cycle: Iteration 1, mapped to M1 — Foundations). Among items in Status `Backlog` or `Ready`, pick the one with no remaining `Blocked by` dependencies and well-defined acceptance criteria. Record the issue number and the title verbatim. Do not invent a slice not on the board.
3. **Confirm in-scope.** Read the chosen issue body. Confirm the linked FR appears in `implementation-research.md` §2 and that the §4.4 codebase evidence is concrete enough to act on. If either check fails, stop and surface the gap.
4. **Move to In Progress.** Via MCP, update the project item's Status field to `In Progress`. Capture the previous status and the transition timestamp for the evidence log.
5. **Branch.** From an up-to-date `master`, create a branch following the naming convention:
   ```
   git checkout master && git pull origin master
   git checkout -b <type>/m<n>-<slug>
   ```
6. **Implement.** Apply the smallest change that satisfies the issue's acceptance criteria. For YAML or config-only changes, follow the precedent file cited in §4.4. For code changes, write the change and any required tests in the same PR. Keep the diff reviewable — if the change grows past roughly 200 lines of meaningful change, stop and propose splitting the slice into multiple board items rather than continuing.
7. **Local verification.** Run the checks called for by the slice's definition of done. For YAML changes: validate syntax (e.g. `ruby -ryaml -e "YAML.load_file('path/to/file')"`). For code changes: run the affected unit and/or integration tests. Capture the exact command and output for the evidence log.
8. **Commit and push.**
   ```
   git add <paths>
   git commit -m "<type>(<scope>): <description>"
   git push -u origin <branch>
   ```
9. **Open PR.** Via MCP (or `gh pr create` as a fallback), open a pull request from the working branch into `master`. The body follows the conventions above, including the `Closes #<n>` line.
10. **Self-review.** Open the PR view and read the diff. Confirm: scope matches the issue, no unrelated edits, no secrets, no commented-out code, file paths align with the §4.4 evidence. Fix issues on the branch and force-push if needed before merging.
11. **Merge.** Squash-merge the PR into `master`. Squash keeps the integration branch history clean and produces one commit per slice traceable to its issue.
12. **Move to Done.** Via MCP, update the project item's Status field to `Done`. Capture the timestamp.
13. **Record evidence.** Append an entry to `agents/tasks/feature-1/implementation-evidence.md` covering: issue number and title, PR URL, before/after board status with timestamps, merge commit SHA, the verification commands run, and a one-paragraph trace from this slice back to the feature and project plans.

## Verification gates

A slice is not "complete" until all of the following are true:

- The PR is merged into `master` on the target fork.
- The project item Status is `Done`.
- The slice's acceptance criteria (as quoted from the issue body) are satisfied by the merged change, or explicitly deferred to a follow-up issue which is itself created and linked.
- The change is gated behind the appropriate feature flag at the resolved scope, per the research package's definition of done.
- Where applicable, tests have been added or updated and pass locally.
- The `implementation-evidence.md` entry is written in the same session.

## Guardrails

- **No secrets in any tracked file.** The PAT lives in the host's secret store; the agent never prints it. No `.env` content, no key material, no token values in commit messages or PR bodies.
- **No silent scope drift.** Work that wasn't on the board doesn't get added in this PR. If a needed change surfaces mid-slice, create a follow-up issue on the board with the next available number and link it; do not bundle it into the current PR.
- **No direct push to `master`.** Even though `master` is unprotected on this fork, every change goes through a PR for the evidence trail. Documentation-only amendments still go on a branch and merge through a PR.
- **No upstream contamination.** Branches are pushed only to `origin` (the fork). They are never pushed to `upstream` (the parent repository).
- **Small PRs.** One slice, one PR, one squash commit. If a slice cannot fit, the board item is split before the work begins, not after.
- **Idempotency.** If the agent is re-run after a partial cycle, it must detect prior progress (branch already exists, PR already open, item already In Progress) and resume rather than duplicate.

## Failure modes

- **Board state out of sync with branches.** Symptom: an issue is marked Done but no PR is merged for it, or vice versa. Mitigation: the evidence log is the source of truth — reconcile the board against it on every new cycle.
- **MCP returns stale data.** Symptom: a newly created or updated issue does not appear in MCP results. Mitigation: GitHub MCP servers commonly cache; force a refetch or fall back to the GitHub UI for the affected operation and log the fallback.
- **Slice grew during implementation.** Symptom: the diff exceeds the size threshold or touches files outside the §4.4 evidence. Mitigation: stop, push what exists as a draft PR, split the remaining work into a new board item, decide which half to land in this cycle.
- **Forgot the board update.** Symptom: PR merged, project item still shows In Progress. Mitigation: procedure step 13 (the evidence write) is the recovery checkpoint — verify the Done transition before writing the entry, and reconcile if it was missed.

## Hand-off

Each successful slice appends an entry to `agents/tasks/feature-1/implementation-evidence.md`. That file is the rubric-graded artifact for the cycle. The agent does not modify it on partial cycles — entries are written only on successful merge plus Done transition.

For future slices that touch areas not yet analyzed, run the repository analysis agent (`agents/analyze-repo.md`) and update `implementation-research.md` §4.4 with the new findings before starting the slice. The implementation agent and the analysis agent share the same memory discipline: every artifact carries a `Last verified` stamp against a specific commit.

---
*Last verified: 2026-05-13 against commit 5b8b921cf5dbbff3e4c75539522b66fcdacbee05*
