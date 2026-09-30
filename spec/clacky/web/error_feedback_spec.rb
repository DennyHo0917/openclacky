# frozen_string_literal: true

RSpec.describe "Web feature error feedback" do
  let(:web_dir) { File.expand_path("../../../lib/clacky/web", __dir__) }

  # Pages already migrated off window.alert(): a blocking native dialog ignores
  # the app theme and stalls the UI, so failures go through the toast stack.
  MIGRATED_PAGES = %w[
    features/skills/store.js
    features/skills/view.js
    features/mcp/store.js
    features/mcp/view.js
    features/tasks/store.js
  ].freeze

  MIGRATED_PAGES.each do |relative_path|
    it "reports failures without native alert() in #{relative_path}" do
      source = File.read(File.join(web_dir, relative_path))
      expect(source).not_to match(/(?<![\w.])alert\(/)
    end
  end

  it "keeps the failure messages that used to be alerted" do
    skills = File.read(File.join(web_dir, "features/skills/store.js"))
    tasks  = File.read(File.join(web_dir, "features/tasks/store.js"))
    mcp    = File.read(File.join(web_dir, "features/mcp/view.js"))

    expect(skills).to include('Modal.toast(I18n.t("skills.toggleError")')
    expect(skills).to include('Modal.toast(data.error || I18n.t("skills.deleteError"), "error")')
    expect(tasks).to include('Modal.toast(I18n.t("tasks.runError")')
    expect(tasks).to include('Modal.toast(I18n.t("tasks.run.deleteError"), "error")')
    expect(mcp).to include('Modal.toast(I18n.t(key, { msg: payload.message }), "error")')
  end
end
