# frozen_string_literal: true
require "luqum/tree"

RSpec.describe Luqum::DeprecatedUtils do
  def word(value, **)
    Luqum::Tree::Word.new(value, **)
  end

  def phrase(value, **)
    Luqum::Tree::Phrase.new(value, **)
  end

  def and_op(*children, **)
    Luqum::Tree::AndOperation.new(*children, **)
  end

  def or_op(*children, **)
    Luqum::Tree::OrOperation.new(*children, **)
  end

  def group(expr, **)
    Luqum::Tree::Group.new(expr, **)
  end

  describe Luqum::DeprecatedUtils::LuceneTreeVisitor do
    let(:basic_visitor_class) do
      Class.new(described_class) do
        def generic_visit(node, _parents)
          [node]
        end
      end
    end

    let(:mro_visitor_class) do
      Class.new(described_class) do
        def visit_or_operation(node, _parents = [])
          ["#{node.children[0]} OR #{node.children[1]}"]
        end

        def visit_base_operation(node, _parents = [])
          ["#{node.children[0]} BASE_OP #{node.children[1]}"]
        end

        def visit_word(node, _parents = [])
          [node.value]
        end
      end
    end

    it "returns no values from the default generic visit" do
      tree = and_op(word("foo"), word("bar"))
      visitor = described_class.new
      expect(visitor.visit(tree).to_a).to eq([])
    end

    it "traverses the tree recursively" do
      tree = and_op(word("foo"), word("bar"))
      visitor = basic_visitor_class.new
      expect(visitor.visit(tree).to_a).to eq([tree, word("foo"), word("bar")])
    end

    it "dispatches using MRO" do
      visitor = mro_visitor_class.new

      tree = or_op(word("a"), word("b"))
      expect(visitor.visit(tree).to_a).to eq(["a OR b", "a", "b"])

      tree = and_op(word("a"), word("b"))
      expect(visitor.visit(tree).to_a).to eq(["a BASE_OP b", "a", "b"])
    end
  end

  describe Luqum::DeprecatedUtils::LuceneTreeTransformer do
    let(:basic_transformer_class) do
      Class.new(described_class) do
        def visit_word(_node, _parents)
          Luqum::Tree::Word.new("lol")
        end

        def visit_phrase(_node, _parents)
          nil
        end
      end
    end

    let(:or_list_operation_class) do
      Class.new(Luqum::Tree::OrOperation)
    end

    it "transforms a simple tree" do
      tree = and_op(word("foo"), word("bar"))
      new_tree = basic_transformer_class.new.visit(tree)
      expect(new_tree).to eq(and_op(word("lol"), word("lol")))
    end

    it "does not change an empty operation" do
      tree = and_op
      new_tree = basic_transformer_class.new.visit(tree)
      expect(new_tree).to eq(and_op)
    end

    it "transforms a single word" do
      tree = word("foo")
      new_tree = basic_transformer_class.new.visit(tree)
      expect(new_tree).to eq(word("lol"))
    end

    it "removes nodes when visit returns nil" do
      tree = and_op(
        and_op(word("foo"), phrase('"bar"')),
        and_op(phrase('"baz"'), phrase('"biz"')),
      )
      new_tree = basic_transformer_class.new.visit(tree)
      expect(new_tree).to eq(
        and_op(
          and_op(word("lol")),
          and_op,
        ),
      )
    end

    it "works with operation subclasses" do
      op_class = or_list_operation_class
      tree = op_class.new(
        op_class.new(word("foo"), phrase('"bar"')),
        op_class.new(phrase('"baz"')),
      )
      new_tree = basic_transformer_class.new.visit(tree)
      expect(new_tree).to eq(
        op_class.new(
          op_class.new(word("lol")),
          op_class.new,
        ),
      )
    end

    it "ignores misleading attributes while replacing nodes" do
      tree = and_op(word("a"), word("b"))
      tree.instance_variable_set(:@misleading1, [])
      tree.instance_variable_set(:@misleading2, [])

      new_tree = basic_transformer_class.new.visit(tree)
      expect(new_tree).to eq(and_op(word("lol"), word("lol")))
    end

    it "preserves repeated sub-expressions with the default transformer" do
      tree = and_op(
        group(or_op(word("bar"), word("foo"))),
        group(or_op(word("bar"), word("foo"), word("spam"))),
      )
      same_tree = described_class.new.visit(Marshal.load(Marshal.dump(tree)))
      expect(same_tree).to eq(tree)
    end
  end

  describe Luqum::DeprecatedUtils::LuceneTreeVisitorV2 do
    let(:basic_visitor_class) do
      Class.new(described_class) do
        def generic_visit(node, parents, context)
          Enumerator.new do |y|
            y << node
            node.children.each do |child|
              visit(child, parents + [node], context).each { |value| y << value }
            end
          end
        end
      end
    end

    let(:mro_visitor_class) do
      Class.new(described_class) do
        def visit_or_operation(node, _parents = [], _context = nil)
          node.children.map { |child| visit(child) }.join(" OR ")
        end

        def visit_base_operation(node, _parents = [], _context = nil)
          node.children.map { |child| visit(child) }.join(" BASE_OP ")
        end

        def visit_word(node, _parents = [], _context = nil)
          node.value
        end
      end
    end

    it "traverses the tree when generic_visit recurses" do
      tree = and_op(word("foo"), word("bar"))
      visitor = basic_visitor_class.new
      expect(visitor.visit(tree).to_a).to eq([tree, word("foo"), word("bar")])
    end

    it "dispatches using MRO" do
      visitor = mro_visitor_class.new

      tree = or_op(word("a"), word("b"))
      expect(visitor.visit(tree)).to eq("a OR b")

      tree = or_op(and_op(word("a"), word("b")), word("c"))
      expect(visitor.visit(tree)).to eq("a BASE_OP b OR c")
    end

    it "raises by default when no visitor exists" do
      visitor = mro_visitor_class.new
      expect { visitor.visit(phrase('"test"')) }.to raise_error(NoMethodError)
    end
  end
end
