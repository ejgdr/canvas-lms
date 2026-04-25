# summarize_folder.prompt.md

Prompt template fed to the LLM when the analyze-repo agent needs to (re)generate a folder summary. The **orchestrator** is responsible for sampling files and substituting the placeholders before sending this prompt. The LLM never picks what to sample — the script does, deterministically, so the same folder produces the same sample set.

---

## Variables the orchestrator substitutes

- `{{FOLDER}}` — folder path relative to repo root (e.g. `app/controllers` or `ui`)
- `{{REPO}}` — repo name (e.g. `canvas-lms`)
- `{{FILE_STATS}}` — one line per sampled file: `<relative_path>  <size_bytes>  <lang>`
- `{{SAMPLED_SNIPPETS}}` — up to 10 snippets of at most 40 lines each, pre-selected by the orchestrator (largest files + most-linked files, not random)
- `{{HASH_FOOTER}}` — sha1 of the concatenated hashes of every file in the folder, used to detect staleness on the next run

---

## Prompt body

You are summarizing a single folder inside the `{{REPO}}` repository. Your summary will be reread by a downstream analysis agent that is trying to stay under a 40% context budget, so prefer density over completeness.

Folder: `{{FOLDER}}`

Files (sampled, not exhaustive):

```
{{FILE_STATS}}
```

Representative snippets:

```
{{SAMPLED_SNIPPETS}}
```

Produce a markdown document with this shape and **no more than 400 words**:

```
# {{FOLDER}}

## What this folder holds
<2–4 sentences describing purpose and the kind of code inside>

## Subdirectories / notable files
<bullet list, each line: `path — one-sentence purpose`. Cap at 8.>

## Entrypoints and key symbols
<bullet list of up to 6 classes/modules/exports a reader should know>

## How it relates to the rest of the repo
<2–3 sentences: what depends on this folder, what it depends on>

## Caveats
<1–2 bullets only if something is unusual — sprawling file count, generated code, vendored third-party, known-deprecated paths. Skip if nothing noteworthy.>

<!-- hash:{{HASH_FOOTER}} -->
```

Rules:

- Do not invent files or symbols that are not in the provided stats or snippets.
- Quote no more than 3 short identifiers; prose over code.
- If the folder is too large or heterogeneous to summarize in 400 words, reply with a single line `SPLIT_REQUIRED: <folder>/<subdir>, <folder>/<subdir>, …` listing which second-level directories should be summarized separately instead. The orchestrator will then call this prompt once per subdirectory.
- The `<!-- hash:... -->` footer must be preserved verbatim — it is how the orchestrator detects staleness next run.
