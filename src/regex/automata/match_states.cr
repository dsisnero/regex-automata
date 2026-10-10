require "./types"
require "./transition_table"

module Regex::Automata
  # Flattened storage for match state pattern IDs.
  #
  # Rust's dense DFA stores match metadata separately from its transition
  # table. We keep the same flattened representation here. The slice index is
  # keyed by the transition-table state index so searches avoid a hash lookup
  # when resolving a match state.
  class MatchStates
    getter pattern_len : Int32

    @state_to_match_index : Array(Int32?)
    @tt : TransitionTable?
    @slices : Array(Tuple(Int32, Int32))
    @pattern_ids : Array(PatternID)

    def self.empty(pattern_len : Int32 = 0) : MatchStates
      new([] of Int32?, [] of Tuple(Int32, Int32), [] of PatternID, pattern_len, nil)
    end

    def self.from_states(states : Array(Regex::Automata::DFA::State), tt : TransitionTable?, pattern_len : Int32? = nil) : MatchStates
      state_to_match_index = Array(Int32?).new(states.size, nil)
      slices = [] of Tuple(Int32, Int32)
      pattern_ids = [] of PatternID
      max_pattern_id = -1

      states.each_with_index do |state, index|
        state.match.each do |pattern_id|
          max_pattern_id = Math.max(max_pattern_id, pattern_id.to_i)
        end
        next if state.match.empty?

        state_to_match_index[index] = slices.size
        slices << {pattern_ids.size, state.match.size}
        pattern_ids.concat(state.match)
      end

      inferred_pattern_len = max_pattern_id >= 0 ? max_pattern_id + 1 : 0
      new(state_to_match_index, slices, pattern_ids, pattern_len || inferred_pattern_len, tt)
    end

    # Builds flattened match metadata from the ordered map form used by DFA
    # transformations. The transition table supplies premultiplied ID indexes.
    def self.from_map(matches : Hash(StateID, Array(PatternID)), pattern_len : Int32, tt : TransitionTable) : MatchStates
      state_to_match_index = Array(Int32?).new(tt.len, nil)
      slices = [] of Tuple(Int32, Int32)
      pattern_ids = [] of PatternID

      matches.keys.sort_by(&.to_i).each do |id|
        raise ArgumentError.new("invalid match state ID") unless tt.is_valid(id)
        pids = matches[id]
        pids.each do |pattern_id|
          raise ArgumentError.new("invalid pattern ID") unless 0 <= pattern_id.to_i < pattern_len
        end
        state_to_match_index[tt.to_index(id)] = slices.size
        slices << {pattern_ids.size, pids.size}
        pattern_ids.concat(pids)
      end
      new(state_to_match_index, slices, pattern_ids, pattern_len, tt)
    end

    def initialize(@state_to_match_index : Array(Int32?), @slices : Array(Tuple(Int32, Int32)), @pattern_ids : Array(PatternID), @pattern_len : Int32, @tt : TransitionTable?)
    end

    # Decodes Rust's standalone match-state payload into owned Crystal arrays.
    # The payload intentionally carries no state IDs; a containing DFA supplies
    # that association, so the returned standalone metadata has no state map.
    def self.from_bytes(slice : Bytes, endian : Symbol = :little) : Tuple(MatchStates, Int32)
      offset = 0
      state_len = read_u32(slice, offset, endian, "match state length").to_i
      offset += 4
      raise DeserializeError.new("match state offset pairs overflow") if state_len > (Int32::MAX // 2)
      slices = Array(Tuple(Int32, Int32)).new(state_len)
      state_len.times do
        start = read_u32(slice, offset, endian, "match state slices")
        offset += 4
        len = read_u32(slice, offset, endian, "match state slices")
        offset += 4
        raise DeserializeError.new("invalid match state slice") if start > Int32::MAX.to_u32 || len > Int32::MAX.to_u32
        slices << {start.to_i32, len.to_i32}
      end
      pattern_len_raw = read_u32(slice, offset, endian, "pattern length")
      offset += 4
      raise DeserializeError.new("invalid pattern length") if pattern_len_raw > Int32::MAX.to_u32
      pattern_len = pattern_len_raw.to_i32
      id_len = read_u32(slice, offset, endian, "pattern ID length").to_i
      offset += 4
      pattern_ids = Array(PatternID).new(id_len)
      id_len.times do
        value = read_u32(slice, offset, endian, "match pattern IDs")
        offset += 4
        raise DeserializeError.new("invalid pattern ID") if value > PatternID::MAX.as_u32
        pattern_ids << PatternID.new(value.to_i32)
      end
      matches = new([] of Int32?, slices, pattern_ids, pattern_len, nil)
      raise matches.validate.not_nil! if matches.validate
      {matches, offset}
    end

    def match_state?(id : StateID) : Bool
      !match_index(id).nil?
    end

    def len : Int32
      @slices.size
    end

    def pattern_len(index : Int32) : Int32
      _, len = @slices[index]
      len
    end

    def pattern_id(index : Int32, match_index : Int32) : PatternID
      start, len = @slices[index]
      raise IndexError.new unless 0 <= match_index < len

      @pattern_ids[start + match_index]
    end

    def pattern_id_slice(index : Int32) : Array(PatternID)
      start, len = @slices[index]
      @pattern_ids[start, len]
    end

    # Reconstruct match-state metadata into the builder-friendly map form.
    # Crystal retains an explicit state-index map, so this remains correct even
    # when match states are not physically contiguous.
    def to_map : Hash(StateID, Array(PatternID))
      map = Hash(StateID, Array(PatternID)).new
      @state_to_match_index.each_with_index do |match_index, state_index|
        next unless match_index

        id = if tt = @tt
               tt.to_state_id(state_index)
             else
               StateID.new(state_index)
             end
        map[id] = pattern_id_slice(match_index)
      end
      map
    end

    # Return all flattened pattern IDs as an owned snapshot.
    def pattern_ids : Array(PatternID)
      @pattern_ids.dup
    end

    # Return match-state slice offsets and lengths as an owned snapshot.
    def slices : Array(Tuple(Int32, Int32))
      @slices.dup
    end

    def match_len(id : StateID) : Int32
      index = match_index(id)
      return 0 unless index

      _, len = @slices[index]
      len
    end

    def match_pattern(id : StateID, index : Int32) : PatternID
      return PatternID.new(0) if @pattern_len == 1

      slice_index = match_index(id)
      raise IndexError.new unless slice_index

      start, len = @slices[slice_index]
      raise IndexError.new unless 0 <= index < len
      @pattern_ids[start + index]
    end

    def memory_usage : Int32
      ((@slices.size * 2 + @pattern_ids.size) * sizeof(PatternID)).to_i32
    end

    # Writes Rust's dense match-state payload: slice count and pairs, unique
    # pattern count, then flattened pattern IDs.
    def write_to(dst : Bytes, endian : Symbol = :little) : Int32
      needed = write_to_len
      raise ArgumentError.new("buffer too small for match states") if dst.size < needed

      offset = 0
      offset = write_u32(@slices.size.to_u32, dst, offset, endian)
      @slices.each do |start, len|
        offset = write_u32(start.to_u32, dst, offset, endian)
        offset = write_u32(len.to_u32, dst, offset, endian)
      end
      offset = write_u32(@pattern_len.to_u32, dst, offset, endian)
      offset = write_u32(@pattern_ids.size.to_u32, dst, offset, endian)
      @pattern_ids.each { |id| offset = write_u32(id.to_i.to_u32, dst, offset, endian) }
      offset
    end

    def write_to_len : Int32
      (3 + (@slices.size * 2) + @pattern_ids.size).to_i32 * sizeof(UInt32)
    end

    # Validate the flattened slice metadata before it is used for match
    # lookups. The containing DFA validates the state-to-match mapping.
    def validate : DeserializeError?
      unless @state_to_match_index.empty? && @tt.nil?
        return DeserializeError.generic("match state slice metadata is malformed") unless @slices.size == @state_to_match_index.compact.size
      end

      @slices.each do |start, len|
        return DeserializeError.generic("invalid pattern ID start offset") if start < 0 || start > @pattern_ids.size
        return DeserializeError.generic("invalid pattern ID length") if len < 0 || start + len > @pattern_ids.size
        @pattern_ids[start, len].each do |pattern_id|
          return DeserializeError.generic("invalid pattern ID") if pattern_id.to_i < 0 || pattern_id.to_i >= @pattern_len
        end
      end
      nil
    end

    def to_owned : MatchStates
      MatchStates.new(@state_to_match_index.dup, @slices.dup, @pattern_ids.dup, @pattern_len, @tt)
    end

    private def match_index(id : StateID) : Int32?
      state_index = if tt = @tt
                      tt.to_index(id)
                    else
                      id.to_i
                    end
      return nil if state_index < 0 || state_index >= @state_to_match_index.size

      @state_to_match_index[state_index]
    end

    private def write_u32(value : UInt32, dst : Bytes, offset : Int32, endian : Symbol) : Int32
      case endian
      when :little
        dst[offset] = (value & 0xFF).to_u8
        dst[offset + 1] = ((value >> 8) & 0xFF).to_u8
        dst[offset + 2] = ((value >> 16) & 0xFF).to_u8
        dst[offset + 3] = ((value >> 24) & 0xFF).to_u8
      when :big
        dst[offset] = ((value >> 24) & 0xFF).to_u8
        dst[offset + 1] = ((value >> 16) & 0xFF).to_u8
        dst[offset + 2] = ((value >> 8) & 0xFF).to_u8
        dst[offset + 3] = (value & 0xFF).to_u8
      else
        raise ArgumentError.new("unsupported endianness")
      end
      offset + sizeof(UInt32)
    end

    private def self.read_u32(src : Bytes, offset : Int32, endian : Symbol, label : String) : UInt32
      raise DeserializeError.new("buffer too small for #{label}") if offset < 0 || offset + 4 > src.size
      case endian
      when :little
        (0...4).reduce(0_u32) { |value, i| value | (src[offset + i].to_u32 << (i * 8)) }
      when :big
        (0...4).reduce(0_u32) { |value, i| (value << 8) | src[offset + i].to_u32 }
      else
        raise ArgumentError.new("unsupported endianness")
      end
    end
  end
end
