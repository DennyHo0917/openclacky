# Server session observation hooks

Extensions can subscribe through `contributes.hooks` in ext.yml, using the same
Ruby hook files and `(payload, agent)` callback signature as existing hooks.
These two events observe the HTTP/WebSocket server lifecycle. They do not change
`on_start` / `on_complete`, and do not claim to cover CLI or channel execution.

- `on_user_input`: a web input is accepted for execution, queueing, or steering.
  Queue consumption does not emit it a second time. Payload: `session_id`,
  `observed_at` (server UTC ISO8601), `source: "web"`. No input text is exposed.
  This source describes transport, not authenticated user identity.
- `on_session_state`: `running`, `awaiting_user`, `completed`, `failed`, or
  `cancelled`. Payload: `session_id`, `observed_at`, `status`, `run_id` (runtime
  task epoch). Failures include `error_code` when available; cancellation includes
  `reason`. A handled on_start result still settles through the server wrapper.
  Superseded task threads cannot emit terminal observations for their successors.

Callbacks run synchronously outside registry locks. Keep them short and dispatch
network work asynchronously. Callback exceptions are isolated and their return
values cannot deny/handle work or suppress later observers. No delivery queue,
retry, persistence, replay, or cross-restart ordering is promised. `run_id` is
local to the running server. Consumers must tolerate missing observations.
