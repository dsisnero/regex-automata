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
        BoundedBacktracker.new(@config, nfa)
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
      @stack : Array(Frame)
      @visited : Visited

      def initialize(re : BoundedBacktracker)
        @stack = [] of Frame
        @visited = Visited.new(re)
      end

      def self.new(re : BoundedBacktracker) : Cache
        previous_def(re)
      end

      def reset(re : BoundedBacktracker) : Nil
        @stack.clear
        @visited.reset(re)
      end

      def memory_usage : Int32
        (@stack.size.to_i64 * sizeof(Frame) + @visited.memory_usage).clamp(0_i64, Int32::MAX.to_i64).to_i32
      end

      def setup_search(re : BoundedBacktracker, input : Regex::Automata::Input) : Regex::Automata::MatchError?
        @stack.clear
        @visited.setup_search(re, input)
      end

      def push(frame : Frame) : Nil
        @stack << frame
      end

      def pop : Frame?
        @stack.pop?
      end

      def visited_insert(id : Regex::Automata::StateID, at : Int32) : Bool
        @visited.insert(id, at)
      end
    end

    private record StepFrame, id : Regex::Automata::StateID, at : Int32
    private record RestoreCaptureFrame, slot : Int32, offset : Int32?
    private alias Frame = StepFrame | RestoreCaptureFrame

    private class Visited
      @bitset : Array(UInt64)
      @stride : Int32

      def initialize(re : BoundedBacktracker)
        @bitset = [] of UInt64
        @stride = 0
        reset(re)
      end

      def reset(re : BoundedBacktracker) : Nil
        @bitset.clear
        @stride = 0
      end

      def setup_search(re : BoundedBacktracker, input : Regex::Automata::Input) : Regex::Automata::MatchError?
        haylen = input.get_span.length
        @stride = haylen + 1
        needed_capacity = re.get_nfa.states.size.to_i64 * @stride
        max_capacity = 8_i64 * re.get_config.get_visited_capacity
        return Regex::Automata::MatchError.haystack_too_long(haylen) if needed_capacity > max_capacity

        needed_blocks = Backtrack.div_ceil(needed_capacity, BLOCK_SIZE).to_i
        while @bitset.size < needed_blocks
          @bitset << 0_u64
        end
        while @bitset.size > needed_blocks
          @bitset.pop
        end
        @bitset.fill(0_u64)
        nil
      end

      def insert(id : Regex::Automata::StateID, at : Int32) : Bool
        table_index = id.to_i64 * @stride + at
        block_index = (table_index // BLOCK_SIZE).to_i
        bit = (table_index % BLOCK_SIZE).to_i
        mask = 1_u64 << bit
        return false unless (@bitset[block_index] & mask) == 0

        @bitset[block_index] |= mask
        true
      end

      def memory_usage : Int64
        @bitset.size.to_i64 * sizeof(UInt64)
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
      def initialize(@config : Config, @nfa : Regex::Automata::NFA::NFA)
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
        caps.clear
        result = try_search_slots_int(cache, input, caps.slots_mut)
        return result if result.is_a?(Regex::Automata::MatchError)

        caps.set_pattern(result)
        nil
      end

      def try_search_slots(cache : Cache, input : Regex::Automata::Input, slots : Array(Regex::Automata::NonMaxUsize?)) : Regex::Automata::PatternID? | Regex::Automata::MatchError
        slots.fill(nil)
        plain_slots = Array(Int32?).new(slots.size, nil)
        result = try_search_slots_int(cache, input, plain_slots)
        return result if result.is_a?(Regex::Automata::MatchError)

        index = 0
        while index < slots.size
          slots[index] = plain_slots[index].try { |offset| Regex::Automata::NonMaxUsize.new(offset).not_nil! }
          index += 1
        end
        result
      end

      private def try_search_slots_int(cache : Cache, input : Regex::Automata::Input, slots : Array(Int32?)) : Regex::Automata::PatternID? | Regex::Automata::MatchError
        slots.fill(nil)
        required_slots = @nfa.group_info.implicit_slot_len
        plain_slots = Array(Int32?).new(Math.max(required_slots, slots.size), nil)
        result = try_search_slots_imp(cache, input.clone, plain_slots)
        return result if result.is_a?(Regex::Automata::MatchError)
        return nil unless half_match = result

        index = 0
        limit = Math.min(slots.size, plain_slots.size)
        while index < limit
          slots[index] = plain_slots[index]
          index += 1
        end
        half_match.pattern
      end

      private def try_search_slots_imp(cache : Cache, input : Regex::Automata::Input, slots : Array(Int32?)) : Regex::Automata::HalfMatch? | Regex::Automata::MatchError
        loop do
          result = search_imp(cache, input, slots)
          return result if result.is_a?(Regex::Automata::MatchError) || result.nil?
          return result unless should_skip_empty_utf8_match?(input, result, slots)

          next_start = result.offset + 1
          return nil if next_start > input.end
          input.set_start(next_start)
        end
      end

      private def search_imp(cache : Cache, input : Regex::Automata::Input, slots : Array(Int32?)) : Regex::Automata::HalfMatch? | Regex::Automata::MatchError
        slots.fill(nil)
        if error = cache.setup_search(self, input)
          return error
        end
        return nil if input.is_done

        anchored, start_id = case input.get_anchored
                             when Regex::Automata::Anchored::No
                               {@nfa.is_always_start_anchored, @nfa.start_anchored}
                             when Regex::Automata::Anchored::Yes
                               {true, @nfa.start_anchored}
                             when Regex::Automata::Anchored::Pattern
                               pid = input.pattern
                               return nil unless pid
                               sid = @nfa.start_pattern(pid)
                               return nil unless sid
                               {true, sid}
                             else
                               return nil
                             end
        return backtrack(cache, input, input.start, start_id, slots) if anchored

        at = input.start
        prefilter = @config.get_prefilter
        while at <= input.end
          if prefilter
            found = prefilter.find(input.haystack, Regex::Automata::Span.new(at, input.end))
            break unless found
            at = found.start
          end
          if half_match = backtrack(cache, input, at, start_id, slots)
            return half_match
          end
          at += 1
        end
        nil
      end

      private def backtrack(cache : Cache, input : Regex::Automata::Input, at : Int32, start_id : Regex::Automata::StateID, slots : Array(Int32?)) : Regex::Automata::HalfMatch?
        cache.push(StepFrame.new(start_id, at))
        while frame = cache.pop
          if frame.is_a?(RestoreCaptureFrame)
            slots[frame.slot] = frame.offset
            next
          end
          if half_match = step(cache, input, frame.as(StepFrame).id, frame.as(StepFrame).at, slots)
            return half_match
          end
        end
        nil
      end

      private def step(cache : Cache, input : Regex::Automata::Input, start_id : Regex::Automata::StateID, start_at : Int32, slots : Array(Int32?)) : Regex::Automata::HalfMatch?
        sid = start_id
        at = start_at
        loop do
          return nil unless cache.visited_insert(sid, at - input.start)

          case state = @nfa.state(sid)
          when ByteRange
            return nil if at >= input.end || !state.trans.matches(input.haystack, at)
            sid = state.trans.next
            at += 1
          when Sparse
            return nil if at >= input.end
            next_id = state.matches(input.haystack, at)
            return nil unless next_id
            sid = next_id
            at += 1
          when Look
            return nil unless look_matches?(state.kind, input.haystack, at)
            sid = state.next
          when Union
            return nil if state.alternates.empty?
            (state.alternates.size - 1).downto(1) { |index| cache.push(StepFrame.new(state.alternates[index], at)) }
            sid = state.alternates[0]
          when BinaryUnion
            cache.push(StepFrame.new(state.alt2, at))
            sid = state.alt1
          when Capture
            if state.slot < slots.size
              cache.push(RestoreCaptureFrame.new(state.slot, slots[state.slot]))
              slots[state.slot] = at
            end
            sid = state.next
          when Empty
            sid = state.next
          when Fail
            return nil
          when Match
            return Regex::Automata::HalfMatch.new(state.pattern_id, at)
          end
        end
      end

      private def look_matches?(kind : Look::Kind, haystack : Bytes, at : Int32) : Bool
        look = case kind
               when Look::Kind::StartLF              then Regex::Automata::Look::StartLF
               when Look::Kind::EndLF                then Regex::Automata::Look::EndLF
               when Look::Kind::StartCRLF            then Regex::Automata::Look::StartCRLF
               when Look::Kind::EndCRLF              then Regex::Automata::Look::EndCRLF
               when Look::Kind::WordBoundaryAscii    then Regex::Automata::Look::WordAscii
               when Look::Kind::NonWordBoundaryAscii then Regex::Automata::Look::WordAsciiNegate
               when Look::Kind::WordBoundaryUnicode  then Regex::Automata::Look::WordUnicode
               when Look::Kind::NonWordBoundaryUnicode
                 Regex::Automata::Look::WordUnicodeNegate
               when Look::Kind::StartText
                 Regex::Automata::Look::Start
               when Look::Kind::EndText
                 Regex::Automata::Look::End
               when Look::Kind::EndTextWithNewline
                 Regex::Automata::Look::EndLF
               else
                 raise "unreachable look assertion kind: #{kind}"
               end
        @nfa.look_matcher.matches(look, haystack, at)
      end

      private def should_skip_empty_utf8_match?(input : Regex::Automata::Input, half_match : Regex::Automata::HalfMatch, slots : Array(Int32?)) : Bool
        return false unless @nfa.has_empty && @nfa.is_utf8

        slot_index = half_match.pattern.to_i * 2
        start = slots[slot_index]?
        finish = slots[slot_index + 1]?
        start == finish && !start.nil? && !input.is_char_boundary(finish.not_nil!)
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
