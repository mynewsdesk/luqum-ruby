# frozen_string_literal: true
require "luqum/visitor"

module Luqum
  module DeprecatedUtils
    class LuceneTreeVisitor
      def initialize
        @get_method_cache = {}
      end

      def visit(node, parents = nil, &)
        parents ||= []
        return enum_for(:visit, node, parents) unless block_given?

        each_result(_get_method(node).call(node, parents), &)
        node.children.each do |child|
          visit(child, parents + [node], &)
        end
      end

      def generic_visit(_node, _parents = nil)
        []
      end

      private

      def _get_method(node)
        @get_method_cache[node.class] ||= begin
          node.class.ancestors.each do |cls|
            next unless cls.is_a?(Class)

            name = cls.name
            next if name.nil?

            candidate = "visit_#{Luqum::Visitor.camel_to_lower(name.split('::').last)}"
            return method(candidate) if respond_to?(candidate, true)
          end
          method(:generic_visit)
        end
      end

      def each_result(result, &)
        Array(result).each(&)
      end
    end

    class LuceneTreeTransformer < LuceneTreeVisitor
      def replace_node(old_node, new_node, parent)
        parent.instance_variables.each do |ivar|
          value = parent.instance_variable_get(ivar)
          if value == old_node
            parent.instance_variable_set(ivar, new_node)
            break
          elsif value.is_a?(Array)
            index = value.index(old_node)
            next if index.nil?

            if new_node.nil?
              value.delete_at(index)
            else
              value[index] = new_node
            end
            break
          end
        end
      end

      def generic_visit(node, _parent = nil)
        node
      end

      def visit(node, parents = nil)
        parents ||= []
        new_node = _get_method(node).call(node, parents)
        replace_node(node, new_node, parents[-1]) if parents.any?
        node = new_node
        node.children.dup.each { |child| visit(child, parents + [node]) } unless node.nil?
        node
      end
    end

    class LuceneTreeVisitorV2 < LuceneTreeVisitor
      def visit(node, parents = nil, context = nil)
        parents ||= []
        _get_method(node).call(node, parents, context)
      end

      def generic_visit(node, _parents = nil, _context = nil)
        raise NoMethodError, "No visitor found for this type of node: #{node.class}"
      end
    end
  end
end
