require "./nfa"
require "./sparse_set"

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

      def clone : BuildError
        BuildError.new(@kind, message || "", @source.try(&.dup), @look,
          size_limit_exceeded: size_limit_exceeded?, size_limit: size_limit)
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

      def self.exceeded_size_limit(limit : Int64) : BuildError
        new(Kind::ExceededSizeLimit, "one-pass DFA exceeded size limit of #{limit} during building", size_limit_exceeded: true, size_limit: limit)
      end
    end

    class Config
      @match_kind : ::Regex::Automata::MatchKind?
      @starts_for_each_pattern : Bool?
      @byte_classes : Bool?
      @size_limit : Int64?
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

      def size_limit(limit : Int?) : Config
        @size_limit = limit.try(&.to_i64)
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
        @byte_classes != false
      end

      def get_size_limit : Int64?
        @size_limit_set ? @size_limit : nil
      end

      def clone : Config
        dup
      end

      def overwrite(other : Config) : Config
        merged = dup
        merged.merge_from(other)
        merged
      end

      protected def merge_from(other : Config) : Nil
        @match_kind = other.@match_kind unless other.@match_kind.nil?
        @starts_for_each_pattern = other.@starts_for_each_pattern unless other.@starts_for_each_pattern.nil?
        @byte_classes = other.@byte_classes unless other.@byte_classes.nil?
        if other.@size_limit_set
          @size_limit = other.@size_limit
          @size_limit_set = true
        end
      end
    end

    # Builds the same one-pass admission graph as Rust's InternalBuilder.
    # The compiled table handles every supported one-pass search, including
    # assertion-bearing and UTF-8-empty cases.
    private class Admission
      PATTERN_ID_LIMIT    = 0x3FFFFF_i32
      STATE_ID_LIMIT      = 1_i32 << 21
      EXPLICIT_SLOT_LIMIT =                  32_i32
      INFO_MASK           = 0x000003FF_FFFFFFFF_u64
      EMPTY_PATTERN       = 0xFFFFFC00_00000000_u64

      @classes : ByteClasses
      @alphabet_len : Int32
      getter stride2 : Int32
      @nfa_to_dfa : Array(Int32)
      @uncompiled : Array(StateID)
      @seen : SparseSet
      @stack : Array(Tuple(StateID, Epsilons))
      @table : Array(UInt64)
      @starts : Array(StateID)
      @min_match_id : Int32
      @matched : Bool

      # Low ten assertion bits and 32 explicit-slot bits, exactly as Rust.
      private struct Epsilons
        getter bits : UInt64

        def initialize(@bits : UInt64 = 0_u64)
        end

        def looks : ::Regex::Automata::LookSet
          ::Regex::Automata::LookSet.from_u32((@bits & 0x3FF_u64).to_u32)
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
          Epsilons.new(@bits | (look.as_repr.to_u64 & 0x3FF_u64))
        end

        def with_slot(slot : Int32) : Epsilons
          Epsilons.new(@bits | (1_u64 << (slot + 10)))
        end

        # The caller supplies only its active explicit-slot region. Slice views
        # keep match-side writes separate from transition scratch.
        def apply_slots(slots : Array(T?) | Slice(T?), at : Int32) : Nil forall T
          bits = (@bits >> 10).to_u32
          until bits == 0_u32
            slot = bits.trailing_zeros_count.to_i32
            break if slot >= slots.size
            {% if T == Int32 %}
              slots[slot] = at
            {% else %}
              slots[slot] = ::Regex::Automata::NonMaxUsize.new(at)
            {% end %}
            bits &= bits - 1_u32
          end
        end
      end

      # A stack value decoded from the flat u64 table, never a nullable heap row.
      private struct Transition
        getter word : UInt64

        def initialize(@word : UInt64)
        end

        def initialize(state_id : StateID, match_wins : Bool, epsilons : Epsilons)
          @word = (state_id.to_i.to_u64 << 43) | (match_wins ? 1_u64 << 42 : 0_u64) | epsilons.bits
        end

        def state_id : StateID
          StateID.new_unchecked((@word >> 43).to_i32)
        end

        def match_wins? : Bool
          (@word & (1_u64 << 42)) != 0
        end

        def epsilons : Epsilons
          Epsilons.new(@word & INFO_MASK)
        end
      end

      def initialize(@config : Config, @nfa : NFA::NFA)
        @classes = @config.get_byte_classes ? @nfa.byte_classes : ByteClasses.singletons
        @alphabet_len = @classes.alphabet_len - 1
        @stride2 = @classes.stride2
        @nfa_to_dfa = Array.new(@nfa.size, -1)
        @uncompiled = [] of StateID
        @seen = SparseSet.new(@nfa.size)
        @stack = [] of Tuple(StateID, Epsilons)
        @table = [] of UInt64
        @starts = [] of StateID
        @min_match_id = Int32::MAX
        @matched = false
      end

      def run : Nil
        @nfa.look_set_any.available
        @nfa.look_set_any.each do |look|
          if look.as_repr > ::Regex::Automata::Look::WordUnicodeNegate.as_repr
            raise BuildError.unsupported_look(look)
          end
        end
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
            add_start_state(start) if start
          end
        end

        until @uncompiled.empty?
          compile_state(@uncompiled.pop)
        end
        shuffle_states
        # InternalBuilder scratch dies after construction in Rust.
        @nfa_to_dfa = [] of Int32
        @uncompiled = [] of StateID
        @stack = [] of Tuple(StateID, Epsilons)
        @seen = SparseSet.new(0)
      end

      def state_len : Int32
        @table.size >> @stride2
      end

      def stride : Int32
        1 << @stride2
      end

      def memory_usage : Int64
        @table.size.to_i64 * sizeof(UInt64) + @starts.size.to_i64 * StateID::SIZE
      end

      def clone : Admission
        copy = dup
        copy.copy_storage
        copy
      end

      protected def copy_storage : Nil
        @config = @config.dup
        @table = @table.dup
        @starts = @starts.dup
      end

      def start(pattern : PatternID? = nil) : StateID
        return @starts[0] unless pattern
        @starts[pattern.to_i + 1]? || StateID::ZERO
      end

      def transition(state_id : StateID, byte : UInt8) : Transition
        Transition.new(@table[(state_id.to_i << @stride2) + @classes[byte]])
      end

      def match_pattern(state_id : StateID) : PatternID?
        id = pattern_word(state_id) >> 42
        id == PATTERN_ID_LIMIT ? nil : PatternID.new(id.to_i32)
      end

      private def pattern_word(state_id : StateID) : UInt64
        @table[(state_id.to_i << @stride2) + @alphabet_len]
      end

      def match_state?(state_id : StateID) : Bool
        state_id.to_i >= @min_match_id
      end

      # The upper bits here are a pattern ID instead of a transition target;
      # the same stack word view exposes the common low epsilon payload.
      def pattern_epsilons(state_id : StateID) : Transition
        Transition.new(pattern_word(state_id))
      end

      private def add_start_state(nfa_id : StateID) : StateID
        id = add_dfa_state(nfa_id)
        @starts << id
        id
      end

      # Rust swaps matching rows toward the tail, then repairs IDs once.
      private def shuffle_states : Nil
        old_for_new = Array.new(state_len) { |index| index }
        destination = state_len - 1
        (state_len - 1).downto(0) do |index|
          next unless match_pattern(StateID.new(index))
          stride.times { |column| @table.swap((index << @stride2) + column, (destination << @stride2) + column) }
          old_for_new.swap(index, destination)
          @min_match_id = destination
          destination -= 1
        end
        remap = Array.new(state_len, 0)
        old_for_new.each_with_index { |old_id, new_id| remap[old_id] = new_id }
        state_len.times do |index|
          offset = index << @stride2
          @alphabet_len.times do |column|
            word = @table[offset + column]
            @table[offset + column] = (remap[(word >> 43).to_i32].to_u64 << 43) | (word & ((1_u64 << 43) - 1))
          end
        end
        @starts.map! { |id| StateID.new(remap[id.to_i]) }
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
        id = StateID.new(state_len)
        raise BuildError.too_many_states(STATE_ID_LIMIT.to_i64) if id.to_i > STATE_ID_LIMIT
        stride.times { @table << 0_u64 }
        @table[(id.to_i << @stride2) + @alphabet_len] = EMPTY_PATTERN
        if limit = @config.get_size_limit
          raise BuildError.exceeded_size_limit(limit) if memory_usage > limit
        end
        id
      end

      private def compile_state(nfa_id : StateID) : Nil
        dfa_id = StateID.new(@nfa_to_dfa[nfa_id.to_i])
        @matched = false
        @seen.clear
        stack = @stack
        stack_push(stack, nfa_id, Epsilons.new)

        until stack.empty?
          id, epsilons = stack.pop
          case state = @nfa.state(id)
          when NFA::ByteRange
            compile_transition(dfa_id, state.trans, epsilons)
          when NFA::Sparse
            state.transitions.each { |transition| compile_transition(dfa_id, transition, epsilons) }
          when NFA::Dense
            state.iter.each { |transition| compile_transition(dfa_id, transition, epsilons) }
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
            @table[(dfa_id.to_i << @stride2) + @alphabet_len] = (state.pattern_id.to_i.to_u64 << 42) | epsilons.bits
          when NFA::Fail
          end
        end
      end

      private def compile_transition(dfa_id : StateID, transition : NFA::Transition, epsilons : Epsilons) : Nil
        next_id = add_dfa_state(transition.next)
        new_transition = Transition.new(next_id, @matched, epsilons)
        @classes.representatives(transition.start.to_i, transition.end.to_i, inclusive_end: true, include_eoi: false).each do |unit|
          byte = unit.as_u8
          next unless byte
          offset = (dfa_id.to_i << @stride2) + @classes[byte]
          old_transition = Transition.new(@table[offset])
          if old_transition.state_id == StateID::ZERO
            @table[offset] = new_transition.word
          elsif old_transition.word != new_transition.word
            raise BuildError.not_one_pass("conflicting transition")
          end
        end
      end

      private def stack_push(stack : Array(Tuple(StateID, Epsilons)), nfa_id : StateID, epsilons : Epsilons) : Nil
        raise BuildError.not_one_pass("multiple epsilon transitions to same state") unless @seen.insert(nfa_id)
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

      def clone : Builder
        copy = dup
        copy.copy_configuration
        copy
      end

      protected def copy_configuration : Nil
        @config = @config.dup
        @thompson_config = @thompson_config.overwrite(::Regex::Automata::HirCompilerConfig.new)
      end

      def self.new : Builder
        previous_def
      end

      def build(pattern : String) : DFA
        build_many([pattern])
      end

      def build_many(patterns : Enumerable(String)) : DFA
        patterns_array = patterns.to_a
        nfa = ::Regex::Automata::NFA::NFA.compiler
          .configure(@thompson_config)
          .syntax(@syntax_config)
          .build_many(patterns_array)
        build_from_nfa(nfa)
      rescue ex : ::Regex::Automata::NFA::BuildError
        raise BuildError.nfa(ex)
      end

      def build_from_nfa(nfa : ::Regex::Automata::NFA::NFA) : DFA
        admission = Admission.new(@config.dup, nfa)
        admission.run
        DFA.new(@config.dup, nfa, admission)
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
        @thompson_config = @thompson_config.overwrite(config)
        self
      end
    end

    class Cache
      getter compiled_slots : Array(Int32?)
      getter compiled_slot_len : Int32

      def initialize(re : DFA)
        @compiled_slots = [] of Int32?
        @compiled_slot_len = 0
        reset(re)
      end

      def clone : Cache
        copy = dup
        copy.copy_slots
        copy
      end

      protected def copy_slots : Nil
        @compiled_slots = @compiled_slots.dup
      end

      def self.new(re : DFA) : Cache
        previous_def(re)
      end

      def reset(re : DFA) : Nil
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
        @compiled_slot_len.times { |index| @compiled_slots[index] = nil }
      end

      def memory_usage : Int32
        @compiled_slots.size.to_i32 * sizeof(Int32?).to_i32
      end
    end

    class DFA
      @config : Config
      @nfa : ::Regex::Automata::NFA::NFA
      @byte_classes : ::Regex::Automata::ByteClasses

      def initialize(@config : Config, @nfa : ::Regex::Automata::NFA::NFA, @admission : Admission)
        @byte_classes = if @config.get_byte_classes
                          @nfa.byte_classes
                        else
                          ::Regex::Automata::ByteClasses.singletons
                        end
      end

      def clone : DFA
        copy = dup
        copy.copy_storage
        copy
      end

      protected def copy_storage : Nil
        @config = @config.dup
        @admission = @admission.clone
      end

      def inspect(io : IO) : Nil
        io << "Regex::Automata::DFA::OnePass::DFA(states: " << state_len
        io << ", patterns: " << pattern_len << ", memory: " << memory_usage << ")"
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
        @config.dup
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
        @admission.stride2
      end

      def stride : Int32
        1 << stride2
      end

      def memory_usage : Int64
        @admission.memory_usage
      end

      def is_match(cache : Cache, haystack : String | Bytes | ::Regex::Automata::Input) : Bool
        input = normalize_and_anchor(haystack)
        input.set_earliest(true)
        result = try_search_slots(cache, input, Slice(Int32?).empty)
        raise result if result.is_a?(::Regex::Automata::MatchError)

        !result.nil?
      end

      def find(cache : Cache, haystack : String | Bytes | ::Regex::Automata::Input) : ::Regex::Automata::Match?
        input = normalize_and_anchor(haystack)
        pair = StaticArray(Int32?, 2).new(nil)
        slots = @nfa.pattern_len == 1 ? pair.to_slice : Array(Int32?).new(@nfa.group_info.implicit_slot_len, nil)
        result = try_search_slots(cache, input, slots)
        raise result if result.is_a?(::Regex::Automata::MatchError)
        pid = result.as?(::Regex::Automata::PatternID)
        return nil unless pid

        slot_start = pid.to_i * 2
        start = slots[slot_start]?
        finish = slots[slot_start + 1]?
        return nil unless start && finish

        ::Regex::Automata::Match.new(pid, start, finish)
      end

      def captures(cache : Cache, haystack : String | Bytes | ::Regex::Automata::Input, caps : ::Regex::Automata::Captures) : Nil
        input = normalize_and_anchor(haystack)
        result = try_search(cache, input, caps)
        raise result if result.is_a?(::Regex::Automata::MatchError)
      end

      def try_search(cache : Cache, input : ::Regex::Automata::Input, caps : ::Regex::Automata::Captures) : Nil | ::Regex::Automata::MatchError
        result = try_search_slots(cache, input, caps.slots_mut)
        return result if result.is_a?(::Regex::Automata::MatchError)

        caps.set_pattern(result)
        nil
      end

      # Both slot representations execute the same compiled loop directly.
      # Slice support also permits the single-pattern scratch to stay on stack.
      def try_search_slots(cache : Cache, input : ::Regex::Automata::Input, slots : Array(T?) | Slice(T?)) : ::Regex::Automata::PatternID? | ::Regex::Automata::MatchError forall T
        unless @nfa.has_empty && @nfa.is_utf8
          return search_compiled(cache, input, slots)
        end
        implicit_len = @nfa.group_info.implicit_slot_len
        if slots.size >= implicit_len
          return filter_utf8_empty_match(input, search_compiled(cache, input, slots), slots)
        end
        if @nfa.pattern_len == 1
          enough = StaticArray(Int32?, 2).new(nil)
          result = search_compiled(cache, input, enough.to_slice)
          return result if result.is_a?(::Regex::Automata::MatchError)
          slots.size.times { |index| put_slot(slots, index, enough[index]) }
          return filter_utf8_empty_match(input, result, enough.to_slice)
        end
        enough = Array(Int32?).new(implicit_len, nil)
        result = search_compiled(cache, input, enough)
        return result if result.is_a?(::Regex::Automata::MatchError)
        slots.size.times { |index| put_slot(slots, index, enough[index]) }
        filter_utf8_empty_match(input, result, enough)
      end

      private def slot_view(slots : Array(T?)) : Slice(T?) forall T
        Slice.new(slots.to_unsafe, slots.size)
      end

      private def slot_view(slots : Slice(T?)) : Slice(T?) forall T
        slots
      end

      private def put_slot(slots : Array(Int32?) | Slice(Int32?), index : Int32, at : Int32?) : Nil
        slots[index] = at
      end

      private def put_slot(slots : Array(::Regex::Automata::NonMaxUsize?) | Slice(::Regex::Automata::NonMaxUsize?), index : Int32, at : Int32?) : Nil
        slots[index] = at.try { |offset| ::Regex::Automata::NonMaxUsize.new(offset) }
      end

      private def slot_offset(value : Int32?) : Int32?
        value
      end

      private def slot_offset(value : ::Regex::Automata::NonMaxUsize?) : Int32?
        value.try(&.get)
      end

      private def search_compiled(cache : Cache, input : ::Regex::Automata::Input, slots) : ::Regex::Automata::PatternID? | ::Regex::Automata::MatchError
        return nil if input.is_done
        slots.fill(nil)
        cache.setup_search(slots.size - @nfa.pattern_len * 2)
        @nfa.patterns.each do |pattern_id|
          start_slot = pattern_id.to_i * 2
          break if start_slot >= slots.size
          put_slot(slots, start_slot, input.start)
        end

        validation = validate_input(input)
        return validation if validation
        state = input.get_anchored == ::Regex::Automata::Anchored::Pattern ? @admission.start(input.pattern) : @admission.start
        matched = nil.as(::Regex::Automata::PatternID?)
        at = input.start
        while at < input.end
          transition = @admission.transition(state, input.haystack[at])
          if @admission.match_state?(state)
            if pattern_id = find_match(state, input, at, slots, cache)
              matched = pattern_id
              return matched if input.get_earliest || (
                                  @config.get_match_kind == ::Regex::Automata::MatchKind::LeftmostFirst && transition.match_wins?
                                )
            end
          end
          looks = transition.epsilons.looks
          return matched if state == StateID::ZERO || (!looks.is_empty && !@nfa.look_matcher.matches_set(looks, input.haystack, at))
          transition.epsilons.apply_slots(slot_view(cache.compiled_slots)[0, cache.compiled_slot_len], at)
          state = transition.state_id
          at += 1
        end
        if @admission.match_state?(state)
          matched = find_match(state, input, input.end, slots, cache) || matched
        end
        matched
      end

      private def filter_utf8_empty_match(input : ::Regex::Automata::Input, pattern_id : ::Regex::Automata::PatternID? | ::Regex::Automata::MatchError, slots) : ::Regex::Automata::PatternID? | ::Regex::Automata::MatchError
        return pattern_id if pattern_id.is_a?(::Regex::Automata::MatchError)
        return nil unless pattern_id
        slot_start = pattern_id.to_i * 2
        start = slot_offset(slots[slot_start])
        finish = slot_offset(slots[slot_start + 1])
        raise "match is missing implicit slots" unless start && finish
        start == finish && !input.is_char_boundary(start) ? nil : pattern_id
      end

      private def find_match(state : StateID, input : ::Regex::Automata::Input, at : Int32, slots, cache : Cache) : ::Regex::Automata::PatternID?
        payload = @admission.pattern_epsilons(state)
        looks = payload.epsilons.looks
        return nil if !looks.is_empty && !@nfa.look_matcher.matches_set(looks, input.haystack, at)
        # The match-state tail invariant proves that the upper field is a valid
        # pattern ID; no extra sentinel check is needed in this hot helper.
        pattern_id = ::Regex::Automata::PatternID.new_unchecked((payload.word >> 42).to_i32)
        end_slot = pattern_id.to_i * 2 + 1
        put_slot(slots, end_slot, at) if end_slot < slots.size
        explicit_start = @nfa.pattern_len * 2
        if explicit_start < slots.size
          cache.compiled_slot_len.times { |index| put_slot(slots, explicit_start + index, cache.compiled_slots[index]) }
          payload.epsilons.apply_slots(slot_view(slots)[explicit_start..], at)
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
          return ::Regex::Automata::MatchError.unsupported_anchored(::Regex::Automata::Anchored::No) unless @nfa.is_always_start_anchored
          nil
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
