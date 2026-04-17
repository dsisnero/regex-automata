module Regex::Automata
  # Special represents the identifiers in a DFA that correspond to "special"
  # states. If a state is one or more of the following, then it is considered
  # special:
  #
  # * dead - A non-matching state where all outgoing transitions lead back to
  #   itself. There is only one of these, regardless of whether minimization
  #   has run. The dead state always has an ID of 0. i.e., It is always the
  #   first state in a DFA.
  # * quit - A state that is entered whenever a byte is seen that should cause
  #   a DFA to give up and stop searching. This results in a MatchError::quit
  #   error being returned at search time. The default configuration for a DFA
  #   has no quit bytes, which means this state is unreachable by default,
  #   although it is always present for reasons of implementation simplicity.
  #   This state is only reachable when the caller configures the DFA to quit
  #   on certain bytes. There is always exactly one of these states and it
  #   is always the second state.
  # * match - An accepting state, i.e., indicative of a match. There may be
  #   zero or more of these states.
  # * accelerated - A state where all of its outgoing transitions, except a
  #   few, loop back to itself. These states are candidates for acceleration
  #   via memchr during search. There may be zero or more of these states.
  # * start - A non-matching state that indicates where the automaton should
  #   start during a search. There is always at least one starting state and
  #   all are guaranteed to be non-match states.
  #
  # These are not mutually exclusive categories.
  #
  # The main problem we want to solve here is the *fast* detection of whether
  # a state is special or not. And we also want to do this while storing as
  # little extra data as possible. AND we want to be able to quickly determine
  # which categories a state falls into above if it is special.
  #
  # We achieve this by essentially shuffling all special states to the beginning
  # of a DFA. That is, all special states appear before every other non-special
  # state. By representing special states this way, we can determine whether a
  # state is special or not by a single comparison, where special.max is the
  # identifier of the last special state in the DFA:
  #
  #     if current_state <= special.max:
  #         ... do something with special state

  # Dead state ID (always 0)
  DEAD_STATE_ID = StateID.new(0)

  # Quit state ID
  QUIT_STATE_ID = StateID.new(1)

  # Special state ranges for a DFA
  struct Special
    # The identifier of the last special state in a DFA. A state is special
    # if and only if its identifier is less than or equal to `max`.
    property max : StateID

    # The identifier of the quit state in a DFA. (There is no analogous field
    # for the dead state since the dead state's ID is always zero, regardless
    # of state ID size.)
    property quit_id : StateID

    # The identifier of the first match state.
    property min_match : StateID

    # The identifier of the last match state.
    property max_match : StateID

    # The identifier of the first accelerated state.
    property min_accel : StateID

    # The identifier of the last accelerated state.
    property max_accel : StateID

    # The identifier of the first start state.
    property min_start : StateID

    # The identifier of the last start state.
    property max_start : StateID

    # Creates a new set of special ranges for a DFA. All ranges are initially
    # set to only contain the dead state. This is interpreted as an empty
    # range.
    def self.new : Special
      Special.new(
        max: DEAD_STATE_ID,
        quit_id: DEAD_STATE_ID,
        min_match: DEAD_STATE_ID,
        max_match: DEAD_STATE_ID,
        min_accel: DEAD_STATE_ID,
        max_accel: DEAD_STATE_ID,
        min_start: DEAD_STATE_ID,
        max_start: DEAD_STATE_ID
      )
    end

    def initialize(
      @max : StateID,
      @quit_id : StateID,
      @min_match : StateID,
      @max_match : StateID,
      @min_accel : StateID,
      @max_accel : StateID,
      @min_start : StateID,
      @max_start : StateID,
    )
    end

    # Remaps all of the special state identifiers using the function given.
    def remap(&map : StateID -> StateID) : Special
      Special.new(
        max: map.call(@max),
        quit_id: map.call(@quit_id),
        min_match: map.call(@min_match),
        max_match: map.call(@max_match),
        min_accel: map.call(@min_accel),
        max_accel: map.call(@max_accel),
        min_start: map.call(@min_start),
        max_start: map.call(@max_start)
      )
    end

    # Returns true if and only if the given state ID is a special state.
    def is_special_state?(id : StateID) : Bool
      id <= @max
    end

    # Returns true if and only if the given state ID is a dead state.
    # The dead state always has an ID of 0.
    def is_dead_state?(id : StateID) : Bool
      id == DEAD_STATE_ID
    end

    # Returns true if and only if the given state ID is a quit state.
    def is_quit_state?(id : StateID) : Bool
      id == @quit_id
    end

    # Returns true if and only if the given state ID is a match state.
    def is_match_state?(id : StateID) : Bool
      @min_match <= id && id <= @max_match
    end

    # Returns true if and only if the given state ID is an accelerated state.
    def is_accel_state?(id : StateID) : Bool
      @min_accel <= id && id <= @max_accel
    end

    # Returns true if and only if the given state ID is a start state.
    def is_start_state?(id : StateID) : Bool
      @min_start <= id && id <= @max_start
    end

    # Returns the total number of match states.
    def match_len : Int32
      if @max_match < @min_match
        0
      else
        (@max_match.to_i - @min_match.to_i) + 1
      end
    end

    # Returns the total number of accelerated states.
    def accel_len : Int32
      if @max_accel < @min_accel
        0
      else
        (@max_accel.to_i - @min_accel.to_i) + 1
      end
    end

    # Returns the total number of start states.
    def start_len : Int32
      if @max_start < @min_start
        0
      else
        (@max_start.to_i - @min_start.to_i) + 1
      end
    end

    # Returns true if there are no match states.
    def no_match_states? : Bool
      @max_match < @min_match
    end

    # Returns true if there are no accelerated states.
    def no_accel_states? : Bool
      @max_accel < @min_accel
    end

    # Returns true if there are no start states.
    def no_start_states? : Bool
      @max_start < @min_start
    end

    # Sets the quit state ID.
    def set_quit_id(id : StateID)
      @quit_id = id
      update_max
    end

    # Removes start states from the set of special states.
    #
    # This is used when 'specialize_start_states' is disabled. When start states
    # are not specialized, they are not considered "special" and thus do not
    # appear in the contiguous region of special states at the beginning of the
    # DFA. This in turn means that 'is_special_state' will return false for
    # start states.
    #
    # This is useful when there is no prefilter. If there's no prefilter, then
    # there's no reason to specialize start states. But if we don't specialize
    # start states, then we probably don't want them to be considered special
    # since being special would mean that we waste time checking whether we're
    # in a start state during a search.
    def set_no_special_start_states
      # Recalculate max special state ID excluding start states
      candidates = [@quit_id, @max_match, @max_accel]
      @max = candidates.max? || DEAD_STATE_ID

      # Reset start state range to empty
      @min_start = DEAD_STATE_ID
      @max_start = DEAD_STATE_ID
    end

    # Adds a match state with the given ID.
    def add_match(id : StateID)
      if no_match_states?
        @min_match = id
        @max_match = id
      else
        if id < @min_match
          @min_match = id
        elsif id > @max_match
          @max_match = id
        end
      end
      update_max
    end

    # Adds an accelerated state with the given ID.
    def add_accel(id : StateID)
      if no_accel_states?
        @min_accel = id
        @max_accel = id
      else
        if id < @min_accel
          @min_accel = id
        elsif id > @max_accel
          @max_accel = id
        end
      end
      update_max
    end

    # Adds a start state with the given ID.
    def add_start(id : StateID)
      if no_start_states?
        @min_start = id
        @max_start = id
      else
        if id < @min_start
          @min_start = id
        elsif id > @max_start
          @max_start = id
        end
      end
      update_max
    end

    # Updates the maximum special state ID.
    private def update_max
      candidates = [@quit_id, @max_match, @max_accel, @max_start]
      @max = candidates.max
    end

    # Serializes the special states to bytes.
    def write_to(buf : Bytes) : Int32
      # Simple serialization: write all IDs as 4-byte integers
      offset = 0
      [@max, @quit_id, @min_match, @max_match, @min_accel, @max_accel, @min_start, @max_start].each do |id|
        buf[offset] = (id.to_i >> 24).to_u8
        buf[offset + 1] = (id.to_i >> 16).to_u8
        buf[offset + 2] = (id.to_i >> 8).to_u8
        buf[offset + 3] = id.to_i.to_u8
        offset += 4
      end
      offset
    end

    # Deserializes special states from bytes.
    def self.from_bytes(buf : Bytes) : Special?
      return nil if buf.size < 32 # 8 IDs * 4 bytes each

      ids = Array(StateID).new(8)
      offset = 0
      8.times do
        id = (buf[offset].to_i32 << 24) | (buf[offset + 1].to_i32 << 16) | (buf[offset + 2].to_i32 << 8) | buf[offset + 3].to_i32
        ids << StateID.new(id)
        offset += 4
      end

      Special.new(
        max: ids[0],
        quit_id: ids[1],
        min_match: ids[2],
        max_match: ids[3],
        min_accel: ids[4],
        max_accel: ids[5],
        min_start: ids[6],
        max_start: ids[7]
      )
    end
  end
end
