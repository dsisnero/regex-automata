require "./nfa"
require "./syntax"
require "./prefilter"
require "./sparse_set"

module Regex::Automata::NFA
  class PikeVM
    class Config
      @match_kind : Regex::Automata::MatchKind?
      @prefilter : Regex::Automata::Prefilter?
      @utf8_empty : Bool?

      def initialize
      end

      def self.new : Config
        previous_def
      end

      def match_kind(kind : Regex::Automata::MatchKind) : Config
        @match_kind = kind
        self
      end

      def prefilter(prefilter : Regex::Automata::Prefilter?) : Config
        @prefilter = prefilter
        self
      end

      def utf8_empty(yes : Bool) : Config
        @utf8_empty = yes
        self
      end

      def get_match_kind : Regex::Automata::MatchKind
        @match_kind || Regex::Automata::MatchKind::LeftmostFirst
      end

      def get_prefilter : Regex::Automata::Prefilter?
        @prefilter
      end

      def get_utf8_empty : Bool
        @utf8_empty.nil? ? true : @utf8_empty.not_nil!
      end

      def overwrite(other : Config) : Config
        merged = Config.new
        merged.match_kind(other.@match_kind || @match_kind || Regex::Automata::MatchKind::LeftmostFirst)
        merged.prefilter(other.@prefilter.nil? ? @prefilter : other.@prefilter)
        merged.utf8_empty(other.@utf8_empty.nil? ? get_utf8_empty : other.@utf8_empty.not_nil!)
        merged
      end
    end

    class Builder
      @config : Config
      @thompson_config : Regex::Automata::HirCompilerConfig
      @syntax_config : Regex::Automata::Syntax::Config

      def initialize
        @config = Config.new
        @thompson_config = NFA.config
        @syntax_config = Regex::Automata::Syntax::Config.new
      end

      def self.new : Builder
        previous_def
      end

      def build(pattern : String) : PikeVM
        build_many([pattern])
      end

      def build_many(patterns : Enumerable(String)) : PikeVM
        nfa = NFA.compiler
          .configure(@thompson_config)
          .syntax(@syntax_config)
          .build_many(patterns.to_a)
        build_from_nfa(nfa)
      end

      def build_from_nfa(nfa : NFA) : PikeVM
        nfa.look_set_any.available
        PikeVM.new(@config, nfa)
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
      @curr : ActiveStates
      @next : ActiveStates

      getter curr : ActiveStates
      getter next : ActiveStates

      def initialize(re : PikeVM)
        @curr = ActiveStates.new(re)
        @next = ActiveStates.new(re)
      end

      def self.new(re : PikeVM) : Cache
        previous_def(re)
      end

      def reset(re : PikeVM) : Nil
        @curr.reset(re)
        @next.reset(re)
      end

      def setup_search(captures_slot_len : Int32) : Nil
        @curr.clear
        @next.clear
        @curr.slot_table.setup_search(captures_slot_len)
        @next.slot_table.setup_search(captures_slot_len)
      end

      def swap_states! : Nil
        curr = @curr
        @curr = @next
        @next = curr
        @next.clear
      end

      def memory_usage : Int32
        @curr.memory_usage + @next.memory_usage
      end
    end

    class FindMatches
      include Enumerable(Regex::Automata::Match)

      def initialize(@re : PikeVM, @cache : Cache, @it : Regex::Automata::Searcher)
      end

      def next : Regex::Automata::Match?
        @it.advance { |input| @re.find(@cache, input) }
      end

      def each(&block : Regex::Automata::Match ->) : Nil
        while match = self.next
          yield match
        end
      end
    end

    class CapturesMatches
      include Enumerable(Regex::Automata::Captures)

      def initialize(@re : PikeVM, @cache : Cache, @caps : Regex::Automata::Captures, @it : Regex::Automata::Searcher)
      end

      def next : Regex::Automata::Captures?
        @it.advance do |input|
          @re.search(@cache, input, @caps)
          @caps.get_match
        end
        return nil unless @caps.is_match

        @caps.clone
      end

      def each(&block : Regex::Automata::Captures ->) : Nil
        while caps = self.next
          yield caps
        end
      end
    end

    private record ExploreFrame, id : Regex::Automata::StateID
    private record RestoreCaptureFrame, slot : Int32, offset : Int32?
    private alias EpsilonFrame = ExploreFrame | RestoreCaptureFrame

    private class SlotTable
      @table : Array(Int32?)
      @used_len : Int32
      @slots_per_state : Int32
      @slots_for_captures : Int32

      def initialize
        @table = [] of Int32?
        @used_len = 0
        @slots_per_state = 0
        @slots_for_captures = 0
      end

      def reset(re : PikeVM) : Nil
        nfa = re.get_nfa
        @slots_per_state = nfa.group_info.slot_len
        @slots_for_captures = Math.max(@slots_per_state, nfa.pattern_len * 2)
        @used_len = nfa.states.size.to_i32 * @slots_per_state + @slots_for_captures
        if @table.size < @used_len
          @table = Array(Int32?).new(@used_len, nil)
        elsif @used_len > 0
          @table[0, @used_len].fill(nil)
        end
      end

      def setup_search(captures_slot_len : Int32) : Nil
        # Public Crystal callers may provide spare output slots. They remain
        # absent; no NFA state has storage beyond its own capture-slot row.
        @slots_for_captures = Math.min(captures_slot_len, @slots_per_state)
      end

      def for_state(id : Regex::Automata::StateID) : Slice(Int32?)
        offset = id.to_i * @slots_per_state
        Slice(Int32?).new(@table.to_unsafe + offset, @slots_for_captures)
      end

      def all_absent : Slice(Int32?)
        offset = @used_len - @slots_for_captures
        slice = Slice(Int32?).new(@table.to_unsafe + offset, @slots_for_captures)
        slice.fill(nil)
        slice
      end

      def copy_from(id : Regex::Automata::StateID, slots : Slice(Int32?)) : Nil
        target = for_state(id)
        index = 0
        while index < target.size
          target[index] = slots[index]
          index += 1
        end
      end

      def copy_to(id : Regex::Automata::StateID, slots : Array(Int32?)) : Nil
        source = for_state(id)
        index = 0
        limit = Math.min(source.size, slots.size)
        while index < limit
          slots[index] = source[index]
          index += 1
        end
      end

      def memory_usage : Int32
        (@table.size * sizeof(Int32?)).to_i32
      end
    end

    private class ActiveStates
      getter set : Regex::Automata::SparseSet
      getter slot_table : SlotTable
      @closure_seen : Regex::Automata::SparseSet

      def initialize(re : PikeVM)
        @set = Regex::Automata::SparseSet.new(re.get_nfa.states.size.to_i32)
        @closure_seen = Regex::Automata::SparseSet.new(re.get_nfa.states.size.to_i32)
        @slot_table = SlotTable.new
        @slot_table.reset(re)
      end

      def reset(re : PikeVM) : Nil
        @set.resize(re.get_nfa.states.size.to_i32)
        @closure_seen.resize(re.get_nfa.states.size.to_i32)
        @slot_table.reset(re)
        clear
      end

      def clear : Nil
        @set.clear
      end

      def empty? : Bool
        @set.empty?
      end

      def add(id : Regex::Automata::StateID, slots : Slice(Int32?)) : Bool
        return false unless @set.insert(id)

        @slot_table.copy_from(id, slots)
        true
      end

      # Reuse a sparse set for each closure instead of allocating a hash set
      # for every NFA step. Existing terminal threads count as visited so that
      # depth-first priority remains identical to the old closure traversal.
      def begin_closure : Nil
        @closure_seen.clear
        @set.each { |id| @closure_seen.insert(id) }
      end

      def mark_seen(id : Regex::Automata::StateID) : Bool
        @closure_seen.insert(id)
      end

      def memory_usage : Int32
        @set.memory_usage + @closure_seen.memory_usage + @slot_table.memory_usage
      end
    end

    def initialize(@config : Config, @nfa : NFA)
    end

    def self.new(pattern : String) : PikeVM
      builder.build(pattern)
    end

    def self.new_many(patterns : Enumerable(String)) : PikeVM
      builder.build_many(patterns)
    end

    def self.new_from_nfa(nfa : NFA) : PikeVM
      builder.build_from_nfa(nfa)
    end

    def self.always_match : PikeVM
      new_from_nfa(NFA.always_match)
    end

    def self.never_match : PikeVM
      new_from_nfa(NFA.never_match)
    end

    def self.config : Config
      Config.new
    end

    def self.builder : Builder
      Builder.new
    end

    def create_captures : Regex::Automata::Captures
      Regex::Automata::Captures.all(@nfa.group_info)
    end

    def create_cache : Cache
      Cache.new(self)
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

    def get_nfa : NFA
      @nfa
    end

    def get_match_kind : Regex::Automata::MatchKind
      @config.get_match_kind
    end

    def get_prefilter : Regex::Automata::Prefilter?
      @config.get_prefilter
    end

    def memory_usage : Int32
      @nfa.memory_usage
    end

    def is_match(cache : Cache, haystack : String | Bytes | Regex::Automata::Input) : Bool
      input = normalize_input(haystack)
      input.earliest(true)
      !find(cache, input).nil?
    end

    def find(cache : Cache, haystack : String | Bytes | Regex::Automata::Input) : Regex::Automata::Match?
      input = normalize_input(haystack)
      pid, slots = search_slots_internal(cache, input, @nfa.group_info.implicit_slot_len)
      return nil unless pid && slots

      start_index = pid.to_i * 2
      start = slots[start_index]?
      finish = slots[start_index + 1]?
      return nil unless start && finish

      Regex::Automata::Match.new(pid, start, finish)
    end

    def captures(cache : Cache, haystack : String | Bytes | Regex::Automata::Input, caps : Regex::Automata::Captures) : Nil
      search(cache, normalize_input(haystack), caps)
    end

    def find_iter(cache : Cache, haystack : String | Bytes | Regex::Automata::Input) : FindMatches
      input = normalize_input(haystack)
      FindMatches.new(self, cache, Regex::Automata::Searcher.new(input))
    end

    def captures_iter(cache : Cache, haystack : String | Bytes | Regex::Automata::Input) : CapturesMatches
      input = normalize_input(haystack)
      CapturesMatches.new(self, cache, create_captures, Regex::Automata::Searcher.new(input))
    end

    def search(cache : Cache, input : Regex::Automata::Input, caps : Regex::Automata::Captures) : Nil
      caps.clear
      pid = search_slots(cache, input, caps.slots_mut)
      caps.set_pattern(pid)
    end

    def search_slots(cache : Cache, input : Regex::Automata::Input, slots : Array(Int32?)) : Regex::Automata::PatternID?
      slots.fill(nil)
      pid, matched_slots = search_slots_internal(cache, input, slots.size.to_i32)
      return nil unless pid && matched_slots

      limit = Math.min(slots.size, matched_slots.size)
      index = 0
      while index < limit
        slots[index] = matched_slots[index]
        index += 1
      end
      pid
    end

    def search_slots(cache : Cache, input : Regex::Automata::Input, slots : Array(Regex::Automata::NonMaxUsize?)) : Regex::Automata::PatternID?
      slots.fill(nil)
      pid, matched_slots = search_slots_internal(cache, input, slots.size.to_i32)
      return nil unless pid && matched_slots

      limit = Math.min(slots.size, matched_slots.size)
      index = 0
      while index < limit
        slots[index] = matched_slots[index].try { |offset| Regex::Automata::NonMaxUsize.new(offset).not_nil! }
        index += 1
      end
      pid
    end

    def which_overlapping_matches(cache : Cache, input : Regex::Automata::Input, patset : Regex::Automata::PatternSet) : Nil
      search_overlapping(cache, input, patset)
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

    private def search_slots_internal(cache : Cache, original_input : Regex::Automata::Input, requested_slot_len : Int32) : Tuple(Regex::Automata::PatternID?, Array(Int32?)?)
      input = original_input.clone
      slot_len = Math.max(requested_slot_len, @nfa.group_info.implicit_slot_len)

      loop do
        hm, matched_slots = search_imp(cache, input, slot_len)
        return {nil, nil} unless hm && matched_slots
        unless should_skip_empty_utf8_match?(input, hm, matched_slots)
          return {hm.pattern, matched_slots}
        end

        return {nil, nil} if input.get_anchored != Regex::Automata::Anchored::No

        # Rust's skip_splits_fwd advances the search start one byte at a time,
        # even when the rejected match was later in the haystack.
        next_start = input.start + 1
        return {nil, nil} if next_start > input.end
        input.set_start(next_start)
      end
    end

    private def search_imp(cache : Cache, input : Regex::Automata::Input, slot_len : Int32) : Tuple(Regex::Automata::HalfMatch?, Array(Int32?)?)
      cache.setup_search(slot_len)
      return {nil, nil} if input.is_done

      allmatches = @config.get_match_kind.continue_past_first_match
      start_config = start_config(input)
      return {nil, nil} unless start_config
      anchored, start_id = start_config
      prefilter = anchored ? nil : @config.get_prefilter

      hm = nil.as(Regex::Automata::HalfMatch?)
      matched_slots = nil.as(Array(Int32?)?)
      at = input.start

      while at <= input.end
        if cache.curr.empty?
          break if hm && !allmatches
          break if anchored && at > input.start
          if prefilter
            span = Regex::Automata::Span.new(at, input.end)
            found = prefilter.find(input.haystack, span)
            break unless found
            at = found.start
          end
        end

        if (hm.nil? || allmatches) && (!anchored || at == input.start)
          add_epsilon_closure(
            cache.curr,
            input,
            at,
            start_id,
            cache.curr.slot_table.all_absent
          )
        end

        pid, slots = advance_threads(cache.curr, cache.next, input, at, allmatches)
        if pid && slots
          hm = Regex::Automata::HalfMatch.new(pid, at)
          matched_slots = slots
        end
        break if input.get_earliest && hm

        cache.swap_states!
        at += 1
      end

      {hm, matched_slots}
    end

    private def search_overlapping(cache : Cache, input : Regex::Automata::Input, patset : Regex::Automata::PatternSet) : Nil
      cache.setup_search(0)
      return if input.is_done

      allmatches = @config.get_match_kind.continue_past_first_match
      start_config = start_config(input)
      return unless start_config
      anchored, start_id = start_config
      prefilter = anchored ? nil : @config.get_prefilter
      at = input.start

      while at <= input.end
        if cache.curr.empty?
          break if !patset.is_empty && !allmatches
          break if anchored && at > input.start
          if prefilter
            span = Regex::Automata::Span.new(at, input.end)
            found = prefilter.find(input.haystack, span)
            break unless found
            at = found.start
          end
        end

        if patset.is_empty || allmatches
          add_epsilon_closure(
            cache.curr,
            input,
            at,
            start_id,
            cache.curr.slot_table.all_absent
          )
        end

        advance_threads_overlapping(cache.curr, cache.next, input, at, allmatches, patset)
        break if patset.is_full || input.get_earliest

        cache.swap_states!
        at += 1
      end
    end

    private def advance_threads(curr : ActiveStates, nxt : ActiveStates, input : Regex::Automata::Input, at : Int32, allmatches : Bool) : Tuple(Regex::Automata::PatternID?, Array(Int32?)?)
      pid = nil.as(Regex::Automata::PatternID?)
      matched_slots = nil.as(Array(Int32?)?)

      curr.set.each do |id|
        state = @nfa.state(id)
        case state
        when Match
          pid = state.pattern_id
          matched_slots = Array(Int32?).new(curr.slot_table.for_state(id).size, nil)
          curr.slot_table.copy_to(id, matched_slots)
          break unless allmatches
        when ByteRange
          if state.trans.matches(input.haystack, at)
            add_epsilon_closure(nxt, input, at + 1, state.trans.next, curr.slot_table.for_state(id))
          end
        when Sparse
          if next_id = state.matches(input.haystack, at)
            add_epsilon_closure(nxt, input, at + 1, next_id, curr.slot_table.for_state(id))
          end
        end
      end

      {pid, matched_slots}
    end

    private def advance_threads_overlapping(curr : ActiveStates, nxt : ActiveStates, input : Regex::Automata::Input, at : Int32, allmatches : Bool, patset : Regex::Automata::PatternSet) : Nil
      curr.set.each do |id|
        state = @nfa.state(id)
        case state
        when Match
          next if should_skip_empty_utf8_thread?(input, at, curr.slot_table.for_state(id), state.pattern_id)
          patset.try_insert(state.pattern_id)
          break unless allmatches
        when ByteRange
          if state.trans.matches(input.haystack, at)
            add_epsilon_closure(nxt, input, at + 1, state.trans.next, curr.slot_table.for_state(id))
          end
        when Sparse
          if next_id = state.matches(input.haystack, at)
            add_epsilon_closure(nxt, input, at + 1, next_id, curr.slot_table.for_state(id))
          end
        end
      end
    end

    private def add_epsilon_closure(active : ActiveStates, input : Regex::Automata::Input, at : Int32, sid : Regex::Automata::StateID, slots : Slice(Int32?)) : Nil
      stack = [] of EpsilonFrame
      stack << ExploreFrame.new(sid)
      active.begin_closure

      until stack.empty?
        frame = stack.pop
        if frame.is_a?(RestoreCaptureFrame)
          slots[frame.slot] = frame.offset
          next
        end
        current_sid = frame.as(ExploreFrame).id
        next unless active.mark_seen(current_sid)

        case state = @nfa.state(current_sid)
        when Fail, Match, ByteRange, Sparse
          active.add(current_sid, slots)
        when Empty
          stack << ExploreFrame.new(state.next)
        when Look
          next unless look_matches?(state.kind, input.haystack, at)
          stack << ExploreFrame.new(state.next)
        when BinaryUnion
          stack << ExploreFrame.new(state.alt2)
          stack << ExploreFrame.new(state.alt1)
        when Union
          last = state.alternates.size - 1
          last.downto(0) do |index|
            stack << ExploreFrame.new(state.alternates[index])
          end
        when Capture
          if state.slot < slots.size
            stack << RestoreCaptureFrame.new(state.slot, slots[state.slot])
            slots[state.slot] = at
          end
          stack << ExploreFrame.new(state.next)
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

    private def start_config(input : Regex::Automata::Input) : Tuple(Bool, Regex::Automata::StateID)?
      case input.get_anchored
      when Regex::Automata::Anchored::No
        if @nfa.is_always_start_anchored
          {true, @nfa.start_anchored}
        else
          {false, @nfa.start_unanchored}
        end
      when Regex::Automata::Anchored::Yes
        {true, @nfa.start_anchored}
      when Regex::Automata::Anchored::Pattern
        pid = input.pattern
        return nil unless pid
        sid = @nfa.start_pattern(pid)
        return nil unless sid
        {true, sid}
      end
    end

    private def should_skip_empty_utf8_match?(input : Regex::Automata::Input, hm : Regex::Automata::HalfMatch, slots : Array(Int32?)) : Bool
      return false unless @config.get_utf8_empty && @nfa.has_empty && @nfa.is_utf8

      slot_index = hm.pattern.to_i * 2
      start = slots[slot_index]?
      finish = slots[slot_index + 1]?
      return false unless start && finish

      start == finish && !input.is_char_boundary(finish)
    end

    private def should_skip_empty_utf8_thread?(input : Regex::Automata::Input, at : Int32, slots : Slice(Int32?), pid : Regex::Automata::PatternID) : Bool
      return false unless @config.get_utf8_empty && @nfa.has_empty && @nfa.is_utf8

      slot_index = pid.to_i * 2
      start = slots[slot_index]?
      finish = slots[slot_index + 1]?
      return false unless start && finish

      start == finish && start == at && !input.is_char_boundary(at)
    end
  end
end
