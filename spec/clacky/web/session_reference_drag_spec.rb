# frozen_string_literal: true

require "open3"

RSpec.describe "Web session reference drag and drop" do
  let(:web_dir) { File.expand_path("../../../lib/clacky/web", __dir__) }
  let(:sessions) { File.read(File.join(web_dir, "sessions.js")) }
  let(:new_session) { File.read(File.join(web_dir, "features/new-session/view.js")) }
  let(:styles) { File.read(File.join(web_dir, "app.css")) }

  it "round-trips and validates the shared Composer drag payload" do
    script = File.expand_path("../../support/session_reference_drag_test.js", __dir__)
    output, status = Open3.capture2e("node", script)
    expect(status.success?).to be(true), output
  end

  it "makes rendered sessions draggable without duplicating reference serialization" do
    expect(sessions).to include("el.draggable = true")
    expect(sessions).to include("Composer.beginReferenceDrag(e.dataTransfer")
    expect(sessions).to include('type: "session"')
  end

  it "routes reference drops before the existing file upload path in both composers" do
    main_reference = sessions.index("Composer.insertDroppedChip")
    main_files = sessions.index("const files = Array.from(e.dataTransfer.files)", main_reference)
    new_reference = new_session.index("Composer.insertDroppedChip")
    new_files = new_session.index("Array.from(e.dataTransfer.files || [])", new_reference)

    expect(main_reference).to be < main_files
    expect(new_reference).to be < new_files
  end

  it "provides a compact drag preview and drop-target feedback" do
    expect(styles).to include(".reference-drag-preview")
    expect(styles).to include('.session-item[draggable="true"]')
    expect(styles).to include(".new-session-composer.drag-over .ns-input-bar-card")
  end
end
