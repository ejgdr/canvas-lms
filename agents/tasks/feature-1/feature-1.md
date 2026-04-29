# Feature: Discussion Thread Summarizer

## Problem

Course discussions accumulate quickly. By mid-semester, a single graded discussion can hold dozens or hundreds of replies, making it impractical for students to catch up before contributing and difficult for instructors to spot unanswered student questions. The result is shallow participation and student questions that go unaddressed for days.

## Target

- **Students:** returning to a long discussion thread before posting their own reply.
- **Instructors:** monitoring active discussions for unanswered questions.

## What the feature does

Two surfaces over the existing discussion experience:

1. A summary block displayed at the top of any discussion thread, showing the main themes, the dominant viewpoints, and the open questions that have not yet received a substantive reply.
2. An instructor-only "Open Questions" digest aggregating unanswered questions from across all discussions in a course, ordered by age.

Summaries are generated on demand and refreshed when the underlying thread changes meaningfully. The feature is protected behind an admin-controlled toggle so teachers or institutions can opt in.

## Why it matters

Reduces the time cost of joining a long discussion, raises the floor of student participation by making catch-up viable, and gives instructors a fast way to find and respond to unanswered questions.

## In scope

- Per-thread summary block on student and instructor views, with a "regenerate" action.
- Instructor-only "Open Questions" digest scoped to a single course.
- Admin-level toggle to enable the feature for a course or institution.
- Cached summaries, invalidated when the thread receives new replies above a defined threshold.

## Out of scope

- Cross-course question digests.
- Auto-replying to student questions.
- Sentiment analysis or participation scoring.
- Summarization of private messages or non-graded discussions outside the course context.

## Success criteria

- A student opening a long discussion thread can read a useful summary and orient themselves before reading the full thread.
- The instructor digest correctly surfaces questions from student replies that have not yet received a substantive instructor or peer response.
- Summaries refresh in a timely way after new high-impact replies and do not regenerate excessively for trivial edits.
- The feature can be fully disabled at the course or institution level without affecting the underlying discussion data.

## Key risks and considerations

- **Privacy of student-authored content.** Sending student discussion content to a third-party model raises privacy concerns. Mitigations include an institutional opt-in toggle, the option to scope summaries to instructor posts plus the viewer's own posts, and a self-hosted model deployment path.
- **Summary quality and bias.** Summaries must not misrepresent minority viewpoints in a thread. A "report summary" action lets users flag inaccurate summaries.
- **Performance.** Summarization runs asynchronously; the thread renders without waiting on the summary, which streams in when ready.
- **Scope discipline.** The instructor digest is a stretch surface, the per-thread summary alone delivers most of the user value.
