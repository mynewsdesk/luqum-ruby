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
    def pos(p, head_transfer: false, tail_transfer: false)
      result = p[0]
      first = p[1]
      if first.pos
        result.pos = first.pos
        result.pos -= first.head.length unless head_transfer
      end
      result.size = 0
      p[1..].each do |elt|
        result.size += (elt.size || 0) + (elt.head || "").length + (elt.tail || "").length
      end
      if head_transfer && first.head && !first.head.empty?
        result.size -= first.head.length
      end
      last = p.last
      if tail_transfer && last.tail && !last.tail.empty?
        result.size -= last.tail.length
      end
    end

    def binary_operation(p, op_tail:)
      pos(p, head_transfer: false, tail_transfer: false)
      p[0].size -= op_tail.length
    end

    def simple_term(p)
      pos(p, head_transfer: true, tail_transfer: true)
      p[0].head = p[1].head
      p[0].tail = p[1].tail
    end

    def unary(p)
      pos(p, head_transfer: true, tail_transfer: false)
      p[0].head = p[1].head
      p[2].head = p[1].tail + p[2].head
    end

    def post_unary(p)
      pos(p, head_transfer: false, tail_transfer: true)
      p[1].tail = p[1].tail + p[2].head
      p[0].tail = p[2].tail
    end

    def paren(p)
      pos(p, head_transfer: true, tail_transfer: true)
      p[0].head = p[1].head
      p[2].head = p[1].tail + p[2].head
      p[2].tail = p[2].tail + p[3].head
      p[0].tail = p[3].tail
    end

    def range(p)
      pos(p, head_transfer: true, tail_transfer: true)
      p[0].head = p[1].head
      p[2].head = p[1].tail + p[2].head
      p[2].tail = p[2].tail + p[3].head
      p[4].head = p[3].tail + p[4].head
      p[4].tail = p[4].tail + p[5].head
      p[0].tail = p[5].tail
    end

    def search_field(p)
      pos(p, head_transfer: true, tail_transfer: false)
      p[0].head = p[1].head
      p[3].head = p[2].tail + p[3].head
    end
  end

  HEAD_TAIL = HeadTailManager.new
end
