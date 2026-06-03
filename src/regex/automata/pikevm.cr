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

      def setup_search : Nil
        @curr.clear
        @next.clear
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

    private record Thread, id : Regex::Automata::StateID, slots : Array(Int32?)

    private class ActiveStates
      getter set : Regex::Automata::SparseSet
      getter threads : Array(Thread)

      def initialize(re : PikeVM)
        @set = Regex::Automata::SparseSet.new(re.get_nfa.states.size.to_i32)
        @threads = [] of Thread
      end

      def reset(re : PikeVM) : Nil
        @set.resize(re.get_nfa.states.size.to_i32)
        clear
      end

      def clear : Nil
        @set.clear
        @threads.clear
      end

      def empty? : Bool
        @threads.empty?
      end

      def add(thread : Thread) : Bool
        return false unless @set.insert(thread.id)

        @threads << thread
        true
      end

      def contains?(id : Regex::Automata::StateID) : Bool
        found = false
        @set.each do |sid|
          if sid == id
            found = true
            break
          end
        end
        found
      end

      def memory_usage : Int32
        @set.memory_usage + (@threads.sum { |thread| thread.slots.size } * sizeof(Int32)).to_i32
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

        next_start = hm.offset + 1
        return {nil, nil} if next_start > input.end
        input.set_start(next_start)
      end
    end

    private def search_imp(cache : Cache, input : Regex::Automata::Input, slot_len : Int32) : Tuple(Regex::Automata::HalfMatch?, Array(Int32?)?)
      cache.setup_search
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
            Array(Int32?).new(slot_len, nil)
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
      cache.setup_search
      return if input.is_done

      allmatches = @config.get_match_kind.continue_past_first_match
      start_config = start_config(input)
      return unless start_config
      anchored, start_id = start_config
      prefilter = anchored ? nil : @config.get_prefilter
      slot_len = @nfa.group_info.implicit_slot_len
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
            Array(Int32?).new(slot_len, nil)
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

      curr.threads.each do |thread|
        state = @nfa.state(thread.id)
        case state
        when Match
          pid = state.pattern_id
          matched_slots = thread.slots.dup
          break unless allmatches
        when ByteRange
          if state.trans.matches(input.haystack, at)
            add_epsilon_closure(nxt, input, at + 1, state.trans.next, thread.slots.dup)
          end
        when Sparse
          if next_id = state.matches(input.haystack, at)
            add_epsilon_closure(nxt, input, at + 1, next_id, thread.slots.dup)
          end
        end
      end

      {pid, matched_slots}
    end

    private def advance_threads_overlapping(curr : ActiveStates, nxt : ActiveStates, input : Regex::Automata::Input, at : Int32, allmatches : Bool, patset : Regex::Automata::PatternSet) : Nil
      curr.threads.each do |thread|
        state = @nfa.state(thread.id)
        case state
        when Match
          next if should_skip_empty_utf8_thread?(input, at, thread.slots, state.pattern_id)
          patset.try_insert(state.pattern_id)
          break unless allmatches
        when ByteRange
          if state.trans.matches(input.haystack, at)
            add_epsilon_closure(nxt, input, at + 1, state.trans.next, thread.slots.dup)
          end
        when Sparse
          if next_id = state.matches(input.haystack, at)
            add_epsilon_closure(nxt, input, at + 1, next_id, thread.slots.dup)
          end
        end
      end
    end

    private def add_epsilon_closure(active : ActiveStates, input : Regex::Automata::Input, at : Int32, sid : Regex::Automata::StateID, slots : Array(Int32?)) : Nil
      stack = [{sid, slots}] of Tuple(Regex::Automata::StateID, Array(Int32?))
      visited = Set(Int32).new
      active.threads.each { |thread| visited.add(thread.id.to_i) }

      until stack.empty?
        current_sid, current_slots = stack.pop
        next if visited.includes?(current_sid.to_i)
        visited.add(current_sid.to_i)

        case state = @nfa.state(current_sid)
        when Fail, Match, ByteRange, Sparse
          active.add(Thread.new(current_sid, current_slots))
        when Empty
          stack << {state.next, current_slots}
        when Look
          next unless look_matches?(state.kind, input.haystack, at)
          stack << {state.next, current_slots}
        when BinaryUnion
          stack << {state.alt2, current_slots.dup}
          stack << {state.alt1, current_slots}
        when Union
          last = state.alternates.size - 1
          last.downto(0) do |index|
            alt_slots = index == 0 ? current_slots : current_slots.dup
            stack << {state.alternates[index], alt_slots}
          end
        when Capture
          next_slots = current_slots.dup
          if state.slot < next_slots.size
            next_slots[state.slot] = at
          end
          stack << {state.next, next_slots}
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

    private def should_skip_empty_utf8_thread?(input : Regex::Automata::Input, at : Int32, slots : Array(Int32?), pid : Regex::Automata::PatternID) : Bool
      return false unless @config.get_utf8_empty && @nfa.has_empty && @nfa.is_utf8

      slot_index = pid.to_i * 2
      start = slots[slot_index]?
      finish = slots[slot_index + 1]?
      return false unless start && finish

      start == finish && start == at && !input.is_char_boundary(at)
    end
  end
end
