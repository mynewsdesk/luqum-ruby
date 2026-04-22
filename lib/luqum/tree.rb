# frozen_string_literal: true

require "bigdecimal"

module Luqum
  module Tree
    WILDCARDS_PATTERN = /(?<=[^\\])[?*]|\\\\[?*]|^[?*]/
    WORD_ESCAPED_CHARS = /\\(.)/

    def self.format_decimal(value)
      return value.to_s unless value.is_a?(BigDecimal)

      s = value.to_s("F")
      s.sub(/\.0+\z/, "")
    end

    # Base class for all items that compose the parse tree.
    class Item
      # Class-level configuration. Each subclass can override.
      class << self
        def equality_attrs
          @equality_attrs ||= (superclass.respond_to?(:equality_attrs) ? superclass.equality_attrs.dup : [])
        end

        def children_attrs
          @children_attrs ||= (superclass.respond_to?(:children_attrs) ? superclass.children_attrs.dup : [])
        end

        def positional_args
          @positional_args ||= (superclass.respond_to?(:positional_args) ? superclass.positional_args.dup : [])
        end

        def set_equality_attrs(*names)
          @equality_attrs = names
        end

        def set_children_attrs(*names)
          @children_attrs = names
        end

        def set_positional_args(*names)
          @positional_args = names
        end
      end

      attr_accessor :pos, :size, :head, :tail

      def initialize(pos: nil, size: nil, head: "", tail: "")
        @pos = pos
        @size = size
        @head = head
        @tail = tail
      end

      # Clone this item but not its children.
      def clone_item(**overrides)
        _clone_item(cls: self.class, **overrides)
      end

      # Internal clone implementation; allows changing target class.
      def _clone_item(cls: self.class, **overrides)
        attrs = { pos: @pos, size: @size, head: @head, tail: @tail }
        self.class.equality_attrs.each do |attr|
          attrs[attr] = instance_variable_get("@#{attr}")
        end
        self.class.children_attrs.each do |attr|
          attrs[attr] = NONE_ITEM
        end
        attrs.merge!(overrides)
        positional = cls.positional_args.map { |name| attrs.delete(name) }
        cls.new(*positional, **attrs)
      end

      def children
        self.class.children_attrs.map { |attr| instance_variable_get("@#{attr}") }
      end

      def children=(values)
        expected = self.class.children_attrs.length
        if values.length != expected
          supplied = values.empty? ? "no" : values.length.to_s
          raise ArgumentError,
            "#{self.class} accepts #{expected} children, and you try to set #{supplied} children"
        end
        self.class.children_attrs.each_with_index do |attr, i|
          instance_variable_set("@#{attr}", values[i])
        end
      end

      # (start, end) position of this element; when head_tail is true, include head/tail.
      def span(head_tail: false)
        return [nil, nil] if @pos.nil?

        start = @pos - (head_tail ? @head.length : 0)
        finish = @pos + @size + (head_tail ? @tail.length : 0)
        [start, finish]
      end

      def to_s(head_tail: false)
        _head_tail(render, head_tail)
      end

      # Override in subclasses; the "bare" body of this item without head/tail wrapping.
      def render
        ""
      end

      def inspect
        kids = children.map(&:inspect).join(", ")
        "#{self.class.name.split('::').last}(#{kids})"
      end

      def ==(other)
        return true if equal?(other)
        return false unless other.is_a?(Item)
        return false unless self.class == other.class

        own_children = children
        other_children = other.children
        return false unless own_children.length == other_children.length
        return false unless self.class.equality_attrs.all? { |a|
          instance_variable_get("@#{a}") == other.instance_variable_get("@#{a}")
        }

        own_children.zip(other_children).all? { |a, b| a == b }
      end

      alias eql? ==

      def hash
        attrs = self.class.equality_attrs.map { |a| instance_variable_get("@#{a}") }
        [self.class, attrs, children].hash
      end

      private

      def _head_tail(value, include)
        include ? "#{@head}#{value}#{@tail}" : value
      end
    end

    # Placeholder item (think None).
    class NoneItem < Item
      def to_s(*)
        ""
      end

      def render
        ""
      end
    end

    NONE_ITEM = NoneItem.new

    # Indicates which field a search expression operates on.
    class SearchField < Item
      set_equality_attrs :name
      set_children_attrs :expr
      set_positional_args :name, :expr

      attr_accessor :name, :expr

      def initialize(name, expr, **)
        @name = name
        @expr = expr
        super(**)
      end

      def render
        "#{@name}:#{@expr.to_s(head_tail: true)}"
      end

      def inspect
        "SearchField(#{@name.inspect}, #{@expr.inspect})"
      end
    end

    class BaseGroup < Item
      set_children_attrs :expr
      set_positional_args :expr

      attr_accessor :expr

      def initialize(expr, **)
        @expr = expr
        super(**)
      end

      def render
        "(#{@expr.to_s(head_tail: true)})"
      end
    end

    class Group < BaseGroup; end
    class FieldGroup < BaseGroup; end

    def self.group_to_fieldgroup(group)
      FieldGroup.new(group.expr, pos: group.pos, size: group.size, head: group.head, tail: group.tail)
    end

    class Range < Item
      LOW_CHAR = { true => "[", false => "{" }.freeze
      HIGH_CHAR = { true => "]", false => "}" }.freeze

      set_equality_attrs :include_high, :include_low
      set_children_attrs :low, :high
      set_positional_args :low, :high

      attr_accessor :low, :high, :include_low, :include_high

      def initialize(low, high, include_low: true, include_high: true, **)
        @low = low
        @high = high
        @include_low = include_low
        @include_high = include_high
        super(**)
      end

      def render
        "#{LOW_CHAR[@include_low]}#{@low.to_s(head_tail: true)}TO#{@high.to_s(head_tail: true)}#{HIGH_CHAR[@include_high]}"
      end
    end

    class Term < Item
      set_equality_attrs :value
      set_positional_args :value

      attr_accessor :value

      def initialize(value, **)
        @value = value
        super(**)
      end

      def unescaped_value
        @value.gsub(WORD_ESCAPED_CHARS, '\1')
      end

      def wildcard?
        @value == "*"
      end

      def iter_wildcards
        return enum_for(:iter_wildcards) unless block_given?

        pos = 0
        while (m = @value.match(WILDCARDS_PATTERN, pos))
          span = [m.begin(0), m.end(0)]
          yield span, m[0]
          pos = m.end(0)
          pos += 1 if pos == m.begin(0)
        end
      end

      def split_wildcards
        parts = []
        last = 0
        @value.scan(WILDCARDS_PATTERN) do
          m = Regexp.last_match
          parts << @value[last...m.begin(0)]
          parts << m[0]
          last = m.end(0)
        end
        parts << @value[last..]
        parts
      end

      def has_wildcard?
        !iter_wildcards.first.nil?
      end

      def render
        @value
      end

      def inspect
        "#{self.class.name.split('::').last}(#{to_s.inspect})"
      end
    end

    class Word < Term; end

    class Phrase < Term
      def initialize(value, **kwargs)
        super
        unless @value.start_with?('"') && @value.end_with?('"')
          raise ArgumentError, "Phrase value must contain the quotes"
        end
      end
    end

    class Regex < Term
      def initialize(value, **kwargs)
        super
        unless @value.start_with?("/") && @value.end_with?("/")
          raise ArgumentError, "Regex value must contain the slashes"
        end
      end
    end

    # Base for approximations (fuzziness and proximity).
    class BaseApprox < Item
      set_equality_attrs :degree
      set_children_attrs :term
      set_positional_args :term

      attr_accessor :term, :degree

      def initialize(term, degree: nil, **)
        @term = term
        @implicit_degree = degree.nil?
        @degree = normalize_degree(degree)
        super(**)
      end

      def implicit_degree?
        @implicit_degree
      end

      def render
        formatted = @implicit_degree ? "" : format_degree
        "#{@term.to_s(head_tail: true)}~#{formatted}"
      end

      def inspect
        "#{self.class.name.split('::').last}(#{@term.inspect}, #{format_degree})"
      end

      private

      def normalize_degree(_)
        raise NotImplementedError
      end

      def format_degree
        Tree.format_decimal(@degree)
      end
    end

    class Fuzzy < BaseApprox
      private

      def normalize_degree(degree)
        degree = 0.5 if degree.nil?
        case degree
        when BigDecimal then degree
        else
          BigDecimal(degree.to_s)
        end
      end
    end

    class Proximity < BaseApprox
      private

      def normalize_degree(degree)
        degree = 1 if degree.nil?
        Integer(degree)
      end

      def format_degree
        @degree.to_s
      end
    end

    class Boost < Item
      set_equality_attrs :force
      set_children_attrs :expr
      set_positional_args :expr

      attr_accessor :expr, :force
      attr_reader :implicit_force

      def initialize(expr, force: nil, **)
        @expr = expr
        @implicit_force = force.nil?
        @force = if force.nil?
                   1
                 else
                   BigDecimal(force.to_s)
                 end
        super(**)
      end

      def render
        formatted = @implicit_force ? "" : Tree.format_decimal(@force)
        "#{@expr.to_s(head_tail: true)}^#{formatted}"
      end

      def inspect
        "Boost(#{@expr.inspect}, #{Tree.format_decimal(@force)})"
      end
    end

    class BaseOperation < Item
      attr_accessor :operands

      def initialize(*operands, **)
        @operands = operands
        super(**)
      end

      def render
        @operands.map { |o| o.to_s(head_tail: true) }.join(self.class::OP.to_s)
      end

      def children
        @operands
      end

      def children=(values)
        @operands = values.to_a
      end
    end

    class BoolOperation < BaseOperation
      OP = ""
    end

    class UnknownOperation < BaseOperation
      OP = ""
    end

    class OrOperation < BaseOperation
      OP = "OR"
    end

    class AndOperation < BaseOperation
      OP = "AND"
    end

    # Create an operation between a and b, merging when either is already of the same class.
    def self.create_operation(cls, left_operand, right_operand, op_tail: " ")
      operands = []
      operands.concat(left_operand.is_a?(cls) ? left_operand.operands : [left_operand])
      left = right_operand.is_a?(cls) ? right_operand.operands.dup : [right_operand]
      left[0].head = (left[0].head || "") + op_tail
      operands.concat(left)
      cls.new(*operands)
    end

    class Unary < Item
      set_children_attrs :a
      set_positional_args :a

      attr_accessor :a

      def initialize(expr, **)
        @a = expr
        super(**)
      end

      def render
        "#{self.class::OP}#{@a.to_s(head_tail: true)}"
      end
    end

    class UnaryOperator < Unary; end

    class Plus < UnaryOperator
      OP = "+"
    end

    class Not < UnaryOperator
      OP = "NOT"
    end

    class Prohibit < UnaryOperator
      OP = "-"
    end

    class OpenRange < Unary
      CHAR = { true => "=", false => "" }.freeze
      set_equality_attrs :include

      attr_accessor :include

      def initialize(expr, include: true, **)
        @include = include
        super(expr, **)
      end

      def render
        "#{self.class::OP}#{CHAR[@include]}#{@a.to_s(head_tail: true)}"
      end
    end

    class From < OpenRange
      OP = ">"
    end

    class To < OpenRange
      OP = "<"
    end
  end
end
