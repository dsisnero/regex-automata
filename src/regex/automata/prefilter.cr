require "./search"
require "regex-syntax"

module Regex::Automata
  # A prefilter for accelerating regex searches by looking for candidate
  # literal prefixes before running the full automaton.
  class Prefilter
    getter kind : MatchKind
    getter max_needle_len : Int32
    getter needles : Array(Bytes)

    @needles : Array(Bytes)
    @is_fast : Bool
    @memory_usage : Int32

    def self.new(kind : MatchKind, needles : Enumerable) : self?
      bytes = needles.map { |needle| bytes_for(needle) }
      return nil if bytes.empty?
      return nil if bytes.any?(&.empty?)

      max_needle_len = bytes.max_of(&.size).to_i32
      memory_usage = bytes.sum(&.size).to_i32
      is_fast = bytes.size == 1 || (bytes.size <= 3 && bytes.all? { |needle| needle.size == 1 })
      prefilter = allocate
      prefilter.initialize(kind, bytes, max_needle_len, memory_usage, is_fast)
      prefilter
    end

    def self.from_hir_prefix(kind : MatchKind, hir : Regex::Syntax::Hir::Hir) : self?
      from_hirs_prefix(kind, [hir])
    end

    def self.from_hirs_prefix(kind : MatchKind, hirs : Enumerable(Regex::Syntax::Hir::Hir)) : self?
      extractor = Regex::Syntax::Hir::LiteralExtraction::Extractor.new
      extractor.kind(Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Prefix)

      prefixes = Regex::Syntax::Hir::LiteralExtraction::Seq.empty
      hirs.each do |hir|
        prefixes.union(extractor.extract(hir))
      end

      case kind
      when MatchKind::All
        prefixes.sort
        prefixes.dedup
      when MatchKind::LeftmostFirst
        prefixes.optimize_for_prefix_by_preference
      end

      literals = prefixes.literals
      return nil unless literals

      new(kind, literals.map(&.bytes))
    end

    def find(haystack : String, span : Span) : Span?
      find(haystack.to_slice, span)
    end

    def find(haystack : Bytes, span : Span) : Span?
      return nil unless valid_span?(haystack, span)

      best_span = nil.as(Span?)
      best_index = Int32::MAX
      @needles.each_with_index do |needle, index|
        next unless start = find_needle(haystack, needle, span)

        candidate = Span.new(start, start + needle.size)
        if better_match?(candidate, index.to_i32, best_span, best_index)
          best_span = candidate
          best_index = index.to_i32
        end
      end
      best_span
    end

    def prefix(haystack : String, span : Span) : Span?
      prefix(haystack.to_slice, span)
    end

    def prefix(haystack : Bytes, span : Span) : Span?
      return nil unless valid_span?(haystack, span)

      @needles.each do |needle|
        next if needle.size > span.length
        next unless starts_with?(haystack, span.start, needle)

        return Span.new(span.start, span.start + needle.size)
      end
      nil
    end

    def memory_usage : Int32
      @memory_usage
    end

    def is_fast : Bool
      @is_fast
    end

    private def initialize(@kind : MatchKind, @needles : Array(Bytes), @max_needle_len : Int32, @memory_usage : Int32, @is_fast : Bool)
    end

    private def self.bytes_for(needle) : Bytes
      needle.to_slice.dup
    end

    private def self.bytes_for(needle : Array(UInt8)) : Bytes
      Bytes.new(needle.size) { |i| needle[i] }
    end

    private def valid_span?(haystack : Bytes, span : Span) : Bool
      span.start >= 0 && span.end >= span.start && span.end <= haystack.size
    end

    private def better_match?(candidate : Span, index : Int32, current : Span?, current_index : Int32) : Bool
      return true unless current
      return true if candidate.start < current.start
      return false if candidate.start > current.start

      index < current_index
    end

    private def find_needle(haystack : Bytes, needle : Bytes, span : Span) : Int32?
      limit = span.end - needle.size
      at = span.start
      while at <= limit
        return at if starts_with?(haystack, at, needle)
        at += 1
      end
      nil
    end

    private def starts_with?(haystack : Bytes, offset : Int32, needle : Bytes) : Bool
      return false if offset < 0 || offset + needle.size > haystack.size

      i = 0
      while i < needle.size
        return false if haystack[offset + i] != needle[i]
        i += 1
      end
      true
    end
  end
end
