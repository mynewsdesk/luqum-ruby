require "luqum/tree"

module Luqum
  module Visitor
    def self.camel_to_lower(name)
      result = name.each_char.map { |c| c =~ /[A-Z]/ ? "_#{c.downcase}" : c.downcase }.join
      result.sub(/\A_/, "")
    end

    # Tree visitor base class. Subclass and implement methods named
    # `visit_<snake_case_class_name>` to handle specific node types.
    #
    # Visit methods take `(node, context, &block)` and yield values through
    # the block. The top-level {#visit} collects the yielded values into an
    # array.
    class TreeVisitor
      VISITOR_METHOD_PREFIX = "visit_"
      GENERIC_VISITOR_METHOD_NAME = "generic_visit"

      attr_reader :track_parents

      def initialize(track_parents: false)
        @track_parents = track_parents
        @method_cache = {}
      end

      def visit(tree, context = nil)
        context ||= {}
        results = []
        visit_iter(tree, context) { |v| results << v }
        results
      end

      def visit_iter(node, context, &block)
        method_name = resolve_method(node)
        send(method_name, node, context, &block)
      end

      def child_context(_node, _child, context, **kwargs)
        ctx = context.dup
        if @track_parents
          ctx[:parents] = (context[:parents] || []) + [kwargs[:parent_node] || _node]
        end
        ctx
      end

      def generic_visit(node, context, &block)
        node.children.each do |child|
          ctx = child_context(node, child, context)
          visit_iter(child, ctx, &block)
        end
      end

      private

      def visitor_method_prefix
        self.class::VISITOR_METHOD_PREFIX
      end

      def generic_visitor_method_name
        self.class::GENERIC_VISITOR_METHOD_NAME
      end

      def resolve_method(node)
        @method_cache[node.class] ||= find_method(node)
      end

      def find_method(node)
        node.class.ancestors.each do |cls|
          next unless cls.is_a?(Class)
          name = cls.name
          next if name.nil?
          short = name.split("::").last
          candidate = "#{visitor_method_prefix}#{Visitor.camel_to_lower(short)}"
          return candidate.to_sym if respond_to?(candidate, true)
        end
        generic_visitor_method_name.to_sym
      end
    end

    # Transformer variant: visit must produce exactly one value, the
    # transformed tree. Default behavior clones each node and its children.
    class TreeTransformer < TreeVisitor
      attr_reader :track_new_parents

      def initialize(track_new_parents: false, **kwargs)
        @track_new_parents = track_new_parents
        super(**kwargs)
      end

      def visit(tree, context = nil)
        context ||= {}
        results = []
        visit_iter(tree, context) { |v| results << v }
        if results.length != 1
          raise ArgumentError,
                "The visit of the tree should have produced exactly one element (the transformed tree)"
        end
        results[0]
      end

      def child_context(node, child, context, **kwargs)
        ctx = super
        if @track_new_parents && kwargs.key?(:new_node)
          ctx[:new_parents] = (context[:new_parents] || []) + [kwargs[:new_node]]
        end
        ctx
      end

      def generic_visit(node, context)
        new_node = _clone_item(node)
        new_node.children = collect_children(node, new_node, context)
        yield new_node
      end

      def collect_children(node, new_node, context)
        results = []
        node.children.each_with_index do |child, i|
          ctx = child_context(node, child, context, new_node: new_node, position: i)
          visit_iter(child, ctx) { |v| results << v }
        end
        results
      end

      private

      def _clone_item(node)
        node.clone_item
      end
    end

    # Extends the context with a `path` tuple: a list of child indices
    # from root to current node.
    module PathTrackingMixin
      def child_context(node, child, context, **kwargs)
        ctx = super
        if kwargs.key?(:position)
          ctx[:path] = (context[:path] || []) + [kwargs[:position]]
        end
        ctx
      end

      def visit(tree, context = nil)
        context ||= {}
        context[:path] ||= []
        super
      end
    end

    class PathTrackingVisitor < TreeVisitor
      include PathTrackingMixin

      def generic_visit(node, context, &block)
        node.children.each_with_index do |child, i|
          ctx = child_context(node, child, context, position: i)
          visit_iter(child, ctx, &block)
        end
      end
    end

    class PathTrackingTransformer < TreeTransformer
      include PathTrackingMixin

      # collect_children already passes position: so this automatically tracks paths
    end
  end
end
