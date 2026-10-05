# Server lifecycle scope

## Lifecycle scope for on_start / on_complete

> Availability: `scope: lifecycle` requires the runtime change on OpenClacky
> branch `codex/session-lifecycle-hooks`; 1.5.16 does not support it. Older
> runtimes can ignore the scope and register a legacy callback instead, so
> upgrade the runtime before enabling this scope. Manifest verification alone
> does not prove runtime support.

Omit `scope` (or use `scope: default`) to keep the existing trigger paths,
callback arguments, and deny/handled behavior. Ruby callbacks can opt into
`scope: lifecycle` for HTTP/WebSocket server observations. Lifecycle callbacks
are registered separately: they do not also fire on the legacy Agent hook
chain, and their return values cannot deny work or suppress later callbacks.
CLI and channel execution are outside this server scope.

| Hook | Arguments | Lifecycle phases |
|------|-----------|------------------|
| `on_start` | `(input, agent, context)` | `input_accepted`: web input accepted for execution, queueing or steering; `input` contains its text. `execution_started`: the server starts a run; `input` is nil and `context[:status]` is `"running"`. |
| `on_complete` | `(result, agent, context)` | `settled`: once after the server run settles, including normal completion, waiting, exceptions, interruption and handled starts. The first argument is the returned result, or a result hash for an exception/interruption. |

The optional trailing `context` belongs to lifecycle callbacks only. Existing
callbacks receive exactly their previous arguments. `input_accepted` counts
acceptance, not queue consumption; consuming the same queued input does not
emit it again. A regular web request produces both start phases, so count
activity only for `input_accepted`. Do not assume the accepted-input notification
precedes the execution-start notification. Automatic runs may only have the
execution phase. `on_complete` fires after queued work in the same server run
settles, not once per tool call or internal Agent turn.

Context includes `session_id`, `observed_at` (server UTC ISO8601) and `phase`.
Input acceptance also has `source: "web"`, a transport hint rather than an
authenticated identity. Execution start and completion include `run_id`, the
runtime task epoch as a string; it is not stable across restarts. Superseded
workers cannot publish their successors' terminal state.

| Completion context status | Meaning |
|---------------------------|---------|
| `awaiting_user` | The result requests `awaiting_user_feedback`. |
| `completed` | No explicit failure or feedback request. This does not certify App generation or validation. |
| `failed` | A raised exception or error/failed result. `error_code` is present when a supported structured credit exception supplies it; otherwise it may be absent or null. |
| `cancelled` | Interrupted; `reason` identifies the cause, such as `user` or `replacement`. |

An execution start alone does not establish recovery from a previous failure.
Error text is not added to context; the normal result retains its existing
shape. Input text and result content may be sensitive: examples log metadata
only.

```yaml
id: session-observer
name: Session Observer
version: "0.1.0"
contributes:
  hooks:
    - event: on_start
      scope: lifecycle
      file: hooks/start.rb
    - event: on_complete
      scope: lifecycle
      file: hooks/complete.rb
```

```ruby
# hooks/start.rb
Clacky::ExtensionHookRegistry.add do |_input, _agent, context|
  next unless context[:phase] == "input_accepted"
  Clacky::Logger.debug("[session-observer] input", session_id: context[:session_id],
                       observed_at: context[:observed_at])
  nil
end
```

```ruby
# hooks/complete.rb
Clacky::ExtensionHookRegistry.add do |_result, _agent, context|
  Clacky::Logger.debug("[session-observer] settled", session_id: context[:session_id],
                       status: context[:status], run_id: context[:run_id])
  nil
end
```

Use separate files for separate registrations: each Ruby file is required only
once. `scope: lifecycle` is supported only for Ruby `on_start` and `on_complete`
callbacks. Programmatic registration uses `agent.add_hook(:on_complete,
scope: :lifecycle) { |result, agent, context| ... }`; shell hooks retain their
existing contract.

Callbacks run synchronously outside the session registry lock. Keep them short
and dispatch network work asynchronously. `StandardError` is logged without
blocking later observers. The host does not persist, retry, replay or acknowledge
observations. Consumers must tolerate missing events and must not infer inactivity
from missing data. `agent.emit_event(persist: true)` is a separate frontend-history
feature and does not persist hook delivery.
