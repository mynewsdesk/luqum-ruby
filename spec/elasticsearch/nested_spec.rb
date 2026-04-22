RSpec.describe Luqum::Elasticsearch::Nested do
  describe ".extract_nested_queries" do
    it "returns nothing when there is no nested query" do
      queries = described_class.extract_nested_queries(
        { "term" => { "text" => { "value" => "spam", "_name" => "spam" } } },
      )
      expect(queries).to eq([])

      queries = described_class.extract_nested_queries(
        {
          "bool" => {
            "must" => [
              { "term" => { "text" => { "value" => "spam", "_name" => "spam" } } },
              { "term" => { "text" => { "value" => "ham", "_name" => "ham" } } },
            ],
          },
        },
      )
      expect(queries).to eq([])
    end

    it "returns nothing for a nested query without a bool inside" do
      queries = described_class.extract_nested_queries(
        {
          "nested" => {
            "path" => "my",
            "query" => { "term" => { "text" => { "value" => "spam", "_name" => "spam" } } },
          },
        },
      )
      expect(queries).to eq([])
    end

    it "extracts bool children inside a nested query" do
      term1 = { "term" => { "text" => { "value" => "spam", "_name" => "spam" } } }
      term2 = { "term" => { "text" => { "value" => "ham", "_name" => "ham" } } }
      bool_query = { "bool" => { "must" => [term1, term2] } }

      queries = described_class.extract_nested_queries(
        { "nested" => { "path" => "my", "query" => bool_query } },
      )

      expect(queries).to eq(
        [
          { "nested" => { "path" => "my", "query" => term1, "_name" => "spam" } },
          { "nested" => { "path" => "my", "query" => term2, "_name" => "ham" } },
        ],
      )
    end

    it "extracts nested bool children when the nested query appears inside a bool" do
      term1 = { "term" => { "text" => { "value" => "spam", "_name" => "spam" } } }
      term2 = { "term" => { "text" => { "value" => "ham", "_name" => "ham" } } }
      term3 = { "term" => { "text" => { "value" => "foo", "_name" => "foo" } } }
      bool_query = { "bool" => { "must" => [term1, term2] } }

      queries = described_class.extract_nested_queries(
        {
          "bool" => {
            "should" => [
              term3,
              { "nested" => { "path" => "my", "query" => bool_query } },
            ],
          },
        },
      )

      expect(queries).to eq(
        [
          { "nested" => { "path" => "my", "query" => term1, "_name" => "spam" } },
          { "nested" => { "path" => "my", "query" => term2, "_name" => "ham" } },
        ],
      )
    end

    it "extracts nested bools inside nested bools" do
      term1 = { "term" => { "text" => { "value" => "bar", "_name" => "bar" } } }
      term2 = { "term" => { "text" => { "value" => "baz", "_name" => "baz" } } }
      term3 = { "term" => { "text" => { "value" => "spam", "_name" => "spam" } } }
      bool_query1 = { "bool" => { "should" => [term1, term2] } }
      bool_query2 = { "bool" => { "must" => [term3, bool_query1] } }

      queries = described_class.extract_nested_queries(
        { "nested" => { "path" => "my", "query" => bool_query2 } },
      )

      expect(queries).to eq(
        [
          { "nested" => { "path" => "my", "query" => term3, "_name" => "spam" } },
          { "nested" => { "path" => "my", "query" => bool_query1 } },
          { "nested" => { "path" => "my", "query" => term1, "_name" => "bar" } },
          { "nested" => { "path" => "my", "query" => term2, "_name" => "baz" } },
        ],
      )
    end

    it "extracts nested queries inside nested queries" do
      term1 = { "term" => { "text" => { "value" => "bar", "_name" => "bar" } } }
      term2 = { "term" => { "text" => { "value" => "baz", "_name" => "baz" } } }
      term3 = { "term" => { "text" => { "value" => "spam", "_name" => "spam" } } }
      bool_query1 = { "bool" => { "should" => [term1, term2] } }
      inner_nested = { "nested" => { "path" => "my.your", "query" => bool_query1 } }
      bool_query2 = { "bool" => { "must" => [term3, inner_nested] } }

      queries = described_class.extract_nested_queries(
        { "nested" => { "path" => "my", "query" => bool_query2 } },
      )

      expect(queries).to eq(
        [
          { "nested" => { "path" => "my", "query" => term3, "_name" => "spam" } },
          { "nested" => { "path" => "my", "query" => inner_nested } },
          {
            "nested" => {
              "path" => "my",
              "_name" => "bar",
              "query" => { "nested" => { "path" => "my.your", "query" => term1 } },
            },
          },
          {
            "nested" => {
              "path" => "my",
              "_name" => "baz",
              "query" => { "nested" => { "path" => "my.your", "query" => term2 } },
            },
          },
        ],
      )
    end

    it "extracts nested queries inside nested bools with nested bool children" do
      term1 = { "term" => { "text" => { "value" => "bar", "_name" => "bar" } } }
      term2 = { "term" => { "text" => { "value" => "foo", "_name" => "foo" } } }
      term3 = { "term" => { "text" => { "value" => "spam", "_name" => "spam" } } }
      bool_query1 = { "bool" => { "must_not" => [term1] } }
      bool_query2 = { "bool" => { "should" => [term2, bool_query1] } }
      inner_nested = { "nested" => { "path" => "my.your", "query" => bool_query2 } }
      bool_query3 = { "bool" => { "must_not" => [inner_nested] } }
      bool_query4 = { "bool" => { "must" => [term3, bool_query3] } }

      queries = described_class.extract_nested_queries(
        { "nested" => { "path" => "my", "query" => bool_query4 } },
      )

      expect(queries).to eq(
        [
          { "nested" => { "path" => "my", "query" => term3, "_name" => "spam" } },
          { "nested" => { "path" => "my", "query" => bool_query3 } },
          { "nested" => { "path" => "my", "query" => inner_nested } },
          {
            "nested" => {
              "path" => "my",
              "_name" => "foo",
              "query" => { "nested" => { "path" => "my.your", "query" => term2 } },
            },
          },
          {
            "nested" => {
              "path" => "my",
              "query" => { "nested" => { "path" => "my.your", "query" => bool_query1 } },
            },
          },
          {
            "nested" => {
              "path" => "my",
              "_name" => "bar",
              "query" => { "nested" => { "path" => "my.your", "query" => term1 } },
            },
          },
        ],
      )
    end

    it "extracts multiple parallel nested queries" do
      term1 = { "term" => { "text" => { "value" => "bar", "_name" => "bar" } } }
      term2 = { "term" => { "text" => { "value" => "foo", "_name" => "foo" } } }
      term3 = { "term" => { "text" => { "value" => "spam", "_name" => "spam" } } }
      bool_query1 = { "bool" => { "should" => [term1] } }
      bool_query2 = { "bool" => { "must_not" => [term2] } }
      nested1 = { "nested" => { "path" => "my.your", "query" => bool_query1 } }
      nested2 = { "nested" => { "path" => "my.his", "query" => bool_query2 } }
      bool_query3 = { "bool" => { "should" => [nested2, nested1] } }
      bool_query4 = { "bool" => { "must" => [term3, bool_query3] } }

      queries = described_class.extract_nested_queries(
        { "nested" => { "path" => "my", "query" => bool_query4 } },
      )

      expect(queries).to eq(
        [
          { "nested" => { "path" => "my", "query" => term3, "_name" => "spam" } },
          { "nested" => { "path" => "my", "query" => bool_query3 } },
          { "nested" => { "path" => "my", "query" => nested2 } },
          { "nested" => { "path" => "my", "query" => nested1 } },
          {
            "nested" => {
              "path" => "my",
              "_name" => "foo",
              "query" => { "nested" => { "path" => "my.his", "query" => term2 } },
            },
          },
          {
            "nested" => {
              "path" => "my",
              "_name" => "bar",
              "query" => { "nested" => { "path" => "my.your", "query" => term1 } },
            },
          },
        ],
      )
    end
  end

  describe ".get_first_name" do
    it "returns the first _name it finds outside bool queries" do
      term = { "term" => { "text" => { "value" => "bar", "_name" => "bar" } } }
      query = [
        { "query" => term, "_name" => "spam" },
        { "query" => term, "_name" => "beurre" },
      ]

      expect(described_class.get_first_name(query)).to eq("spam")
    end
  end
end
