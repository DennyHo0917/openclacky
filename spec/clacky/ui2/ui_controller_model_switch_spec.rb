# frozen_string_literal: true

require "spec_helper"
require "clacky/ui2/ui_controller"

# Tests for the `/model` card list. The modal is stubbed so the spec only
# exercises choice construction: which entries make the list and where the
# current-model bullet lands once sidecar entries are filtered out.
RSpec.describe Clacky::UI2::UIController, "#show_model_switch_modal" do
  let(:controller) { described_class.new }
  let(:modal) { instance_double(Clacky::UI2::Components::ModalComponent) }
  let(:submodels_for) { ->(_model) { [] } }

  let(:config) do
    Clacky::AgentConfig.new(
      models: [
        { "id" => "id-stt", "type" => "stt", "mode" => "auto" },
        { "id" => "id-a", "model" => "chat-a" },
        { "id" => "id-img", "model" => "gpt-image-1", "type" => "image", "mode" => "custom" },
        { "id" => "id-b", "model" => "chat-b", "type" => "default" }
      ],
      current_model_id: "id-b"
    )
  end

  before do
    allow(Clacky::UI2::Components::ModalComponent).to receive(:new).and_return(modal)
    controller.instance_variable_set(:@layout, double("layout", rerender_all: nil))
  end

  def card_choices(cfg = config)
    choices = nil
    allow(modal).to receive(:show) { |**kw| choices = kw[:choices]; nil }
    controller.show_model_switch_modal(cfg, submodels_for)
    choices
  end

  it "omits sidecar entries from the card list" do
    expect(card_choices.map { |c| c[:value][:card_model] }).to eq(["chat-a", "chat-b"])
  end

  it "marks the current model after filtering shifts the positions" do
    choices = card_choices
    expect(choices[1][:name]).to start_with("● chat-b")
    expect(choices.count { |c| c[:name].start_with?("●") }).to eq(1)
  end

  it "returns nil when every entry is a sidecar" do
    sidecar_only = Clacky::AgentConfig.new(
      models: [{ "id" => "id-stt", "type" => "stt", "mode" => "auto" }]
    )
    expect(modal).not_to receive(:show)
    expect(controller.show_model_switch_modal(sidecar_only, submodels_for)).to be_nil
  end
end
