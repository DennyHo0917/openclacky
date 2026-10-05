# frozen_string_literal: true
require "spec_helper"
require "clacky/server/http_server"

RSpec.describe "Server session observation hooks" do
  let(:config) { Clacky::AgentConfig.new }
  let(:registry) { Clacky::Server::SessionRegistry.new(agent_config: config) }
  let(:events) { Queue.new }
  let(:agent) { double("agent", to_session_data: {}, take_pending_input: nil) }
  let(:server) do
    Clacky::Server::HttpServer.allocate.tap do |s|
      s.instance_variable_set(:@registry, registry)
      s.instance_variable_set(:@agent_config, config)
      s.instance_variable_set(:@session_manager, double("sessions", save: nil))
    end
  end

  before do
    registry.create(session_id: "s")
    registry.with_session("s") { |s| s[:agent] = agent }
    allow(registry).to receive(:evict_excess_idle!)
    [:broadcast_session_update, :broadcast_all, :broadcast].each { |method| allow(server).to receive(method) }
    allow(agent).to receive(:notify_session_lifecycle) { |event, _value, payload| events << [event, payload] }
  end

  def observations
    rows = []
    rows << events.pop until events.empty?
    rows
  end

  [[:success, false, "completed"], [:success, true, "awaiting_user"], [:error, false, "failed"]].each do |status, waiting, expected|
    it "reports #{expected} even when a run returns without on_complete" do
      worker = server.send(:run_agent_task, "s", agent) { { status: status, awaiting_user_feedback: waiting } }
      expect(worker.join(2)).not_to be_nil
      rows = observations
      expect(rows.map { |_, data| data[:status] }).to eq(["running", expected])
      expect(rows.map { |_, data| data[:run_id] }.uniq).to eq(["1"])
      expect(rows.all? { |event, data| [:on_start, :on_complete].include?(event) && Time.iso8601(data[:observed_at]) }).to be(true)
    end
  end

  it "reports exceptions and interruption without relying on completion hooks" do
    [RuntimeError.new("failed"), Clacky::AgentInterrupted.new].each do |error|
      worker = server.send(:run_agent_task, "s", agent) { raise error }
      expect(worker.join(2)).not_to be_nil
      expect(observations.last[1][:status]).to eq(error.is_a?(Clacky::AgentInterrupted) ? "cancelled" : "failed")
    end
  end

  it "emits only a failed terminal observation when final persistence raises" do
    store = server.instance_variable_get(:@session_manager)
    calls = 0
    allow(store).to receive(:save) do
      calls += 1
      raise "final save failed" if calls == 2
    end
    worker = server.send(:run_agent_task, "s", agent) { { status: :success } }
    worker.join(2)
    expect(observations.map { |_, data| data[:status] }).to eq(["running", "failed"])
  end

  it "does not let a superseded worker publish its terminal state" do
    entered, finish = Queue.new, Queue.new
    worker = server.send(:run_agent_task, "s", agent) { entered << true; finish.pop; { status: :success } }
    entered.pop
    registry.claim_epoch("s")
    finish << true
    worker.join(2)
    expect(observations.map { |_, data| data[:status] }).to eq(["running"])
  ensure
    worker&.kill if worker&.alive?
  end

  %w[queue steer].each do |mode|
    it "observes #{mode} input immediately without starting another run" do
      config.input_behavior = mode
      registry.with_session("s") { |s| s[:status] = :running }
      allow(agent).to receive(:enqueue_input)
      server.send(:handle_user_message, "s", "private content")
      rows = observations
      expect(rows.size).to eq(1)
      expect(rows.first[0]).to eq(:on_start)
      expect(rows.first[1][:source]).to eq("web")
      expect(rows.first[1]).not_to have_key(:content)
    end
  end

  it "reports structured credit errors without exposing error text" do
    worker = server.send(:run_agent_task, "s", agent) do
      raise Clacky::InsufficientCreditError.new("private upstream detail", error_code: "insufficient_credit")
    end
    worker.join(2)
    payload = observations.last[1]
    expect(payload[:status]).to eq("failed")
    expect(payload[:error_code]).to eq("insufficient_credit")
    expect(payload).not_to have_key(:message)
  end

  it "observes a direct web input once when the server starts it" do
    allow(agent).to receive(:history).and_return([{}])
    allow(agent).to receive(:parse_skill_command).and_return(found: false)
    allow(agent).to receive(:run).and_return(status: :success)
    worker = server.send(:handle_user_message, "s", "hello")
    worker.join(2)
    rows = observations
    expect(rows.map(&:first)).to eq([:on_start, :on_start, :on_complete])
  end

  it "does not report input accepted when server capacity rejects the run" do
    allow(agent).to receive(:history).and_return([{}])
    allow(agent).to receive(:parse_skill_command).and_return(found: false)
    allow(registry).to receive(:running_full?).and_return(true)
    server.send(:handle_user_message, "s", "hello")
    expect(observations).to be_empty
  end

  it "ignores observer verdicts and isolates observer failures" do
    real = Clacky::Agent.allocate
    real.instance_variable_set(:@session_id, "s")
    hooks = Clacky::HookManager.new(agent: real)
    real.instance_variable_set(:@hooks, hooks)
    hooks.add(:on_complete, scope: :lifecycle) { raise "broken observer" }
    hooks.add(:on_complete, scope: :lifecycle) { { action: :deny } }
    hooks.add(:on_complete, scope: :lifecycle) { |_result, owner, data| events << [data, owner] }
    real.notify_session_lifecycle(:on_complete, { status: :success }, status: "completed")
    data, owner = events.pop
    expect(data).to eq(session_id: "s", status: "completed")
    expect(owner).to be(real)
  end
end
