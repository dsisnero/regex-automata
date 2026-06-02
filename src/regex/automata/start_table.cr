require "./errors"
require "./search"
require "./start_config"
require "./types"

module Regex::Automata
  enum Start
    NonWordByte
    WordByte
    Text
    LineLF
    LineCR
    CustomLineTerminator

    def self.len : Int32
      6
    end

    def as_u8 : UInt8
      to_i.to_u8
    end

    def as_usize : Int32
      to_i32
    end
  end

  struct StartByteMap
    @map : StaticArray(Start, 256)

    def initialize(@map : StaticArray(Start, 256))
    end

    def self.new(lookm : LookMatcher) : StartByteMap
      map = StaticArray(Start, 256).new(Start::NonWordByte)
      map['\n'.ord] = Start::LineLF
      map['\r'.ord] = Start::LineCR
      map['_'.ord] = Start::WordByte

      ('0'.ord..'9'.ord).each { |byte| map[byte] = Start::WordByte }
      ('A'.ord..'Z'.ord).each { |byte| map[byte] = Start::WordByte }
      ('a'.ord..'z'.ord).each { |byte| map[byte] = Start::WordByte }

      lineterm = lookm.get_line_terminator
      if lineterm != '\r'.ord.to_u8 && lineterm != '\n'.ord.to_u8
        map[lineterm] = Start::CustomLineTerminator
      end
      StartByteMap.new(map)
    end

    def get(byte : UInt8) : Start
      @map[byte]
    end
  end

  # Dense DFA start state metadata.
  #
  # The Rust implementation stores a richer matrix of starts for different
  # contexts. This port currently models the anchored/unanchored start states
  # that the DFA builder materializes and centralizes the policy logic here so
  # the DFA API no longer reaches into raw instance variables directly.
  struct StartTable
    getter kind : StartKind
    getter dead : StateID
    getter unanchored : StateID
    getter anchored : StateID
    getter universal_start_unanchored : StateID?
    getter universal_start_anchored : StateID?
    getter unanchored_states : Hash(Start, StateID)
    getter anchored_states : Hash(Start, StateID)
    getter pattern_states : Hash(PatternID, Hash(Start, StateID))

    def initialize(@kind : StartKind, @unanchored : StateID, @anchored : StateID, unanchored_states : Hash(Start, StateID)? = nil, anchored_states : Hash(Start, StateID)? = nil, pattern_states : Hash(PatternID, Hash(Start, StateID))? = nil, @universal_start_unanchored : StateID? = nil, @universal_start_anchored : StateID? = nil, @dead : StateID = StateID.new(0))
      @unanchored_states = unanchored_states || default_states(@unanchored)
      @anchored_states = anchored_states || default_states(@anchored)
      @pattern_states = pattern_states || {} of PatternID => Hash(Start, StateID)
      @universal_start_unanchored ||= compute_universal_start(@unanchored_states, Anchored::No)
      @universal_start_anchored ||= compute_universal_start(@anchored_states, Anchored::Yes)
    end

    def start(anchored : Anchored) : StateID | StartError
      start(anchored, Start::Text, nil)
    end

    def start(anchored : Anchored, start : Start, pattern : PatternID? = nil) : StateID | StartError
      case anchored
      when Anchored::No
        return UnsupportedAnchoredStartError.new(anchored) if @kind == StartKind::Anchored
        @unanchored_states[start]? || @unanchored
      when Anchored::Yes
        return UnsupportedAnchoredStartError.new(anchored) if @kind == StartKind::Unanchored
        @anchored_states[start]? || @anchored
      when Anchored::Pattern
        return UnsupportedAnchoredStartError.new(anchored, pattern) unless pattern
        return UnsupportedAnchoredStartError.new(anchored, pattern) if @pattern_states.empty?
        states = @pattern_states[pattern]?
        return @dead unless states
        states[start]? || states[Start::Text]? || UnsupportedAnchoredStartError.new(anchored, pattern)
      else
        UnsupportedAnchoredStartError.new(anchored, pattern)
      end
    end

    def universal_start(anchored : Anchored) : StateID?
      case anchored
      when Anchored::No
        @universal_start_unanchored
      when Anchored::Yes
        @universal_start_anchored
      else
        nil
      end
    end

    def start_state?(id : StateID) : Bool
      @unanchored_states.values.includes?(id) ||
        @anchored_states.values.includes?(id) ||
        @pattern_states.values.any? { |states| states.values.includes?(id) }
    end

    def remap(&block : StateID -> StateID) : StartTable
      unanchored = yield @unanchored
      anchored = yield @anchored
      unanchored_states = @unanchored_states.transform_values { |id| yield id }
      anchored_states = @anchored_states.transform_values { |id| yield id }
      pattern_states = @pattern_states.transform_values do |states|
        states.transform_values { |id| yield id }
      end
      universal_unanchored = @universal_start_unanchored.try { |id| yield id }
      universal_anchored = @universal_start_anchored.try { |id| yield id }

      StartTable.new(
        @kind,
        unanchored,
        anchored,
        unanchored_states,
        anchored_states,
        pattern_states,
        universal_unanchored,
        universal_anchored,
        yield @dead
      )
    end

    def self.from_look_behind(byte : UInt8?) : Start
      return Start::Text if byte.nil?

      StartByteMap.new(LookMatcher.new).get(byte)
    end

    private def default_states(id : StateID) : Hash(Start, StateID)
      {
        Start::NonWordByte          => id,
        Start::WordByte             => id,
        Start::Text                 => id,
        Start::LineLF               => id,
        Start::LineCR               => id,
        Start::CustomLineTerminator => id,
      }
    end

    private def compute_universal_start(states : Hash(Start, StateID), anchored : Anchored) : StateID?
      case anchored
      when Anchored::No
        return nil if @kind == StartKind::Anchored
      when Anchored::Yes
        return nil if @kind == StartKind::Unanchored
      else
        return nil
      end

      ids = states.values.uniq
      ids.size == 1 ? ids.first : nil
    end
  end
end
