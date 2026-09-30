# frozen_string_literal: true

RSpec.describe "Model picker auto row" do
  let(:web_dir) { File.expand_path("../../../lib/clacky/web", __dir__) }
  let(:picker)  { File.read(File.join(web_dir, "components/model-picker.js")) }
  let(:styles)  { File.read(File.join(web_dir, "app.css")) }
  let(:i18n)    { File.read(File.join(web_dir, "i18n.js")) }

  it "tags the auto alias row with the economy-first label" do
    expect(picker).to include('className = "sib-auto-tag"')
    expect(picker).to include('I18n.t("sib.auto.tag")')
    expect(styles).to include(".sib-auto-tag {")
    expect(i18n).to include('"sib.auto.tag"')
  end

  it "drops both the tag and the hover card once the alias is pinned" do
    expect(picker).to include('&& !hasActiveOverride) {')
    expect(picker).to include("_decorateAutoRow(opt, m.model, right);")
  end
end
