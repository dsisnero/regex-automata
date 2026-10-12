module Regex::Automata::Empty
  # Mirrors util/empty.rs for low-level DFA half-match searches. The caller
  # invokes this only when UTF-8 mode is enabled and the NFA can match empty.
  def self.skip_splits_fwd(input : Input, initial : HalfMatch, &find : Input -> HalfMatch? | MatchError) : HalfMatch? | MatchError
    skip_splits(input, initial, true, &find)
  end

  def self.skip_splits_rev(input : Input, initial : HalfMatch, &find : Input -> HalfMatch? | MatchError) : HalfMatch? | MatchError
    skip_splits(input, initial, false, &find)
  end

  private def self.skip_splits(input : Input, initial : HalfMatch, forward : Bool, &find : Input -> HalfMatch? | MatchError) : HalfMatch? | MatchError
    return input.is_char_boundary(initial.offset) ? initial : nil if input.get_anchored != Anchored::No

    result = initial
    search = input.clone
    until input.is_char_boundary(result.offset)
      if forward
        search.set_start(search.start + 1)
      else
        return nil if search.end == 0
        search.set_end(search.end - 1)
      end
      return nil if search.is_done

      next_result = yield search
      return next_result unless next_result.is_a?(HalfMatch)
      result = next_result
    end
    result
  end
end
