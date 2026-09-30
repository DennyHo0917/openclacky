# frozen_string_literal: true

RSpec.describe "Memory card action buttons" do
  let(:web_dir) { File.expand_path("../../../lib/clacky/web", __dir__) }
  let(:view)    { File.read(File.join(web_dir, "features/profile/view.js")) }
  let(:styles)  { File.read(File.join(web_dir, "app.css")) }

  it "renders the card actions as icon-only buttons" do
    expect(view.scan(/class="btn-memory-(?:curate|edit|delete|expand)"/).size).to eq(4)
    # Labels repeat on every row of the list, so they only live in the tooltip now.
    expect(view).not_to include('_t("memories.curate")}</span>')
    expect(view).not_to include('_t("memories.edit")}</span>')
    expect(view).not_to include('_t("memories.delete")}</span>')
  end

  it "keeps an accessible name on every icon button" do
    expect(view.scan(/class="btn-memory-\w+"[^>]*aria-label=/).size).to eq(4)
  end

  it "sizes all four buttons and their glyphs the same" do
    expect(styles).to match(
      /\.btn-memory-curate,\s*\.btn-memory-edit,\s*\.btn-memory-delete,\s*\.btn-memory-expand\s*\{\s*width: 1\.875rem;\s*height: 1\.875rem;/
    )
    expect(styles).to match(
      /\.btn-memory-expand svg\s*\{\s*width: 0\.8125rem;\s*height: 0\.8125rem;\s*\}/
    )
  end

  it "keeps the icon buttons readable instead of placeholder grey" do
    block = styles[/\.btn-memory-curate,\s*\.btn-memory-edit,\s*\.btn-memory-delete,\s*\.btn-memory-expand\s*\{[^}]*\}/]
    expect(block).not_to be_nil
    expect(block).to include("color: var(--color-text-secondary)")
    expect(styles[/\.btn-memories-mini\s*\{[^}]*\}/]).to include("color: var(--color-text-secondary)")
  end

  it "no longer hides button labels on narrow screens" do
    expect(styles).not_to include(".btn-memory-curate span")
    expect(styles).not_to include(".btn-memory-delete span")
  end
end
