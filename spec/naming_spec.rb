# frozen_string_literal: true

RSpec.describe Luqum::Naming do
  def word(value, **)
    Luqum::Tree::Word.new(value, **)
  end

  def phrase(value, **)
    Luqum::Tree::Phrase.new(value, **)
  end

  def regex(value, **)
    Luqum::Tree::Regex.new(value, **)
  end

  def range(low, high, include_low: true, include_high: true, **)
    Luqum::Tree::Range.new(
      low,
      high,
      include_low: include_low,
      include_high: include_high,
      **,
    )
  end

  def search_field(name, expr, **)
    Luqum::Tree::SearchField.new(name, expr, **)
  end

  def group(expr, **)
    Luqum::Tree::Group.new(expr, **)
  end

  def field_group(expr, **)
    Luqum::Tree::FieldGroup.new(expr, **)
  end

  def and_op(*children, **)
    Luqum::Tree::AndOperation.new(*children, **)
  end

  def or_op(*children, **)
    Luqum::Tree::OrOperation.new(*children, **)
  end

  def unknown_op(*children, **)
    Luqum::Tree::UnknownOperation.new(*children, **)
  end

  def fuzzy(term, degree: nil, **)
    Luqum::Tree::Fuzzy.new(term, degree: degree, **)
  end

  def proximity(term, degree:, **)
    Luqum::Tree::Proximity.new(term, degree: degree, **)
  end

  def plus(expr, **)
    Luqum::Tree::Plus.new(expr, **)
  end

  def not_op(expr, **)
    Luqum::Tree::Not.new(expr, **)
  end

  def prohibit(expr, **)
    Luqum::Tree::Prohibit.new(expr, **)
  end

  def boost(expr, force:, **)
    Luqum::Tree::Boost.new(expr, force: force, **)
  end

  def names_to_path(node, path = [])
    names = {}
    node_name = Luqum::Naming.get_name(node)
    names[node_name] = path if node_name
    node.children.each_with_index do |child, i|
      names.merge!(names_to_path(child, path + [i]))
    end
    names
  end

  def simple_naming(node, names = {}, path = [])
    node_name = if node.is_a?(Luqum::Tree::Term)
                  node.value.delete_prefix('"').delete_suffix('"').delete_prefix("/").delete_suffix("/").downcase
                else
                  name = node.class.name.split("::").last.downcase
                  name.end_with?("operation") ? name.delete_suffix("operation") : name
                end
    if names.key?(node_name)
      node_name += (1 + names.keys.count { |candidate_name| candidate_name.start_with?(node_name) }).to_s
    end
    Luqum::Naming.set_name(node, node_name)
    names[node_name] = path
    node.children.each_with_index do |child, i|
      simple_naming(child, names, path + [i])
    end
    names
  end

  def paths_to_names(tree, paths)
    Set.new(paths.map { |path| Luqum::Naming.get_name(Luqum::Naming.element_from_path(tree, path)) })
  end

  describe ".auto_name" do
    it "names a single term-like root node" do
      tree = word("test")
      names = described_class.auto_name(tree)
      expect(described_class.get_name(tree)).to eq("a")
      expect(names).to eq({ "a" => [] })

      tree = phrase('"test"')
      names = described_class.auto_name(tree)
      expect(described_class.get_name(tree)).to eq("a")
      expect(names).to eq({ "a" => [] })

      tree = range(word("test"), word("*"))
      names = described_class.auto_name(tree)
      expect(described_class.get_name(tree)).to eq("a")
      expect(names).to eq({ "a" => [] })

      tree = regex("/test/")
      names = described_class.auto_name(tree)
      expect(described_class.get_name(tree)).to eq("a")
      expect(names).to eq({ "a" => [] })
    end

    it "names direct children of simple operations" do
      [Luqum::Tree::AndOperation, Luqum::Tree::OrOperation, Luqum::Tree::UnknownOperation].each do |op_class|
        tree = op_class.new(word("test"), phrase('"test"'))
        names = described_class.auto_name(tree)
        expect(described_class.get_name(tree)).to be_nil
        expect(described_class.get_name(tree.children[0])).to eq("a")
        expect(described_class.get_name(tree.children[1])).to eq("b")
        expect(names).to eq({ "a" => [0], "b" => [1] })
      end
    end

    it "names nested trees in traversal order" do
      tree = and_op(
        or_op(
          search_field("bar", word("test")),
          and_op(
            proximity(phrase('"test"'), degree: 2),
            search_field("baz", word("test")),
          ),
        ),
        group(
          unknown_op(
            fuzzy(word("test")),
            phrase('"test"'),
          ),
        ),
      )

      names = described_class.auto_name(tree)
      expect(names.keys.sort).to eq(%w[a b c d e f g h])

      and1 = tree
      expect(described_class.get_name(and1)).to be_nil

      or1 = and1.children[0]
      expect(described_class.get_name(or1)).to eq("a")
      expect(names["a"]).to eq([0])

      sfield1 = or1.children[0]
      expect(described_class.get_name(sfield1)).to eq("c")
      expect(names["c"]).to eq([0, 0])
      expect(described_class.get_name(sfield1.expr)).to be_nil

      and2 = or1.children[1]
      expect(described_class.get_name(and2)).to eq("d")
      expect(names["d"]).to eq([0, 1])

      expect(described_class.get_name(and2.children[0])).to eq("e")
      expect(names["e"]).to eq([0, 1, 0])
      expect(described_class.get_name(and2.children[0].term)).to be_nil

      sfield2 = and2.children[1]
      expect(described_class.get_name(sfield2)).to eq("f")
      expect(names["f"]).to eq([0, 1, 1])
      expect(described_class.get_name(sfield2.expr)).to be_nil

      group1 = and1.children[1]
      expect(described_class.get_name(group1)).to eq("b")
      expect(names["b"]).to eq([1])

      unknown1 = group1.children[0]
      expect(described_class.get_name(unknown1)).to be_nil
      expect(described_class.get_name(unknown1.children[0])).to eq("g")
      expect(names["g"]).to eq([1, 0, 0])
      expect(described_class.get_name(unknown1.children[0].term)).to be_nil
      expect(described_class.get_name(unknown1.children[1])).to eq("h")
      expect(names["h"]).to eq([1, 0, 1])
    end
  end

  describe "utility helpers" do
    it "builds matching and non-matching paths from names" do
      names = {
        "a" => [0],
        "b" => [1],
        "c" => [0, 0],
        "d" => [0, 1],
        "e" => [1, 0, 1],
      }

      expect(described_class.matching_from_names([], names)).to eq(
        [Set.new, Set[[0], [1], [0, 0], [0, 1], [1, 0, 1]]],
      )
      expect(described_class.matching_from_names(%w[a b], names)).to eq(
        [Set[[0], [1]], Set[[0, 0], [0, 1], [1, 0, 1]]],
      )
      expect(described_class.matching_from_names(%w[a e], names)).to eq(
        [Set[[0], [1, 0, 1]], Set[[1], [0, 0], [0, 1]]],
      )
      expect(described_class.matching_from_names(["c"], names)).to eq(
        [Set[[0, 0]], Set[[0], [1], [0, 1], [1, 0, 1]]],
      )

      expect do
        described_class.matching_from_names(["x"], names)
      end.to raise_error(KeyError)
    end

    it "looks up elements by path and by name" do
      tree = and_op(
        or_op(
          search_field("bar", word("test")),
          group(
            and_op(
              proximity(phrase('"test"'), degree: 2),
              search_field("baz", word("test")),
              fuzzy(word("test")),
              phrase('"test"'),
            ),
          ),
        ),
      )
      names = {
        "a" => [],
        "b" => [0, 1],
        "c" => [0, 1, 0, 2],
        "d" => [0, 1, 0, 2, 0],
        "e" => [0, 1, 0, 3],
      }

      expect(described_class.element_from_path(tree, [])).to eq(tree)
      expect(described_class.element_from_name(tree, "a", names)).to eq(tree)
      expect(described_class.element_from_path(tree, [0, 1])).to eq(tree.children[0].children[1])
      expect(described_class.element_from_name(tree, "b", names)).to eq(tree.children[0].children[1])
      expect(described_class.element_from_path(tree, [0, 1, 0, 2])).to eq(fuzzy(word("test")))
      expect(described_class.element_from_name(tree, "c", names)).to eq(fuzzy(word("test")))
      expect(described_class.element_from_path(tree, [0, 1, 0, 2, 0])).to eq(word("test"))
      expect(described_class.element_from_name(tree, "d", names)).to eq(word("test"))
      expect(described_class.element_from_path(tree, [0, 1, 0, 3])).to eq(phrase('"test"'))
      expect(described_class.element_from_name(tree, "e", names)).to eq(phrase('"test"'))

      expect do
        described_class.element_from_path(tree, [1])
      end.to raise_error(IndexError)
    end
  end

  describe Luqum::Naming::MatchingPropagator do
    let(:propagate_matching) { described_class.new }

    it "propagates through OR operations" do
      tree = or_op(word("foo"), phrase('"bar"'), word("baz"))
      all_paths = Set[[0], [1], [2]]

      matching = Set.new
      paths_ok, paths_ko = propagate_matching.call(tree, matching, all_paths - matching)
      expect(paths_ok).to eq(Set.new)
      expect(paths_ko).to eq(Set[[], [0], [1], [2]])

      matching = Set[[2]]
      paths_ok, paths_ko = propagate_matching.call(tree, matching, all_paths - matching)
      expect(paths_ok).to eq(Set[[], [2]])
      expect(paths_ko).to eq(Set[[0], [1]])

      matching = Set[[0], [2]]
      paths_ok, paths_ko = propagate_matching.call(tree, matching, all_paths - matching)
      expect(paths_ok).to eq(Set[[], [0], [2]])
      expect(paths_ko).to eq(Set[[1]])

      matching = Set[[0], [1], [2]]
      paths_ok, paths_ko = propagate_matching.call(tree, matching, all_paths - matching)
      expect(paths_ok).to eq(Set[[], [0], [1], [2]])
      expect(paths_ko).to eq(Set.new)
    end

    it "propagates through AND operations" do
      tree = and_op(word("foo"), phrase('"bar"'), word("baz"))
      all_paths = Set[[0], [1], [2]]

      matching = Set.new
      paths_ok, paths_ko = propagate_matching.call(tree, matching, all_paths - matching)
      expect(paths_ok).to eq(Set.new)
      expect(paths_ko).to eq(Set[[], [0], [1], [2]])

      matching = Set[[2]]
      paths_ok, paths_ko = propagate_matching.call(tree, matching, all_paths - matching)
      expect(paths_ok).to eq(Set[[2]])
      expect(paths_ko).to eq(Set[[], [0], [1]])

      matching = Set[[0], [2]]
      paths_ok, paths_ko = propagate_matching.call(tree, matching, all_paths - matching)
      expect(paths_ok).to eq(Set[[0], [2]])
      expect(paths_ko).to eq(Set[[], [1]])

      matching = Set[[0], [1], [2]]
      paths_ok, paths_ko = propagate_matching.call(tree, matching, all_paths - matching)
      expect(paths_ok).to eq(Set[[], [0], [1], [2]])
      expect(paths_ko).to eq(Set.new)
    end

    it "treats unknown operations as OR by default and AND when configured" do
      tree = unknown_op(word("foo"), phrase('"bar"'), word("baz"))
      tree_or = or_op(word("foo"), phrase('"bar"'), word("baz"))
      tree_and = and_op(word("foo"), phrase('"bar"'), word("baz"))
      propagate_or = propagate_matching
      propagate_and = described_class.new(default_operation: Luqum::Tree::AndOperation)

      [Set.new, Set[[2]], Set[[0], [2]], Set[[0], [1], [2]]].each do |matching|
        expect(propagate_or.call(tree, matching)).to eq(
          propagate_matching.call(tree_or, matching, Set.new),
        )
        expect(propagate_and.call(tree, matching)).to eq(
          propagate_matching.call(tree_and, matching, Set.new),
        )
      end
    end

    it "propagates negation nodes" do
      [prohibit(word("foo")), not_op(word("foo"))].each do |tree|
        paths_ok, paths_ko = propagate_matching.call(tree, Set.new, Set[[0]])
        expect(paths_ok).to eq(Set[[]])
        expect(paths_ko).to eq(Set[[0]])

        paths_ok, paths_ko = propagate_matching.call(tree, Set[[0]], Set.new)
        expect(paths_ok).to eq(Set[[0]])
        expect(paths_ko).to eq(Set[[]])
      end
    end

    it "propagates nested negations" do
      [Luqum::Tree::Prohibit, Luqum::Tree::Not].each do |neg_class|
        tree = and_op(
          neg_class.new(
            or_op(
              neg_class.new(
                and_op(
                  neg_class.new(word("a")),
                  word("b"),
                ),
              ),
              word("c"),
            ),
          ),
          word("d"),
        )

        a = [0, 0, 0, 0, 0, 0]
        b = [0, 0, 0, 0, 1]
        c = [0, 0, 1]
        d = [1]
        not_a = [0, 0, 0, 0, 0]
        ab = [0, 0, 0, 0]
        not_ab = [0, 0, 0]
        abc = [0, 0]
        not_abc = [0]
        abcd = []

        paths_ok, paths_ko = propagate_matching.call(tree, Set.new, Set[a, b, c, d])
        expect(paths_ok).to eq(Set[not_a, not_ab, abc])
        expect(paths_ko).to eq(Set[a, b, ab, c, not_abc, d, abcd])

        paths_ok, paths_ko = propagate_matching.call(tree, Set[b, d], Set[a, c])
        expect(paths_ok).to eq(Set[not_a, b, ab, not_abc, d, abcd])
        expect(paths_ko).to eq(Set[a, not_ab, c, abc])

        paths_ok, paths_ko = propagate_matching.call(tree, Set[a, b, c], Set[d])
        expect(paths_ok).to eq(Set[a, b, not_ab, c, abc])
        expect(paths_ko).to eq(Set[not_a, ab, not_abc, d, abcd])

        paths_ok, paths_ko = propagate_matching.call(tree, Set[a, b, c, d], Set.new)
        expect(paths_ok).to eq(Set[a, b, not_ab, c, abc, d])
        expect(paths_ko).to eq(Set[not_a, ab, not_abc, abcd])
      end
    end

    it "handles single elements" do
      [word("a"), phrase('"a"'), regex("/a/")].each do |tree|
        paths_ok, paths_ko = propagate_matching.call(tree, Set.new)
        expect(paths_ok).to eq(Set.new)
        expect(paths_ko).to eq(Set[[]])

        paths_ok, paths_ko = propagate_matching.call(tree, Set[[]])
        expect(paths_ok).to eq(Set[[]])
        expect(paths_ko).to eq(Set.new)
      end
    end

    it "does not propagate into ranges or approximations" do
      [
        range(word("a"), word("b")),
        fuzzy(word("foo")),
        proximity(phrase('"bar baz"'), degree: 2),
      ].each do |tree|
        paths_ok, paths_ko = propagate_matching.call(tree, Set.new, Set[[]])
        expect(paths_ok).to eq(Set.new)
        expect(paths_ko).to eq(Set[[]])

        paths_ok, paths_ko = propagate_matching.call(tree, Set[[]], Set.new)
        expect(paths_ok).to eq(Set[[]])
        expect(paths_ko).to eq(Set.new)
      end
    end

    it "propagates through single-child wrapper nodes" do
      tree = boost(
        group(
          search_field(
            "foo",
            field_group(
              plus(word("bar")),
            ),
          ),
        ),
        force: 2,
      )

      paths_ok, paths_ko = propagate_matching.call(tree, Set.new, Set[[]])
      expect(paths_ok).to eq(Set.new)
      expect(paths_ko).to eq(Set[[], [0], [0, 0], [0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0, 0]])

      paths_ok, paths_ko = propagate_matching.call(tree, Set[[]], Set.new)
      expect(paths_ok).to eq(Set[[], [0], [0, 0], [0, 0, 0], [0, 0, 0, 0], [0, 0, 0, 0, 0]])
      expect(paths_ko).to eq(Set.new)
    end

    it "propagates through a mixed tree" do
      tree = and_op(
        or_op(
          search_field(
            "mine",
            field_group(
              plus(
                and_op(
                  word("foo"),
                  regex("/fizz/"),
                ),
              ),
            ),
          ),
          boost(
            group(
              and_op(
                phrase('"ham"'),
                word("spam"),
                prohibit(fuzzy(word("fuzz"))),
              ),
            ),
            force: 2,
          ),
        ),
        not_op(
          or_op(
            word('"bar"'),
            word('"baz"'),
          ),
        ),
      )
      to_path = simple_naming(tree)

      paths_ok, paths_ko = propagate_matching.call(tree, Set.new)
      expect(paths_to_names(tree, paths_ok)).to eq(Set["prohibit", "not"])
      expect(paths_to_names(tree, paths_ko)).to eq(
        Set[
          "and", "or", "searchfield", "fieldgroup", "plus", "and2", "foo", "fizz",
          "boost", "group", "and3", "ham", "spam", "fuzzy", "or2", "bar", "baz"
        ],
      )

      paths_ok, paths_ko = propagate_matching.call(
        tree,
        Set[to_path["foo"], to_path["fizz"], to_path["ham"]],
      )
      expect(paths_to_names(tree, paths_ok)).to eq(
        Set[
          "and", "or", "searchfield", "fieldgroup", "plus", "and2", "foo", "fizz", "ham",
          "prohibit", "not"
        ],
      )
      expect(paths_to_names(tree, paths_ko)).to eq(
        Set["boost", "group", "and3", "spam", "fuzzy", "or2", "bar", "baz"],
      )

      paths_ok, paths_ko = propagate_matching.call(
        tree,
        Set[to_path["foo"], to_path["fizz"], to_path["ham"], to_path["spam"]],
      )
      expect(paths_to_names(tree, paths_ok)).to eq(
        Set[
          "and", "or", "searchfield", "fieldgroup", "plus", "and2", "foo", "fizz", "ham",
          "prohibit", "boost", "group", "and3", "spam", "not"
        ],
      )
      expect(paths_to_names(tree, paths_ko)).to eq(Set["fuzzy", "or2", "bar", "baz"])

      paths_ok, paths_ko = propagate_matching.call(
        tree,
        Set[
          to_path["foo"],
          to_path["fizz"],
          to_path["ham"],
          to_path["spam"],
          to_path["fuzzy"],
          to_path["bar"],
        ],
      )
      expect(paths_to_names(tree, paths_ok)).to eq(
        Set[
          "or", "searchfield", "fieldgroup", "plus", "and2",
          "foo", "fizz", "ham", "spam", "fuzzy", "or2", "bar"
        ],
      )
      expect(paths_to_names(tree, paths_ko)).to eq(
        Set["and", "boost", "group", "and3", "prohibit", "not", "baz"],
      )
    end
  end

  describe Luqum::Naming::HTMLMarker do
    let(:mark_html) { described_class.new }

    it "marks a single element" do
      tree = Luqum::Parser.parse('"b"')

      out = mark_html.call(tree, Set[[]], Set.new)
      expect(out).to eq('<span class="ok">"b"</span>')

      out = mark_html.call(tree, Set[[]], Set.new, parcimonious: false)
      expect(out).to eq('<span class="ok">"b"</span>')

      out = mark_html.call(tree, Set.new, Set[[]])
      expect(out).to eq('<span class="ko">"b"</span>')

      out = mark_html.call(tree, Set.new, Set[[]], parcimonious: false)
      expect(out).to eq('<span class="ko">"b"</span>')
    end

    it "marks multiple elements" do
      tree = Luqum::Parser.parse("(foo OR bar~2 OR baz^2) AND NOT spam")
      names = simple_naming(tree)
      foo = names["foo"]
      bar = names["fuzzy"]
      baz = names["boost"]
      spam = names["spam"]
      or_ = names["or"]
      and_ = names["and"]
      not_ = names["not"]

      out = mark_html.call(tree, Set[foo, bar, baz, or_, and_, not_], Set[spam])
      expect(out).to eq(
        '<span class="ok">(foo OR bar~2 OR baz^2) AND NOT<span class="ko"> spam</span></span>',
      )

      out = mark_html.call(tree, Set[foo, bar, baz, or_, and_, not_], Set[spam], parcimonious: false)
      expect(out).to eq(
        '<span class="ok">' \
        '(<span class="ok"><span class="ok">foo </span>OR<span class="ok"> bar~2 </span>OR' \
        '<span class="ok"> baz^2</span></span>) ' \
        "AND" \
        '<span class="ok"> NOT<span class="ko"> spam</span></span>' \
        "</span>",
      )

      out = mark_html.call(tree, Set[not_], Set[foo, bar, baz, or_, and_, spam])
      expect(out).to eq(
        '<span class="ko">(foo OR bar~2 OR baz^2) AND' \
        '<span class="ok"> NOT<span class="ko"> spam</span></span></span>',
      )

      mark = described_class.new(ok_class: "success", ko_class: "failure", element: "li")
      out = mark.call(tree, Set[not_], Set[foo, bar, baz, or_, and_, spam])
      expect(out).to eq(
        '<li class="failure">(foo OR bar~2 OR baz^2) AND' \
        '<li class="success"> NOT<li class="failure"> spam</li></li></li>',
      )
    end
  end

  describe Luqum::Naming::ExpressionMarker do
    it "returns the tree unchanged by default" do
      tree = Luqum::Parser.parse("foo AND bar")
      marker = described_class.new
      out = marker.call(tree, Set[[], [0], [1]], {})
      expect(out).to eq(tree)
    end
  end
end
