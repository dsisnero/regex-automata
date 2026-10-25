require "./search"
require "./teddy_matcher"
require "./aho_dfa"
require "./aho_contiguous_nfa"
require "regex-syntax"

module Regex::Automata
  # A prefilter for accelerating regex searches by looking for candidate
  # literal prefixes before running the full automaton.
  class Prefilter
    getter kind : MatchKind
    getter max_needle_len : Int32
    getter needles : Array(Bytes)
    getter strategy_name : String

    @needles : Array(Bytes)
    @is_fast : Bool
    @memory_usage : Int32
    @aho : AhoDfa | AhoContiguousNfa | Nil
    @teddy : TeddyMatcher?
    @byte_set : Bytes?

    def self.new(kind : MatchKind, needles : Enumerable) : self?
      bytes = needles.map { |needle| bytes_for(needle) }
      return nil if bytes.empty?
      return nil if bytes.any?(&.empty?)

      max_needle_len = bytes.max_of(&.size).to_i32
      memory_usage = bytes.sum(&.size).to_i32
      is_fast = bytes.size == 1 ||
                (bytes.size <= 3 && bytes.all? { |needle| needle.size == 1 }) ||
                (bytes.size <= 64 && bytes.min_of(&.size) >= 3)
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
      if teddy = @teddy
        return teddy.find(haystack, span).try(&.[1])
      end
      if aho = @aho
        return aho.find(haystack, span).try(&.[1])
      end
      if byte_set = @byte_set
        at = span.start
        while at < span.end
          return Span.new(at, at + 1) if byte_set[haystack[at]] != 0
          at += 1
        end
        return nil
      end

      return find_byte_needles(haystack, span) if @needles.size <= 3 && @needles.all? { |needle| needle.size == 1 }

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
      if aho = @aho
        return aho.prefix(haystack, span).try(&.[1])
      end
      if byte_set = @byte_set
        return nil if span.start >= span.end
        return Span.new(span.start, span.start + 1) if byte_set[haystack[span.start]] != 0
        return nil
      end

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

    def find_with_index(haystack : Bytes, span : Span) : Tuple(Int32, Span)?
      return nil unless valid_span?(haystack, span)
      return @teddy.not_nil!.find(haystack, span) if @teddy
      @aho.try(&.find(haystack, span))
    end

    def prefix_with_index(haystack : Bytes, span : Span) : Tuple(Int32, Span)?
      return nil unless valid_span?(haystack, span)
      @aho.try(&.prefix(haystack, span))
    end

    def indexed_matcher? : Bool
      !@aho.nil?
    end

    # Diagnostic for verifying the pinned dependency's backend selection.
    def aho_backend_name : String?
      case @aho
      when AhoDfa           then "dfa"
      when AhoContiguousNfa then "contiguous-nfa"
      else                       nil
      end
    end

    def is_fast : Bool
      @is_fast
    end

    private def initialize(@kind : MatchKind, @needles : Array(Bytes), @max_needle_len : Int32, @memory_usage : Int32, @is_fast : Bool)
      @byte_set = nil
      @teddy = nil
      @strategy_name = if @needles.size == 1
                         if @needles[0].size == 1
                           @memory_usage = 0
                           "memchr"
                         else
                           "memmem"
                         end
                       elsif @needles.size == 2 && @needles.all? { |needle| needle.size == 1 }
                         @memory_usage = 0
                         "memchr2"
                       elsif @needles.size == 3 && @needles.all? { |needle| needle.size == 1 }
                         @memory_usage = 0
                         "memchr3"
                       elsif @needles.size <= 64 && TeddyMatcher.available?
                         @teddy = TeddyMatcher.new(@needles)
                         @is_fast = @needles.min_of(&.size) >= 3
                         "teddy"
                       elsif @needles.size > 64 && @needles.all? { |needle| needle.size == 1 }
                         set = Bytes.new(256, 0_u8)
                         @needles.each { |needle| set[needle[0]] = 1_u8 }
                         @byte_set = set
                         @memory_usage = 0
                         @is_fast = false
                         "byteset"
                       else
                         "aho-corasick"
                       end
      @aho = if @needles.size > 1 && !(@needles.size <= 3 && @needles.all? { |needle| needle.size == 1 })
               if @byte_set
                 nil
               elsif @needles.size <= 500
                 AhoDfa.new(@needles, @max_needle_len)
               else
                 AhoContiguousNfa.new(@needles, @max_needle_len)
               end
             end
      if aho = @aho
        @memory_usage = aho.memory_usage
        @is_fast = false if @needles.size > 64
      end
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

    # This is the Crystal equivalent of Rust's memchr/memchr2/memchr3 choice.
    # Searching each of at most three bytes with the runtime's indexed lookup
    # avoids repeatedly comparing all needles at every haystack offset.
    private def find_byte_needles(haystack : Bytes, span : Span) : Span?
      best_span = nil.as(Span?)
      best_index = Int32::MAX
      @needles.each_with_index do |needle, index|
        found = haystack.index(needle[0], span.start)
        next unless found && found < span.end

        candidate = Span.new(found, found + 1)
        if better_match?(candidate, index.to_i32, best_span, best_index)
          best_span = candidate
          best_index = index.to_i32
        end
      end
      best_span
    end

    private def better_match?(candidate : Span, index : Int32, current : Span?, current_index : Int32) : Bool
      return true unless current
      return true if candidate.start < current.start
      return false if candidate.start > current.start

      index < current_index
    end

    private def find_needle(haystack : Bytes, needle : Bytes, span : Span) : Int32?
      if needle.size == 1
        found = haystack.index(needle[0], span.start)
        return found if found && found < span.end
        return nil
      end

      limit = span.end - needle.size
      at = span.start
      while at <= limit
        found = haystack.index(needle[0], at)
        return nil unless found && found <= limit
        return found if starts_with?(haystack, found, needle)

        at = found + 1
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
