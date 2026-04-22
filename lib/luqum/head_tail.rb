# frozen_string_literal: true

module Luqum
  # Lightweight wrapper for non-AST token values (operators, delimiters).
  # Carries pos/size/head/tail so the parser can treat every token uniformly.
  class TokenValue
    attr_accessor :value, :pos, :size, :head, :tail

    def initialize(value)
      @value = value
      @pos = nil
      @size = nil
      @head = ""
      @tail = ""
    end

    def to_s
      @value.to_s
    end

    def inspect
      "TokenValue(#{@value})"
    end
  end

  # Applies head/tail/pos/size bookkeeping to parse results.
  # The `p` argument follows the PLY convention: p[0] is the resulting node,
  # p[1..] are the children consumed by the grammar rule.
  class HeadTailManager
    def pos(parsed_items, head_transfer: false, tail_transfer: false)
      result = parsed_items[0]
      first = parsed_items[1]
      if first.pos
        result.pos = first.pos
        result.pos -= first.head.length unless head_transfer
      end
      result.size = 0
      parsed_items[1..].each do |elt|
        result.size += (elt.size || 0) + (elt.head || "").length + (elt.tail || "").length
      end
      if head_transfer && first.head && !first.head.empty?
        result.size -= first.head.length
      end
      last = parsed_items.last
      if tail_transfer && last.tail && !last.tail.empty?
        result.size -= last.tail.length
      end
    end

    def binary_operation(parsed_items, op_tail:)
      pos(parsed_items, head_transfer: false, tail_transfer: false)
      parsed_items[0].size -= op_tail.length
    end

    def simple_term(parsed_items)
      pos(parsed_items, head_transfer: true, tail_transfer: true)
      parsed_items[0].head = parsed_items[1].head
      parsed_items[0].tail = parsed_items[1].tail
    end

    def unary(parsed_items)
      pos(parsed_items, head_transfer: true, tail_transfer: false)
      parsed_items[0].head = parsed_items[1].head
      parsed_items[2].head = parsed_items[1].tail + parsed_items[2].head
    end

    def post_unary(parsed_items)
      pos(parsed_items, head_transfer: false, tail_transfer: true)
      parsed_items[1].tail = parsed_items[1].tail + parsed_items[2].head
      parsed_items[0].tail = parsed_items[2].tail
    end

    def paren(parsed_items)
      pos(parsed_items, head_transfer: true, tail_transfer: true)
      parsed_items[0].head = parsed_items[1].head
      parsed_items[2].head = parsed_items[1].tail + parsed_items[2].head
      parsed_items[2].tail = parsed_items[2].tail + parsed_items[3].head
      parsed_items[0].tail = parsed_items[3].tail
    end

    def range(parsed_items)
      pos(parsed_items, head_transfer: true, tail_transfer: true)
      parsed_items[0].head = parsed_items[1].head
      parsed_items[2].head = parsed_items[1].tail + parsed_items[2].head
      parsed_items[2].tail = parsed_items[2].tail + parsed_items[3].head
      parsed_items[4].head = parsed_items[3].tail + parsed_items[4].head
      parsed_items[4].tail = parsed_items[4].tail + parsed_items[5].head
      parsed_items[0].tail = parsed_items[5].tail
    end

    def search_field(parsed_items)
      pos(parsed_items, head_transfer: true, tail_transfer: false)
      parsed_items[0].head = parsed_items[1].head
      parsed_items[3].head = parsed_items[2].tail + parsed_items[3].head
    end
  end

  HEAD_TAIL = HeadTailManager.new
end
