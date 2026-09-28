# frozen_string_literal: true

module Clacky
  module Utils
    # Agent-only context prepended to channel messages; build and strip share these fragments.
    module ChannelPrompt
      SENDER_OPEN        = "[Sender: "
      SENDER_CLOSE       = "]"
      GROUP_HEADER_OPEN  = "[Group chat history ("
      GROUP_HEADER_CLOSE = " messages)]"
      SEPARATOR          = "---"

      SENDER_LINE = /#{Regexp.escape(SENDER_OPEN)}[^#{Regexp.escape(SENDER_CLOSE)}]*#{Regexp.escape(SENDER_CLOSE)}\n?/.freeze
      GROUP_BLOCK = /#{Regexp.escape(GROUP_HEADER_OPEN)}\d+#{Regexp.escape(GROUP_HEADER_CLOSE)}\n.*?\n#{Regexp.escape(SEPARATOR)}\n/m.freeze
      # Only the first sender line goes, so one the user typed at the start of their text survives.
      PREFIX = /\A(?:#{GROUP_BLOCK})?#{SENDER_LINE}/.freeze

      # @param history [Array<Hash>, nil] group chat entries with :user_id and :text
      def self.build(text, sender:, history: nil)
        sender_line = "#{SENDER_OPEN}#{sender}#{SENDER_CLOSE}"
        return "#{sender_line}\n#{text}" if history.nil? || history.empty?

        header = "#{GROUP_HEADER_OPEN}#{history.size}#{GROUP_HEADER_CLOSE}"
        lines  = history.map { |e| "#{e[:user_id]}: #{e[:text]}" }.join("\n")
        [header, lines, SEPARATOR, sender_line, text].join("\n")
      end

      def self.strip(text)
        text.to_s.sub(PREFIX, "")
      end
    end
  end
end
