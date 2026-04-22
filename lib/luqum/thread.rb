# frozen_string_literal: true

require "luqum/parser"

module Luqum
  module Thread
    # API-compatible parse alias. Our Ruby parser creates fresh state per
    # call, so it is already thread-safe — this module exists for symmetry
    # with the Python luqum API.
    def self.parse(input)
      Luqum::Parser.parse(input)
    end
  end
end
