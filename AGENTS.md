# Reusable capsule editing workflow

## Project purpose

Maintain general-purpose video editing tools for many capsules. Keep episode
choices in data and Markdown, not in new scripts for each capsule. Reuse
`render-timeline.ps1`, `change-speed.ps1`, `crop-video.ps1`, `image-to-video.ps1`,
`add-intro.ps1`, and `add-music.ps1`. Create a private episode workspace using
`new-capsule-workspace.ps1 -Name <episode-name>`. Extend a general tool when a
requested operation is missing.

## Public tools and private work

Keep the repository root limited to reusable scripts, README.md, AGENTS.md and
.gitignore. All actual media, presentations, templates, edit sheets, JSON plans,
render notes, logs, previews, checks, delivery outputs and episode-specific
helpers belong under the ignored `local-work/` directory. Use generic examples
in public files; do not copy private titles, source names, URLs or measurements
into them. Do not stage private work or use `git add -f` on ignored content.

Keep `local-work/` ignored during local agent work. Git ignore rules do not
remove filesystem access. If a search skips ignored files, use explicit file
paths or `rg --files --hidden --no-ignore local-work`. Ask the user to name the
episode if several workspaces match; do not silently choose the latest folder.

Use `local-work/capsule-history/<episode>/` for each capsule. Keep `cuts.md` at
that folder's top level, with `videos/`, `images/`, `templates/`, `plans/`,
`notes/`, `renders/`, `logs/`, `preview/` and `tests/` beneath it. Shared reusable
private assets belong in `local-work/shared/`. Local check scripts can live in
`local-work/tools/`. Never move or delete an older episode to start a new one.

## Starting point: human notes

The selected episode's `cuts.md` is the human-facing source of editorial intent.
Accept short notes with filenames, source ranges, and plain-language directions.
Do not require a schema, JSON, output timestamps, speed calculations or exact
overlay coordinates from the human. The workspace creator supplies starter notes.
Determine whether the request is preparation or rendering from the user's words.
If unclear, inspect the notes and prepare the timeline first.

## Stage 1: prepare the timeline

When asked to plan, enhance, or prepare `cuts.md`:

1. Read the human notes and inspect actual media with FFprobe. Inspect frames
   when crop areas or webcam positions matter. Preserve requested cuts and order.
2. Resolve durations, audio sources, crop versus resize, overlay placement,
   canvas size, and any timing mismatch. Surface editorial choices that need
   the human's decision; do independent preparation while awaiting the answer.
   Do not silently change narration speed, remove content, or invent footage.
3. Rewrite `cuts.md` as a concise, readable edit sheet: title/status, source cuts,
   an output-time timeline, audio/layout decisions, unresolved items, expected
   runtime, and a short next-chat prompt. Preserve the original source ranges
   in that document. Explain decisions in plain language; keep low-level
   settings, FFmpeg research and long commands in `notes/`, and logs in `logs/`.
4. Create or update an agent-maintained `<capsule>-plan.json` for supported
   timeline operations under `plans/`, deriving it from `cuts.md`. Include a link/name in the
   edit sheet. JSON is an execution artifact, not something humans must author.
   For cropping/music or other operations outside the JSON renderer, record
   exact commands and order in companion render notes using the general tools.
   JSON media paths resolve relative to the JSON file: a plan in `plans/`
   normally uses `../videos/...` and `../images/...`. Commands run the general
   scripts from the repository root with explicit private plan/output paths.
   Do not invent unsupported JSON fields and assume they execute.
5. Run preflight where applicable. Mark unresolved decisions clearly. A preview
   may verify layout; preparation alone does not request a final video render.

## Stage 2: render the prepared timeline

When asked to create/render the video, including from another chat:

1. Read `cuts.md`, this file, the named plan and any linked render notes. Check
   that files, ranges, audio, layout and speed decisions still match. Treat
   `cuts.md` as editorial authority; regenerate stale derived settings rather
   than rendering an older JSON silently. Ask only about material ambiguity.
2. Run the documented general tools with explicit plan/output paths. For
   supported compositions use `render-timeline.ps1 -Plan ... -Output ...`.
   A render request authorizes executing the prepared plan; do not introduce
   another approval step when the necessary choices are already settled.
3. Preserve original media. Write final outputs to `renders/`, previews to
   `preview/`, logs to `logs/`, and episode-specific checks to `tests/`.
   Validate sources and output protection, render,
   inspect streams and runtime, decode-check, and inspect edit/overlay boundaries.
   Report visual or audible limitations honestly; do not claim a listening
   review or full playback if only probing or sample frames were checked.
4. Record the final output and checks briefly in `cuts.md`, then hand off the
   video. Do not silently make new editorial cuts during rendering.

## Reuse and handoff

Each episode keeps its own edit sheet and complete history under its private
workspace. Start another folder for the next capsule. Keep JSON-relative media
paths and Markdown links valid if files move. Preserve existing artifacts unless
the user requests cleanup. Git ignore rules do not remove files already tracked
or historical commits; inspect the index and history when preparing a release.
Do not push, rewrite history or publish a release unless requested. A fresh
snapshot of generic public files avoids carrying old private Git history.

## AI Telemetry Handoff

After completing meaningful AI-assisted work tied to a Jira issue, ticket, pull
request, branch, commit, or other delivery artifact, use the
`ai-telemetry-reporting` skill before final handoff.

Run this only when all are true:
- The current task produced useful delivery progress.
- The work has a concrete target such as a Jira issue, ticket, pull request,
  git branch, or git commit.
- The work is more than a trivial answer, status check, wording-only change, or
  broad planning with no deliverable.

Use checkpoint behavior so repeated telemetry reports describe only work since
the last valid `aiTelemetryInsights` checkpoint.

If submitting to Jira, confirm the issue key and destination before any write.
Use `jira_add_worklog` with the telemetry payload's `worklogTime`, and wrap JSON
comments with Jira `{code:json}` macros.

Do not attach, submit, post, or route telemetry to an external system unless the
user explicitly asks for that destination and confirms the write.
