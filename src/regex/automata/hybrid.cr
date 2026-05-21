require "./nfa"
require "./look"
require "./hir_compiler"

module Regex::Automata::Hybrid
  alias StateID = Regex::Automata::StateID
  alias PatternID = Regex::Automata::PatternID

  class LazyDFA
    enum Anchored : Int32
      No  = 0
      Yes = 1
    end

    private class LazyState
      getter id : StateID
      getter nfa_set : Set(StateID)
      getter look_have : Regex::Automata::LookSet
      getter? is_from_word : Bool
      getter? is_half_crlf : Bool
      getter look_need : Regex::Automata::LookSet
      getter match : Array(PatternID)
      getter transitions : Hash(UInt8, StateID)

      def initialize(@id : StateID, @nfa_set : Set(StateID), @look_have : Regex::Automata::LookSet, @is_from_word : Bool, @is_half_crlf : Bool, @look_need : Regex::Automata::LookSet, @match : Array(PatternID))
        @transitions = {} of UInt8 => StateID
      end

      def accepting? : Bool
        !@match.empty?
      end
    end

    @nfa : Regex::Automata::NFA::NFA
    @states : Array(LazyState)
    @state_map : Hash(Tuple(Set(StateID), Regex::Automata::LookSet, Bool, Bool), StateID)
    @start_unanchored : StateID
    @start_anchored : StateID
    @nfa_has_word : Bool
    @nfa_has_crlf : Bool

    def initialize(@nfa : Regex::Automata::NFA::NFA)
      @states = [] of LazyState
      @state_map = {} of Tuple(Set(StateID), Regex::Automata::LookSet, Bool, Bool) => StateID
      @nfa_has_word = false
      @nfa_has_crlf = false
      analyze_nfa_look_requirements

      start_look_have = Regex::Automata::LookSet.new.insert(Regex::Automata::Look::Start).insert(Regex::Automata::Look::StartLF)
      if @nfa_has_crlf
        start_look_have = start_look_have.insert(Regex::Automata::Look::StartCRLF)
      end

      unanchored_nfa_start = valid_nfa_start(@nfa.start_unanchored)
      anchored_nfa_start = valid_nfa_start(@nfa.start_anchored, fallback: unanchored_nfa_start)

      @start_unanchored = add_state(Set{unanchored_nfa_start}, start_look_have, false, false)
      @start_anchored = add_state(Set{anchored_nfa_start}, start_look_have, false, false)
    end

    def self.compile(hir : Regex::Syntax::Hir::Hir, utf8 : Bool = true) : LazyDFA
      nfa = Regex::Automata::HirCompiler.new(utf8: utf8).compile(hir)
      new(nfa)
    end

    def size : Int32
      @states.size
    end

    def universal_start_state(mode : Int32) : StateID?
      case mode
      when Anchored::No.value
        @start_unanchored
      when Anchored::Yes.value
        @start_anchored
      else
        nil
      end
    end

    def find_longest_match(input : String, anchored : Anchored = Anchored::No) : Tuple(Int32, Array(PatternID))?
      find_longest_match(input.to_slice, anchored)
    end

    def find_longest_match(input : Bytes, anchored : Anchored = Anchored::No) : Tuple(Int32, Array(PatternID))?
      current = anchored == Anchored::Yes ? @start_anchored : @start_unanchored
      last_match : Tuple(Int32, Array(PatternID))? = nil

      idx = 0
      while idx < input.size
        next_id = next_state(current, input[idx])
        break if next_id.to_i < 0

        current = next_id
        state = @states[current.to_i]
        if state.accepting?
          last_match = {idx + 1, state.match}
        end

        idx += 1
      end

      if last_match.nil?
        start_state = @states[(anchored == Anchored::Yes ? @start_anchored : @start_unanchored).to_i]
        if start_state.accepting?
          last_match = {0, start_state.match}
        end
      end

      last_match
    end

    private def next_state(current : StateID, byte : UInt8) : StateID
      state = @states[current.to_i]
      if next_id = state.transitions[byte]?
        return next_id
      end

      current_look_have = state.look_have
      if byte == '\n'.ord.to_u8
        current_look_have = current_look_have.insert(Regex::Automata::Look::EndLF)
        if !state.is_half_crlf?
          current_look_have = current_look_have.insert(Regex::Automata::Look::EndCRLF)
        end
      elsif byte == '\r'.ord.to_u8
        current_look_have = current_look_have.insert(Regex::Automata::Look::EndCRLF)
      end

      if @nfa_has_crlf && state.is_half_crlf? && byte != '\n'.ord.to_u8
        current_look_have = current_look_have.insert(Regex::Automata::Look::StartCRLF)
      end

      if @nfa_has_word
        if state.is_from_word? != ::Regex::Automata.is_word_byte(byte)
          current_look_have = current_look_have.insert(Regex::Automata::Look::WordAscii).remove(Regex::Automata::Look::WordAsciiNegate)
        else
          current_look_have = current_look_have.remove(Regex::Automata::Look::WordAscii).insert(Regex::Automata::Look::WordAsciiNegate)
        end
      end

      next_look_have = state.look_have.remove(Regex::Automata::Look::Start).remove(Regex::Automata::Look::StartLF).remove(Regex::Automata::Look::StartCRLF)
      if byte == '\n'.ord.to_u8
        next_look_have = next_look_have.insert(Regex::Automata::Look::StartLF)
        if @nfa_has_crlf
          next_look_have = next_look_have.insert(Regex::Automata::Look::StartCRLF)
        end
      end
      next_look_have = next_look_have.remove(Regex::Automata::Look::WordAscii).remove(Regex::Automata::Look::WordAsciiNegate)

      next_is_from_word = @nfa_has_word && ::Regex::Automata.is_word_byte(byte)
      next_is_half_crlf = @nfa_has_crlf && byte == '\r'.ord.to_u8

      effective_set = state.nfa_set
      if !current_look_have.difference(state.look_have).intersection(state.look_need).empty?
        effective_set = @nfa.epsilon_closure_with_look(state.nfa_set, current_look_have)
      end

      moved = Set(StateID).new
      effective_set.each do |nfa_id|
        @nfa.transitions(nfa_id, byte).each do |next_nfa_id|
          moved.add(next_nfa_id)
        end
      end

      closure = @nfa.epsilon_closure_with_look(moved, next_look_have)
      next_id = if closure.empty?
                  StateID.new(-1)
                else
                  add_state(closure, next_look_have, next_is_from_word, next_is_half_crlf)
                end

      state.transitions[byte] = next_id
      next_id
    end

    private def add_state(nfa_set : Set(StateID), look_have : Regex::Automata::LookSet, is_from_word : Bool, is_half_crlf : Bool) : StateID
      key = {nfa_set, look_have, is_from_word, is_half_crlf}
      if existing = @state_map[key]?
        return existing
      end

      closure = @nfa.epsilon_closure_with_look(nfa_set, look_have)
      key = {closure, look_have, is_from_word, is_half_crlf}
      if existing = @state_map[key]?
        return existing
      end

      look_need = Regex::Automata::LookSet.new
      matches = [] of PatternID
      closure.each do |nfa_id|
        nfa_state = @nfa.states[nfa_id.to_i]
        if nfa_state.is_a?(Regex::Automata::NFA::Look)
          look_need = look_need.union(look_from_nfa_kind(nfa_state.kind))
        elsif nfa_state.is_a?(Regex::Automata::NFA::Match) && nfa_state.next.nil?
          matches << nfa_state.pattern_id
        end
      end
      matches.uniq!
      matches.sort!

      id = StateID.new(@states.size)
      @states << LazyState.new(id, closure, look_have, is_from_word, is_half_crlf, look_need, matches)
      @state_map[key] = id
      id
    end

    private def look_from_nfa_kind(kind : Regex::Automata::NFA::Look::Kind) : Regex::Automata::LookSet
      case kind
      when Regex::Automata::NFA::Look::Kind::Start
        Regex::Automata::LookSet.from_look(Regex::Automata::Look::StartLF).insert(Regex::Automata::Look::StartCRLF)
      when Regex::Automata::NFA::Look::Kind::End
        Regex::Automata::LookSet.from_look(Regex::Automata::Look::EndLF).insert(Regex::Automata::Look::EndCRLF)
      when Regex::Automata::NFA::Look::Kind::WordBoundaryAscii
        Regex::Automata::LookSet.from_look(Regex::Automata::Look::WordAscii)
      when Regex::Automata::NFA::Look::Kind::NonWordBoundaryAscii
        Regex::Automata::LookSet.from_look(Regex::Automata::Look::WordAsciiNegate)
      when Regex::Automata::NFA::Look::Kind::WordBoundaryUnicode
        Regex::Automata::LookSet.from_look(Regex::Automata::Look::WordUnicode)
      when Regex::Automata::NFA::Look::Kind::NonWordBoundaryUnicode
        Regex::Automata::LookSet.from_look(Regex::Automata::Look::WordUnicodeNegate)
      when Regex::Automata::NFA::Look::Kind::StartText
        Regex::Automata::LookSet.from_look(Regex::Automata::Look::Start)
      when Regex::Automata::NFA::Look::Kind::EndText, Regex::Automata::NFA::Look::Kind::EndTextWithNewline
        Regex::Automata::LookSet.from_look(Regex::Automata::Look::End)
      else
        Regex::Automata::LookSet.new
      end
    end

    private def analyze_nfa_look_requirements
      @nfa.states.each do |state|
        next unless state.is_a?(Regex::Automata::NFA::Look)
        case state.kind
        when Regex::Automata::NFA::Look::Kind::WordBoundaryAscii,
             Regex::Automata::NFA::Look::Kind::NonWordBoundaryAscii,
             Regex::Automata::NFA::Look::Kind::WordBoundaryUnicode,
             Regex::Automata::NFA::Look::Kind::NonWordBoundaryUnicode
          @nfa_has_word = true
        when Regex::Automata::NFA::Look::Kind::Start, Regex::Automata::NFA::Look::Kind::End
          @nfa_has_crlf = true
        end
      end
    end

    private def valid_nfa_start(start : StateID, fallback : StateID? = nil) : StateID
      return start if start.to_i >= 0 && start.to_i < @nfa.states.size
      fallback || StateID.new(0)
    end
  end
end
