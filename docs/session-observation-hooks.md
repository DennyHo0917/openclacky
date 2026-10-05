# Agent task lifecycle hooks

## Task lifecycle: on_start / on_complete

> Availability: the additional context and abnormal completion paths require
> the runtime change on branch `codex/session-lifecycle-hooks`. They are not
> available in 1.5.16. Upgrade the runtime before relying on these fields.

Use the existing events without extra configuration. `on_start` runs after task
and history initialization, before execution, and retains `deny` / `handled`.
`on_complete` observes the outcome of each Agent turn, including normal completion,
waiting, handled starts, denial, exceptions and interruption. Its return value is
ignored, including `deny` and `handled`; all completion callbacks can run.

Ruby callbacks receive `(input, agent, context)` or `(result, agent, context)`.
The first two positions are unchanged; ordinary two-argument Ruby blocks ignore
the extra argument. Existing completion callbacks must check `result[:status] ==
:success` before doing success-only work. A handled result has `context[:handled]`
set to true; skip follow-up work already performed by the handler.

These are Agent-turn events for server, CLI and channel execution, not server
persistence notifications. Queued input emits start only when consumed; steering
inside an active turn does not create an extra start or completion. Automatic goal
continuations have their own turn events. Normal completion fires before goal
continuation, and exceptions still propagate after notification. A superseded
turn's exception cleanup cannot settle its successor.

Context contains `session_id`, `run_id` (process-local task ID, not durable),
`source` (execution source, not authenticated identity), `input_created_at` (the
optional timestamp passed to `run`), `observed_at` (UTC ISO8601), and `status`.
Start status is `running`. No input text is added to context; input and result
arguments can contain sensitive data.

| Completion context status | Meaning |
|---------------------------|---------|
| `completed` | Result explicitly has `status: :success`, without a feedback request. This does not certify App generation or validation. |
| `awaiting_user` | Successful result requests `awaiting_user_feedback`. |
| `failed` | Exception or non-success result. Structured exceptions can supply `error_code`. |
| `cancelled` | Interruption or denial. `reason` may be `user`, `replacement`, `hook_denied` or `tool_denied`. |

Cancelled completion notifications carry `result[:status] == :cancelled`, even
when the original denial return value remains unchanged for queue compatibility.
An execution start alone does not establish recovery from a previous failure.

```yaml
id: session-observer
name: Session Observer
version: "0.1.0"
contributes:
  hooks:
    - event: on_start
      file: hooks/start.rb
    - event: on_complete
      file: hooks/complete.rb
```

```ruby
# hooks/start.rb
Clacky::ExtensionHookRegistry.add do |_input, _agent, context|
  next unless context
  Clacky::Logger.debug("[session-observer] started", session_id: context[:session_id],
                       run_id: context[:run_id])
  nil
end
```

```ruby
# hooks/complete.rb
Clacky::ExtensionHookRegistry.add do |_result, _agent, context|
  next unless context
  Clacky::Logger.debug("[session-observer] settled", session_id: context[:session_id],
                       status: context[:status], run_id: context[:run_id])
  nil
end
```

Use separate files for separate registrations: each Ruby file is required only
once. Programmatic registration uses `agent.add_hook(:on_complete) { |result,
agent, context| ... }`. Shell hooks keep their JSON payload shape; neither the
Agent nor context is serialized, while abnormal completion results are now reported.

Callbacks execute synchronously; keep them short and dispatch network work
asynchronously. `StandardError` is logged without stopping later callbacks.
The host does not persist, retry, replay or acknowledge hook delivery. Consumers
must tolerate missing events and cannot infer inactivity solely from missing data.
`agent.emit_event(persist: true)` is a separate frontend-history feature.
