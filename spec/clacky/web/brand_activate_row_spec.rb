# frozen_string_literal: true

RSpec.describe "Brand activation field row" do
  let(:web_dir) { File.expand_path("../../../lib/clacky/web", __dir__) }
  let(:styles)  { File.read(File.join(web_dir, "app.css")) }

  it "levels the license input with the activate button" do
    block = styles[/\.brand-activate-fields \.field-input,\s*\.brand-activate-fields \.btn-primary \{[^}]*\}/]
    expect(block).not_to be_nil
    expect(block).to include("height: 2rem", "padding-top: 0", "padding-bottom: 0")

    button = styles[/\.brand-activate-fields \.btn-primary \{[^}]*flex-shrink[^}]*\}/]
    expect(button).to include("font-size: 0.8125rem", "flex-shrink: 0")
  end
end
