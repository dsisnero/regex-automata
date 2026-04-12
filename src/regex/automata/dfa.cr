require "./nfa"
require "./byte_classes"
require "./look"
require "./byte_set"
require "./config"
require "./automaton"
require "./hir_compiler"
require "set"

module Regex::Automata::DFA
  include Regex::Automata

  # Special state IDs
  DEAD_STATE_ID = StateID.new(-1)
  QUIT_STATE_ID = StateID.new(-2)

  # Check if a state ID is special (dead or quit)
  def self.special_state?(id : StateID) : Bool
    id.to_i < 0
  end

  # Check if a state ID is a dead state
  def self.dead_state?(id : StateID) : Bool
    id.to_i == -1
  end

  # Check if a state ID is a quit state
  def self.quit_state?(id : StateID) : Bool
    id.to_i == -2
  end

  # DFA state with transitions for each byte class
  class State
    getter id : StateID
    getter next : Array(StateID)    # indexed by byte class
    getter match : Array(PatternID) # empty if not accepting
    getter look_need : LookSet      # look-around assertions present in this state
    getter look_have : LookSet      # look-around assertions satisfied at this state
    getter? is_from_word : Bool     # whether previous byte was a word byte (for word boundaries)
    getter? is_half_crlf : Bool     # whether we're in a half-CRLF state (for CRLF anchors)
    property eoi_next : StateID     # transition on end-of-input (-1 = none)

    def initialize(@id : StateID, byte_classes : Int32, @look_need : LookSet = LookSet.new, @look_have : LookSet = LookSet.new, @is_from_word : Bool = false, @is_half_crlf : Bool = false)
      @next = Array.new(byte_classes, StateID.new(-1)) # -1 = no transition
      @match = [] of PatternID
      @eoi_next = StateID.new(-1)
    end

    # Create a copy of this state with new ID
    def dup(new_id : StateID) : State
      state = State.new(new_id, @next.size, @look_need, @look_have, @is_from_word, @is_half_crlf)
      state.next.replace(@next.dup)
      state.match.replace(@match.dup)
      state.eoi_next = @eoi_next
      state
    end

    def set_transition(byte_class : Int32, target : StateID)
      @next[byte_class] = target
    end

    def add_match(pattern_id : PatternID)
      # Insert in sorted order, maintaining uniqueness
      idx = @match.bsearch_index { |pid| pid >= pattern_id } || @match.size
      if idx == @match.size || @match[idx] != pattern_id
        @match.insert(idx, pattern_id)
      end
    end

    def accepting? : Bool
      !@match.empty?
    end
  end

  # Deterministic Finite Automaton
  class DFA < Regex::Automata::Automaton
    getter states : Array(State)
    getter start_unanchored : StateID
    getter start_anchored : StateID
    getter byte_classifier : ByteClasses
    # For backward compatibility, returns alphabet length
    getter byte_classes : Int32
    # Accelerator bytes for each state (empty slice if not accelerated)
    getter accelerators : Array(Bytes)
    # Prefilter for accelerating searches (optional)
    getter prefilter : Prefilter?
    # Set of bytes that cause the DFA to quit (stop searching)
    getter quitset : ByteSet
    # Various flags describing DFA behavior
    getter flags : DFAFlags

    def initialize(@states : Array(State), start_unanchored : StateID, byte_classes : ByteClasses | Int32, start_anchored : StateID? = nil, accelerators : Array(Bytes)? = nil, prefilter : Prefilter? = nil, quitset : ByteSet = ByteSet.new, flags : DFAFlags = DFAFlags.new)
      @start_unanchored = start_unanchored
      @start_anchored = start_anchored || start_unanchored
      @byte_classifier = case byte_classes
                         when ByteClasses
                           byte_classes
                         when Int32
                           ByteClasses.identity
                         else
                           raise "Unreachable"
                         end
      @byte_classes = @byte_classifier.alphabet_len
      @accelerators = accelerators || Array.new(@states.size) { Bytes.empty }
      @prefilter = prefilter
      @quitset = quitset
      @flags = flags
    end

    def start : StateID
      @start_unanchored
    end

    # Get number of states
    def size : Int32
      @states.size
    end

    # Get state by ID
    def [](id : StateID) : State
      @states[id.to_i]
    end

    # Remove dead states (unreachable or can't reach accept state)
    def remove_dead_states : DFA
      # Forward reachable from start
      forward = Set{@start_unanchored}
      stack = [@start_unanchored]
      while !stack.empty?
        state_id = stack.pop
        current_state = @states[state_id.to_i]
        current_state.next.each do |next_id|
          if next_id.to_i >= 0 && !forward.includes?(next_id)
            forward.add(next_id)
            stack.push(next_id)
          end
        end
      end

      # Backward reachable from accepting states
      backward = Set(StateID).new
      # Build reverse transitions
      reverse = Array(Set(StateID)).new(@states.size) { Set(StateID).new }
      @states.each_with_index do |state, i|
        state.next.each do |next_id|
          if next_id.to_i >= 0
            reverse[next_id.to_i].add(StateID.new(i))
          end
        end
      end

      # Start from accepting states
      stack.clear
      @states.each_with_index do |state, i|
        if state.accepting?
          state_id = StateID.new(i)
          backward.add(state_id)
          stack.push(state_id)
        end
      end

      # BFS from accepting states
      while !stack.empty?
        state_id = stack.pop
        reverse[state_id.to_i].each do |prev_id|
          unless backward.includes?(prev_id)
            backward.add(prev_id)
            stack.push(prev_id)
          end
        end
      end

      # Live states = intersection
      live = forward & backward
      return self if live.size == @states.size

      # Create mapping from old to new state IDs
      old_to_new = {} of StateID => StateID
      new_states = [] of State
      live.to_a.sort_by(&.to_i).each_with_index do |old_id, new_index|
        new_id = StateID.new(new_index)
        old_to_new[old_id] = new_id
        # Create copy of state with new ID
        old_state = @states[old_id.to_i]
        new_state = old_state.dup(new_id)
        new_states << new_state
      end

      # Update transitions in new states
      new_states.each do |state|
        state.next.each_with_index do |next_id, i|
          if next_id.to_i >= 0 && old_to_new.has_key?(next_id)
            state.next[i] = old_to_new[next_id]
          elsif next_id.to_i >= 0
            state.next[i] = StateID.new(-1)
          end
        end
      end

      # Update start state
      new_start_unanchored = old_to_new[@start_unanchored]? || StateID.new(0)
      new_start_anchored = old_to_new[@start_anchored]? || new_start_unanchored

      DFA.new(new_states, new_start_unanchored, @byte_classifier, new_start_anchored)
    end

    # Reduce byte classes using equivalence analysis
    def reduce_byte_classes : DFA
      byte_classes = ByteClasses.from_dfa(self)
      byte_classes.apply_to_dfa(self)
    end

    # Find the longest match in the input string
    # Returns tuple of (end_position, matched_pattern_ids) or nil if no match
    def find_longest_match(input : String) : Tuple(Int32, Array(PatternID))?
      find_longest_match(input.to_slice)
    end

    # Find the longest match in a byte slice
    def find_longest_match(slice : Bytes) : Tuple(Int32, Array(PatternID))?
      last_match : Tuple(Int32, Array(PatternID))? = nil
      current_state_id = @start_unanchored
      states = @states
      byte_classifier = @byte_classifier

      idx = 0
      size = slice.size

      # Process bytes in a simple loop (uncomment for unrolled version)
      while idx < size
        byte = slice[idx]
        byte_class = byte_classifier[byte]
        next_state_id = states[current_state_id.to_i].next[byte_class]
        if next_state_id.to_i < 0
          # No transition - stop searching
          break
        end

        current_state_id = next_state_id
        state = states[current_state_id.to_i]
        if state.accepting?
          last_match = {idx + 1, state.match}
        end
        idx += 1
      end

      # Check if start state is accepting (empty string match)
      if last_match.nil? && states[@start_unanchored.to_i].accepting?
        last_match = {0, states[@start_unanchored.to_i].match}
      end

      last_match
    end

    # Try to search forward, returning either a match or a MatchError
    def try_search_fwd(slice : Bytes) : Tuple(Int32, Array(PatternID)) | Nil | MatchError
      last_match : Tuple(Int32, Array(PatternID))? = nil
      current_state_id = @start_unanchored
      states = @states
      byte_classifier = @byte_classifier

      idx = 0
      size = slice.size

      while idx < size
        byte = slice[idx]
        byte_class = byte_classifier[byte]
        next_state_id = states[current_state_id.to_i].next[byte_class]

        # Check for quit state
        if ::Regex::Automata::DFA.quit_state?(next_state_id)
          return MatchError.quit(byte, idx)
        end

        if next_state_id.to_i < 0
          # No transition - stop searching
          break
        end

        current_state_id = next_state_id
        state = states[current_state_id.to_i]
        if state.accepting?
          last_match = {idx + 1, state.match}
        end
        idx += 1
      end

      # Check if start state is accepting (empty string match)
      if last_match.nil? && states[@start_unanchored.to_i].accepting?
        last_match = {0, states[@start_unanchored.to_i].match}
      end

      last_match
    end

    # Try to search in reverse, returning either a match or a MatchError
    def try_search_rev(slice : Bytes) : Tuple(Int32, Array(PatternID)) | Nil | MatchError
      last_match : Tuple(Int32, Array(PatternID))? = nil
      current_state_id = @start_unanchored
      states = @states
      byte_classifier = @byte_classifier

      idx = slice.size - 1
      while idx >= 0
        byte = slice[idx]
        byte_class = byte_classifier[byte]
        next_state_id = states[current_state_id.to_i].next[byte_class]

        # Debug: print state and transition
        if ENV["LOGOS_DEBUG_DFA_SEARCH"]?
          puts "Reverse search: idx=#{idx}, byte=#{byte}, byte_class=#{byte_class}, current_state=#{current_state_id.to_i}, next_state=#{next_state_id.to_i}"
        end

        # Check for quit state
        if ::Regex::Automata::DFA.quit_state?(next_state_id)
          return MatchError.quit(byte, idx)
        end

        if next_state_id.to_i < 0
          # No transition - stop searching
          break
        end

        current_state_id = next_state_id
        state = states[current_state_id.to_i]
        if state.accepting?
          # In reverse search, we report the start position (idx)
          last_match = {idx, state.match}
        end
        idx -= 1
      end

      # Check if start state is accepting (empty string match)
      if last_match.nil? && states[@start_unanchored.to_i].accepting?
        last_match = {slice.size, states[@start_unanchored.to_i].match}
      end

      last_match
    end

    # Get next state ID for given byte
    def next_state(current : StateID, input : UInt8) : StateID
      byte_class = @byte_classifier[input]
      next_id = @states[current.to_i].next[byte_class]
      next_id.to_i >= 0 ? next_id : StateID.new(0)
    end

    # Unsafe version of next_state that assumes valid state ID
    def next_state_unchecked(current : StateID, input : UInt8) : StateID
      byte_class = @byte_classifier[input]
      @states[current.to_i].next[byte_class]
    end

    # Get next state ID for end-of-input (EOI) transition
    def next_eoi_state(current : StateID) : StateID
      next_id = @states[current.to_i].eoi_next
      next_id.to_i >= 0 ? next_id : StateID.new(0)
    end

    # Check if state is a match state
    def match_state?(id : StateID) : Bool
      !@states[id.to_i].match.empty?
    end

    # Alias for compatibility with Rust Automaton trait
    def is_match_state?(id : StateID) : Bool
      match_state?(id)
    end

    # Check if state is a dead state
    def is_dead_state?(id : StateID) : Bool
      ::Regex::Automata::DFA.dead_state?(id)
    end

    # Check if state is a quit state
    def is_quit_state?(id : StateID) : Bool
      ::Regex::Automata::DFA.quit_state?(id)
    end

    # Check if state is a special state (dead, quit, match, start, etc.)
    def is_special_state?(id : StateID) : Bool
      id.to_i < 0 || match_state?(id) || id == @start_unanchored || id == @start_anchored
    end

    # Check if state is a start state
    def is_start_state?(id : StateID) : Bool
      id == @start_unanchored || id == @start_anchored
    end

    # Check if state is an accelerated state
    def is_accel_state?(id : StateID) : Bool
      !@accelerators[id.to_i].empty?
    end

    # Returns the number of patterns in this automaton
    def pattern_len : Int32
      1 # Single pattern for now
    end

    # Returns the number of matches in the given state
    def match_len(id : StateID) : Int32
      @states[id.to_i].match.size
    end

    # Returns the pattern ID for the match at the given index in the given state
    def match_pattern(id : StateID, index : Int32) : PatternID
      @states[id.to_i].match[index]
    end

    # Returns true if and only if this automaton is guaranteed to be valid for UTF-8 input
    def is_utf8? : Bool
      true # Assume UTF-8 for now
    end

    # Returns true if and only if this automaton is always anchored at the start
    def is_always_start_anchored? : Bool
      false # Not always anchored
    end

    # Returns the accelerator bytes for the given state
    def accelerator(id : StateID) : Bytes
      # Return accelerator bytes for the state
      @accelerators[id.to_i]
    end

    # Try to search for overlapping matches forward
    def try_search_overlapping_fwd(slice : Bytes) : Array(Tuple(Int32, Array(PatternID))) | MatchError
      [] of Tuple(Int32, Array(PatternID)) # Empty array for now
    end

    # Get universal start state for given anchored mode
    def universal_start_state(mode : Anchored) : StateID?
      case mode
      when Anchored::No
        @start_unanchored
      when Anchored::Yes
        @start_anchored
      else
        nil
      end
    end

    # Whether DFA can match empty string
    def has_empty? : Bool
      # Check if start state is a match state
      is_match_state?(@start_unanchored)
    end

    # Returns the prefilter for this DFA, if one exists
    def get_prefilter : Prefilter?
      @prefilter
    end

    # Returns the start state for the given configuration
    def start_state(config : StartConfig) : StateID | StartError
      # Check for quit bytes in look-behind
      if look_behind = config.look_behind
        if @quitset.includes?(look_behind)
          return QuitStartError.new(look_behind)
        end
      end

      # Check for unsupported anchored modes
      case config.anchored
      when Anchored::No, Anchored::Yes
        # Supported
      else
        return UnsupportedAnchoredStartError.new(config.anchored)
      end

      # Return appropriate start state
      case config.anchored
      when Anchored::No
        @start_unanchored
      when Anchored::Yes
        @start_anchored || @start_unanchored
      else
        # Should not reach here due to check above
        @start_unanchored
      end
    end

    # Returns the start state for a forward search (for backward compatibility)
    def start_state_forward_method(anchored : Anchored) : StateID
      config = StartConfig.new(nil, anchored)
      result = start_state(config)
      case result
      when StateID
        result
      when StartError
        # For backward compatibility, return start state even on error
        case anchored
        when Anchored::No
          @start_unanchored
        when Anchored::Yes
          @start_anchored || @start_unanchored
        else
          @start_unanchored
        end
      end
    end

    # Returns the start state for a reverse search (for backward compatibility)
    def start_state_reverse(anchored : Anchored) : StateID
      # For now, use same as forward
      start_state_forward_method(anchored)
    end

    # Map byte to its equivalence class
    private def byte_to_class(byte : UInt8) : Int32
      @byte_classifier[byte]
    end
  end

  # Subset construction builder
  class Builder
    @nfa : NFA::NFA?
    @dfa_states : Array(State)
    @state_map : Hash(Tuple(Set(StateID), LookSet, Bool, Bool), StateID) # (NFA state set, look_have, is_from_word, is_half_crlf) -> DFA state ID
    @byte_classes : ByteClasses
    @nfa_has_word : Bool
    @nfa_has_crlf : Bool
    @config : Config
    @quitset : ByteSet
    @hir_compiler : HirCompiler

    # Create a new builder with default configuration
    def self.new : Builder
      Builder.new(Config.new)
    end

    # Create a new builder from an NFA
    def self.from_nfa(nfa : NFA::NFA, config : Config = Config.new) : Builder
      Builder.new(config, nfa: nfa)
    end

    # Configure the builder with a new configuration
    def configure(config : Config) : Builder
      Builder.new(config, nfa: @nfa, hir_compiler: @hir_compiler)
    end

    # Configure the builder using a block
    def configure(&block : Config -> Config) : Builder
      config = block.call(@config.dup)
      Builder.new(config, nfa: @nfa, hir_compiler: @hir_compiler)
    end

    # Configure the Thompson NFA compiler
    def thompson(&block : HirCompilerConfig -> HirCompilerConfig) : Builder
      config = @config
      hir_compiler_config = HirCompilerConfig.new
      hir_compiler_config = block.call(hir_compiler_config)
      hir_compiler = HirCompiler.new(hir_compiler_config)
      Builder.new(config, nfa: @nfa, hir_compiler: hir_compiler)
    end

    def initialize(config : Config = Config.new, nfa : NFA::NFA? = nil, hir_compiler : HirCompiler? = nil, byte_classes : ByteClasses | Int32 = 256)
      @config = config
      @quitset = config.quitset
      @nfa = nfa
      @hir_compiler = hir_compiler || HirCompiler.new

      # Implicitly enable Unicode word boundaries if all non-ASCII bytes are quit bytes
      if !config.unicode_word_boundary? && all_non_ascii_bytes_are_quit?(@quitset)
        # Enable Unicode word boundaries
        @config = config.unicode_word_boundary(true)
        if ENV["LOGOS_DEBUG_DFA_BUILD"]?
          puts "Implicitly enabled Unicode word boundaries because all non-ASCII bytes are quit bytes"
        end
      end

      # Create byte classes with quit bytes in separate classes
      @byte_classes = case byte_classes
                      when ByteClasses
                        # If we already have byte classes, we need to ensure quit bytes are separate
                        # For now, just use the provided classes
                        byte_classes
                      when Int32
                        if @quitset.empty?
                          ByteClasses.identity
                        else
                          ByteClasses.with_quitset(@quitset)
                        end
                      else
                        raise "Unreachable"
                      end
      @dfa_states = [] of State
      @state_map = {} of Tuple(Set(StateID), LookSet, Bool, Bool) => StateID

      # Precompute whether NFA contains word boundary or CRLF assertions
      @nfa_has_word = false
      @nfa_has_crlf = false
      if nfa = @nfa
        nfa.states.each do |state|
          if state.is_a?(NFA::Look)
            case state.kind
            when NFA::Look::Kind::WordBoundary, NFA::Look::Kind::NonWordBoundary
              @nfa_has_word = true
            when NFA::Look::Kind::Start, NFA::Look::Kind::End
              @nfa_has_crlf = true
            when NFA::Look::Kind::StartText, NFA::Look::Kind::EndText, NFA::Look::Kind::EndTextWithNewline
              # These are start/end text anchors, not CRLF line anchors
              # CRLF anchors are not represented in NFA::Look::Kind (only Start/End)
              # We'll treat them as CRLF? Actually Start and End are line anchors (^, $) which can be CRLF-aware
              # but our NFA doesn't distinguish. We'll need to handle later.
            end
          end
        end
      end
    end

    # Build DFA from NFA using subset construction
    # Build DFA from a pattern string
    def build(pattern : String) : DFA
      # Parse pattern to HIR
      hir = Regex::Syntax::Parser.new.parse(pattern)

      # Compile HIR to NFA
      nfa = @hir_compiler.compile(hir)

      # Build DFA from NFA
      Builder.from_nfa(nfa, @config).build
    end

    # Compute accelerators for DFA states
    private def compute_accelerators(states : Array(State), byte_classes : ByteClasses) : Array(Bytes)
      accelerators = Array.new(states.size) { Bytes.empty }

      states.each_with_index do |state, idx|
        # Skip dead and quit states
        next if state.id.to_i < 0

        # Analyze if state can be accelerated
        accelerator = analyze_acceleration(state, byte_classes)
        unless accelerator.empty?
          accelerators[idx] = accelerator
        end
      end

      accelerators
    end

    # Analyze a state to see if it can be accelerated
    # Returns accelerator bytes if state can be accelerated, empty array otherwise
    # Ported from Rust's State.accelerate() method
    private def analyze_acceleration(state : State, byte_classes : ByteClasses) : Bytes
      # We just try to add bytes to our accelerator. Once adding fails
      # (because we've added too many bytes), then give up.
      accelerator_bytes = [] of UInt8

      # Check each byte class (transition)
      (0...byte_classes.alphabet_len).each do |byte_class|
        next_state = state.next[byte_class]

        # Skip self-transitions (id == self.id())
        next if next_state == state.id

        # This byte class causes exit from the state
        # Add all bytes in this equivalence class to accelerator
        (0..255).each do |byte|
          if byte_classes[byte] == byte_class
            # Check if we can add this byte
            # Max 3 bytes in accelerator (per Rust Accel::add())
            if accelerator_bytes.size >= 3
              return Bytes.empty # Too many bytes, can't accelerate
            end

            # Reject ASCII space as a poor accelerator (per Rust implementation)
            if byte == ' '.ord
              return Bytes.empty # ASCII space is a poor accelerator
            end

            # Check if byte already in accelerator (Rust asserts this doesn't happen)
            if accelerator_bytes.includes?(byte.to_u8)
              # In Rust, this would panic. We'll just skip duplicate bytes.
              next
            end

            # Add byte to accelerator
            accelerator_bytes << byte.to_u8
          end
        end
      end

      # Return accelerator if we have any bytes
      if accelerator_bytes.empty?
        Bytes.empty
      else
        # Note: Rust doesn't sort the bytes, they're added in the order encountered
        # Convert to Bytes
        slice = Bytes.new(accelerator_bytes.size)
        accelerator_bytes.each_with_index do |byte, i|
          slice[i] = byte
        end
        slice
      end
    end

    # Build DFA from the configured NFA
    def build : DFA
      raise "No NFA configured. Use build(pattern) or provide an NFA to the builder." unless @nfa

      nfa = @nfa.not_nil!
      unanchored_start_nfa = valid_nfa_start(nfa.start_unanchored)
      anchored_start_nfa = valid_nfa_start(nfa.start_anchored, fallback: unanchored_start_nfa)
      # Start with epsilon closure of NFA start states
      unanchored_start_set = nfa.epsilon_closure(Set{unanchored_start_nfa})
      anchored_start_set = nfa.epsilon_closure(Set{anchored_start_nfa})
      start_look_have = LookSet.new.insert(Look::StartLF).insert(Look::Start)
      if @nfa_has_crlf
        start_look_have = start_look_have.insert(Look::StartCRLF)
      end
      unanchored_start_id = add_dfa_state(unanchored_start_set, start_look_have, false, false)
      anchored_start_id = add_dfa_state(anchored_start_set, start_look_have, false, false)

      # Add quit state if we have quit bytes
      unless @quitset.empty?
        add_quit_state
      end

      # Process queue of unprocessed DFA states
      queue = [unanchored_start_id]
      processed = Set{unanchored_start_id}
      unless processed.includes?(anchored_start_id)
        queue << anchored_start_id
        processed.add(anchored_start_id)
      end

      if ENV["LOGOS_DEBUG_DFA_BUILD"]?
        puts "DFA build: unanchored_start_set size #{unanchored_start_set.size}, unanchored_start_id #{unanchored_start_id}, anchored_start_id #{anchored_start_id}"
      end

      while !queue.empty?
        dfa_id = queue.pop
        dfa_state = @dfa_states[dfa_id.to_i]

        if ENV["LOGOS_DEBUG_DFA_BUILD"]? && @dfa_states.size % 10 == 0
          puts "DFA build: processing state #{dfa_id.to_i}, total states #{@dfa_states.size}, queue size #{queue.size}"
        end

        # Find NFA set for this DFA state
        nfa_set = nil
        look_have = LookSet.new
        is_from_word = false
        is_half_crlf = false
        @state_map.each do |key, id|
          if id == dfa_id
            nfa_set = key[0]
            look_have = key[1]
            is_from_word = key[2]
            is_half_crlf = key[3]
            break
          end
        end
        next if nfa_set.nil? # Should not happen

                # For each byte class, compute transition
        @byte_classes.alphabet_len.times do |byte_class|
          byte = @byte_classes.representative(byte_class)
          next_set = Set(StateID).new
          current_look_have = look_have

          # Look-ahead assertions based on the current byte.
          if byte == '\n'.ord.to_u8
            current_look_have = current_look_have.insert(Look::EndLF)
            if !is_half_crlf
              current_look_have = current_look_have.insert(Look::EndCRLF)
            end
          elsif byte == '\r'.ord.to_u8
            current_look_have = current_look_have.insert(Look::EndCRLF)
          end

          if @nfa_has_crlf && is_half_crlf && byte != '\n'.ord.to_u8
            current_look_have = current_look_have.insert(Look::StartCRLF)
          end

          if @nfa_has_word
            if is_from_word != Regex::Automata.is_word_byte(byte)
              current_look_have = current_look_have.insert(Look::WordAscii).remove(Look::WordAsciiNegate)
            else
              current_look_have = current_look_have.remove(Look::WordAscii).insert(Look::WordAsciiNegate)
            end
          end

          # Update satisfied look mask for the next position
          # Start assertions (^, \A) are only true at position 0
          # After consuming a byte, we're no longer at start
          next_look_have = look_have.remove(Look::StartLF).remove(Look::Start).remove(Look::StartCRLF)

          # Start of line assertions are true after a line terminator.
          if byte == '\n'.ord.to_u8
            next_look_have = next_look_have.insert(Look::StartLF)
            if @nfa_has_crlf
              next_look_have = next_look_have.insert(Look::StartCRLF)
            end
          end

          # Word boundary assertions are computed per transition.
          next_look_have = next_look_have.remove(Look::WordAscii).remove(Look::WordAsciiNegate)

          # Determine next is_from_word flag (for word boundary detection)
          next_is_from_word = @nfa_has_word && Regex::Automata.is_word_byte(byte)
          next_is_half_crlf = @nfa_has_crlf && byte == '\r'.ord.to_u8

          # Recompute epsilon closure if new look-ahead assertions are satisfied.
          effective_nfa_set = nfa_set
          if !current_look_have.difference(look_have).intersection(dfa_state.look_need).empty?
            effective_nfa_set = nfa.epsilon_closure_with_look(nfa_set, current_look_have)
          end

          next_set.clear
          effective_nfa_set.each do |nfa_id|
            transitions = nfa.transitions(nfa_id, byte)
            transitions.each do |next_nfa_id|
              next_set.add(next_nfa_id)
            end
          end

          # Compute next set closure (needed for both quit check and regular transition)
          next_set_closure = nfa.epsilon_closure_with_look(next_set, next_look_have)

          # Check for quit bytes first (they overrule regex matching)
          if !@quitset.empty? && is_quit_byte_class?(byte_class)
            # If we have quit bytes and this byte class corresponds to a quit byte,
            # transition to quit state (overrules any regex matching)
            if ENV["LOGOS_DEBUG_DFA_BUILD"]?
              puts "Setting transition for byte class #{byte_class} to QUIT_STATE_ID for state #{dfa_id.to_i} (quit byte overrides regex)"
            end
            dfa_state.set_transition(byte_class, QUIT_STATE_ID)
          elsif !next_set_closure.empty?
            key = {next_set_closure, next_look_have, next_is_from_word, next_is_half_crlf}
            next_id = @state_map[key]?
            if next_id.nil?
              next_id = add_dfa_state(next_set, next_look_have, next_is_from_word, next_is_half_crlf)
              unless processed.includes?(next_id)
                queue << next_id
                processed.add(next_id)
              end
            end
            dfa_state.set_transition(byte_class, next_id)
          end
        end
      end

      # Compute EOI transitions for each DFA state.
      initial_size = @dfa_states.size
      (0...initial_size).each do |idx|
        nfa_set = nil
        look_have = LookSet.new
        is_from_word = false
        is_half_crlf = false
        @state_map.each do |key, id|
          if id.to_i == idx
            nfa_set = key[0]
            look_have = key[1]
            is_from_word = key[2]
            is_half_crlf = key[3]
            break
          end
        end
        next if nfa_set.nil?

        eoi_look_have = look_have.insert(Look::End).insert(Look::EndLF)
        if @nfa_has_crlf || is_half_crlf
          eoi_look_have = eoi_look_have.insert(Look::EndCRLF)
        end

        eoi_id = add_dfa_state(nfa_set, eoi_look_have, is_from_word, false)
        @dfa_states[idx].eoi_next = eoi_id
      end

      # Compute accelerators if enabled
      accelerators = if @config.accelerate?
                       compute_accelerators(@dfa_states, @byte_classes)
                     else
                       Array.new(@dfa_states.size) { Bytes.empty }
                     end

      DFA.new(@dfa_states, unanchored_start_id, @byte_classes, anchored_start_id, accelerators)
    end

    private def valid_nfa_start(start : StateID, fallback : StateID? = nil) : StateID
      return start if @nfa && start.to_i >= 0 && start.to_i < @nfa.not_nil!.states.size
      fallback || StateID.new(0)
    end

    private def add_dfa_state(nfa_set : Set(StateID), look_have : LookSet = LookSet.new, is_from_word : Bool = false, is_half_crlf : Bool = false) : StateID
      raise "No NFA configured" unless @nfa
      nfa = @nfa.not_nil!

      # First compute epsilon closure with the given satisfied look conditions
      closure = nfa.epsilon_closure_with_look(nfa_set, look_have)

      # Check if we already have a DFA state for this (closure, look_have)
      key = {closure, look_have, is_from_word, is_half_crlf}
      if existing = @state_map[key]?
        return existing
      end

      dfa_id = StateID.new(@dfa_states.size)

      # Compute look need set from NFA states that are look-around assertions
      look_need = LookSet.new
      closure.each do |nfa_id|
        nfa_state = nfa.states[nfa_id.to_i]
        if nfa_state.is_a?(NFA::Look)
          look_need = look_need.union(look_from_nfa_kind(nfa_state.kind))
        end
      end

      state = State.new(dfa_id, @byte_classes.alphabet_len, look_need, look_have, is_from_word, is_half_crlf)

      # Check if any NFA state in set is a match
      if ENV["LOGOS_DEBUG_DFA"]?
        puts "DFA state #{dfa_id.to_i}: NFA set size #{nfa_set.size}, look_need #{look_need}, look_have #{look_have}"
        nfa_set.each do |nfa_id|
          nfa_state = nfa.states[nfa_id.to_i]
          puts "  NFA state #{nfa_id.to_i}: #{nfa_state.class} #{nfa_state.is_a?(NFA::Match) ? "(match pattern #{nfa_state.pattern_id.to_i}, next=#{nfa_state.next.inspect})" : ""}"
        end
      end
      closure.each do |nfa_id|
        nfa_state = nfa.states[nfa_id.to_i]
        if nfa_state.is_a?(NFA::Match)
          # Only consider match states with no outgoing epsilon transitions as accepting
          if nfa_state.next.nil?
            if ENV["LOGOS_DEBUG_DFA"]?
              puts "DFA state #{dfa_id.to_i}: adding match for pattern #{nfa_state.pattern_id.to_i}"
            end
            state.add_match(nfa_state.pattern_id)
          else
            if ENV["LOGOS_DEBUG_DFA"]?
              puts "DFA state #{dfa_id.to_i}: skipping match for pattern #{nfa_state.pattern_id.to_i} (has epsilon transition)"
            end
          end
        end
      end

      @dfa_states << state
      @state_map[key] = dfa_id
      dfa_id
    end

    private def add_quit_state : StateID
      # Create a quit state
      quit_state_id = QUIT_STATE_ID
      quit_state = State.new(quit_state_id, @byte_classes.alphabet_len)

      # Quit state has no transitions (all go to dead state)
      @byte_classes.alphabet_len.times do |i|
        quit_state.set_transition(i, DEAD_STATE_ID)
      end

      # Add quit state to DFA states
      @dfa_states << quit_state

      quit_state_id
    end

    private def is_quit_byte_class?(byte_class : Int32) : Bool
      # Check if this byte class contains any quit bytes
      # Since we're using ByteClasses.with_quitset, all quit bytes should be in class 0
      # But we should check more carefully
      return false if @quitset.empty?

      # For now, assume quit bytes are in class 0
      # This is true if we're using ByteClasses.with_quitset
      byte_class == 0
    end

    private def look_from_nfa_kind(kind : NFA::Look::Kind) : LookSet
      case kind
      when NFA::Look::Kind::Start
        LookSet.from_look(Look::StartLF).insert(Look::StartCRLF)
      when NFA::Look::Kind::End
        LookSet.from_look(Look::EndLF).insert(Look::EndCRLF)
      when NFA::Look::Kind::WordBoundary
        if @config.unicode_word_boundary?
          LookSet.from_look(Look::WordUnicode)
        else
          LookSet.from_look(Look::WordAscii)
        end
      when NFA::Look::Kind::NonWordBoundary
        if @config.unicode_word_boundary?
          LookSet.from_look(Look::WordUnicodeNegate)
        else
          LookSet.from_look(Look::WordAsciiNegate)
        end
      when NFA::Look::Kind::StartText
        LookSet.from_look(Look::Start)
      when NFA::Look::Kind::EndText, NFA::Look::Kind::EndTextWithNewline
        LookSet.from_look(Look::End)
      else
        raise "Unreachable look kind: #{kind}"
      end
    end

    private def all_non_ascii_bytes_are_quit?(quitset : ByteSet) : Bool
      # Check if all bytes 0x80-0xFF are in the quit set
      (0x80..0xFF).all? do |b|
        quitset.includes?(b.to_u8)
      end
    end
  end
end
