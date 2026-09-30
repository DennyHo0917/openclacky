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

  it "binds the full current and new-session pages as shared drop zones" do
    expect(sessions).to include('zone: document.getElementById("chat-panel")')
    expect(new_session).to include('zone: $("welcome")')
    expect(sessions).not_to include('inputArea.addEventListener("drop"')
    expect(new_session).not_to include('composer.addEventListener("drop"')
  end

  it "provides a compact drag preview and page-level drop-target feedback" do
    expect(styles).to include(".reference-drag-preview")
    expect(styles).to include('.session-item[draggable="true"]')
    expect(styles).to include("#chat-panel.drag-over")
    expect(styles).to include("#welcome.drag-over")
  end
end
