require "luqum/tree"
require "luqum/visitor"

module Luqum
  module Tree
    RSpec.describe "Visitor" do
      describe Luqum::Visitor::TreeVisitor do
        let(:basic_visitor_class) do
          Class.new(Luqum::Visitor::TreeVisitor) do
            def generic_visit(node, context, &)
              yield node
              super
            end
          end
        end

        let(:tracking_parents_visitor_class) do
          Class.new(Luqum::Visitor::TreeVisitor) do
            def generic_visit(node, context, &)
              yield [node, context[:parents]]
              super
            end
          end
        end

        let(:mro_visitor_class) do
          Class.new(Luqum::Visitor::TreeVisitor) do
            def visit_or_operation(node, context, &)
              yield "#{node.children[0]} OR #{node.children[1]}"
              generic_visit(node, context, &)
            end

            def visit_base_operation(node, context, &)
              yield "#{node.children[0]} BASE_OP #{node.children[1]}"
              generic_visit(node, context, &)
            end

            def visit_word(node, _context)
              yield node.value
            end
          end
        end

        it "generic_visit yields nothing by default" do
          tree = AndOperation.new(Word.new("foo"), Word.new("bar"))
          visitor = Luqum::Visitor::TreeVisitor.new
          expect(visitor.visit(tree)).to eq([])
          expect(visitor.visit(tree, {})).to eq([])
        end

        it "visits every node" do
          tree = AndOperation.new(Word.new("foo"), Word.new("bar"))
          visitor = basic_visitor_class.new
          nodes = visitor.visit(tree)
          expect(nodes).to eq([tree, Word.new("foo"), Word.new("bar")])
        end

        it "tracks parents when asked" do
          tree = AndOperation.new(Word.new("foo"), Proximity.new(Phrase.new('"bar"'), degree: 2))
          visitor = tracking_parents_visitor_class.new(track_parents: true)
          nodes = visitor.visit(tree)
          expect(nodes).to eq([
                                [tree, nil],
                                [Word.new("foo"), [tree]],
                                [Proximity.new(Phrase.new('"bar"'), degree: 2), [tree]],
                                [Phrase.new('"bar"'), [tree, Proximity.new(Phrase.new('"bar"'), degree: 2)]],
                              ])
        end

        it "omits parents when not tracking" do
          tree = AndOperation.new(Word.new("foo"), Phrase.new('"bar"'))
          visitor = tracking_parents_visitor_class.new
          nodes = visitor.visit(tree)
          expect(nodes).to eq([
                                [tree, nil],
                                [Word.new("foo"), nil],
                                [Phrase.new('"bar"'), nil],
                              ])
        end

        it "dispatches by MRO" do
          visitor = mro_visitor_class.new

          tree = OrOperation.new(Word.new("a"), Word.new("b"))
          expect(visitor.visit(tree)).to eq(["a OR b", "a", "b"])

          # AndOperation has no specific method, inherits BaseOperation,
          # so visit_base_operation is used.
          tree = AndOperation.new(Word.new("a"), Word.new("b"))
          expect(visitor.visit(tree)).to eq(["a BASE_OP b", "a", "b"])
        end
      end

      describe Luqum::Visitor::TreeTransformer do
        let(:basic_transformer_class) do
          Class.new(Luqum::Visitor::TreeTransformer) do
            def visit_word(_node, context)
              yield Word.new(context[:replacement] || "lol")
            end

            def visit_phrase(_node, _context)
              # yields nothing = removal
            end

            def visit_base_operation(node, context)
              results = []
              generic_visit(node, context) { |n| results << n }
              new_node = results[0]
              if new_node.children.empty?
                nil
              elsif new_node.children.length == 1
                yield new_node.children[0]
              else
                yield new_node
              end
            end
          end
        end

        let(:tracking_parents_transformer_class) do
          Class.new(Luqum::Visitor::TreeTransformer) do
            def visit_word(node, context)
              results = []
              generic_visit(node, context) { |n| results << n }
              new_node = results[0]
              new_parents = context[:new_parents] || []
              if new_parents.any? { |p| p.is_a?(SearchField) }
                new_node.value = "lol"
              end
              yield new_node
            end
          end
        end

        let(:raising_transformer_class) do
          Class.new(Luqum::Visitor::TreeTransformer) do
            def generic_visit(node, _context)
              yield node
              yield node
            end
          end
        end

        let(:raising_transformer_class_2) do
          Class.new(Luqum::Visitor::TreeTransformer) do
            def generic_visit(_node, _context)
              raise ArgumentError, "Random error"
            end
          end
        end

        it "transforms a simple tree" do
          tree = AndOperation.new(Word.new("foo"), Word.new("bar"))
          new_tree = basic_transformer_class.new.visit(tree)
          expect(new_tree).to eq(AndOperation.new(Word.new("lol"), Word.new("lol")))
        end

        it "passes context values through" do
          tree = AndOperation.new(Word.new("foo"), Word.new("bar"))
          new_tree = basic_transformer_class.new.visit(tree, { replacement: "rotfl" })
          expect(new_tree).to eq(AndOperation.new(Word.new("rotfl"), Word.new("rotfl")))
        end

        it "leaves a NONE_ITEM tree unchanged" do
          tree = AndOperation.new(NONE_ITEM, NONE_ITEM)
          new_tree = basic_transformer_class.new.visit(tree)
          expect(new_tree).to eq(tree)
        end

        it "transforms a single word tree" do
          tree = Word.new("foo")
          new_tree = basic_transformer_class.new.visit(tree)
          expect(new_tree).to eq(Word.new("lol"))
        end

        it "tracks new parents" do
          tree = OrOperation.new(Word.new("foo"), SearchField.new("test", Word.new("bar")))
          expected = OrOperation.new(Word.new("foo"), SearchField.new("test", Word.new("lol")))
          transformer = tracking_parents_transformer_class.new(track_new_parents: true)
          expect(transformer.visit(tree)).to eq(expected)
        end

        it "collapses empty operations" do
          tree = AndOperation.new(
            OrOperation.new(Word.new("spam"), Word.new("ham")),
            AndOperation.new(Word.new("foo"), Phrase.new('"bar"')),
            AndOperation.new(Phrase.new('"baz"'), Phrase.new('"biz"')),
          )
          new_tree = basic_transformer_class.new.visit(tree)
          expect(new_tree).to eq(
            AndOperation.new(OrOperation.new(Word.new("lol"), Word.new("lol")), Word.new("lol")),
          )
        end

        it "preserves repeated sub-expressions via default transformer" do
          tree = AndOperation.new(
            Group.new(OrOperation.new(Word.new("bar"), Word.new("foo"))),
            Group.new(OrOperation.new(Word.new("bar"), Word.new("foo"), Word.new("spam"))),
          )
          same_tree = Luqum::Visitor::TreeTransformer.new.visit(Marshal.load(Marshal.dump(tree)))
          expect(same_tree).to eq(tree)
        end

        it "raises when more than one element results" do
          tree = Word.new("foo")
          expect { raising_transformer_class.new.visit(tree) }.to raise_error(
            ArgumentError, /exactly one element/
          )
        end

        it "lets unrelated errors pass through" do
          tree = Word.new("foo")
          expect { raising_transformer_class_2.new.visit(tree) }.to raise_error(
            ArgumentError, "Random error"
          )
        end
      end

      describe Luqum::Visitor::PathTrackingVisitor do
        let(:term_path_visitor_class) do
          Class.new(Luqum::Visitor::PathTrackingVisitor) do
            def visit_term(node, context)
              yield [context[:path], node.value]
            end
          end
        end

        it "visits a simple term" do
          paths = term_path_visitor_class.new.visit(Word.new("foo"))
          expect(paths).to eq([[[], "foo"]])
        end

        it "visits a complex tree and records paths" do
          tree = AndOperation.new(
            Group.new(OrOperation.new(
              Word.new("foo"),
              Word.new("bar"),
              Boost.new(Fuzzy.new(Word.new("baz")), force: 2),
            )),
            Proximity.new(Phrase.new('"spam ham"')),
            SearchField.new("fizz", Regex.new("/fuzz/")),
          )
          paths = term_path_visitor_class.new.visit(tree)
          expect(paths.sort_by { |p, _| p }).to eq([
                                                     [[0, 0, 0], "foo"],
                                                     [[0, 0, 1], "bar"],
                                                     [[0, 0, 2, 0, 0], "baz"],
                                                     [[1, 0], '"spam ham"'],
                                                     [[2, 0], "/fuzz/"],
                                                   ])
        end
      end

      describe Luqum::Visitor::PathTrackingTransformer do
        let(:term_path_transformer_class) do
          Class.new(Luqum::Visitor::PathTrackingTransformer) do
            def visit_term(node, context)
              path = context[:path].map(&:to_s).join("-")
              quote = case node
                      when Phrase then '"'
                      when Regex then "/"
                      else ""
                      end
              value = if quote.empty?
                        node.value
                      else
                        node.value.delete_prefix(quote).delete_suffix(quote)
                      end
              yield node.clone_item(value: "#{quote}#{value}@#{path}#{quote}")
            end
          end
        end

        it "transforms a simple word" do
          tree = term_path_transformer_class.new.visit(Word.new("foo"))
          expect(tree).to eq(Word.new("foo@"))
        end

        it "transforms a complex tree" do
          tree = AndOperation.new(
            Group.new(OrOperation.new(
              Word.new("foo"),
              Word.new("bar"),
              Boost.new(Fuzzy.new(Word.new("baz")), force: 2),
            )),
            Proximity.new(Phrase.new('"spam ham"')),
            SearchField.new("fizz", Regex.new("/fuzz/")),
          )
          transformed = term_path_transformer_class.new.visit(tree)
          expected = AndOperation.new(
            Group.new(OrOperation.new(
              Word.new("foo@0-0-0"),
              Word.new("bar@0-0-1"),
              Boost.new(Fuzzy.new(Word.new("baz@0-0-2-0-0")), force: 2),
            )),
            Proximity.new(Phrase.new('"spam ham@1-0"')),
            SearchField.new("fizz", Regex.new("/fuzz@2-0/")),
          )
          expect(transformed).to eq(expected)
        end
      end
    end
  end
end
