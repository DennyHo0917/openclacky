# frozen_string_literal: true

require "open3"

RSpec.describe "Web phase card status when a message is sent mid-run" do
  it "leaves running phases alone until the backend reports an interrupt" do
    script = File.expand_path("../../support/phase_queue_interrupt_test.js", __dir__)
    output, status = Open3.capture2e("node", script)
    expect(status.success?).to be(true), output
  end
end
