# frozen_string_literal: true
require "spec_helper"

RSpec.describe Clacky::Agent, "run completion hooks" do
  let(:config) { Clacky::AgentConfig.new(memory_update_enabled: false, skill_evolution: { enabled: false }) }
  let(:client) { Clacky::Client.new("test", base_url: "https://unused.invalid", model: "test") }
  let(:agent) do
    described_class.new(client, config, working_dir: Dir.pwd, ui: double("ui").as_null_object,
                       profile: "coding", session_id: "test-session", source: :web)
  end
  let(:seen) { [] }
  before do
    allow(agent).to receive(:think).and_return(content: "done", tool_calls: [])
    allow(agent).to receive(:run_skill_evolution_hooks)
    allow(agent).to receive(:run_memory_update_subagent)
    agent.add_hook(:on_complete) { |result, owner, context| seen << [result, owner, context] }
  end

  it "keeps the first two arguments and emits one successful completion" do
    result = agent.run("hello", created_at: 123)
    expect(seen.size).to eq(1)
    expect(seen.first[0]).to equal(result)
    expect(seen.first[1]).to equal(agent)
    expect(seen.first[2]).to include(status: "completed", session_id: "test-session", input_created_at: 123)
  end

  it "reports structured failure once while preserving the raised exception" do
    error = Clacky::InsufficientCreditError.new("credits", error_code: "insufficient_credit")
    allow(agent).to receive(:think).and_raise(error)
    expect { agent.run("hello") }.to raise_error(error)
    expect(seen.size).to eq(1)
    expect(seen.first[0][:status]).to eq(:error)
    expect(seen.first[2]).to include(status: "failed", error_code: "insufficient_credit")
  end

  it "reports interruption as cancellation rather than success" do
    allow(agent).to receive(:think).and_raise(Clacky::AgentInterrupted)
    expect { agent.run("hello") }.to raise_error(Clacky::AgentInterrupted)
    expect(seen.size).to eq(1)
    expect(seen.first[0][:status]).to eq(:cancelled)
    expect(seen.first[2]).to include(status: "cancelled", reason: "user")
  end

  it "reports handled feedback once without executing the loop" do
    agent.add_hook(:on_start) { {action: :handled, result: {status: :success, awaiting_user_feedback: true}} }
    expect(agent).not_to receive(:think)
    agent.run("hello")
    expect(seen.size).to eq(1)
    expect(seen.first[2]).to include(status: "awaiting_user", handled: true)
  end

  it "does not allow completion verdicts to suppress later observers" do
    agent.add_hook(:on_complete) { {action: :deny} }
    agent.add_hook(:on_complete) { raise "observer error" }
    tail = []
    agent.add_hook(:on_complete) { tail << true; nil }
    expect(agent.run("hello")[:status]).to eq(:success)
    expect(tail).to eq([true])
  end

  it "does not emit completion for a goal control command with no task" do
    allow(agent).to receive(:handle_goal_command).and_return(handled: true, result: {status: :success})
    agent.run("/goal status")
    expect(seen).to be_empty
  end

  it "does not let an unwinding old task settle a newer task" do
    allow(agent).to receive(:think) do
      agent.instance_variable_set(:@current_task_id, 99)
      raise Clacky::AgentInterrupted
    end
    expect { agent.run("hello") }.to raise_error(Clacky::AgentInterrupted)
    expect(seen).to be_empty
  end

  it "settles each queued task only when it actually runs" do
    starts = []
    agent.add_hook(:on_start) { |input, _owner, context| starts << [input, context] }
    agent.enqueue_input("queued", created_at: 123)
    expect(starts).to be_empty
    agent.run_pending_input(agent.take_pending_input)
    expect(starts.size).to eq(1)
    expect(seen.size).to eq(1)
  end
end
