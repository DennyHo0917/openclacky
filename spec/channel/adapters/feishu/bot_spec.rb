# frozen_string_literal: true

require "clacky/server/channel/adapters/feishu/adapter"

RSpec.describe Clacky::Channel::Adapters::Feishu::Bot do
  let(:bot) do
    described_class.new(app_id: "cli_test", app_secret: "secret")
  end

  describe "#with_token_retry" do
    it "returns the response when the token is valid" do
      result = bot.send(:with_token_retry) { { "code" => 0 } }
      expect(result).to eq("code" => 0)
    end

    it "clears the token cache and retries once when token is invalid (99991663)" do
      bot.instance_variable_set(:@token_cache, "stale-token")
      bot.instance_variable_set(:@token_expires_at, Time.now + 3600)

      calls = 0
      result = bot.send(:with_token_retry) do
        calls += 1
        calls == 1 ? { "code" => 99991663 } : { "code" => 0, "msg" => "success" }
      end

      expect(result).to eq("code" => 0, "msg" => "success")
      expect(calls).to eq(2)
      expect(bot.instance_variable_get(:@token_cache)).to be_nil
      expect(bot.instance_variable_get(:@token_expires_at)).to be_nil
    end

    it "does not retry when the error is unrelated" do
      calls = 0
      result = bot.send(:with_token_retry) do
        calls += 1
        { "code" => 99991672, "msg" => "scope missing" }
      end

      expect(result["code"]).to eq(99991672)
      expect(calls).to eq(1)
    end
  end

  describe "authenticated requests retry on token revocation" do
    it "wraps post with token retry and refreshes the cached token" do
      bot.instance_variable_set(:@token_cache, "stale-token")
      bot.instance_variable_set(:@token_expires_at, Time.now + 3600)

      conn = double("conn")
      resp1 = double("resp1", success?: true, body: JSON.generate("code" => 99991663))
      resp2 = double("resp2", success?: true, body: JSON.generate("code" => 0, "msg" => "ok"))

      calls = 0
      allow(conn).to receive(:post) do |_path, &block|
        # Faraday executes the request block, which calls tenant_access_token
        req = double("req")
        allow(req).to receive(:headers).and_return({})
        allow(req).to receive(:params).and_return({})
        allow(req).to receive(:body=)
        block.call(req)
        calls += 1
        calls == 1 ? resp1 : resp2
      end

      allow(bot).to receive(:build_connection).and_return(conn)
      allow(bot).to receive(:post_without_auth).and_return(
        "code" => 0, "tenant_access_token" => "fresh-token"
      )

      result = bot.send(:post, "/open-apis/im/v1/messages", { receive_id: "oc_1" })

      expect(result["code"]).to eq(0)
      expect(calls).to eq(2)
      expect(bot.instance_variable_get(:@token_cache)).to eq("fresh-token")
    end

    it "wraps put with token retry" do
      conn = double("conn")
      response = double("response", success?: true, body: JSON.generate("code" => 0))
      request = double("request", headers: {})
      allow(request).to receive(:body=)
      allow(conn).to receive(:put).and_yield(request).and_return(response)
      allow(bot).to receive(:build_connection).and_return(conn)
      allow(bot).to receive(:tenant_access_token).and_return("token")

      result = bot.send(:put, "/open-apis/cardkit/v1/cards/card_1/settings", { sequence: 2 })

      expect(result).to eq("code" => 0)
      expect(conn).to have_received(:put)
    end
  end

  describe "progress cards" do
    let(:inserts) { [] }
    let(:insert_codes) { [] }

    before do
      allow(bot).to receive(:post) do |path, payload, params: {}|
        case path
        when "/open-apis/cardkit/v1/cards"
          { "code" => 0, "data" => { "card_id" => "card_progress" } }
        when "/open-apis/im/v1/messages/om_user/reply"
          { "code" => 0, "data" => { "message_id" => "om_progress" } }
        when "/open-apis/cardkit/v1/cards/card_progress/elements"
          inserts << payload
          { "code" => insert_codes.shift || 0 }
        else
          raise "Unexpected POST #{path} payload=#{payload.inspect} params=#{params.inspect}"
        end
      end
    end

    it "creates a native streaming CardKit card and replies with its card reference" do
      result = bot.send_progress_card("oc_chat", { "zh" => "思考中...", "en" => "Thinking..." }, reply_to: "om_user")

      expect(bot).to have_received(:post).with("/open-apis/cardkit/v1/cards", satisfy { |payload|
        card = JSON.parse(payload[:data])
        elements = card.dig("body", "elements")
        payload[:type] == "card_json" &&
          card["schema"] == "2.0" &&
          card.dig("config", "streaming_mode") == true &&
          card.dig("config", "summary") == {
            "content" => "[Generating...]",
            "i18n_content" => { "zh_cn" => "[生成中...]", "en_us" => "[Generating...]" }
          } &&
          elements.size == 2 &&
          elements[0]["element_id"] == "content" &&
          elements[1] == {
            "tag" => "markdown",
            "element_id" => "status",
            "content" => "<font color='grey'>Thinking...</font>",
            "i18n_content" => {
              "zh_cn" => "<font color='grey'>思考中...</font>",
              "en_us" => "<font color='grey'>Thinking...</font>"
            }
          }
      })
      expect(bot).to have_received(:post).with(
        "/open-apis/im/v1/messages/om_user/reply",
        {
          msg_type: "interactive",
          content: JSON.generate({ type: "card", data: { card_id: "card_progress" } })
        }
      )

      expect(result).to eq(message_id: "om_progress", progress_id: "card_progress")
    end

    it "replaces the status element with a plain status string" do
      bot.send_progress_card("oc_chat", "Thinking...", reply_to: "om_user")
      expect(bot).to receive(:put) do |path, payload|
        expect(path).to eq("/open-apis/cardkit/v1/cards/card_progress/elements/status")
        expect(payload).to include(sequence: 2, uuid: "r_card_progress_2")
        expect(JSON.parse(payload[:element])).to eq(
          "tag" => "markdown",
          "element_id" => "status",
          "content" => "<font color='grey'>$ ls</font>"
        )
        { "code" => 0 }
      end

      expect(bot.update_progress_card("card_progress", "$ ls", state: :working)).to be true
    end

    it "replaces the status element with localized status text" do
      bot.send_progress_card("oc_chat", "Thinking...", reply_to: "om_user")
      status_element = nil
      allow(bot).to receive(:put) do |_path, payload|
        status_element = JSON.parse(payload[:element])
        { "code" => 0 }
      end

      bot.update_progress_card("card_progress", { "zh" => "处理中...", "en" => "Working..." }, state: :working)

      expect(status_element).to include(
        "content" => "<font color='grey'>Working...</font>",
        "i18n_content" => {
          "zh_cn" => "<font color='grey'>处理中...</font>",
          "en_us" => "<font color='grey'>Working...</font>"
        }
      )
    end

    it "inserts the process panel on first history, then replaces its content" do
      bot.send_progress_card("oc_chat", "Thinking...", reply_to: "om_user")
      calls = []
      allow(bot).to receive(:put) do |path, payload|
        calls << [path, payload]
        { "code" => 0 }
      end

      expect(bot.update_progress_card(
        "card_progress",
        "Working...",
        state: :working,
        content: "Latest step",
        history: "First step\n\nLatest step"
      )).to be true

      expect(inserts.size).to eq(1)
      expect(inserts[0]).to include(
        type: "insert_before",
        target_element_id: "content",
        sequence: 2,
        uuid: "i_card_progress_2"
      )
      panel = JSON.parse(inserts[0][:elements]).first
      expect(panel).to include("tag" => "collapsible_panel", "expanded" => false)
      expect(panel.dig("header", "title")).to eq(
        "tag" => "plain_text",
        "text_color" => "grey",
        "text_size" => "notation",
        "content" => "View process",
        "i18n_content" => { "zh_cn" => "查看过程", "en_us" => "View process" }
      )
      expect(panel.dig("header", "icon", "color")).to eq("grey")
      expect(panel.dig("border", "color")).to eq("grey")
      expect(panel.dig("elements", 0)).to include(
        "text_size" => "notation",
        "element_id" => "process_history",
        "content" => "First step\n\nLatest step"
      )
      expect(calls.map(&:first)).to eq([
        "/open-apis/cardkit/v1/cards/card_progress/elements/content",
        "/open-apis/cardkit/v1/cards/card_progress/elements/status"
      ])
      content_element = JSON.parse(calls[0][1][:element])
      expect(content_element).to include(
        "element_id" => "content",
        "content" => "Latest step"
      )
      expect(JSON.parse(calls[1][1][:element])).to include(
        "content" => "<font color='grey'>Working...</font>"
      )

      calls.clear
      bot.update_progress_card("card_progress", "Working...", state: :working, history: "First step\n\nNext step")

      expect(inserts.size).to eq(1)
      expect(calls[0][0]).to eq("/open-apis/cardkit/v1/cards/card_progress/elements/process_history")
      expect(JSON.parse(calls[0][1][:element])).to eq(
        "tag" => "markdown",
        "element_id" => "process_history",
        "text_size" => "notation",
        "content" => "First step\n\nNext step"
      )
    end

    it "retries inserting the process panel after a failed insert" do
      insert_codes << 230001
      bot.send_progress_card("oc_chat", "Thinking...", reply_to: "om_user")
      paths = []
      allow(bot).to receive(:put) do |path, _payload|
        paths << path
        { "code" => 0 }
      end

      bot.update_progress_card("card_progress", "Working...", state: :working, history: "Step 1")
      bot.update_progress_card("card_progress", "Working...", state: :working, history: "Step 2")

      expect(inserts.size).to eq(2)
      expect(JSON.parse(inserts[1][:elements]).first.dig("elements", 0, "content")).to eq("Step 2")
      expect(paths).not_to include("/open-apis/cardkit/v1/cards/card_progress/elements/process_history")
    end

    it "inserts the process panel when history first arrives at finalize" do
      bot.send_progress_card("oc_chat", "Thinking...", reply_to: "om_user")
      allow(bot).to receive(:put).and_return("code" => 0)
      allow(bot).to receive(:patch).and_return("code" => 0)

      expect(bot.update_progress_card("card_progress", "Finished", state: :success, history: "Only step")).to be true
      expect(inserts.size).to eq(1)
      expect(JSON.parse(inserts[0][:elements]).first.dig("elements", 0, "content")).to eq("Only step")
    end

    it "writes final content, marks the status done, and closes streaming mode" do
      bot.send_progress_card("oc_chat", "Thinking...", reply_to: "om_user")
      calls = []
      allow(bot).to receive(:put) do |path, payload|
        calls << [path, payload]
        { "code" => 0 }
      end
      expect(bot).to receive(:patch) do |path, payload|
        expect(path).to eq("/open-apis/cardkit/v1/cards/card_progress/settings")
        settings = JSON.parse(payload[:settings])
        expect(settings.dig("config", "streaming_mode")).to be false
        expect(settings.dig("config", "summary", "content")).to eq("Finished")
        expect(payload[:sequence]).to eq(4)
        { "code" => 0 }
      end

      expect(bot.update_progress_card("card_progress", "Finished", state: :success)).to be true
      expect(inserts).to be_empty
      expect(calls.size).to eq(2)
      expect(calls[0][0]).to eq(
        "/open-apis/cardkit/v1/cards/card_progress/elements/content"
      )
      content_element = JSON.parse(calls[0][1][:element])
      expect(calls[0][1]).to include(
        sequence: 2
      )
      expect(content_element).to include(
        "element_id" => "content",
        "content" => "Finished"
      )
      expect(calls[1][0]).to eq(
        "/open-apis/cardkit/v1/cards/card_progress/elements/status"
      )
      expect(calls[1][1]).to include(sequence: 3)
      expect(JSON.parse(calls[1][1][:element])).to include(
        "content" => "<font color='grey'>Done</font>",
        "i18n_content" => {
          "zh_cn" => "<font color='grey'>已完成</font>",
          "en_us" => "<font color='grey'>Done</font>"
        }
      )
    end

    it "localizes the final content and summary when given translations" do
      bot.send_progress_card("oc_chat", "Thinking...", reply_to: "om_user")
      content_element = nil
      allow(bot).to receive(:put) do |path, payload|
        content_element = JSON.parse(payload[:element]) if path.end_with?("/elements/content")
        { "code" => 0 }
      end
      summary = nil
      allow(bot).to receive(:patch) do |_path, payload|
        summary = JSON.parse(payload[:settings]).dig("config", "summary")
        { "code" => 0 }
      end

      expect(bot.update_progress_card(
        "card_progress",
        { "zh" => "任务已中断。", "en" => "Task interrupted." },
        state: :interrupted
      )).to be true
      expect(content_element).to include(
        "content" => "Task interrupted.",
        "i18n_content" => { "zh_cn" => "任务已中断。", "en_us" => "Task interrupted." }
      )
      expect(summary).to eq(
        "content" => "Task interrupted.",
        "i18n_content" => { "zh_cn" => "任务已中断。", "en_us" => "Task interrupted." }
      )
    end

    it "reports a failed final content update so the caller can fall back" do
      bot.send_progress_card("oc_chat", "Thinking...", reply_to: "om_user")
      allow(bot).to receive(:put) do |path, _payload|
        if path.end_with?("/elements/content")
          { "code" => 230001, "msg" => "invalid card" }
        else
          { "code" => 0 }
        end
      end
      allow(bot).to receive(:patch).and_return("code" => 0)

      expect(bot.update_progress_card("card_progress", "Finished", state: :success)).to be false
      expect(bot.update_progress_card("card_progress", "Finished", state: :success)).to be false
    end

    {
      failed: ["Failed", "失败"],
      interrupted: ["Stopped", "已停止"],
      waiting: ["Waiting for input", "等待输入"]
    }.each do |state, (label, zh_label)|
      it "marks a #{state} task as #{label}" do
        bot.send_progress_card("oc_chat", "Thinking...", reply_to: "om_user")
        status_element = nil
        allow(bot).to receive(:put) do |path, payload|
          status_element = JSON.parse(payload[:element]) if path.end_with?("/elements/status")
          { "code" => 0 }
        end
        allow(bot).to receive(:patch).and_return("code" => 0)

        expect(bot.update_progress_card("card_progress", "Result", state: state)).to be true
        expect(status_element["i18n_content"]).to eq(
          "zh_cn" => "<font color='grey'>#{zh_label}</font>",
          "en_us" => "<font color='grey'>#{label}</font>"
        )
      end
    end
  end
end
