# frozen_string_literal: true
RSpec.describe Luqum::Elasticsearch::Tree do
  describe Luqum::Elasticsearch::Tree::EShould do
    it "keeps operation options in the bool query" do
      op = described_class.new(
        [
          Luqum::Elasticsearch::Tree::EWord.new("a"),
          Luqum::Elasticsearch::Tree::EWord.new("b"),
          Luqum::Elasticsearch::Tree::EWord.new("c"),
        ],
        minimum_should_match: 2,
      )

      expect(op.json).to eq(
        {
          "bool" => {
            "should" => [
              { "term" => { "" => { "value" => "a" } } },
              { "term" => { "" => { "value" => "b" } } },
              { "term" => { "" => { "value" => "c" } } },
            ],
            "minimum_should_match" => 2,
          },
        },
      )
    end
  end
end
