require "luqum/visitor"

module Luqum
  module Naming
    NAME_ATTR = "@_luqum_name".freeze

    class TreeAutoNamer < Luqum::Visitor::PathTrackingVisitor
      LETTERS = "abcdefghilklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".freeze
      POS_LETTER = LETTERS.chars.each_with_index.to_h.freeze

      def next_name(name)
        return LETTERS[0] if name.nil?

        actual_pos = POS_LETTER.fetch(name[-1])
        next_letter = LETTERS[actual_pos + 1]
        next_letter.nil? ? name + LETTERS[0] : name[0...-1] + next_letter
      end

      def visit_base_operation(node, context, &)
        name = context[:global][:name]
        node.children.each_with_index do |child, i|
          name = next_name(name)
          Luqum::Naming.set_name(child, name)
          context[:global][:name_to_path][name] = context[:path] + [i]
        end
        context[:global][:name] = name
        generic_visit(node, context, &)
      end

      def visit(node)
        context = { global: { name: nil, name_to_path: {} } }
        super(node, context)
        name_to_path = context[:global][:name_to_path]
        if name_to_path.empty?
          node_name = next_name(context[:global][:name])
          Luqum::Naming.set_name(node, node_name)
          name_to_path[node_name] = []
        end
        name_to_path
      end
    end

    class MatchingPropagator
      OR_NODES = [Luqum::Tree::OrOperation].freeze
      NEGATION_NODES = [Luqum::Tree::Not, Luqum::Tree::Prohibit].freeze
      NO_CHILDREN_PROPAGATE = [Luqum::Tree::Range, Luqum::Tree::BaseApprox].freeze

      def initialize(default_operation: Luqum::Tree::OrOperation)
        @or_nodes = OR_NODES.dup
        @or_nodes << Luqum::Tree::UnknownOperation if default_operation == Luqum::Tree::OrOperation
      end

      def call(tree, matching, other = Set.new)
        _, paths_ok, paths_ko = propagate(tree, Set.new(matching), Set.new(other), [])
        [paths_ok, paths_ko]
      end

      private

      def status_from_parent(path, matching, other)
        if matching.include?(path)
          true
        elsif other.include?(path)
          false
        elsif path.empty?
          false
        else
          status_from_parent(path[0...-1], matching, other)
        end
      end

      def propagate(node, matching, other, path)
        paths_ok = Set.new
        paths_ko = Set.new
        children_status = []

        if !node.children.empty? && NO_CHILDREN_PROPAGATE.none? { |cls| node.is_a?(cls) }
          node.children.each_with_index do |child, i|
            child_ok, sub_ok, sub_ko = propagate(child, matching, other, path + [i])
            paths_ok.merge(sub_ok)
            paths_ko.merge(sub_ko)
            children_status << child_ok
          end
        end

        node_ok = if matching.include?(path)
                    true
                  elsif children_status.any?
                    @or_nodes.any? { |cls| node.is_a?(cls) } ? children_status.any? : children_status.all?
                  else
                    status_from_parent(path, matching, other)
                  end

        node_ok = !node_ok if NEGATION_NODES.any? { |cls| node.is_a?(cls) }

        if node_ok
          paths_ok.add(path)
        else
          paths_ko.add(path)
        end

        [node_ok, paths_ok, paths_ko]
      end
    end

    class ExpressionMarker < Luqum::Visitor::PathTrackingTransformer
      def mark_node(node, _path, *_info)
        node
      end

      def generic_visit(node, context)
        new_node = nil
        super { |visited| new_node = visited }
        yield mark_node(new_node, context[:path], *context[:info])
      end

      def call(tree, *info)
        visit(tree, { info: info })
      end
    end

    class HTMLMarker < ExpressionMarker
      def initialize(ok_class: "ok", ko_class: "ko", element: "span")
        super()
        @ok_class = ok_class
        @ko_class = ko_class
        @element = element
      end

      def css_class(path, paths_ok, paths_ko)
        if paths_ok.include?(path)
          @ok_class
        elsif paths_ko.include?(path)
          @ko_class
        end
      end

      def mark_node(node, path, paths_ok, paths_ko, parcimonious)
        node_class = css_class(path, paths_ok, paths_ko)
        add_class = !node_class.nil?
        if add_class && parcimonious
          parent_class = nil
          parent_path = path
          while parent_class.nil? && !parent_path.empty?
            parent_path = parent_path[0...-1]
            parent_class = css_class(parent_path, paths_ok, paths_ko)
          end
          add_class = node_class != parent_class
        end
        if add_class
          node.head = %(<#{@element} class="#{node_class}">#{node.head})
          node.tail = %(#{node.tail}</#{@element}>)
        end
        node
      end

      def call(tree, paths_ok, paths_ko, parcimonious: true)
        new_tree = super(tree, paths_ok, paths_ko, parcimonious)
        new_tree.to_s(head_tail: true)
      end
    end

    class << self
      def set_name(node, value)
        node.instance_variable_set(NAME_ATTR, value)
      end

      def get_name(node)
        node.instance_variable_get(NAME_ATTR)
      end

      def auto_name(tree, _targets = nil, _all_names = false)
        TreeAutoNamer.new.visit(tree)
      end

      def matching_from_names(names, name_to_path)
        matching = Set.new(names.map { |name| name_to_path.fetch(name) })
        [matching, Set.new(name_to_path.values) - matching]
      end

      def element_from_path(tree, path)
        node = tree
        current_path = path.dup
        node = node.children.fetch(current_path.shift) until current_path.empty?
        node
      end

      def element_from_name(tree, name, name_to_path)
        element_from_path(tree, name_to_path.fetch(name))
      end
    end
  end
end
