module Regex::Automata::Determinize
  def self.next(
    nfa : ::Regex::Automata::NFA::NFA,
    match_kind : ::Regex::Automata::MatchKind,
    sparses : ::Regex::Automata::SparseSets,
    stack : Array(::Regex::Automata::StateID),
    state : State,
    unit : ::Regex::Automata::Unit,
    empty_builder : StateBuilderEmpty,
  ) : StateBuilderNFA
    sparses.clear
    rev = nfa.is_reverse
    lookm = nfa.look_matcher

    state.iter_nfa_state_ids do |nfa_id|
      sparses.set1.insert(nfa_id)
    end

    unless state.look_need.empty?
      look_have = state.look_have
      case unit.as_u8
      when '\r'.ord.to_u8
        look_have = look_have.insert(::Regex::Automata::Look::EndCRLF) if !rev || !state.is_half_crlf?
      when '\n'.ord.to_u8
        look_have = look_have.insert(::Regex::Automata::Look::EndCRLF) if rev || !state.is_half_crlf?
      when Nil
        look_have = look_have
          .insert(::Regex::Automata::Look::End)
          .insert(::Regex::Automata::Look::EndLF)
          .insert(::Regex::Automata::Look::EndCRLF)
      end
      look_have = look_have.insert(::Regex::Automata::Look::EndLF) if unit.is_byte(lookm.get_line_terminator)
      if state.is_half_crlf? &&
         ((rev && !unit.is_byte('\r'.ord.to_u8)) || (!rev && !unit.is_byte('\n'.ord.to_u8)))
        look_have = look_have.insert(::Regex::Automata::Look::StartCRLF)
      end
      if state.is_from_word? == unit.is_word_byte
        look_have = look_have
          .insert(::Regex::Automata::Look::WordAsciiNegate)
          .insert(::Regex::Automata::Look::WordUnicodeNegate)
      else
        look_have = look_have
          .insert(::Regex::Automata::Look::WordAscii)
          .insert(::Regex::Automata::Look::WordUnicode)
      end
      unless unit.is_word_byte
        look_have = look_have
          .insert(::Regex::Automata::Look::WordEndHalfAscii)
          .insert(::Regex::Automata::Look::WordEndHalfUnicode)
      end
      if state.is_from_word? && !unit.is_word_byte
        look_have = look_have
          .insert(::Regex::Automata::Look::WordEndAscii)
          .insert(::Regex::Automata::Look::WordEndUnicode)
      elsif !state.is_from_word? && unit.is_word_byte
        look_have = look_have
          .insert(::Regex::Automata::Look::WordStartAscii)
          .insert(::Regex::Automata::Look::WordStartUnicode)
      end

      unless ((look_have - state.look_have) & state.look_need).empty?
        sparses.set1.each do |nfa_id|
          epsilon_closure(nfa, nfa_id, look_have, stack, sparses.set2)
        end
        sparses.swap
        sparses.set2.clear
      end
    end

    builder = empty_builder.into_matches
    if nfa.look_set_any.contains_anchor_line && unit.is_byte(lookm.get_line_terminator)
      builder.set_look_have { |have| have.insert(::Regex::Automata::Look::StartLF) }
    end
    if nfa.look_set_any.contains_anchor_crlf &&
       ((rev && unit.is_byte('\r'.ord.to_u8)) || (!rev && unit.is_byte('\n'.ord.to_u8)))
      builder.set_look_have { |have| have.insert(::Regex::Automata::Look::StartCRLF) }
    end
    if nfa.look_set_any.contains_word && !unit.is_word_byte
      builder.set_look_have do |have|
        have.insert(::Regex::Automata::Look::WordStartHalfAscii)
          .insert(::Regex::Automata::Look::WordStartHalfUnicode)
      end
    end

    sparses.set1.each do |nfa_id|
      case nfa_state = nfa.state(nfa_id)
      when ::Regex::Automata::NFA::Union,
           ::Regex::Automata::NFA::BinaryUnion,
           ::Regex::Automata::NFA::Fail,
           ::Regex::Automata::NFA::Look,
           ::Regex::Automata::NFA::Capture,
           ::Regex::Automata::NFA::Empty
      when ::Regex::Automata::NFA::Match
        builder.add_match_pattern_id(nfa_state.pattern_id)
        break unless match_kind == ::Regex::Automata::MatchKind::All
      when ::Regex::Automata::NFA::ByteRange
        if nfa_state.trans.matches_unit(unit)
          epsilon_closure(nfa, nfa_state.trans.next, builder.look_have, stack, sparses.set2)
        end
      when ::Regex::Automata::NFA::Sparse
        if next_id = nfa_state.matches_unit(unit)
          epsilon_closure(nfa, next_id, builder.look_have, stack, sparses.set2)
        end
      end
    end

    unless sparses.set2.is_empty
      builder.set_is_from_word if nfa.look_set_any.contains_word && unit.is_word_byte
      if nfa.look_set_any.contains_anchor_crlf &&
         ((rev && unit.is_byte('\n'.ord.to_u8)) || (!rev && unit.is_byte('\r'.ord.to_u8)))
        builder.set_is_half_crlf
      end
    end

    builder_nfa = builder.into_nfa
    add_nfa_states(nfa, sparses.set2, builder_nfa)
    builder_nfa
  end

  def self.epsilon_closure(
    nfa : ::Regex::Automata::NFA::NFA,
    start_nfa_id : ::Regex::Automata::StateID,
    look_have : ::Regex::Automata::LookSet,
    stack : Array(::Regex::Automata::StateID),
    set : ::Regex::Automata::SparseSet,
  ) : Nil
    raise "epsilon_closure scratch stack must be empty" unless stack.empty?

    unless nfa.state(start_nfa_id).is_epsilon
      set.insert(start_nfa_id)
      return
    end

    stack << start_nfa_id
    until stack.empty?
      id = stack.pop
      loop do
        break unless id
        current_id = id
        break unless set.insert(current_id)

        case state = nfa.state(current_id)
        when ::Regex::Automata::NFA::ByteRange,
             ::Regex::Automata::NFA::Sparse,
             ::Regex::Automata::NFA::Fail,
             ::Regex::Automata::NFA::Match
          break
        when ::Regex::Automata::NFA::Look
          break unless look_matches?(state.kind, look_have)
          id = state.next
        when ::Regex::Automata::NFA::Union
          next_id = state.alternates[0]?
          break unless next_id
          state.alternates[1..].reverse_each { |alt| stack << alt }
          id = next_id
        when ::Regex::Automata::NFA::BinaryUnion
          stack << state.alt2
          id = state.alt1
        when ::Regex::Automata::NFA::Capture,
             ::Regex::Automata::NFA::Empty
          id = state.next
        end
      end
    end
  end

  def self.add_nfa_states(
    nfa : ::Regex::Automata::NFA::NFA,
    set : ::Regex::Automata::SparseSet,
    builder : StateBuilderNFA,
  ) : Nil
    set.each do |nfa_id|
      case state = nfa.state(nfa_id)
      when ::Regex::Automata::NFA::ByteRange,
           ::Regex::Automata::NFA::Sparse,
           ::Regex::Automata::NFA::Union,
           ::Regex::Automata::NFA::BinaryUnion,
           ::Regex::Automata::NFA::Fail,
           ::Regex::Automata::NFA::Match
        builder.add_nfa_state_id(nfa_id)
      when ::Regex::Automata::NFA::Look
        builder.add_nfa_state_id(nfa_id)
        builder.set_look_need { |need| need | look_set_from_kind(state.kind) }
      when ::Regex::Automata::NFA::Capture,
           ::Regex::Automata::NFA::Empty
      end
    end
    builder.set_look_have { |_| ::Regex::Automata::LookSet.empty } if builder.look_need.empty?
  end

  def self.set_lookbehind_from_start(
    nfa : ::Regex::Automata::NFA::NFA,
    start : ::Regex::Automata::Start,
    builder : StateBuilderMatches,
  ) : Nil
    rev = nfa.is_reverse
    lineterm = nfa.look_matcher.get_line_terminator
    lookset = nfa.look_set_any

    case start
    when ::Regex::Automata::Start::NonWordByte
      if lookset.contains_word
        builder.set_look_have do |have|
          have.insert(::Regex::Automata::Look::WordStartHalfAscii)
            .insert(::Regex::Automata::Look::WordStartHalfUnicode)
        end
      end
    when ::Regex::Automata::Start::WordByte
      builder.set_is_from_word if lookset.contains_word
    when ::Regex::Automata::Start::Text
      builder.set_look_have { |have| have.insert(::Regex::Automata::Look::Start) } if lookset.contains_anchor_haystack
      if lookset.contains_anchor_line
        builder.set_look_have do |have|
          have.insert(::Regex::Automata::Look::StartLF)
            .insert(::Regex::Automata::Look::StartCRLF)
        end
      end
      if lookset.contains_word
        builder.set_look_have do |have|
          have.insert(::Regex::Automata::Look::WordStartHalfAscii)
            .insert(::Regex::Automata::Look::WordStartHalfUnicode)
        end
      end
    when ::Regex::Automata::Start::LineLF
      if rev
        builder.set_is_half_crlf if lookset.contains_anchor_crlf
        builder.set_look_have { |have| have.insert(::Regex::Automata::Look::StartLF) } if lookset.contains_anchor_line
      else
        builder.set_look_have { |have| have.insert(::Regex::Automata::Look::StartCRLF) } if lookset.contains_anchor_line
      end
      if lookset.contains_anchor_line && lineterm == '\n'.ord.to_u8
        builder.set_look_have { |have| have.insert(::Regex::Automata::Look::StartLF) }
      end
      if lookset.contains_word
        builder.set_look_have do |have|
          have.insert(::Regex::Automata::Look::WordStartHalfAscii)
            .insert(::Regex::Automata::Look::WordStartHalfUnicode)
        end
      end
    when ::Regex::Automata::Start::LineCR
      if lookset.contains_anchor_crlf
        if rev
          builder.set_look_have { |have| have.insert(::Regex::Automata::Look::StartCRLF) }
        else
          builder.set_is_half_crlf
        end
      end
      if lookset.contains_anchor_line && lineterm == '\r'.ord.to_u8
        builder.set_look_have { |have| have.insert(::Regex::Automata::Look::StartLF) }
      end
      if lookset.contains_word
        builder.set_look_have do |have|
          have.insert(::Regex::Automata::Look::WordStartHalfAscii)
            .insert(::Regex::Automata::Look::WordStartHalfUnicode)
        end
      end
    when ::Regex::Automata::Start::CustomLineTerminator
      builder.set_look_have { |have| have.insert(::Regex::Automata::Look::StartLF) } if lookset.contains_anchor_line
      if lookset.contains_word
        if ::Regex::Automata::Utf8.is_word_byte(lineterm)
          builder.set_is_from_word
        else
          builder.set_look_have do |have|
            have.insert(::Regex::Automata::Look::WordStartHalfAscii)
              .insert(::Regex::Automata::Look::WordStartHalfUnicode)
          end
        end
      end
    end
  end

  private def self.look_matches?(
    kind : ::Regex::Automata::NFA::Look::Kind,
    look_have : ::Regex::Automata::LookSet,
  ) : Bool
    case kind
    when ::Regex::Automata::NFA::Look::Kind::StartLF
      look_have.includes?(::Regex::Automata::Look::StartLF)
    when ::Regex::Automata::NFA::Look::Kind::EndLF
      look_have.includes?(::Regex::Automata::Look::EndLF)
    when ::Regex::Automata::NFA::Look::Kind::StartCRLF
      look_have.includes?(::Regex::Automata::Look::StartCRLF)
    when ::Regex::Automata::NFA::Look::Kind::EndCRLF
      look_have.includes?(::Regex::Automata::Look::EndCRLF)
    when ::Regex::Automata::NFA::Look::Kind::WordBoundaryAscii
      look_have.includes?(::Regex::Automata::Look::WordAscii)
    when ::Regex::Automata::NFA::Look::Kind::NonWordBoundaryAscii
      look_have.includes?(::Regex::Automata::Look::WordAsciiNegate)
    when ::Regex::Automata::NFA::Look::Kind::WordBoundaryUnicode
      look_have.includes?(::Regex::Automata::Look::WordUnicode)
    when ::Regex::Automata::NFA::Look::Kind::NonWordBoundaryUnicode
      look_have.includes?(::Regex::Automata::Look::WordUnicodeNegate)
    when ::Regex::Automata::NFA::Look::Kind::StartText
      look_have.includes?(::Regex::Automata::Look::Start)
    when ::Regex::Automata::NFA::Look::Kind::EndText,
         ::Regex::Automata::NFA::Look::Kind::EndTextWithNewline
      look_have.includes?(::Regex::Automata::Look::End)
    else
      false
    end
  end

  private def self.look_set_from_kind(kind : ::Regex::Automata::NFA::Look::Kind) : ::Regex::Automata::LookSet
    case kind
    when ::Regex::Automata::NFA::Look::Kind::StartLF
      ::Regex::Automata::LookSet.singleton(::Regex::Automata::Look::StartLF)
    when ::Regex::Automata::NFA::Look::Kind::EndLF
      ::Regex::Automata::LookSet.singleton(::Regex::Automata::Look::EndLF)
    when ::Regex::Automata::NFA::Look::Kind::StartCRLF
      ::Regex::Automata::LookSet.singleton(::Regex::Automata::Look::StartCRLF)
    when ::Regex::Automata::NFA::Look::Kind::EndCRLF
      ::Regex::Automata::LookSet.singleton(::Regex::Automata::Look::EndCRLF)
    when ::Regex::Automata::NFA::Look::Kind::WordBoundaryAscii
      ::Regex::Automata::LookSet.singleton(::Regex::Automata::Look::WordAscii)
    when ::Regex::Automata::NFA::Look::Kind::NonWordBoundaryAscii
      ::Regex::Automata::LookSet.singleton(::Regex::Automata::Look::WordAsciiNegate)
    when ::Regex::Automata::NFA::Look::Kind::WordBoundaryUnicode
      ::Regex::Automata::LookSet.singleton(::Regex::Automata::Look::WordUnicode)
    when ::Regex::Automata::NFA::Look::Kind::NonWordBoundaryUnicode
      ::Regex::Automata::LookSet.singleton(::Regex::Automata::Look::WordUnicodeNegate)
    when ::Regex::Automata::NFA::Look::Kind::StartText
      ::Regex::Automata::LookSet.singleton(::Regex::Automata::Look::Start)
    when ::Regex::Automata::NFA::Look::Kind::EndText,
         ::Regex::Automata::NFA::Look::Kind::EndTextWithNewline
      ::Regex::Automata::LookSet.singleton(::Regex::Automata::Look::End)
    else
      ::Regex::Automata::LookSet.empty
    end
  end
end
