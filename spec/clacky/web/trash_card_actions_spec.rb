# frozen_string_literal: true

RSpec.describe "File Recall card action buttons" do
  let(:web_dir) { File.expand_path("../../../lib/clacky/web", __dir__) }
  let(:view)    { File.read(File.join(web_dir, "features/trash/view.js")) }
  let(:styles)  { File.read(File.join(web_dir, "app.css")) }
  let(:i18n)    { File.read(File.join(web_dir, "i18n.js")) }

  it "renders both card actions as icon-only buttons" do
    expect(view.scan(/class="btn-trash-(?:session-)?(?:restore|delete)"/).size).to eq(4)
    # Labels repeat on every row of the list, so they only live in the tooltip now.
    expect(view).not_to include('_t("trash.restore")}</span>')
    expect(view).not_to include('_t("trash.delete")}</span>')
    expect(view).not_to include('_t("trash.restoreSession")}</span>')
    expect(view).not_to include('_t("trash.deleteSession")}</span>')
  end

  it "keeps an accessible name on every icon button" do
    expect(view.scan(/class="btn-trash-(?:session-)?(?:restore|delete)"[^>]*aria-label=/).size).to eq(4)
  end

  it "sizes the file and session buttons with one shared rule" do
    block = styles[/\.btn-trash-restore,\s*\.btn-trash-delete,\s*\.btn-trash-session-restore,\s*\.btn-trash-session-delete\s*\{[^}]*\}/]
    expect(block).not_to be_nil
    expect(block).to include("width: 1.875rem", "height: 1.875rem", "border-radius: 6px", "background: transparent")

    glyphs = styles[/\.btn-trash-restore svg,\s*\.btn-trash-delete svg,\s*\.btn-trash-session-restore svg,\s*\.btn-trash-session-delete svg\s*\{[^}]*\}/]
    expect(glyphs).to include("width: 0.8125rem", "height: 0.8125rem")

    # The old per-button paddings are what made the two buttons look unrelated.
    expect(styles).not_to include(".btn-trash-delete {\n  padding:")
  end

  it "gives every toolbar control the same shape" do
    block = styles[/\.trash-filter-chip,\s*\.trash-filter-project-wrap,\s*\.btn-trash-action\s*\{[^}]*\}/]
    expect(block).not_to be_nil
    expect(block).to include("height: 1.75rem", "border-radius: 6px", "font-size: 0.75rem")
  end

  it "keeps a neutral hover on restore and reserves red for delete" do
    restore = styles[/\.btn-trash-restore:hover:not\(:disabled\),\s*\.btn-trash-session-restore:hover:not\(:disabled\)\s*\{[^}]*\}/]
    expect(restore).not_to be_nil
    expect(restore).not_to include("--color-success")
    expect(restore).to include("color: var(--color-text-primary)")

    delete = styles[/\.btn-trash-delete:hover:not\(:disabled\),\s*\.btn-trash-session-delete:hover:not\(:disabled\)\s*\{[^}]*\}/]
    expect(delete).to include("--color-error")
  end

  it "labels the 7-day cleanup in plain words" do
    expect(i18n).not_to include("清理 >7 天")
    expect(i18n).to include('"trash.emptyOld":    "清理 7 天前"')
  end
end
