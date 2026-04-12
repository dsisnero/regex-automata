module Regex::Automata::DFA
  # Returns an iterator over the matching patterns of a given dfa state.
  # Returns pattern IDs in ascending order.
  def self.iter_matches(state_id : StateID, dfa : DFA) : Array(PatternID)
    return [] of PatternID unless dfa.match_state?(state_id)

    num_matches = dfa.match_len(state_id)
    Array.new(num_matches) { |i| dfa.match_pattern(state_id, i) }
  end

  # Returns an iterator over the child states of a given dfa state.
  # Returns children in order of input byte (0..255), then eoi.
  # No deduplication of child states is performed.
  def self.iter_children(dfa : DFA, state : StateID) : Array(StateID)
    children = Array(StateID).new(257) # 256 bytes + EOI

    # Byte transitions
    256.times do |byte|
      children << dfa.next_state(state, byte.to_u8)
    end

    # EOI transition
    children << dfa.next_eoi_state(state)

    children
  end

  # This utility function returns every state accessible by the dfa
  # from a root state. Returns the states in ascending order.
  def self.get_states(dfa : DFA, root : StateID) : Array(StateID)
    states = Set(StateID).new
    states.add(root)
    explore_stack = [root]

    while !explore_stack.empty?
      state = explore_stack.pop
      iter_children(dfa, state).each do |child|
        if states.add?(child)
          explore_stack.push(child)
        end
      end
    end

    sorted = states.to_a
    sorted.sort!
    sorted
  end
end
