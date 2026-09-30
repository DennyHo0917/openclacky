# frozen_string_literal: true

RSpec.describe "Assistant Memory document layout" do
  let(:web_dir) { File.expand_path("../../../lib/clacky/web", __dir__) }
  let(:html)    { File.read(File.join(web_dir, "index.html")) }
  let(:styles)  { File.read(File.join(web_dir, "app.css")) }
  let(:view)    { File.read(File.join(web_dir, "features/profile/view.js")) }

  it "keeps every page subtitle under its title instead of beside it" do
    # .channels-page-header is a space-between flex row, so a subtitle that is a
    # direct child lands at the far right edge of the page instead of under the
    # title — it has to sit inside the header's text column.
    headers = html.split('<div class="channels-page-header">').drop(1)
    expect(headers).not_to be_empty
    headers.each do |block|
      next unless block.include?("channels-page-subtitle")

      before_subtitle = block[0, block.index("channels-page-subtitle")]
      expect(before_subtitle).to include('class="channels-page-header-main"')
    end
  end

  it "gives the SOUL / USER panes a document layout that fills the page" do
    expect(html.scan(/profile-tab-panel[^"]*profile-doc/).size).to eq(2)
    # The body fills the content area; only the heading row drops its own rule,
    # since the paper below already draws the boundary.
    expect(styles).to include(".profile-doc > .profile-section-head {")
    expect(styles).not_to include("max-width: 46rem;")
  end

  it "draws the markdown body as a bordered page" do
    expect(styles).to include(".profile-markdown {")
    expect(styles).to match(/\.profile-markdown \{[^}]*border: 1px solid var\(--color-border-primary\)/)
    expect(styles).to match(/\.profile-markdown \{[^}]*font-size: 0\.875rem/)
    expect(styles).not_to include(".profile-markdown h1 { font-size: 1.125rem; }")
  end

  it "shows the full memory path on hover" do
    expect(view).to include("pathEl.title")
  end
end
