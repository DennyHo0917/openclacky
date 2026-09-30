# frozen_string_literal: true

require "spec_helper"
require "clacky/rich_ui/view_renderer"

RSpec.describe Clacky::RichUI::ViewRenderer, ".config_menu_choices" do
  let(:config) do
    Clacky::AgentConfig.new(
      models: [
        { "id" => "id-stt", "type" => "stt", "mode" => "auto" },
        { "id" => "id-a", "model" => "chat-a", "api_key" => "sk-aaaa1111bbbb2222" },
        { "id" => "id-b", "model" => "chat-b", "type" => "default", "api_key" => "sk-cccc3333dddd4444" }
      ],
      current_model_id: "id-b"
    )
  end

  def model_choices(cfg = config)
    described_class.config_menu_choices(cfg).select { |c| c.dig(:value, :action) == :switch }
  end

  it "omits sidecar entries" do
    expect(model_choices.map { |c| c[:value][:model_id] }).to eq(["id-a", "id-b"])
  end

  it "flags the current model after filtering shifts the positions" do
    choices = model_choices
    expect(choices.select { |c| c[:current] }.map { |c| c[:value][:model_id] }).to eq(["id-b"])
  end
end
