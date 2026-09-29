# frozen_string_literal: true

require "spec_helper"
require "clacky/server/channel"

RSpec.describe Clacky::Channel::Adapters::Feishu::Adapter do
  let(:bot) { instance_double(Clacky::Channel::Adapters::Feishu::Bot) }
  let(:routed) { [] }
  let(:allowed_users) { nil }
  let(:adapter) do
    described_class.new(app_id: "cli_test", app_secret: "secret", allowed_users: allowed_users).tap do |a|
      a.instance_variable_set(:@bot, bot)
      a.instance_variable_set(:@on_message, ->(event) { routed << event })
    end
  end
  let(:callback) do
    {
      "event" => {
        "operator" => { "open_id" => "ou_user" },
        "action" => { "value" => { "question_card" => "tok", "question" => 0, "option" => 1 } },
        "context" => { "open_chat_id" => "oc_chat", "open_message_id" => "om_card" }
      }
    }
  end

  before do
    allow(Clacky::ThreadRegistry).to receive(:spawn) { |_opts, &block| block.call }
  end

  describe "#handle_card_action" do
    it "routes a completed card answer back as an inbound message" do
      allow(bot).to receive(:answer_question_card).with(callback)
        .and_return(reply: { toast: { type: "success" } }, text: "Sushi")

      expect(adapter.handle_card_action(callback)).to eq(toast: { type: "success" })
      expect(routed.size).to eq(1)
      expect(routed.first).to include(
        type: :message,
        platform: :feishu,
        chat_id: "oc_chat",
        user_id: "ou_user",
        text: "Sushi",
        message_id: "om_card",
        chat_type: :direct
      )
    end

    it "answers the click without routing while questions remain" do
      allow(bot).to receive(:answer_question_card).and_return(reply: {}, text: nil)

      expect(adapter.handle_card_action(callback)).to eq({})
      expect(routed).to be_empty
    end

    context "with an allowed users list" do
      let(:allowed_users) { ["ou_other"] }

      it "ignores clicks from anyone else" do
        expect(bot).not_to receive(:answer_question_card)

        expect(adapter.handle_card_action(callback)).to eq({})
        expect(routed).to be_empty
      end
    end

    it "keeps the callback answerable when the bot raises" do
      allow(bot).to receive(:answer_question_card).and_raise(StandardError, "boom")

      expect(adapter.handle_card_action(callback)).to eq({})
      expect(routed).to be_empty
    end
  end

  describe "#handle_message_event" do
    let(:message) { { type: :message, platform: :feishu, chat_id: "oc_chat", user_id: "ou_user", text: "Sushi", chat_type: :direct } }

    it "forgets the pending cards of the chat so its buttons cannot answer again" do
      expect(bot).to receive(:forget_question_cards).with("oc_chat")

      adapter.handle_message_event(message)

      expect(routed).to eq([message])
    end

    it "leaves the cards alone for a message it drops" do
      expect(bot).not_to receive(:forget_question_cards)

      adapter.handle_message_event(message.merge(unsupported: true))
    end
  end
end
