# frozen_string_literal: true

RSpec.describe Luqum::Elasticsearch::Tree::ElasticSearchItemFactory do
  it "lets explicit field_options override factory defaults" do
    factory = described_class.new(
      [],
      {},
      { "foo" => { "match_type" => "phrase" } },
    )

    word = factory.build(Luqum::Elasticsearch::Visitor::EWord, "bar")
    expect(word.field_options).to eq({ "foo" => { "match_type" => "phrase" } })

    word = factory.build(
      Luqum::Elasticsearch::Visitor::EWord,
      "bar",
      field_options: { "foo" => { "match_type" => "term" } },
    )
    expect(word.field_options).to eq({ "foo" => { "match_type" => "term" } })
  end
end
