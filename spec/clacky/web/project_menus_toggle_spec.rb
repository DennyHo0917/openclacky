# frozen_string_literal: true

require "open3"

RSpec.describe "Web project menus toggle" do
  it "closes the organize and project menus when their own button is clicked again" do
    script = File.expand_path("../../support/project_menus_toggle_test.js", __dir__)
    output, status = Open3.capture2e("node", script)
    expect(status.success?).to be(true), output
  end
end
