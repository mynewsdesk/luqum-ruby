require "luqum/visitor"

module Luqum
  module AutoHeadTail
    SPACER = " ".freeze

    # Transformer that populates empty `head` / `tail` on tree items so a
    # hand-built tree prints back to a valid Lucene expression.
    class Transformer < Luqum::Visitor::TreeTransformer
      def add_head(node)
        node.head = SPACER if node.head.nil? || node.head.empty?
      end

      def add_tail(node)
        node.tail = SPACER if node.tail.nil? || node.tail.empty?
      end

      def visit_base_operation(node, context)
        new_node = node.clone_item
        children = collect_children(node, new_node, context)
        add_tail(children.first)
        children[1...-1].each do |child|
          add_head(child)
          add_tail(child)
        end
        add_head(children.last)
        new_node.children = children
        yield new_node
      end

      def visit_unknown_operation(node, context)
        new_node = node.clone_item
        children = collect_children(node, new_node, context)
        children[0...-1].each { |child| add_tail(child) }
        new_node.children = children
        yield new_node
      end

      def visit_not(node, context)
        new_node = node.clone_item
        children = collect_children(node, new_node, context)
        add_head(children.first)
        new_node.children = children
        yield new_node
      end

      def visit_range(node, context)
        new_node = node.clone_item
        children = collect_children(node, new_node, context)
        add_tail(children.first)
        add_head(children.last)
        new_node.children = children
        yield new_node
      end

      def call(tree)
        visit(tree)
      end
    end

    DEFAULT = Transformer.new

    def self.auto_head_tail(tree)
      DEFAULT.call(tree)
    end
  end
end
