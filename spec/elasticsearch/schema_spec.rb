RSpec.describe Luqum::Elasticsearch::SchemaAnalyzer do
  let(:mapping) do
    {
      "properties" => {
        "text" => { "type" => "text" },
        "author" => {
          "type" => "nested",
          "properties" => {
            "firstname" => {
              "type" => "text",
              "fields" => {
                "english" => { "analyzer" => "english" },
                "raw" => { "type" => "keyword" },
              },
            },
            "lastname" => { "type" => "text" },
            "book" => {
              "type" => "nested",
              "properties" => {
                "title" => { "type" => "text" },
                "isbn" => {
                  "type" => "object",
                  "properties" => {
                    "ref" => { "type" => "keyword" },
                  },
                },
                "format" => {
                  "type" => "nested",
                  "properties" => {
                    "ftype" => { "type" => "keyword" },
                  },
                },
              },
            },
          },
        },
        "publish" => {
          "type" => "nested",
          "properties" => {
            "site" => { "type" => "keyword" },
            "idnum" => { "type" => "long" },
          },
        },
        "manager" => {
          "type" => "object",
          "properties" => {
            "firstname" => { "type" => "text" },
            "address" => {
              "type" => "object",
              "properties" => {
                "zipcode" => { "type" => "keyword" },
              },
            },
            "subteams" => {
              "type" => "nested",
              "properties" => {
                "supervisor" => {
                  "type" => "object",
                  "properties" => {
                    "name" => {
                      "type" => "text",
                      "fields" => { "raw" => { "type" => "keyword" } },
                    },
                  },
                },
              },
            },
          },
        },
      },
    }
  end

  let(:index_settings) do
    {
      "settings" => {
        "query" => { "default_field" => "text" },
      },
      "mappings" => mapping,
    }
  end

  it "returns the default field" do
    analyzer = described_class.new(index_settings)
    expect(analyzer.default_field).to eq("text")
  end

  it "lists not analyzed fields" do
    analyzer = described_class.new(index_settings)
    expect(analyzer.not_analyzed_fields.sort).to eq(
      [
        "author.book.format.ftype",
        "author.book.isbn.ref",
        "author.firstname.raw",
        "manager.address.zipcode",
        "manager.subteams.supervisor.name.raw",
        "publish.idnum",
        "publish.site",
      ],
    )
  end

  it "builds nested field specs" do
    analyzer = described_class.new(index_settings)
    expect(analyzer.nested_fields).to eq(
      {
        "author" => {
          "firstname" => {},
          "lastname" => {},
          "book" => {
            "format" => {
              "ftype" => {},
            },
            "title" => {},
            "isbn" => {},
          },
        },
        "publish" => {
          "site" => {},
          "idnum" => {},
        },
        "manager.subteams" => {
          "supervisor" => {},
        },
      },
    )
  end

  it "lists object fields" do
    analyzer = described_class.new(index_settings)
    expect(analyzer.object_fields.sort).to eq(
      [
        "author.book.isbn.ref",
        "manager.address.zipcode",
        "manager.firstname",
        "manager.subteams.supervisor.name",
      ],
    )
  end

  it "lists sub fields" do
    analyzer = described_class.new(index_settings)
    expect(analyzer.sub_fields.sort).to eq(
      [
        "author.firstname.english",
        "author.firstname.raw",
        "manager.subteams.supervisor.name.raw",
      ],
    )
  end

  it "handles an empty schema" do
    analyzer = described_class.new({})
    expect(analyzer.default_field).to eq("*")
    expect(analyzer.not_analyzed_fields).to eq([])
    expect(analyzer.nested_fields).to eq({})
    expect(analyzer.object_fields).to eq([])
  end
end
