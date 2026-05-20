require "./search"

module Regex::Automata::DFA
  # Re-open the DFA module to add Regex class
  # This file should be required after dfa.cr
  # A regular expression that uses deterministic finite automata for fast
  # searching.
  #
  # A regular expression is comprised of two DFAs, a "forward" DFA and a
  # "reverse" DFA. The forward DFA is responsible for detecting the end of
  # a match while the reverse DFA is responsible for detecting the start
  # of a match. Thus, in order to find the bounds of any given match, a
  # forward search must first be run followed by a reverse search. A match
  # found by the forward DFA guarantees that the reverse DFA will also find
  # a match.
  #
  # This type provides convenience routines you might have come to expect,
  # such as finding the start/end of a match and iterating over all
  # non-overlapping matches. This `Regex` type is limited in its capabilities
  # to what a DFA can provide. Therefore, APIs involving capturing groups,
  # for example, are not provided.
  class Regex
    @forward : DFA
    @reverse : DFA

    # Create a new regex from the given pattern using the default configuration.
    #
    # If there was a problem parsing or compiling the pattern, then a
    # `BuildError` is raised.
    #
    # # Example
    #
    # ```
    # re = Regex::Automata::DFA::Regex.new("foo[0-9]+bar")
    # assert re.is_match("foo12345bar")
    # assert !re.is_match("foobar")
    # ```
    def self.new(pattern : String) : Regex
      RegexBuilder.new.build(pattern)
    end

    # Like `new`, but parses multiple patterns into a single "regex set."
    # This similarly uses the default regex configuration.
    #
    # When matches are returned, the pattern ID corresponds to the index of
    # the pattern in the slice given.
    #
    # # Example
    #
    # ```
    # re = Regex::Automata::DFA::Regex.new_many(&["[a-z]+", "[0-9]+"])
    # assert re.is_match("abc")  # pattern 0
    # assert re.is_match("123")  # pattern 1
    # assert !re.is_match("@#$") # neither pattern
    # ```
    def self.new_many(patterns : Enumerable(String)) : Regex
      RegexBuilder.new.build_many(patterns)
    end

    # Return a builder for configuring the construction of a `Regex`.
    #
    # This is a convenience routine to avoid needing to import the
    # `Builder` type in common cases.
    #
    # # Example
    #
    # ```
    # re = Regex::Automata::DFA::Regex.builder.build("foo[0-9]+bar")
    # assert re.is_match("foo12345bar")
    # ```
    def self.builder : RegexBuilder
      RegexBuilder.new
    end

    # Create a new regex from forward and reverse DFAs.
    #
    # This is useful when deserializing a regex from some arbitrary
    # memory region. This is also useful for building regexes from other
    # types of DFAs.
    #
    # If you're building the DFAs from scratch instead of building new DFAs
    # from other DFAs, then you'll need to make sure that the reverse DFA is
    # configured correctly to match the intended semantics. Namely:
    #
    # * It should be anchored.
    # * It should use `MatchKind::All` semantics.
    # * It should match in reverse.
    # * Otherwise, its configuration should match the forward DFA.
    #
    # If these conditions aren't satisfied, then the behavior of searches is
    # unspecified.
    def initialize(@forward : DFA, @reverse : DFA)
    end

    # Returns true if and only if this regex matches the given haystack.
    #
    # This routine may short circuit if it knows that scanning future input
    # will never lead to a different result. In particular, if the underlying
    # DFA enters a match state or a dead state, then this routine will return
    # `true` or `false`, respectively, without inspecting any future input.
    #
    # # Panics
    #
    # This routine panics if the search could not complete. This can occur
    # in a number of circumstances:
    #
    # * The configuration of the DFA may permit it to "quit" the search.
    # For example, setting quit bytes or enabling heuristic support for
    # Unicode word boundaries. The default configuration does not enable any
    # option that could result in the DFA quitting.
    # * When the provided `Input` configuration is not supported. For
    # example, by providing an unsupported anchor mode.
    #
    # When a search panics, callers cannot know whether a match exists or
    # not.
    #
    # Use `#try_search` if you want to handle these error conditions.
    #
    # # Example
    #
    # ```
    # re = Regex::Automata::DFA::Regex.new("foo[0-9]+bar")
    # assert re.is_match("foo12345bar")
    # assert !re.is_match("foobar")
    # ```
    def is_match(haystack : String | Bytes) : Bool
      input = Input.new(haystack).earliest(true)
      # Not only can we do an "earliest" search, but we can avoid doing a
      # reverse scan too.
      result = @forward.try_search_fwd(input.haystack[input.start...input.end])
      if result.is_a?(MatchError)
        raise "search error: #{result}"
      end
      !result.nil?
    end

    # Returns the start and end offset of the leftmost match. If no match
    # exists, then `nil` is returned.
    #
    # # Panics
    #
    # This routine panics if the search could not complete. This can occur
    # in a number of circumstances:
    #
    # * The configuration of the DFA may permit it to "quit" the search.
    # For example, setting quit bytes or enabling heuristic support for
    # Unicode word boundaries. The default configuration does not enable any
    # option that could result in the DFA quitting.
    # * When the provided `Input` configuration is not supported. For
    # example, by providing an unsupported anchor mode.
    #
    # When a search panics, callers cannot know whether a match exists or
    # not.
    #
    # Use `#try_search` if you want to handle these error conditions.
    #
    # # Example
    #
    # ```
    # # Greediness is applied appropriately.
    # re = Regex::Automata::DFA::Regex.new("foo[0-9]+")
    # match = re.find("zzzfoo12345zzz")
    # assert match
    # assert match.pattern == PatternID.new(0)
    # assert match.start == 3
    # assert match.end == 11 # "foo12345" is 8 chars starting at position 3
    #
    # # Even though a match is found after reading the first byte (`a`),
    # # the default leftmost-first match semantics demand that we find the
    # # earliest match that prefers earlier parts of the pattern over latter
    # # parts.
    # re = Regex::Automata::DFA::Regex.new("abc|a")
    # match = re.find("abc")
    # assert match
    # assert match.start == 0
    # assert match.end == 3 # "abc"
    # ```
    def find(haystack : String | Bytes) : Match?
      result = try_search(Input.new(haystack))
      if result.is_a?(MatchError)
        raise "search error: #{result}"
      end
      result.as?(Match)
    end

    # Returns an iterator over all non-overlapping leftmost matches in the
    # given bytes. If no match exists, then the iterator yields no elements.
    #
    # This corresponds to the "standard" regex search iterator.
    #
    # # Panics
    #
    # If the search returns an error during iteration, then iteration
    # panics. See `#find` for the panic conditions.
    #
    # Use `#try_search` with a custom iterator if you want to handle these
    # error conditions.
    #
    # # Example
    #
    # ```
    # re = Regex::Automata::DFA::Regex.new("foo[0-9]+")
    # text = "foo1 foo12 foo123"
    # matches = re.find_iter(text).to_a
    # assert matches.size == 3
    # assert matches[0].start == 0
    # assert matches[0].end == 4 # "foo1"
    # assert matches[1].start == 5
    # assert matches[1].end == 10 # "foo12"
    # assert matches[2].start == 11
    # assert matches[2].end == 17 # "foo123"
    # ```
    def find_iter(haystack : String | Bytes) : FindMatches
      it = Searcher.new(Input.new(haystack))
      FindMatches.new(self, it)
    end

    # Returns the start and end offset of the leftmost match. If no match
    # exists, then `nil` is returned.
    #
    # This is like `#find` but with two differences:
    #
    # 1. It is not generic over `Into<Input>` and instead accepts a
    # `&Input`. This permits reusing the same `Input` for multiple searches
    # without needing to create a new one. This _may_ help with latency.
    # 2. It returns an error if the search could not complete where as
    # `#find` will panic.
    #
    # # Errors
    #
    # This routine errors if the search could not complete. This can occur
    # in the following circumstances:
    #
    # * The configuration of the DFA may permit it to "quit" the search.
    # For example, setting quit bytes or enabling heuristic support for
    # Unicode word boundaries. The default configuration does not enable any
    # option that could result in the DFA quitting.
    # * When the provided `Input` configuration is not supported. For
    # example, by providing an unsupported anchor mode.
    #
    # When a search returns an error, callers cannot know whether a match
    # exists or not.
    def try_search(input : Input) : Match? | MatchError
      fwd = @forward
      rev = @reverse

      # Forward search
      end_match = fwd.try_search_fwd(input.haystack[input.start...input.end])
      return end_match if end_match.is_a?(MatchError)

      end_half = end_match.as?(Tuple(Int32, Array(PatternID)))
      return nil unless end_half

      end_pos, pattern_ids = end_half
      # Adjust end_pos to be absolute position in haystack
      end_pos += input.start
      pattern = pattern_ids.first? || PatternID.new(0)

      # This special cases an empty match at the beginning of the search. If
      # our end matches our start, then since a reverse DFA can't match past
      # the start, it must follow that our starting position is also our end
      # position. So short circuit and skip the reverse search.
      if input.start == end_pos
        return Match.new(pattern, end_pos, end_pos)
      end

      # We can also skip the reverse search if we know our search was
      # anchored. This occurs either when the input config is anchored or
      # when we know the regex itself is anchored. In this case, we know the
      # start of the match, if one is found, must be the start of the
      # search.
      if is_anchored(input)
        return Match.new(pattern, input.start, end_pos)
      end

      # N.B. I have tentatively convinced myself that it isn't necessary
      # to specify the specific pattern for the reverse search since the
      # reverse search will always find the same pattern to match as the
      # forward search. But I lack a rigorous proof. Why not just provide
      # the pattern anyway? Well, if it is needed, then leaving it out
      # gives us a chance to find a witness. (Also, if we don't need to
      # specify the pattern, then we don't need to build the reverse DFA
      # with 'starts_for_each_pattern' enabled.)
      #
      # We also need to be careful to disable 'earliest' for the reverse
      # search, since it could be enabled for the forward search. In the
      # reverse case, to satisfy "leftmost" criteria, we need to match
      # as much as we can. We also need to be careful to make the search
      # anchored. We don't want the reverse search to report any matches
      # other than the one beginning at the end of our forward search.
      revsearch = Input.new(input.haystack)
        .span(input.start...end_pos)
        .anchored(Anchored::Yes)
        .earliest(false)

      start_match = rev.try_search_rev(revsearch.haystack[revsearch.start...revsearch.end])
      return start_match if start_match.is_a?(MatchError)

      start_half = start_match.as?(Tuple(Int32, Array(PatternID)))
      # Reverse search must match if forward search does
      return nil unless start_half

      start_pos, start_pattern_ids = start_half
      # Adjust start_pos to be absolute position in haystack
      start_pos += revsearch.start
      start_pattern = start_pattern_ids.first? || PatternID.new(0)

      # Forward and reverse search must match same pattern
      if start_pattern != pattern
        # This should never happen with a properly constructed regex
        raise "forward and reverse search must match same pattern"
      end

      raise "start > end in match" if start_pos > end_pos

      Match.new(pattern, start_pos, end_pos)
    end

    # Returns true if either the given input specifies an anchored search
    # or if the underlying DFA is always anchored.
    private def is_anchored(input : Input) : Bool
      case input.anchored
      when Anchored::No
        # TODO: Implement is_always_start_anchored for DFA
        false
      when Anchored::Yes, Anchored::Pattern
        true
      else
        false
      end
    end

    # Return the underlying DFA responsible for forward matching.
    #
    # This is useful for accessing the underlying DFA and converting it to
    # some other format or size. See the `Builder#build_from_dfas` docs
    # for an example of where this might be useful.
    def forward : DFA
      @forward
    end

    # Return the underlying DFA responsible for reverse matching.
    #
    # This is useful for accessing the underlying DFA and converting it to
    # some other format or size. See the `Builder#build_from_dfas` docs
    # for an example of where this might be useful.
    def reverse : DFA
      @reverse
    end

    # Returns the total number of patterns matched by this regex.
    #
    # # Example
    #
    # ```
    # re = Regex::Automata::DFA::Regex.new_many(&["[a-z]+", "[0-9]+", "\\w+"])
    # assert re.pattern_len == 3
    # ```
    def pattern_len : Int32
      fwd_len = @forward.pattern_len
      rev_len = @reverse.pattern_len
      raise "forward and reverse DFA pattern length mismatch" unless fwd_len == rev_len
      fwd_len
    end

    # TODO: Implement FindMatches iterator
    class FindMatches
      @re : Regex
      @it : Searcher

      def initialize(@re : Regex, @it : Searcher)
      end

      def each(&block : Match ->)
        while @it.has_next?
          input = @it.next_input
          result = @re.try_search(input)
          if result.is_a?(MatchError)
            raise "search error: #{result}"
          end

          match = result.as?(Match)
          if match
            yield match
            @it = @it.advance(match)
          else
            break
          end
        end
      end

      include Iterator(Match)

      def next
        while @it.has_next?
          input = @it.next_input
          result = @re.try_search(input)
          if result.is_a?(MatchError)
            raise "search error: #{result}"
          end

          match = result.as?(Match)
          if match
            @it = @it.advance(match)
            return match
          else
            break
          end
        end
        stop
      end
    end

    # TODO: Implement Searcher for iteration
    class Searcher
      def initialize(input : Input)
        @input = input
      end

      def has_next? : Bool
        @input.start < @input.end
      end

      def next_input : Input
        @input
      end

      def advance(match : Match) : Searcher
        # Advance to just after the match
        new_start = match.end
        # But if the match is empty, we need to advance by at least 1 byte
        # to avoid infinite loops
        if match.empty?
          new_start += 1
        end
        Searcher.new(@input.span(new_start...@input.end))
      end
    end
  end

  # A builder for a regex that uses deterministic finite automata.
  #
  # This builder permits configuring a regex before constructing it. This
  # includes setting a variety of options that affect how a regex is built
  # and how it performs searches.
  class RegexBuilder
    @dfa_builder : Builder

    # Create a new regex builder with the default configuration.
    def initialize
      @dfa_builder = Builder.new
    end

    # Create a new regex builder with the given DFA builder.
    def initialize(@dfa_builder : Builder)
    end

    # Build a regex from the given pattern.
    #
    # If there was a problem parsing or compiling the pattern, then a
    # `BuildError` is raised.
    def build(pattern : String) : Regex
      build_many([pattern])
    end

    # Build a regex from the given patterns.
    #
    # When matches are returned, the pattern ID corresponds to the index of
    # the pattern in the slice given.
    def build_many(patterns : Enumerable(String)) : Regex
      # Build forward DFA
      forward = @dfa_builder.build_many(patterns)

      # Build reverse DFA with appropriate configuration
      # Note: We don't set prefilter since Config doesn't have that method yet
      reverse_builder = @dfa_builder.configure do |config|
        config
          .specialize_start_states(false)
          .start_kind(StartKind::Anchored)
          .match_kind(MatchKind::All)
      end

      # Configure Thompson NFA compiler for reverse matching
      reverse = reverse_builder.thompson do |config|
        config.reverse(true)
      end.build_many(patterns)

      Regex.new(forward, reverse)
    end

    # Build a regex from its component forward and reverse DFAs.
    #
    # This is useful when deserializing a regex from some arbitrary
    # memory region. This is also useful for building regexes from other
    # types of DFAs.
    #
    # If you're building the DFAs from scratch instead of building new DFAs
    # from other DFAs, then you'll need to make sure that the reverse DFA is
    # configured correctly to match the intended semantics. Namely:
    #
    # * It should be anchored.
    # * It should use `MatchKind::All` semantics.
    # * It should match in reverse.
    # * Otherwise, its configuration should match the forward DFA.
    #
    # If these conditions aren't satisfied, then the behavior of searches is
    # unspecified.
    def build_from_dfas(forward : DFA, reverse : DFA) : Regex
      Regex.new(forward, reverse)
    end

    # Configure the underlying DFA builder.
    #
    # This permits setting DFA-specific options such as quit bytes,
    # Unicode word boundary support and more.
    def configure(&block : Config -> Config) : RegexBuilder
      RegexBuilder.new(@dfa_builder.configure(&block))
    end

    # Configure the Thompson NFA compiler.
    #
    # This permits setting NFA-specific options such as whether to build
    # the NFA in reverse, whether to shrink the NFA and more.
    def thompson(&block : HirCompilerConfig -> HirCompilerConfig) : RegexBuilder
      RegexBuilder.new(@dfa_builder.thompson(&block))
    end
  end
end
