# frozen_string_literal: true

require "open3"

RSpec.describe "Web workspace add to chat" do
  it "stages a file picked in the Files tab and focuses the message input" do
    script = File.expand_path("../../support/workspace_add_to_chat_test.js", __dir__)
    output, status = Open3.capture2e("node", script)
    expect(status.success?).to be(true), output
  end
end
