# frozen_string_literal: true

require "spec_helper"
require "clacky/server/channel"

RSpec.describe Clacky::Channel::ChannelManager do
  let(:manager) do
    described_class.new(
      session_registry:  {},
      session_builder:   -> { nil },
      run_agent_task:    ->(*) {},
      interrupt_session: ->(*) {},
      channel_config:    {}
    )
  end

  let(:config) do
    Clacky::AgentConfig.new(models: [
      { "id" => "id-a", "model" => "chat-a" },
      { "id" => "id-stt", "type" => "stt", "mode" => "auto" },
      { "id" => "id-img", "model" => "gpt-image-1", "type" => "image", "mode" => "custom" },
      { "id" => "id-b", "model" => "chat-b", "type" => "default" }
    ])
  end

  let(:agent) do
    instance_double(
      Clacky::Agent,
      config:             config,
      available_models:   config.model_names,
      current_model_info: { model: "chat-a", card_model: "chat-a", base_url: "https://api.example.com" }
    )
  end

  let(:adapter) { double("adapter") }

  describe "#show_model_list" do
    it "lists chat models only, so numbering skips sidecar entries" do
      sent = nil
      allow(adapter).to receive(:send_text) { |_chat_id, text| sent = text }

      manager.show_model_list(adapter, "chat-1", agent)

      expect(sent).to include("1. chat-a")
      expect(sent).to include("2. chat-b")
      expect(sent).not_to include("gpt-image-1")
    end
  end

  describe "#switch_model_by_index" do
    it "resolves the number against the same list the user saw" do
      allow(adapter).to receive(:send_text)
      allow(agent).to receive(:switch_model_by_id).with("id-b").and_return(true)
      allow(agent).to receive(:current_model_info).and_return({ model: "chat-b" })

      manager.switch_model_by_index(adapter, "chat-1", agent, 1)

      expect(agent).to have_received(:switch_model_by_id).with("id-b")
    end

    it "rejects a number past the end of the chat model list" do
      sent = nil
      allow(adapter).to receive(:send_text) { |_chat_id, text| sent = text }
      allow(agent).to receive(:switch_model_by_id)

      manager.switch_model_by_index(adapter, "chat-1", agent, 2)

      expect(sent).to include("Invalid number")
      expect(agent).not_to have_received(:switch_model_by_id)
    end
  end
end
