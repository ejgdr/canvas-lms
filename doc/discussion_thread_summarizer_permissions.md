# Discussion Thread Summarizer — Permission Audit (M1, FR-4/FR-9/NFR-6)

## Decision

The Discussion Thread Summarizer feature (v1) introduces no new permission
objects, RoleOverride entries, or ACL surfaces. It reuses the two existing
permission gates already present on `DiscussionTopic`.

## Gates reused

### Summary read access — `:read` via `visible_for?`

`app/models/discussion_topic.rb` — `set_policy` block:

```ruby
given { |user| visible_for?(user) }
can :read
```

`visible_for?` enforces `read_forum` (or `read_announcements` for
announcements), section-specific visibility, and group membership. Any user
who cannot pass this check cannot retrieve a summary, even by direct ID
(satisfies acceptance criterion 1).

The "users must post before seeing replies" requirement (FR-9) is enforced by
`user_can_see_posts?`. Summary generation is suppressed for viewers who have
not yet posted, using the same code path that denies reply visibility
(satisfies acceptance criterion 2).

### Digest tab access — `:moderate_forum`

`app/models/discussion_topic.rb` — `set_policy` block:

```ruby
given { |user, session| context.grants_all_rights?(user, session, :moderate_forum, :read_forum) }
can :moderate_forum
```

The instructor-only "Open Questions" digest is gated on this existing check.
No student or non-moderator can reach the digest tab without holding
`moderate_forum` on the course context (satisfies acceptance criterion 3).

## Release note

> **Discussion Thread Summarizer** (feature flag `discussion_thread_summarizer`,
> off by default): no new permissions are required. Existing `read_forum` and
> `moderate_forum` rights govern all new surfaces. No new `RoleOverride` or
> permission type is introduced (NFR-6).
