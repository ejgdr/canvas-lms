# Memory technique: last-verified metadata + re-grounding triggers

## Why this technique fits

Canvas LMS is an upstream that moves underneath any fork. Agent notes written against last week's code rot quietly. The cheapest defense is to stamp every agent artifact with the commit hash it was verified against, and to make re-grounding the first step of every new agent session — not an optional afterthought. This pairs with cross-session memory provided by the editor's own tooling; the markdown stamps are the project-specific layer.

## Connection to other agents

- `agents/analyze-repo.md` (analysis agent): its outputs are only trusted when its `Last verified` stamp is at least as fresh as the most recent upstream sync.
- Future `agents/feature-implementation.md`: must begin each session by re-grounding against the current HEAD before touching code.

## Procedure (file rituals)

1. Every agent markdown file under `agents/` carries a footer line of the form `Last verified: YYYY-MM-DD against commit <sha>`.
2. Before each agent session, run a re-ground prompt that outputs `git rev-parse HEAD`, re-confirms the files the agent depends on still exist at their documented paths, and updates the stamp.
3. If the re-ground reveals a moved path or renamed doc, the agent file is amended in the same session — never deferred.
4. Before a long implementation session, the working context is purged to the current relevant slice plus a one-paragraph summary; older detail stays in the file but is not pasted into the prompt.

## Failure modes and mitigations

- **Stale-stamp drift**: someone bumps the date without re-running the diff. Mitigation: the re-ground prompt requires citing the upstream commit hash, not just a date. No commit hash, no stamp refresh.
- **Over-trust of summaries**: a compressed summary outlives the code it summarized. Mitigation: summaries inherit the stamp of the source they were compressed from; if the source is re-stamped, the summary is regenerated.

## Evidence excerpt

During a Canvas Docker bring-up session, the re-grounding pattern surfaced two issues that a stale-context agent would have missed.

Excerpt 1 — diagnosing a silent script exit by reading the script source at the working commit:

> The logging.sh sourced at startup runs `tput bold/sgr0/setaf` — these fail without TERM set, and because `set -e` is active in the outer script, the first failing tput call kills it before any output reaches stdout… TERM=dumb (set by sudo) makes `tput bold` exit 1. Since logging.sh runs `BOLD="$(tput bold)"` at source time and `set -e` is active, the script dies before printing a single character.

Excerpt 2 — diagnosing a container UID write failure by going to a different doc file at the same commit:

> Documented fix — `doc/docker/README.md` (Linux section): "Just on Linux, you may want to run this to avoid a few permissions issues first by granting Canvas docker containers write access to your Canvas folder:" `setfacl -Rm u:9999:rwX,g:9999:rwX .` …

Both diagnoses cited specific paths inside the repo at the working commit. Neither relied on cached agent assumptions.

---
*Last verified: 2026-05-13 against commit 5b8b921cf5dbbff3e4c75539522b66fcdacbee05*
