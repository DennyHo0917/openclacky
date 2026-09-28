# frozen_string_literal: true

require "spec_helper"
require "clacky/server/channel"

RSpec.describe Clacky::Utils::ChannelPrompt do
  let(:history) { [{ user_id: "ou_a", text: "早" }, { user_id: "ou_b", text: "午\n饭" }] }

  describe ".build" do
    it "prefixes a single-chat message with the sender line" do
      expect(described_class.build("你好", sender: "ou_abc")).to eq("[Sender: ou_abc]\n你好")
    end

    it "wraps group chat history before the sender line" do
      expect(described_class.build("你好", sender: "ou_abc", history: history.first(1)))
        .to eq("[Group chat history (1 messages)]\nou_a: 早\n---\n[Sender: ou_abc]\n你好")
    end

    it "treats empty history as a single chat" do
      expect(described_class.build("你好", sender: "ou_abc", history: [])).to eq("[Sender: ou_abc]\n你好")
    end
  end

  describe ".strip round-trip" do
    ["你好", "line1\nline2", "a\n---\nb", "[Sender: typed]\nhi", ""].each do |text|
      it "recovers #{text.inspect} from a single-chat prompt" do
        expect(described_class.strip(described_class.build(text, sender: "ou_abc"))).to eq(text)
      end

      it "recovers #{text.inspect} from a group-chat prompt" do
        prompt = described_class.build(text, sender: "ou_abc", history: history)
        expect(described_class.strip(prompt)).to eq(text)
      end
    end

    it "leaves text without a channel prefix untouched" do
      expect(described_class.strip("hello [Sender: x]\nworld")).to eq("hello [Sender: x]\nworld")
    end

    it "tolerates nil" do
      expect(described_class.strip(nil)).to eq("")
    end
  end

  describe "ChannelManager integration" do
    let(:manager) do
      Clacky::Channel::ChannelManager.new(
        session_registry: nil, session_builder: nil, run_agent_task: nil,
        interrupt_session: nil, channel_config: nil
      )
    end

    it "strips what ChannelManager actually builds for single chats" do
      prompt = manager.send(:build_prompt_with_context, { user_id: "ou_abc" }, "你好")
      expect(described_class.strip(prompt)).to eq("你好")
    end

    it "strips what ChannelManager actually builds for group chats" do
      prompt = manager.send(:build_prompt_with_context, { user_id: "ou_abc", group_history: history }, "你好")
      expect(described_class.strip(prompt)).to eq("你好")
    end
  end
end
