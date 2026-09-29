# frozen_string_literal: true

require_relative "en"
require_relative "zh"

module Clacky
  module I18n
    LOCALES = {
      "zh" => Clacky::Locales::ZH,
      "en" => Clacky::Locales::EN
    }.freeze
    DEFAULT_LOCALE = "en"

    def self.t(key, **vars)
      translate(locale, key, **vars)
    end

    def self.translate(code, key, **vars)
      table = LOCALES[code] || LOCALES[DEFAULT_LOCALE]
      msg   = table[key] || LOCALES[DEFAULT_LOCALE][key] || key
      vars.empty? ? msg : format(msg, **vars)
    end

    # Builds { locale_code => value } for every supported locale.
    def self.localized
      LOCALES.keys.map { |code| [code, yield(code)] }.to_h
    end

    def self.translations(key, **vars)
      localized { |code| translate(code, key, **vars) }
    end

    def self.locale
      return Thread.current[:lang] if Thread.current[:lang]

      lang = ENV["LC_ALL"] || ENV["LC_MESSAGES"] || ENV["LANG"] || ""
      lang.match?(/\Azh/i) ? "zh" : "en"
    end
  end
end
