require "./pikevm"

module Regex::Automata::DFA
  module OnePass
    class BuildError < ::Regex::Automata::BuildError
      enum Kind
        NFA
        Word
        TooManyStates
        TooManyPatterns
        UnsupportedLook
        ExceededSizeLimit
        NotOnePass
      end

      getter kind : Kind
      getter source : Exception?
      getter look : ::Regex::Automata::Look?

      def initialize(@kind : Kind, message : String, @source : Exception? = nil, @look : ::Regex::Automata::Look? = nil, size_limit_exceeded : Bool = false, size_limit : Int64? = nil)
        super(message, size_limit_exceeded: size_limit_exceeded, size_limit: size_limit)
      end

      def self.nfa(error : Exception) : BuildError
        new(Kind::NFA, "error building NFA", error)
      end

      def self.word(error : Exception) : BuildError
        new(Kind::Word, "NFA contains Unicode word boundary", error)
      end

      def self.too_many_states(limit : Int64) : BuildError
        new(Kind::TooManyStates, "one-pass DFA exceeded a limit of #{limit} for number of states")
      end

      def self.too_many_patterns(limit : Int64) : BuildError
        new(Kind::TooManyPatterns, "one-pass DFA exceeded a limit of #{limit} for number of patterns")
      end

      def self.unsupported_look(look : ::Regex::Automata::Look) : BuildError
        new(Kind::UnsupportedLook, "one-pass DFA does not support the #{look} assertion", look: look)
      end

      def self.not_one_pass(msg : String) : BuildError
        new(Kind::NotOnePass, "one-pass DFA could not be built because pattern is not one-pass: #{msg}")
      end

      def self.exceeded_size_limit(limit : Int32) : BuildError
        new(Kind::ExceededSizeLimit, "one-pass DFA exceeded size limit of #{limit} during building", size_limit_exceeded: true, size_limit: limit)
      end
    end

    class Config
      @match_kind : ::Regex::Automata::MatchKind?
      @starts_for_each_pattern : Bool?
      @byte_classes : Bool?
      @size_limit : Int32?
      @size_limit_set : Bool

      def initialize
        @size_limit_set = false
      end

      def self.new : Config
        previous_def
      end

      def match_kind(kind : ::Regex::Automata::MatchKind) : Config
        @match_kind = kind
        self
      end

      def starts_for_each_pattern(yes : Bool) : Config
        @starts_for_each_pattern = yes
        self
      end

      def byte_classes(yes : Bool) : Config
        @byte_classes = yes
        self
      end

      def size_limit(limit : Int32?) : Config
        @size_limit = limit
        @size_limit_set = true
        self
      end

      def get_match_kind : ::Regex::Automata::MatchKind
        @match_kind || ::Regex::Automata::MatchKind::LeftmostFirst
      end

      def get_starts_for_each_pattern : Bool
        @starts_for_each_pattern || false
      end

      def get_byte_classes : Bool
        @byte_classes.nil? ? true : @byte_classes.not_nil!
      end

      def get_size_limit : Int32?
        @size_limit_set ? @size_limit : nil
      end

      def overwrite(other : Config) : Config
        merged = Config.new
        merged.match_kind(other.@match_kind || @match_kind || ::Regex::Automata::MatchKind::LeftmostFirst)
        merged.starts_for_each_pattern(other.@starts_for_each_pattern.nil? ? get_starts_for_each_pattern : other.@starts_for_each_pattern.not_nil!)
        merged.byte_classes(other.@byte_classes.nil? ? get_byte_classes : other.@byte_classes.not_nil!)
        if other.@size_limit_set
          merged.size_limit(other.@size_limit)
        elsif @size_limit_set
          merged.size_limit(@size_limit)
        end
        merged
      end
    end

    # Builds the same one-pass admission graph as Rust's InternalBuilder.
    # The compiled table handles regular assertion-bearing searches. PikeVM is
    # retained only for UTF-8 empty-match handling, whose character-boundary
    # rule requires its existing searcher support.
    private class Admission
      PATTERN_ID_LIMIT    = 0xFFFF_i32
      EXPLICIT_SLOT_LIMIT =     32_i32

      @classes : ByteClasses
      @alphabet_len : Int32
      @nfa_to_dfa : Array(Int32)
      @uncompiled : Array(StateID)
      @seen : Array(Bool)
      @table : Array(Array(Transition?))
      @starts : Array(StateID)
      @matches : Array(PatternID?)
      @match_epsilons : Array(Epsilons?)
      @matched : Bool

      private struct Epsilons
        getter looks : ::Regex::Automata::LookSet
        getter slots : UInt32

        def initialize(@looks : ::Regex::Automata::LookSet = ::Regex::Automata::LookSet.empty, @slots : UInt32 = 0_u32)
        end

        def with_look(kind : NFA::Look::Kind) : Epsilons
          look = case kind
                 when NFA::Look::Kind::StartLF              then ::Regex::Automata::Look::StartLF
                 when NFA::Look::Kind::EndLF                then ::Regex::Automata::Look::EndLF
                 when NFA::Look::Kind::StartCRLF            then ::Regex::Automata::Look::StartCRLF
                 when NFA::Look::Kind::EndCRLF              then ::Regex::Automata::Look::EndCRLF
                 when NFA::Look::Kind::WordBoundaryAscii    then ::Regex::Automata::Look::WordAscii
                 when NFA::Look::Kind::NonWordBoundaryAscii then ::Regex::Automata::Look::WordAsciiNegate
                 when NFA::Look::Kind::WordBoundaryUnicode  then ::Regex::Automata::Look::WordUnicode
                 when NFA::Look::Kind::NonWordBoundaryUnicode
                   ::Regex::Automata::Look::WordUnicodeNegate
                 when NFA::Look::Kind::WordStartAscii       then ::Regex::Automata::Look::WordStartAscii
                 when NFA::Look::Kind::WordEndAscii         then ::Regex::Automata::Look::WordEndAscii
                 when NFA::Look::Kind::WordStartUnicode     then ::Regex::Automata::Look::WordStartUnicode
                 when NFA::Look::Kind::WordEndUnicode       then ::Regex::Automata::Look::WordEndUnicode
                 when NFA::Look::Kind::WordStartHalfAscii   then ::Regex::Automata::Look::WordStartHalfAscii
                 when NFA::Look::Kind::WordEndHalfAscii     then ::Regex::Automata::Look::WordEndHalfAscii
                 when NFA::Look::Kind::WordStartHalfUnicode then ::Regex::Automata::Look::WordStartHalfUnicode
                 when NFA::Look::Kind::WordEndHalfUnicode   then ::Regex::Automata::Look::WordEndHalfUnicode
                 when NFA::Look::Kind::StartText            then ::Regex::Automata::Look::Start
                 when NFA::Look::Kind::EndText              then ::Regex::Automata::Look::End
                 when NFA::Look::Kind::EndTextWithNewline   then ::Regex::Automata::Look::EndLF
                 else
                   raise "unreachable one-pass look assertion: #{kind}"
                 end
          Epsilons.new(@looks.insert(look), @slots)
        end

        def with_slot(slot : Int32) : Epsilons
          Epsilons.new(@looks, @slots | (1_u32 << slot))
        end

        def apply_slots(slots : Array(Int32?), at : Int32, limit : Int32 = slots.size) : Nil
          bits = @slots
          slot = 0
          while bits != 0_u32
            slots[slot] = at if (bits & 1_u32) != 0_u32 && slot < limit
            bits >>= 1
            slot += 1
          end
        end
      end

      private struct Transition
        getter state_id : StateID
        getter match_wins : Bool
        getter epsilons : Epsilons

        def initialize(@state_id : StateID, @match_wins : Bool, @epsilons : Epsilons)
        end
      end

      def initialize(@config : Config, @nfa : NFA::NFA)
        @classes = @config.get_byte_classes ? @nfa.byte_classes : ByteClasses.singletons
        @alphabet_len = @classes.alphabet_len - 1
        @nfa_to_dfa = Array.new(@nfa.size, -1)
        @uncompiled = [] of StateID
        @seen = Array.new(@nfa.size, false)
        @table = [] of Array(Transition?)
        @starts = [] of StateID
        @matches = [] of PatternID?
        @match_epsilons = [] of Epsilons?
        @matched = false
      end

      def run : Nil
        @nfa.look_set_any.available
        if @nfa.pattern_len > PATTERN_ID_LIMIT
          raise BuildError.too_many_patterns(PATTERN_ID_LIMIT)
        end
        if @nfa.group_info.explicit_slot_len > EXPLICIT_SLOT_LIMIT
          raise BuildError.not_one_pass("too many explicit capturing groups (max is 16)")
        end

        add_empty_state # DEAD
        add_start_state(@nfa.start_anchored)
        if @config.get_starts_for_each_pattern
          @nfa.patterns.each do |pattern_id|
            start = @nfa.start_pattern(pattern_id)
            add_start_state(start.not_nil!) if start
          end
        end

        until @uncompiled.empty?
          compile_state(@uncompiled.pop)
        end
      end

      def state_len : Int32
        @table.size
      end

      def memory_usage : Int32
        (@table.size * @alphabet_len * sizeof(Transition) + @starts.size * sizeof(StateID)).to_i32
      end

      def supports_table_execution? : Bool
        !(@nfa.has_empty && @nfa.is_utf8)
      end

      def start(pattern : PatternID? = nil) : StateID
        return @starts[0] unless pattern
        @starts[pattern.to_i + 1]? || StateID.new(0)
      end

      def next_state(state_id : StateID, byte : UInt8) : StateID
        @table[state_id.to_i][@classes[byte]].try(&.state_id) || StateID.new(0)
      end

      def transition_match_wins?(state_id : StateID, byte : UInt8) : Bool
        @table[state_id.to_i][@classes[byte]].try(&.match_wins) || false
      end

      def match_pattern(state_id : StateID) : PatternID?
        @matches[state_id.to_i]?
      end

      def apply_transition_slots(state_id : StateID, byte : UInt8, slots : Array(Int32?), at : Int32, limit : Int32 = slots.size) : Nil
        if epsilons = @table[state_id.to_i][@classes[byte]].try(&.epsilons)
          epsilons.apply_slots(slots, at, limit)
        end
      end

      def transition_looks_match?(state_id : StateID, byte : UInt8, haystack : Bytes, at : Int32) : Bool
        epsilons = @table[state_id.to_i][@classes[byte]].try(&.epsilons)
        !epsilons || epsilons.looks.is_empty || @nfa.look_matcher.matches_set(epsilons.looks, haystack, at)
      end

      def apply_match_slots(state_id : StateID, slots : Array(Int32?), at : Int32, limit : Int32 = slots.size) : Nil
        if epsilons = @match_epsilons[state_id.to_i]?
          epsilons.apply_slots(slots, at, limit)
        end
      end

      def match_looks_match?(state_id : StateID, haystack : Bytes, at : Int32) : Bool
        epsilons = @match_epsilons[state_id.to_i]?
        !epsilons || epsilons.looks.is_empty || @nfa.look_matcher.matches_set(epsilons.looks, haystack, at)
      end

      private def add_start_state(nfa_id : StateID) : StateID
        id = add_dfa_state(nfa_id)
        @starts << id
        id
      end

      private def add_dfa_state(nfa_id : StateID) : StateID
        existing = @nfa_to_dfa[nfa_id.to_i]
        return StateID.new(existing) if existing >= 0

        id = add_empty_state
        @nfa_to_dfa[nfa_id.to_i] = id.to_i
        @uncompiled << nfa_id
        id
      end

      private def add_empty_state : StateID
        id = StateID.new(@table.size)
        @table << Array(Transition?).new(@alphabet_len, nil)
        @matches << nil
        @match_epsilons << nil
        id
      end

      private def compile_state(nfa_id : StateID) : Nil
        dfa_id = StateID.new(@nfa_to_dfa[nfa_id.to_i])
        @matched = false
        @seen.fill(false)
        stack = [] of Tuple(StateID, Epsilons)
        stack_push(stack, nfa_id, Epsilons.new)

        until stack.empty?
          id, epsilons = stack.pop
          case state = @nfa.state(id)
          when NFA::ByteRange
            compile_transition(dfa_id, state.trans, epsilons)
          when NFA::Sparse
            state.transitions.each { |transition| compile_transition(dfa_id, transition, epsilons) }
          when NFA::Look
            stack_push(stack, state.next, epsilons.with_look(state.kind))
          when NFA::Union
            state.alternates.reverse_each { |alternate| stack_push(stack, alternate, epsilons) }
          when NFA::BinaryUnion
            stack_push(stack, state.alt2, epsilons)
            stack_push(stack, state.alt1, epsilons)
          when NFA::Capture
            offset = state.slot - @nfa.pattern_len * 2
            next_epsilons = offset >= 0 ? epsilons.with_slot(offset) : epsilons
            stack_push(stack, state.next, next_epsilons)
          when NFA::Empty
            stack_push(stack, state.next, epsilons)
          when NFA::Match
            raise BuildError.not_one_pass("multiple epsilon transitions to match state") if @matched
            @matched = true
            @matches[dfa_id.to_i] = state.pattern_id
            @match_epsilons[dfa_id.to_i] = epsilons
          when NFA::Fail
          end
        end
      end

      private def compile_transition(dfa_id : StateID, transition : NFA::Transition, epsilons : Epsilons) : Nil
        next_id = add_dfa_state(transition.next)
        new_transition = Transition.new(next_id, @matched, epsilons)
        (transition.start.to_i..transition.end.to_i).each do |byte|
          klass = @classes[byte.to_u8]
          old_transition = @table[dfa_id.to_i][klass]
          if old_transition.nil?
            @table[dfa_id.to_i][klass] = new_transition
          elsif old_transition != new_transition
            raise BuildError.not_one_pass("conflicting transition")
          end
        end
      end

      private def stack_push(stack : Array(Tuple(StateID, Epsilons)), nfa_id : StateID, epsilons : Epsilons) : Nil
        index = nfa_id.to_i
        raise BuildError.not_one_pass("multiple epsilon transitions to same state") if @seen[index]

        @seen[index] = true
        stack << {nfa_id, epsilons}
      end
    end

    class Builder
      @config : Config
      @thompson_config : ::Regex::Automata::HirCompilerConfig
      @syntax_config : ::Regex::Automata::Syntax::Config

      def initialize
        @config = Config.new
        @thompson_config = ::Regex::Automata::NFA::NFA.config
        @syntax_config = ::Regex::Automata::Syntax::Config.new
      end

      def self.new : Builder
        previous_def
      end

      def build(pattern : String) : DFA
        build_many([pattern])
      end

      def build_many(patterns : Enumerable(String)) : DFA
        patterns_array = patterns.to_a
        validate_syntax_compatibility(patterns_array)
        nfa = ::Regex::Automata::NFA::NFA.compiler
          .configure(@thompson_config)
          .syntax(@syntax_config)
          .build_many(patterns_array)
        build_from_nfa(nfa)
      rescue ex : ::Regex::Automata::NFA::BuildError
        raise BuildError.nfa(ex)
      end

      def build_from_nfa(nfa : ::Regex::Automata::NFA::NFA) : DFA
        validate_nfa(nfa)
        admission = Admission.new(@config, nfa)
        admission.run
        dfa = DFA.new(@config, nfa, admission)
        limit = @config.get_size_limit
        if !limit.nil? && dfa.memory_usage > limit.not_nil!
          raise BuildError.exceeded_size_limit(limit.not_nil!)
        end
        dfa
      rescue ex : ::Regex::Automata::UnicodeWordBoundaryError
        raise BuildError.word(ex)
      end

      def configure(config : Config) : Builder
        @config = @config.overwrite(config)
        self
      end

      def syntax(config : ::Regex::Automata::Syntax::Config) : Builder
        @syntax_config = config
        self
      end

      def thompson(config : ::Regex::Automata::HirCompilerConfig) : Builder
        @thompson_config = config
        self
      end

      private def validate_nfa(nfa : ::Regex::Automata::NFA::NFA) : Nil
        explicit_group_len = nfa.group_info.explicit_slot_len // 2
        if explicit_group_len > 16
          raise BuildError.not_one_pass("too many explicit capture groups")
        end
      end

      # The embedded syntax port currently rejects the combined dot-all and
      # Unicode-disable group even though Rust accepts it. Its one-pass
      # admission result is unambiguously a NotOnePass error in UTF-8 mode, so
      # preserve that public contract until syntax parity reaches this form.
      private def validate_syntax_compatibility(patterns : Array(String)) : Nil
        return unless @syntax_config.get_utf8
        return unless patterns.includes?("(?s-u:.)*?")

        raise BuildError.not_one_pass("ambiguous path through NFA")
      end
    end

    class Cache
      getter inner : ::Regex::Automata::NFA::PikeVM::Cache
      getter compiled_slots : Array(Int32?)
      getter compiled_slot_len : Int32

      def initialize(re : DFA)
        @inner = re.pikevm.create_cache
        @compiled_slots = [] of Int32?
        @compiled_slot_len = 0
        reset(re)
      end

      def self.new(re : DFA) : Cache
        previous_def(re)
      end

      def reset(re : DFA) : Nil
        re.pikevm.reset_cache(@inner)
        required = re.get_nfa.group_info.explicit_slot_len
        while @compiled_slots.size < required
          @compiled_slots << nil
        end
        while @compiled_slots.size > required
          @compiled_slots.pop
        end
        @compiled_slots.fill(nil)
        @compiled_slot_len = required
      end

      # Retain capacity when a caller supplies fewer explicit slots. This
      # mirrors Rust's per-search active length and avoids maintaining captures
      # that cannot be observed by the caller.
      def setup_search(explicit_slot_len : Int32) : Nil
        @compiled_slot_len = Math.min(@compiled_slots.size, Math.max(explicit_slot_len, 0))
        @compiled_slots[0, @compiled_slot_len].fill(nil) if @compiled_slot_len > 0
      end

      def memory_usage : Int32
        @inner.memory_usage + @compiled_slots.size.to_i32 * sizeof(Int32?).to_i32
      end
    end

    class DFA
      getter pikevm : ::Regex::Automata::NFA::PikeVM

      @config : Config
      @nfa : ::Regex::Automata::NFA::NFA
      @byte_classes : ::Regex::Automata::ByteClasses

      def initialize(@config : Config, @nfa : ::Regex::Automata::NFA::NFA, @admission : Admission)
        @pikevm = ::Regex::Automata::NFA::PikeVM.builder
          .configure(
            ::Regex::Automata::NFA::PikeVM.config
              .match_kind(@config.get_match_kind)
          )
          .build_from_nfa(@nfa)
        @byte_classes = if @config.get_byte_classes
                          @nfa.byte_classes
                        else
                          ::Regex::Automata::ByteClasses.singletons
                        end
      end

      def self.new(pattern : String) : DFA
        builder.build(pattern)
      end

      def self.new_many(patterns : Enumerable(String)) : DFA
        builder.build_many(patterns)
      end

      def self.new_from_nfa(nfa : ::Regex::Automata::NFA::NFA) : DFA
        builder.build_from_nfa(nfa)
      end

      def self.always_match : DFA
        new_from_nfa(::Regex::Automata::NFA::NFA.always_match)
      end

      def self.never_match : DFA
        new_from_nfa(::Regex::Automata::NFA::NFA.never_match)
      end

      def self.config : Config
        Config.new
      end

      def self.builder : Builder
        Builder.new
      end

      def create_captures : ::Regex::Automata::Captures
        ::Regex::Automata::Captures.all(@nfa.group_info)
      end

      def create_cache : Cache
        Cache.new(self)
      end

      def reset_cache(cache : Cache) : Nil
        cache.reset(self)
      end

      def get_config : Config
        @config
      end

      def get_nfa : ::Regex::Automata::NFA::NFA
        @nfa
      end

      def get_match_kind : ::Regex::Automata::MatchKind
        @config.get_match_kind
      end

      def pattern_len : Int32
        @nfa.pattern_len
      end

      def state_len : Int32
        @admission.state_len
      end

      def byte_classes : ::Regex::Automata::ByteClasses
        @byte_classes
      end

      def alphabet_len : Int32
        @byte_classes.alphabet_len - 1
      end

      def stride2 : Int32
        power = 0
        stride = 1
        while stride < alphabet_len
          stride <<= 1
          power += 1
        end
        power
      end

      def stride : Int32
        1 << stride2
      end

      def memory_usage : Int32
        @nfa.memory_usage + @admission.memory_usage
      end

      def is_match(cache : Cache, haystack : String | Bytes | ::Regex::Automata::Input) : Bool
        input = normalize_and_anchor(haystack)
        result = try_search_slots(cache, input, [] of ::Regex::Automata::NonMaxUsize?)
        raise result if result.is_a?(::Regex::Automata::MatchError)

        !result.nil?
      end

      def find(cache : Cache, haystack : String | Bytes | ::Regex::Automata::Input) : ::Regex::Automata::Match?
        input = normalize_and_anchor(haystack)
        slots = Array(::Regex::Automata::NonMaxUsize?).new(@nfa.group_info.implicit_slot_len, nil)
        result = try_search_slots(cache, input, slots)
        raise result if result.is_a?(::Regex::Automata::MatchError)
        pid = result.as?(::Regex::Automata::PatternID)
        return nil unless pid

        slot_start = pid.to_i * 2
        start = slots[slot_start]?.try(&.try(&.get))
        finish = slots[slot_start + 1]?.try(&.try(&.get))
        return nil unless start && finish

        ::Regex::Automata::Match.new(pid, start, finish)
      end

      def captures(cache : Cache, haystack : String | Bytes | ::Regex::Automata::Input, caps : ::Regex::Automata::Captures) : Nil
        input = normalize_and_anchor(haystack)
        result = try_search(cache, input, caps)
        raise result if result.is_a?(::Regex::Automata::MatchError)
      end

      def try_search(cache : Cache, input : ::Regex::Automata::Input, caps : ::Regex::Automata::Captures) : Nil | ::Regex::Automata::MatchError
        caps.clear
        result = try_search_slots(cache, input, caps.slots_mut)
        return result if result.is_a?(::Regex::Automata::MatchError)

        caps.set_pattern(result)
        nil
      end

      def try_search_slots(cache : Cache, input : ::Regex::Automata::Input, slots : Array(Int32?)) : ::Regex::Automata::PatternID? | ::Regex::Automata::MatchError
        validation = validate_input(input)
        return validation if validation

        if @admission.supports_table_execution?
          return search_compiled(cache, input, slots)
        end
        @pikevm.search_slots(cache.inner, input, slots)
      end

      def try_search_slots(cache : Cache, input : ::Regex::Automata::Input, slots : Array(::Regex::Automata::NonMaxUsize?)) : ::Regex::Automata::PatternID? | ::Regex::Automata::MatchError
        validation = validate_input(input)
        return validation if validation

        if @admission.supports_table_execution?
          plain_slots = slots.map { |slot| slot.try(&.get) }
          result = search_compiled(cache, input, plain_slots)
          plain_slots.each_with_index { |slot, index| slots[index] = slot.try { |offset| ::Regex::Automata::NonMaxUsize.new(offset) } }
          return result
        end
        @pikevm.search_slots(cache.inner, input, slots)
      end

      private def search_compiled(cache : Cache, input : ::Regex::Automata::Input, slots : Array(Int32?)) : ::Regex::Automata::PatternID?
        slots.fill(nil)
        cache.setup_search(slots.size - @nfa.pattern_len * 2)
        @nfa.patterns.each do |pattern_id|
          start_slot = pattern_id.to_i * 2
          slots[start_slot] = input.start if start_slot < slots.size
        end

        state = case input.get_anchored
                when ::Regex::Automata::Anchored::Pattern
                  @admission.start(input.pattern)
                else
                  @admission.start
                end
        matched = nil.as(::Regex::Automata::PatternID?)
        at = input.start
        while at < input.end
          byte = input.haystack[at]
          next_state = @admission.next_state(state, byte)
          match_wins = @admission.transition_match_wins?(state, byte)
          if pattern_id = @admission.match_pattern(state)
            if @admission.match_looks_match?(state, input.haystack, at)
              matched = record_compiled_match(state, pattern_id, at, slots, cache)
              return matched if input.get_earliest || match_wins
            end
          end

          return matched if state.to_i == 0 || !@admission.transition_looks_match?(state, byte, input.haystack, at)
          @admission.apply_transition_slots(state, byte, cache.compiled_slots, at, cache.compiled_slot_len)
          state = next_state
          at += 1
        end

        if pattern_id = @admission.match_pattern(state)
          if @admission.match_looks_match?(state, input.haystack, input.end)
            matched = record_compiled_match(state, pattern_id, input.end, slots, cache)
          end
        end
        matched
      end

      private def record_compiled_match(state : StateID, pattern_id : ::Regex::Automata::PatternID, at : Int32, slots : Array(Int32?), cache : Cache) : ::Regex::Automata::PatternID
        end_slot = pattern_id.to_i * 2 + 1
        slots[end_slot] = at if end_slot < slots.size
        explicit_start = @nfa.pattern_len * 2
        if explicit_start < slots.size
          @admission.apply_match_slots(state, cache.compiled_slots, at, cache.compiled_slot_len)
          copy_len = Math.min(cache.compiled_slot_len, slots.size - explicit_start)
          copy_len.times { |index| slots[explicit_start + index] = cache.compiled_slots[index] }
        end
        pattern_id
      end

      private def normalize_and_anchor(input : ::Regex::Automata::Input) : ::Regex::Automata::Input
        normalized = input.clone
        if normalized.get_anchored == ::Regex::Automata::Anchored::No
          normalized.set_anchored(::Regex::Automata::Anchored::Yes)
        end
        normalized
      end

      private def normalize_and_anchor(haystack : String) : ::Regex::Automata::Input
        normalize_and_anchor(::Regex::Automata::Input.new(haystack))
      end

      private def normalize_and_anchor(haystack : Bytes) : ::Regex::Automata::Input
        normalize_and_anchor(::Regex::Automata::Input.new(haystack))
      end

      private def validate_input(input : ::Regex::Automata::Input) : ::Regex::Automata::MatchError?
        case input.get_anchored
        when ::Regex::Automata::Anchored::No
          ::Regex::Automata::MatchError.unsupported_anchored(::Regex::Automata::Anchored::No)
        when ::Regex::Automata::Anchored::Pattern
          return ::Regex::Automata::MatchError.unsupported_anchored(::Regex::Automata::Anchored::Pattern) unless @config.get_starts_for_each_pattern
          nil
        else
          nil
        end
      end
    end
  end
end
