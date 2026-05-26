require "./pikevm"

module Regex::Automata::NFA
  module Backtrack
    BLOCK_SIZE               = 8_i64 * 8_i64
    DEFAULT_VISITED_CAPACITY = 256_i64 * (1_i64 << 10)

    def self.min_visited_capacity(nfa : Regex::Automata::NFA::NFA, input : Regex::Automata::Input) : Int64
      div_ceil(nfa.states.size.to_i64 * (input.get_span.length.to_i64 + 1_i64), 8_i64)
    end

    def self.div_ceil(lhs : Int64, rhs : Int64) : Int64
      return lhs // rhs if lhs % rhs == 0

      (lhs // rhs) + 1_i64
    end

    class Config
      @prefilter : Regex::Automata::Prefilter?
      @prefilter_set : Bool
      @visited_capacity : Int64?

      def initialize
        @prefilter_set = false
      end

      def self.new : Config
        previous_def
      end

      def prefilter(prefilter : Regex::Automata::Prefilter?) : Config
        @prefilter = prefilter
        @prefilter_set = true
        self
      end

      def visited_capacity(capacity : Int64) : Config
        @visited_capacity = capacity
        self
      end

      def get_prefilter : Regex::Automata::Prefilter?
        @prefilter
      end

      def get_visited_capacity : Int64
        @visited_capacity || DEFAULT_VISITED_CAPACITY
      end

      def overwrite(other : Config) : Config
        merged = Config.new
        if other.@prefilter_set
          merged.prefilter(other.@prefilter)
        elsif @prefilter_set
          merged.prefilter(@prefilter)
        end
        merged.visited_capacity(other.@visited_capacity || get_visited_capacity)
        merged
      end
    end

    class Builder
      @config : Config
      @thompson_config : Regex::Automata::HirCompilerConfig
      @syntax_config : Regex::Automata::Syntax::Config

      def initialize
        @config = Config.new
        @thompson_config = Regex::Automata::NFA::NFA.config
        @syntax_config = Regex::Automata::Syntax::Config.new
      end

      def self.new : Builder
        previous_def
      end

      def build(pattern : String) : BoundedBacktracker
        build_many([pattern])
      end

      def build_many(patterns : Enumerable(String)) : BoundedBacktracker
        nfa = Regex::Automata::NFA::NFA.compiler
          .configure(@thompson_config)
          .syntax(@syntax_config)
          .build_many(patterns.to_a)
        build_from_nfa(nfa)
      end

      def build_from_nfa(nfa : Regex::Automata::NFA::NFA) : BoundedBacktracker
        nfa.look_set_any.available
        pikevm = Regex::Automata::NFA::PikeVM.builder
          .configure(
            Regex::Automata::NFA::PikeVM.config
              .match_kind(Regex::Automata::MatchKind::LeftmostFirst)
              .prefilter(@config.get_prefilter)
          )
          .build_from_nfa(nfa)
        BoundedBacktracker.new(@config, nfa, pikevm)
      rescue ex : Regex::Automata::UnicodeWordBoundaryError
        raise Regex::Automata::BuildError.new(ex.message)
      end

      def configure(config : Config) : Builder
        @config = @config.overwrite(config)
        self
      end

      def syntax(config : Regex::Automata::Syntax::Config) : Builder
        @syntax_config = config
        self
      end

      def thompson(config : Regex::Automata::HirCompilerConfig) : Builder
        @thompson_config = config
        self
      end
    end

    class Cache
      getter inner : Regex::Automata::NFA::PikeVM::Cache

      @visited_bytes : Int64

      def initialize(re : BoundedBacktracker)
        @inner = re.pikevm.create_cache
        @visited_bytes = visited_bytes_for(re)
      end

      def self.new(re : BoundedBacktracker) : Cache
        previous_def(re)
      end

      def reset(re : BoundedBacktracker) : Nil
        re.pikevm.reset_cache(@inner)
        @visited_bytes = visited_bytes_for(re)
      end

      def memory_usage : Int32
        (@inner.memory_usage.to_i64 + @visited_bytes).clamp(0_i64, Int32::MAX.to_i64).to_i32
      end

      private def visited_bytes_for(re : BoundedBacktracker) : Int64
        capacity = re.get_config.get_visited_capacity
        blocks = Backtrack.div_ceil(capacity * 8_i64, BLOCK_SIZE)
        blocks * (BLOCK_SIZE // 8_i64)
      end
    end

    class TryFindMatches
      def initialize(@re : BoundedBacktracker, @cache : Cache, input : Regex::Automata::Input)
        @caps = Regex::Automata::Captures.matches(@re.get_nfa.group_info)
        @it = Regex::Automata::Searcher.new(input)
      end

      def next : Regex::Automata::Match? | Regex::Automata::MatchError
        @it.try_advance do |input|
          result = @re.try_search(@cache, input, @caps)
          if result.is_a?(Regex::Automata::MatchError)
            result
          else
            @caps.get_match
          end
        end
      end
    end

    class TryCapturesMatches
      def initialize(@re : BoundedBacktracker, @cache : Cache, input : Regex::Automata::Input)
        @caps = @re.create_captures
        @it = Regex::Automata::Searcher.new(input)
      end

      def next : Regex::Automata::Captures? | Regex::Automata::MatchError
        result = @it.try_advance do |input|
          finder_result = @re.try_search(@cache, input, @caps)
          if finder_result.is_a?(Regex::Automata::MatchError)
            finder_result
          else
            @caps.get_match
          end
        end
        return result if result.is_a?(Regex::Automata::MatchError)
        return nil unless result

        @caps.clone
      end
    end

    class BoundedBacktracker
      getter pikevm : Regex::Automata::NFA::PikeVM

      def initialize(@config : Config, @nfa : Regex::Automata::NFA::NFA, @pikevm : Regex::Automata::NFA::PikeVM)
      end

      def self.new(pattern : String) : BoundedBacktracker
        builder.build(pattern)
      end

      def self.new_many(patterns : Enumerable(String)) : BoundedBacktracker
        builder.build_many(patterns)
      end

      def self.new_from_nfa(nfa : Regex::Automata::NFA::NFA) : BoundedBacktracker
        builder.build_from_nfa(nfa)
      end

      def self.always_match : BoundedBacktracker
        new_from_nfa(Regex::Automata::NFA::NFA.always_match)
      end

      def self.never_match : BoundedBacktracker
        new_from_nfa(Regex::Automata::NFA::NFA.never_match)
      end

      def self.config : Config
        Config.new
      end

      def self.builder : Builder
        Builder.new
      end

      def create_cache : Cache
        Cache.new(self)
      end

      def create_captures : Regex::Automata::Captures
        Regex::Automata::Captures.all(@nfa.group_info)
      end

      def reset_cache(cache : Cache) : Nil
        cache.reset(self)
      end

      def pattern_len : Int32
        @nfa.pattern_len
      end

      def get_config : Config
        @config
      end

      def get_nfa : Regex::Automata::NFA::NFA
        @nfa
      end

      def get_prefilter : Regex::Automata::Prefilter?
        @config.get_prefilter
      end

      def memory_usage : Int32
        @nfa.memory_usage
      end

      def max_haystack_len : Int32
        states_len = @nfa.states.size.to_i64
        return 0 if states_len <= 0

        capacity = 8_i64 * @config.get_visited_capacity
        blocks = Backtrack.div_ceil(capacity, BLOCK_SIZE)
        real_capacity = blocks * BLOCK_SIZE
        max_len = (real_capacity // states_len) - 1_i64
        return 0 if max_len < 0

        max_len.clamp(0_i64, Int32::MAX.to_i64).to_i32
      end

      def try_is_match(cache : Cache, haystack : String | Bytes | Regex::Automata::Input) : Bool | Regex::Automata::MatchError
        input = normalize_input(haystack)
        input.earliest(true)
        result = try_search_slots(cache, input, [] of Regex::Automata::NonMaxUsize?)
        return result if result.is_a?(Regex::Automata::MatchError)

        !result.nil?
      end

      def try_find(cache : Cache, haystack : String | Bytes | Regex::Automata::Input) : Regex::Automata::Match? | Regex::Automata::MatchError
        input = normalize_input(haystack)

        if @nfa.pattern_len == 1
          slots = Array(Regex::Automata::NonMaxUsize?).new(2, nil)
          result = try_search_slots(cache, input, slots)
          return result if result.is_a?(Regex::Automata::MatchError)
          pid = result.as?(Regex::Automata::PatternID)
          return nil unless pid
          start = slots[0]?.try(&.try(&.get))
          finish = slots[1]?.try(&.try(&.get))
          return nil unless start && finish

          return Regex::Automata::Match.new(pid, start, finish)
        end

        slots = Array(Regex::Automata::NonMaxUsize?).new(@nfa.group_info.implicit_slot_len, nil)
        result = try_search_slots(cache, input, slots)
        return result if result.is_a?(Regex::Automata::MatchError)
        pid = result.as?(Regex::Automata::PatternID)
        return nil unless pid
        slot_start = pid.to_i * 2
        start = slots[slot_start]?.try(&.try(&.get))
        finish = slots[slot_start + 1]?.try(&.try(&.get))
        return nil unless start && finish

        Regex::Automata::Match.new(pid, start, finish)
      end

      def try_captures(cache : Cache, haystack : String | Bytes | Regex::Automata::Input, caps : Regex::Automata::Captures) : Nil | Regex::Automata::MatchError
        input = normalize_input(haystack)
        try_search(cache, input, caps)
      end

      def try_find_iter(cache : Cache, haystack : String | Bytes | Regex::Automata::Input) : TryFindMatches
        TryFindMatches.new(self, cache, normalize_input(haystack))
      end

      def try_captures_iter(cache : Cache, haystack : String | Bytes | Regex::Automata::Input) : TryCapturesMatches
        TryCapturesMatches.new(self, cache, normalize_input(haystack))
      end

      def try_search(cache : Cache, input : Regex::Automata::Input, caps : Regex::Automata::Captures) : Nil | Regex::Automata::MatchError
        error = haystack_length_error(input)
        return error if error

        @pikevm.search(cache.inner, input, caps)
        nil
      end

      def try_search_slots(cache : Cache, input : Regex::Automata::Input, slots : Array(Regex::Automata::NonMaxUsize?)) : Regex::Automata::PatternID? | Regex::Automata::MatchError
        error = haystack_length_error(input)
        return error if error

        @pikevm.search_slots(cache.inner, input, slots)
      end

      private def haystack_length_error(input : Regex::Automata::Input) : Regex::Automata::MatchError?
        haylen = input.get_span.length.to_i64
        states_len = @nfa.states.size.to_i64
        stride = haylen + 1_i64
        needed_capacity = states_len * stride
        max_capacity = 8_i64 * @config.get_visited_capacity
        return Regex::Automata::MatchError.haystack_too_long(input.get_span.length) if needed_capacity > max_capacity

        nil
      end

      private def normalize_input(input : Regex::Automata::Input) : Regex::Automata::Input
        input.clone
      end

      private def normalize_input(haystack : String) : Regex::Automata::Input
        Regex::Automata::Input.new(haystack)
      end

      private def normalize_input(haystack : Bytes) : Regex::Automata::Input
        Regex::Automata::Input.new(haystack)
      end
    end
  end
end
