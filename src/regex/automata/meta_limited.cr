module Regex::Automata::Meta
  module Limited
    extend self

    def dfa_try_search_half_rev(
      dfa : ::Regex::Automata::DFA::DFA,
      input : ::Regex::Automata::Input,
      min_start : Int32,
    ) : ::Regex::Automata::HalfMatch? | RetryError
      sid = dfa.start_state_reverse(input)
      return RetryFailError.from_match_error(sid) if sid.is_a?(::Regex::Automata::MatchError)

      current = sid.as(::Regex::Automata::StateID)
      mat = nil.as(::Regex::Automata::HalfMatch?)

      if input.start == input.end
        return dfa_eoi_rev(dfa, input, current, mat)
      end

      at = input.end - 1
      loop do
        current = dfa.next_state(current, input.haystack[at])
        if dfa.is_special_state?(current)
          if dfa.is_match_state?(current)
            mat = ::Regex::Automata::HalfMatch.new(dfa.match_pattern(current, 0), at + 1)
          elsif dfa.is_dead_state?(current)
            return mat
          elsif dfa.is_quit_state?(current)
            return RetryFailError.new(at)
          end
        end
        break if at == input.start

        at -= 1
        return RetryQuadraticError.new if at < min_start
      end

      was_dead = dfa.is_dead_state?(current)
      eoi = dfa_eoi_rev(dfa, input, current, mat)
      return eoi if eoi.is_a?(RetryError)
      mat = eoi

      if at == input.start &&
         mat &&
         mat.offset > input.start &&
         !was_dead
        return RetryQuadraticError.new
      end
      mat
    end

    private def dfa_eoi_rev(
      dfa : ::Regex::Automata::DFA::DFA,
      input : ::Regex::Automata::Input,
      current : ::Regex::Automata::StateID,
      mat : ::Regex::Automata::HalfMatch?,
    ) : ::Regex::Automata::HalfMatch? | RetryError
      if input.start > 0
        byte = input.haystack[input.start - 1]
        current = dfa.next_state(current, byte)
        if dfa.is_match_state?(current)
          mat = ::Regex::Automata::HalfMatch.new(dfa.match_pattern(current, 0), input.start)
        elsif dfa.is_quit_state?(current)
          return RetryFailError.new(input.start - 1)
        end
      else
        current = dfa.next_eoi_state(current)
        if dfa.is_match_state?(current)
          mat = ::Regex::Automata::HalfMatch.new(dfa.match_pattern(current, 0), 0)
        end
      end
      mat
    end
  end
end
