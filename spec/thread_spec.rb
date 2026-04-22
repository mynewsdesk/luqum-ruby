# frozen_string_literal: true

require "luqum/thread"
require "luqum/parser"

RSpec.describe Luqum::Thread do
  it "parses the same query concurrently without corrupting results" do
    qs = <<~QS
      (title:"foo bar" AND body:"quick fox") OR title:fox AND
      (title:"foo bar" AND body:"quick fox") OR
      title:fox AND (title:"foo bar" AND body:"quick fox") OR
      title:fox AND (title:"foo bar" AND body:"quick fox") OR
      title:fox AND (title:"foo bar" AND body:"quick fox") OR title:fox
    QS
    expected = Luqum::Parser.parse(qs)

    queue = Queue.new
    threads = 100.times.map do
      Thread.new do
        Luqum::Thread.parse(qs)
        queue << Luqum::Thread.parse(qs)
      end
    end
    threads.each(&:join)
    expect(queue.size).to eq(100)
    100.times { expect(queue.pop).to eq(expected) }
  end
end
