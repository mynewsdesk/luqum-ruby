# frozen_string_literal: true

require "luqum/deprecated_utils"
require "luqum/visitor"

module Luqum
  module Utils
    LuceneTreeVisitor = Luqum::DeprecatedUtils::LuceneTreeVisitor
    LuceneTreeTransformer = Luqum::DeprecatedUtils::LuceneTreeTransformer
    LuceneTreeVisitorV2 = Luqum::DeprecatedUtils::LuceneTreeVisitorV2

    class UnknownOperationResolver < Luqum::Visitor::TreeTransformer
      VALID_OPERATIONS = [
        nil,
        Luqum::Tree::AndOperation,
        Luqum::Tree::OrOperation,
        Luqum::Tree::BoolOperation,
      ].freeze
      DEFAULT_OPERATION = Luqum::Tree::AndOperation

      def initialize(resolve_to: nil, add_head: " ")
        unless VALID_OPERATIONS.include?(resolve_to)
          raise ArgumentError,
            "#{resolve_to.inspect} is not a valid value for resolve_to"
        end

        @resolve_to = resolve_to
        @add_head = add_head
        super(track_parents: true)
      end

      def visit_or_operation(node, context, &)
        track_last_op(node, context)
        generic_visit(node, context, &)
      end

      def visit_and_operation(node, context, &)
        track_last_op(node, context)
        generic_visit(node, context, &)
      end

      def visit_unknown_operation(node, context)
        operation = @resolve_to.nil? ? get_last_op(context) : @resolve_to
        new_node = operation.new(pos: node.pos, size: node.size, head: node.head, tail: node.tail)
        new_node.children = collect_children(node, new_node, context)
        new_node.children[1..]&.each do |child|
          child.head = @add_head + child.head
        end
        yield new_node
      end

      def call(tree)
        visit(tree)
      end

      private

      def last_operation(context)
        context[:last_operation] ||= {}
      end

      def first_nonop_parent(parents)
        parents.each do |parent|
          return parent.object_id unless parent.is_a?(Luqum::Tree::BaseOperation)
        end
        nil
      end

      def track_last_op(node, context)
        return unless @resolve_to.nil?

        parent = first_nonop_parent(context[:parents] || [])
        last_operation(context)[parent] = node.class
      end

      def get_last_op(context)
        parent = first_nonop_parent(context[:parents] || [])
        last_operation(context).fetch(parent, DEFAULT_OPERATION)
      end
    end

    class OpenRangeTransformer < Luqum::Visitor::TreeTransformer
      WILDCARD_WORD = Luqum::Tree::Word.new("*")

      def initialize(merge_ranges: false, add_head: " ")
        @merge_ranges = merge_ranges
        @add_head = add_head
        super(track_parents: true)
      end

      def visit_and_operation(node, context, &)
        unless @merge_ranges
          generic_visit(node, context, &)
          return
        end

        new_node = Luqum::Tree::AndOperation.new(pos: node.pos, size: node.size, head: node.head, tail: node.tail)
        new_children = []
        possible_ranges = []
        possible_ranges_bound_side = nil

        collect_children(node, new_node, context).each do |child|
          child_bound_side = get_node_bound_side(child)
          unless child_bound_side.nil?
            if possible_ranges.empty? || possible_ranges_bound_side == child_bound_side
              possible_ranges << child
              possible_ranges_bound_side = child_bound_side
            else
              joining_child = possible_ranges.shift
              if child_bound_side == :low
                joining_child.low = child.low
                joining_child.include_low = child.include_low
              else
                joining_child.high = child.high
                joining_child.include_high = child.include_high
              end
              next
            end
          end

          new_children << child
        end

        new_node.children = new_children
        yield new_node
      end

      def visit_from(node, context, &)
        visit_from_to(node, context, :low, &)
      end

      def visit_to(node, context, &)
        visit_from_to(node, context, :high, &)
      end

      def call(tree)
        visit(tree)
      end

      private

      def get_node_bound_side(node)
        return nil unless node.is_a?(Luqum::Tree::Range)

        if node.low == WILDCARD_WORD && node.high != WILDCARD_WORD
          :high
        elsif node.low != WILDCARD_WORD && node.high == WILDCARD_WORD
          :low
        end
      end

      def visit_from_to(node, context, bound_side)
        new_node = if bound_side == :low
                     Luqum::Tree::Range.new(
                       nil,
                       WILDCARD_WORD.clone_item,
                       include_low: node.include,
                       include_high: true,
                       pos: node.pos,
                       size: node.size,
                       head: node.head,
                       tail: node.tail,
                     )
                   else
                     Luqum::Tree::Range.new(
                       WILDCARD_WORD.clone_item,
                       nil,
                       include_low: true,
                       include_high: node.include,
                       pos: node.pos,
                       size: node.size,
                       head: node.head,
                       tail: node.tail,
                     )
                   end

        child = collect_children(node, new_node, context).first
        if bound_side == :low
          new_node.low = child
        else
          new_node.high = child
        end

        new_node.low.tail += @add_head
        new_node.high.head += @add_head
        yield new_node
      end
    end

    class << self
      def normalize_nested_fields_specs(nested_fields)
        if nested_fields.nil?
          {}
        elsif nested_fields.is_a?(Hash)
          nested_fields.transform_values { |value| normalize_nested_fields_specs(value) }
        else
          nested_fields.each_with_object({}) { |sub, result| result[sub] = {} }
        end
      end

      def flatten_nested_fields_specs(nested_fields)
        if nested_fields.is_a?(Hash)
          Set.new(flatten_fields_specs(nested_fields).map { |parts| parts.join(".") })
        elsif nested_fields.nil?
          Set.new
        else
          Set.new(nested_fields)
        end
      end

      def normalize_object_fields_specs(object_fields)
        return nil if object_fields.nil?

        if object_fields.is_a?(Hash)
          Set.new(flatten_fields_specs(object_fields).map { |parts| parts.join(".") })
        else
          Set.new(object_fields)
        end
      end

      private

      def flatten_fields_specs(object_fields)
        if object_fields.nil? || (object_fields.respond_to?(:empty?) && object_fields.empty?)
          [[]]
        elsif object_fields.is_a?(Hash)
          object_fields.flat_map do |key, value|
            flatten_fields_specs(value).map { |parts| [key] + parts }
          end
        else
          object_fields.map { |key| [key] }
        end
      end
    end
  end
end
