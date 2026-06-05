require "./src/regex-automata"

# List all abstract methods from Automaton
abstract_methods = [
  "next_state(current : StateID, input : UInt8) : StateID",
  "next_eoi_state(current : StateID) : StateID",
  "start_state_forward(anchored : Anchored) : StateID | MatchError",
  "start_state_reverse(anchored : Anchored) : StateID | MatchError",
  "is_special_state?(id : StateID) : Bool",
  "is_dead_state?(id : StateID) : Bool",
  "is_quit_state?(id : StateID) : Bool",
  "is_match_state?(id : StateID) : Bool",
  "is_start_state?(id : StateID) : Bool",
  "is_accel_state?(id : StateID) : Bool",
  "pattern_len : Int32",
  "match_len(id : StateID) : Int32",
  "match_pattern(id : StateID, index : Int32) : PatternID",
  "has_empty? : Bool",
  "is_utf8? : Bool",
  "is_always_start_anchored? : Bool",
  "accelerator(id : StateID) : Bytes",
  "try_search_fwd(slice : Bytes) : Tuple(Int32, Array(PatternID))? | MatchError",
  "try_search_rev(slice : Bytes) : Tuple(Int32, Array(PatternID))? | MatchError",
  "try_search_overlapping_fwd(slice : Bytes) : Array(Tuple(Int32, Array(PatternID))) | MatchError",
]

puts "Checking if DFA implements all abstract methods..."
puts "Total abstract methods: #{abstract_methods.size}"

# Try to create a DFA instance to trigger compilation check
begin
  dfa = Regex::Automata::DFA::DFA.new(
    [] of Regex::Automata::DFA::State,
    Regex::Automata::StateID.new(0),
    256
  )
  puts "✓ DFA created successfully - all abstract methods implemented!"
rescue e : Exception
  puts "✗ Error creating DFA: #{e.message}"
end
