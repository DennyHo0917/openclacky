# frozen_string_literal: true

require "spec_helper"

RSpec.describe Clacky::ExtensionHookLoader do
  let(:builtin)   { Dir.mktmpdir }
  let(:installed) { Dir.mktmpdir }
  let(:local)     { Dir.mktmpdir }

  after do
    [builtin, installed, local].each { |d| FileUtils.remove_entry(d) if Dir.exist?(d) }
    Clacky::ExtensionLoader.instance_variable_set(:@last_result, nil)
    Clacky::ExtensionHookRegistry.clear!
  end

  def make_ext(root, ext_id, manifest, files = {})
    dir = File.join(root, ext_id)
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, "ext.yml"), manifest)
    files.each do |rel, content|
      path = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
    end
  end

  def reload_layers
    Clacky::ExtensionLoader.load_all(
      layers: { builtin: builtin, installed: installed, local: local }
    )
  end

  it "registers a hook callback the agent can later apply" do
    manifest = <<~YAML
      id: audit-pack
      origin: self
      contributes:
        hooks:
          - event: before_tool_use
            file: hooks/audit.rb
    YAML
    hook_file = <<~RUBY
      Clacky::ExtensionHookRegistry.add do |tool, *_args|
        $audit_seen ||= []
        $audit_seen << tool
        { action: :allow }
      end
    RUBY
    make_ext(local, "audit-pack", manifest, "hooks/audit.rb" => hook_file)

    reload_layers
    result = described_class.load_all

    expect(result.skipped).to be_empty
    expect(result.registered.size).to eq(1)

    hm = Clacky::HookManager.new
    Clacky::ExtensionHookRegistry.apply_to(hm)
    $audit_seen = nil
    hm.trigger(:before_tool_use, "shell")
    expect($audit_seen).to eq(["shell"])
  ensure
    $audit_seen = nil
  end

  it "skips a hook with an unknown event" do
    manifest = <<~YAML
      id: bad-event-pack
      origin: self
      contributes:
        hooks:
          - event: bogus_event
            file: hooks/noop.rb
    YAML
    make_ext(local, "bad-event-pack", manifest, "hooks/noop.rb" => "# noop")

    reload_layers
    result = described_class.load_all

    expect(result.registered).to be_empty
    expect(result.skipped.first[1]).to match(/unknown event/)
  end

  it "isolates a hook file that raises during load" do
    manifest = <<~YAML
      id: crash-pack
      origin: self
      contributes:
        hooks:
          - event: on_complete
            file: hooks/crash.rb
    YAML
    make_ext(local, "crash-pack", manifest, "hooks/crash.rb" => "raise 'boom'")

    reload_layers
    result = described_class.load_all

    expect(result.registered).to be_empty
    expect(result.skipped.first[1]).to match(/boom/)
  end
  it "loads lifecycle scope from the manifest without changing legacy callbacks" do
    manifest = <<~YAML
      id: lifecycle-pack
      origin: self
      contributes:
        hooks:
          - event: on_complete
            scope: lifecycle
            file: hooks/lifecycle.rb
          - event: on_complete
            file: hooks/legacy.rb
    YAML
    make_ext(local, "lifecycle-pack", manifest,
      "hooks/lifecycle.rb" => 'Clacky::ExtensionHookRegistry.add { |result, agent, context| $lifecycle_seen << [result, agent, context] }',
      "hooks/legacy.rb" => 'Clacky::ExtensionHookRegistry.add { |*args| $legacy_seen << args }')
    reload_layers
    expect(described_class.load_all.skipped).to be_empty
    owner = Object.new
    hm = Clacky::HookManager.new(agent: owner)
    Clacky::ExtensionHookRegistry.apply_to(hm)
    $legacy_seen, $lifecycle_seen = [], []
    hm.trigger(:on_complete, {status: :success})
    expect($legacy_seen).to eq([[{status: :success}, owner]])
    expect($lifecycle_seen).to be_empty
    hm.notify_lifecycle(:on_complete, {status: :error}, {status: "failed"})
    expect($legacy_seen.size).to eq(1)
    expect($lifecycle_seen).to eq([[{status: :error}, owner, {status: "failed"}]])
  ensure
    $legacy_seen = $lifecycle_seen = nil
  end

  it "rejects lifecycle scope on tool hooks instead of running it as a legacy hook" do
    manifest = <<~YAML
      id: invalid-scope-pack
      origin: self
      contributes:
        hooks:
          - event: before_tool_use
            scope: lifecycle
            file: hooks/noop.rb
    YAML
    make_ext(local, "invalid-scope-pack", manifest, "hooks/noop.rb" => 'raise "must not load"')
    reload_layers
    result = described_class.load_all
    expect(result.registered).to be_empty
    expect(result.skipped.first[1]).to match(/Invalid hook scope/)
  end

end
