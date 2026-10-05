# frozen_string_literal: true

require_relative "advisor"

# on_complete: a run has ended — reset the per-run analysis budget so the
# next run starts fresh.
Clacky::ExtensionHookRegistry.add do |result, agent, context|
  next unless Clacky::Advisor.enabled_for?(agent)

  successful = result.is_a?(Hash) && result[:status] == :success && !context&.dig(:handled)
  Clacky::Advisor.worker_for(agent).finish_run(analyze: successful)
end
