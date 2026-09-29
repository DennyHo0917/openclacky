# frozen_string_literal: true

require "open3"

RSpec.describe "Web session actions menu toggle" do
  it "closes the menu when its own button is clicked again" do
    script = File.expand_path("../../support/session_actions_menu_toggle_test.js", __dir__)
    output, status = Open3.capture2e("node", script)
    expect(status.success?).to be(true), output
  end
end
