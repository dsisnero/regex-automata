module Regex::Automata::Meta
  module StopAt
    extend self

    def dfa_try_search_half_fwd(
      dfa : ::Regex::Automata::DFA::DFA,
      input : ::Regex::Automata::Input,
    ) : ::Regex::Automata::HalfMatch | Int32 | RetryFailError
      sid = dfa.start_state_forward(input)
      return RetryFailError.from_match_error(sid) if sid.is_a?(::Regex::Automata::MatchError)

      current = sid.as(::Regex::Automata::StateID)
      mat = nil.as(::Regex::Automata::HalfMatch?)
      at = input.start
      while at < input.end
        current = dfa.next_state(current, input.haystack[at])
        if dfa.is_special_state?(current)
          if dfa.is_match_state?(current)
            mat = ::Regex::Automata::HalfMatch.new(dfa.match_pattern(current, 0), at)
            return mat if input.earliest
            if dfa.is_accel_state?(current)
              needs = dfa.accelerator(current)
              at = ::Regex::Automata.find_fwd(needs, input.haystack, at) || input.end
              next
            end
          elsif dfa.is_accel_state?(current)
            needs = dfa.accelerator(current)
            at = ::Regex::Automata.find_fwd(needs, input.haystack, at) || input.end
            next
          elsif dfa.is_dead_state?(current)
            return mat || at
          elsif dfa.is_quit_state?(current)
            return RetryFailError.new(at)
          end
        end
        at += 1
      end

      eoi = dfa_eoi_fwd(dfa, input, current, mat)
      return eoi if eoi.is_a?(RetryFailError)
      mat = eoi
      mat || at
    end

    def hybrid_try_search_half_fwd(
      dfa : ::Regex::Automata::Hybrid::DFA,
      cache : ::Regex::Automata::Hybrid::Cache,
      input : ::Regex::Automata::Input,
    ) : ::Regex::Automata::HalfMatch | Int32 | RetryFailError
      sid = dfa.start_state_forward(cache, input)
      return RetryFailError.from_match_error(sid) if sid.is_a?(::Regex::Automata::MatchError)

      current = sid.as(::Regex::Automata::Hybrid::LazyStateID)
      mat = nil.as(::Regex::Automata::HalfMatch?)
      at = input.start
      while at < input.end
        next_state = dfa.next_state(cache, current, input.haystack[at])
        return RetryFailError.new(at) if next_state.is_a?(::Regex::Automata::Hybrid::CacheError)
        current = next_state.as(::Regex::Automata::Hybrid::LazyStateID)
        if current.is_match
          mat = ::Regex::Automata::HalfMatch.new(dfa.match_pattern(cache, current, 0), at)
          return mat if input.earliest
        elsif current.is_dead
          return mat || at
        elsif current.is_quit
          return RetryFailError.new(at)
        end
        at += 1
      end

      next_state = if byte = input.haystack[input.end]?
                     dfa.next_state(cache, current, byte)
                   else
                     dfa.next_eoi_state(cache, current)
                   end
      return RetryFailError.new(input.end) if next_state.is_a?(::Regex::Automata::Hybrid::CacheError)
      current = next_state.as(::Regex::Automata::Hybrid::LazyStateID)
      if current.is_match
        mat = ::Regex::Automata::HalfMatch.new(dfa.match_pattern(cache, current, 0), input.end)
      elsif current.is_quit && input.end < input.haystack.size
        return RetryFailError.new(input.end)
      end
      mat || at
    end

    private def dfa_eoi_fwd(
      dfa : ::Regex::Automata::DFA::DFA,
      input : ::Regex::Automata::Input,
      current : ::Regex::Automata::StateID,
      mat : ::Regex::Automata::HalfMatch?,
    ) : ::Regex::Automata::HalfMatch? | RetryFailError
      sp = input.get_span
      if byte = input.haystack[sp.end]?
        current = dfa.next_state(current, byte)
        if dfa.is_match_state?(current)
          mat = ::Regex::Automata::HalfMatch.new(dfa.match_pattern(current, 0), sp.end)
        elsif dfa.is_quit_state?(current)
          return RetryFailError.new(sp.end)
        end
      else
        current = dfa.next_eoi_state(current)
        if dfa.is_match_state?(current)
          mat = ::Regex::Automata::HalfMatch.new(dfa.match_pattern(current, 0), input.haystack.size)
        end
      end
      mat
    end
  end
end
