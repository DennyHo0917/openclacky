# frozen_string_literal: true

require "spec_helper"
require "clacky/server/channel"

RSpec.describe Clacky::Channel::Adapters::Feishu::WSClient do
  let(:client) { described_class.new(app_id: "cli_test", app_secret: "secret") }
  let(:frames) { [] }
  let(:frame) do
    {
      seq_id: 7,
      log_id: "log_1",
      service: 1,
      method: 1,
      headers: { "type" => frame_type, "message_id" => "m_1" },
      payload: JSON.generate(payload)
    }
  end

  before do
    rec = frames
    allow(client).to receive(:send_frame) { |args| rec << args }
  end

  def handle
    client.send(:handle_data_frame, frame, frame[:headers])
  end

  def response_body
    JSON.parse(frames.first[:payload])
  end

  context "with an event frame" do
    let(:frame_type) { "event" }
    let(:payload) { { "header" => { "event_type" => "im.message.receive_v1" } } }

    it "acknowledges the frame and dispatches the event" do
      dispatched = []
      client.instance_variable_set(:@on_event, ->(data) { dispatched << data })

      handle

      expect(dispatched).to eq([payload])
      expect(response_body).to eq("code" => 200)
    end
  end

  context "with a card callback frame" do
    let(:frame_type) { "card" }
    let(:payload) { { "event" => { "action" => { "value" => { "option" => 1 } } } } }

    it "answers the frame with the base64-encoded handler reply" do
      client.instance_variable_set(:@on_card_action, ->(_data) { { toast: { type: "success" } } })

      handle

      expect(response_body["code"]).to eq(200)
      expect(JSON.parse(Base64.strict_decode64(response_body["data"]))).to eq("toast" => { "type" => "success" })
    end

    it "still answers the frame when the handler raises" do
      client.instance_variable_set(:@on_card_action, ->(_data) { raise "boom" })

      handle

      expect(response_body).to eq("code" => 200)
    end
  end

  context "with a card.action.trigger event frame" do
    let(:frame_type) { "event" }
    let(:payload) do
      {
        "schema" => "2.0",
        "header" => { "event_type" => "card.action.trigger" },
        "event" => { "action" => { "value" => { "option" => 1 } } }
      }
    end

    it "routes it to the card handler and answers with its reply" do
      handled = []
      dispatched = []
      client.instance_variable_set(:@on_card_action, ->(data) { handled << data; { toast: { type: "success" } } })
      client.instance_variable_set(:@on_event, ->(data) { dispatched << data })

      handle

      expect(handled).to eq([payload])
      expect(dispatched).to be_empty
      expect(frames.size).to eq(1)
      expect(JSON.parse(Base64.strict_decode64(response_body["data"]))).to eq("toast" => { "type" => "success" })
    end
  end
end
