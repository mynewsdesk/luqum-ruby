# frozen_string_literal: true
module Luqum
  # Raised when a query has a problem in its structure
  class InconsistentQueryError < StandardError; end

  # Raised when an OR and an AND are on the same level
  # (we don't know how to handle this case)
  class OrAndAndOnSameLevelError < InconsistentQueryError; end

  # Raised when a SearchField is nested in another SearchField
  # (doesn't make sense, e.g. field1:(spam AND field2:eggs))
  class NestedSearchFieldError < InconsistentQueryError; end

  # Raised when a dotted field name is queried which is not an object field
  class ObjectSearchFieldError < InconsistentQueryError; end

  # Exception raised while parsing a lucene statement
  class ParseError < StandardError; end

  # Raised when parser encounters an invalid statement
  class ParseSyntaxError < ParseError; end

  # Raised when parser encounters an invalid character
  class IllegalCharacterError < ParseError; end
end
