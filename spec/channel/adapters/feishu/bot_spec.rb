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
        "content" => "<font color='green'>Done</font>",
        "i18n_content" => {
          "zh_cn" => "<font color='green'>已完成</font>",
          "en_us" => "<font color='green'>Done</font>"
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
      failed: ["Failed", "失败", "red"],
      interrupted: ["Stopped", "已停止", "grey"],
      waiting: ["Waiting for input", "等待输入", "orange"]
    }.each do |state, (label, zh_label, color)|
      it "marks a #{state} task as #{label}" do
        bot.send_progress_card("oc_chat", "Thinking...", reply_to: "om_user")
        status_element = nil
        allow(bot).to receive(:put) do |path, payload|
          status_element = JSON.parse(payload[:element]) if path.end_with?("/elements/status")
          { "code" => 0 }
        end
        allow(bot).to receive(:patch).and_return("code" => 0)

        expect(bot.update_progress_card("card_progress", "Result", state: state)).to be true
        expect(status_element["content"]).to eq("<font color='#{color}'>#{label}</font>")
        expect(status_element["i18n_content"]).to eq(
          "zh_cn" => "<font color='#{color}'>#{zh_label}</font>",
          "en_us" => "<font color='#{color}'>#{label}</font>"
        )
      end
    end
  end

  describe "question cards" do
    let(:questions) do
      [{
        question: "Dinner?",
        description: "",
        options: ["Hotpot", "Sushi"],
        multi: false,
        allow_free_text: true,
        recommended: 1
      }]
    end

    let(:sent) { [] }

    before do
      allow(bot).to receive(:post) do |path, payload, params: {}|
        sent << [path, payload, params]
        { "code" => 0, "data" => { "message_id" => "om_card" } }
      end
    end

    def click(token, question: 0, option: 0)
      bot.answer_question_card(
        "event" => { "action" => { "value" => { "question_card" => token, "question" => question, "option" => option } } }
      )
    end

    def card_token
      button = JSON.parse(sent.last[1][:content]).dig("body", "elements").find { |e| e["tag"] == "button" }
      button.dig("behaviors", 0, "value", "question_card")
    end

    it "renders one callback button per option and highlights the recommendation" do
      expect(bot.send_questions("oc_chat", questions, context: "Pick one", reply_to: "om_user")).to eq(message_id: "om_card")

      path, payload, params = sent.last
      expect(path).to eq("/open-apis/im/v1/messages")
      expect(params).to eq(receive_id_type: "chat_id")
      expect(payload[:msg_type]).to eq("interactive")
      expect(payload[:reply_to_message_id]).to eq("om_user")

      card = JSON.parse(payload[:content])
      expect(card["schema"]).to eq("2.0")
      elements = card.dig("body", "elements")
      expect(elements[0]["content"]).to eq("**Context:** Pick one")
      expect(elements[0]["i18n_content"]).to eq("zh_cn" => "**背景:** Pick one", "en_us" => "**Context:** Pick one")
      expect(elements[1]["content"]).to eq("**Question:** Dinner?")
      expect(elements[1]["i18n_content"]).to eq("zh_cn" => "**问题:** Dinner?", "en_us" => "**Question:** Dinner?")

      buttons = elements.select { |e| e["tag"] == "button" }
      expect(buttons.map { |b| b.dig("text", "content") }).to eq(["Hotpot", "Sushi"])
      expect(buttons.map { |b| b["type"] }).to eq(%w[default primary])
      expect(buttons[0]["behaviors"]).to eq([{
        "type" => "callback",
        "value" => { "question_card" => card_token, "question" => 0, "option" => 0 }
      }])
      expect(elements.last["content"]).to eq("Or reply with your own answer.")
    end

    it "returns the clicked option as the answer and replaces the buttons with it" do
      bot.send_questions("oc_chat", questions)

      result = click(card_token, option: 1)

      expect(result[:text]).to eq("Sushi")
      expect(result[:reply][:toast][:type]).to eq("success")
      expect(result[:reply][:toast][:i18n]).to eq("zh_cn" => "已记录你的选择", "en_us" => "Answer recorded")
      answered = result[:reply][:card][:data].dig(:body, :elements)
      expect(answered.none? { |e| e[:tag] == "button" }).to be true
      expect(answered.last[:content]).to eq("✅ Sushi")
    end

    it "waits for every question before answering and keeps unanswered buttons" do
      multi = questions + [{
        question: "Drink?",
        description: "",
        options: ["Tea"],
        multi: false,
        allow_free_text: false,
        recommended: nil
      }]
      bot.send_questions("oc_chat", multi)
      token = card_token

      first = click(token, question: 0, option: 0)
      expect(first[:text]).to be_nil
      remaining = first[:reply][:card][:data].dig(:body, :elements).select { |e| e[:tag] == "button" }
      expect(remaining.map { |b| b.dig(:text, :content) }).to eq(["Tea"])

      second = click(token, question: 1, option: 0)
      expect(second[:text]).to eq("Dinner?: Hotpot\nDrink?: Tea")
    end

    it "warns instead of answering when the card is no longer tracked" do
      result = click("gone")

      expect(result[:text]).to be_nil
      expect(result[:reply][:toast][:type]).to eq("warning")
      expect(result[:reply][:toast][:content]).to eq("This question is no longer active.")
    end

    it "ignores a click that is not a question card callback" do
      expect(bot.answer_question_card("event" => { "action" => {} })).to eq(reply: {})
    end

    it "declines questions without options" do
      expect(bot.send_questions("oc_chat", [questions.first.merge(options: [])])).to be_nil
      expect(bot.send_questions("oc_chat", [])).to be_nil
      expect(sent).to be_empty
    end

    context "with a multi-select question" do
      let(:questions) do
        [
          { question: "Toppings?", description: "", options: %w[Egg Tofu Beef], multi: true,
            allow_free_text: false, recommended: 0 },
          { question: "Size?", description: "", options: %w[Small Large], multi: false,
            allow_free_text: false, recommended: nil }
        ]
      end

      def submit(token)
        bot.answer_question_card("event" => { "action" => { "value" => { "question_card" => token, "submit" => true } } })
      end

      def buttons_of(reply)
        reply[:card][:data].dig(:body, :elements).select { |e| e[:tag] == "button" }
      end

      it "preselects the recommendation, hints multi-select and adds a submit button" do
        bot.send_questions("oc_chat", questions)

        elements = JSON.parse(sent.last[1][:content]).dig("body", "elements")
        buttons = elements.select { |e| e["tag"] == "button" }
        expect(buttons.map { |b| b["type"] }).to eq(%w[primary_filled default default default default primary_filled])
        expect(buttons.last.dig("text", "i18n_content")).to eq("zh_cn" => "提交", "en_us" => "Submit")
        expect(buttons.last.dig("behaviors", 0, "value")).to eq("question_card" => card_token, "submit" => true)
        expect(elements.map { |e| e["content"] }).to include("Select all that apply, then submit.")
      end

      it "toggles picks without answering, then submits every selection in option order" do
        bot.send_questions("oc_chat", questions)
        token = card_token

        toggled = click(token, question: 0, option: 2)
        expect(toggled[:text]).to be_nil
        expect(toggled[:reply]).not_to have_key(:toast)
        expect(buttons_of(toggled[:reply]).first(3).map { |b| b[:type] }).to eq(%w[primary_filled default primary_filled])

        click(token, question: 0, option: 0)
        click(token, question: 0, option: 1)
        click(token, question: 1, option: 0)
        switched = click(token, question: 1, option: 1)
        expect(switched[:text]).to be_nil
        expect(buttons_of(switched[:reply])[3, 2].map { |b| b[:type] }).to eq(%w[default primary_filled])

        result = submit(token)
        expect(result[:text]).to eq("Toppings?: Tofu; Beef\nSize?: Large")
        expect(buttons_of(result[:reply])).to be_empty
        expect(submit(token)[:reply][:toast][:type]).to eq("warning")
      end

      it "refuses to submit while a question has no pick" do
        bot.send_questions("oc_chat", questions)

        result = submit(card_token)

        expect(result[:text]).to be_nil
        expect(result[:reply][:toast][:type]).to eq("warning")
        expect(result[:reply][:toast][:i18n]).to eq("zh_cn" => "请先完成所有问题。", "en_us" => "Please answer every question first.")
      end
    end

    it "forgets the cards of one chat once the user answers by typing" do
      bot.send_questions("oc_chat", questions)
      typed = card_token
      bot.send_questions("oc_other", questions)
      untouched = card_token

      bot.forget_question_cards("oc_chat")

      expect(click(typed)[:reply][:toast][:type]).to eq("warning")
      expect(click(untouched)[:text]).to eq("Hotpot")
    end

    it "forgets a card whose send failed so a later click cannot answer it" do
      allow(bot).to receive(:post) do |path, payload, params: {}|
        sent << [path, payload, params]
        { "code" => 230001, "msg" => "nope" }
      end

      expect(bot.send_questions("oc_chat", questions)).to be_nil
      expect(click(card_token)[:reply][:toast][:type]).to eq("warning")
    end
  end
end
