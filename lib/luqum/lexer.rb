# frozen_string_literal: true
require 'English'
require "luqum/tree"
require "luqum/exceptions"
require "luqum/head_tail"

module Luqum
  class Lexer
    RESERVED = {
      "AND" => :AND_OP,
      "OR" => :OR_OP,
      "NOT" => :NOT,
      "TO" => :TO,
    }.freeze

    # A Lucene term: any char that isn't a delimiter or whitespace, with
    # `\\.` escapes, plus a special lookbehind-based allowance so that
    # `T\d{2}:\d{2}(:\d{2})?` (the `:` inside date-times) doesn't end the term.
    TERM_RE = %r{
      (?:
        [^\s:\^~(){}\[\]/"'+\-\\<>]
        |
        \\.
      )
      (?:
        [^\s:\^\\~(){}\[\]]
        |
        \\.
        |
        (?<=T\d{2}):\d{2}(?::\d{2})?
      )*
    }x

    PHRASE_RE = /"(?:[^\\"]|\\.)*"/
    REGEX_RE = %r{/(?:[^\\/]|\\.)*/}
    APPROX_RE = /~([0-9.]+)?/
    BOOST_RE = /\^([0-9.]+)?/
    SEPARATOR_RE = /\s+/

    class Token
      attr_accessor :type, :value
      attr_reader :pos, :size

      def initialize(type, value, pos, size)
        @type = type
        @value = value
        @pos = pos
        @size = size
      end

      def inspect
        "#<Token #{@type} #{@value.inspect} @#{@pos}>"
      end
    end

    def tokenize(input)
      tokens = []
      pos = 0
      pending_head = nil
      last_tok = nil
      input = input.to_s

      while pos < input.length
        rest = input[pos..]

        # whitespace
        if (m = rest.match(/\A#{SEPARATOR_RE.source}/))
          if pos.zero?
            pending_head = m[0]
          elsif last_tok
            last_tok.value.tail = (last_tok.value.tail || "") + m[0]
          end
          pos += m[0].length
          next
        end

        type, value, length = match_next(rest)
        raise IllegalCharacterError, "Illegal character '#{rest[0]}' at position #{pos}" if type.nil?

        value.pos = pos
        value.size = length
        if pending_head
          value.head = pending_head
          pending_head = nil
        end

        tok = Token.new(type, value, pos, length)
        tokens << tok
        last_tok = tok
        pos += length
      end

      tokens
    end

    private

    def match_next(rest)
      # Order matters: phrase and regex before term (they contain chars term excludes);
      # APPROX/BOOST before TERM (because `~` and `^` aren't part of a term);
      # simple single-char tokens; finally TERM (greedy catch-all).
      case rest
      when /\A#{PHRASE_RE.source}/o
        [:PHRASE, Tree::Phrase.new($LAST_MATCH_INFO[0]), $LAST_MATCH_INFO[0].length]
      when /\A#{REGEX_RE.source}/o
        [:REGEX, Tree::Regex.new($LAST_MATCH_INFO[0]), $LAST_MATCH_INFO[0].length]
      when /\A~([0-9.]+)?/
        [:APPROX, TokenValue.new(::Regexp.last_match(1)), $LAST_MATCH_INFO[0].length]
      when /\A\^([0-9.]+)?/
        [:BOOST, TokenValue.new(::Regexp.last_match(1)), $LAST_MATCH_INFO[0].length]
      when /\A\+/
        [:PLUS, TokenValue.new("+"), 1]
      when /\A-/
        [:MINUS, TokenValue.new("-"), 1]
      when /\A:/
        [:COLUMN, TokenValue.new(":"), 1]
      when /\A\(/
        [:LPAREN, TokenValue.new("("), 1]
      when /\A\)/
        [:RPAREN, TokenValue.new(")"), 1]
      when /\A[\[{]/
        [:LBRACKET, TokenValue.new($LAST_MATCH_INFO[0]), 1]
      when /\A[\]}]/
        [:RBRACKET, TokenValue.new($LAST_MATCH_INFO[0]), 1]
      when /\A>=?/
        [:GREATERTHAN, TokenValue.new($LAST_MATCH_INFO[0]), $LAST_MATCH_INFO[0].length]
      when /\A<=?/
        [:LESSTHAN, TokenValue.new($LAST_MATCH_INFO[0]), $LAST_MATCH_INFO[0].length]
      when /\A#{TERM_RE.source}/xo
        matched = $LAST_MATCH_INFO[0]
        if (reserved = RESERVED[matched])
          [reserved, TokenValue.new(matched), matched.length]
        else
          [:TERM, Tree::Word.new(matched), matched.length]
        end
      else
        [nil, nil, 0]
      end
    end
  end
end
