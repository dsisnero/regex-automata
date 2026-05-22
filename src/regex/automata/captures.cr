require "./search"
require "./types"

module Regex::Automata
  class GroupInfoError < Error
  end

  class GroupInfo
    getter names_by_pattern : Array(Array(String?))

    @name_to_index_by_pattern : Array(Hash(String, Int32))
    @explicit_slot_starts : Array(Int32)

    def self.empty : GroupInfo
      new([] of Array(String?))
    end

    def initialize(@names_by_pattern : Array(Array(String?)))
      @name_to_index_by_pattern = [] of Hash(String, Int32)
      @explicit_slot_starts = [] of Int32
      validate!
      build_indexes!
      build_slot_starts!
    end

    def to_index(pid : PatternID, name : String) : Int32?
      @name_to_index_by_pattern[pid.to_i]?.try(&.[name]?)
    end

    def to_name(pid : PatternID, group_index : Int32) : String?
      return nil if group_index < 0

      @names_by_pattern[pid.to_i]?.try(&.[group_index]?)
    end

    def pattern_names(pid : PatternID) : GroupInfoPatternNames
      GroupInfoPatternNames.new(@names_by_pattern[pid.to_i]? || [] of String?)
    end

    def all_names : GroupInfoAllNames
      GroupInfoAllNames.new(self)
    end

    def slots(pid : PatternID, group_index : Int32) : Tuple(Int32, Int32)?
      start = slot(pid, group_index)
      start ? {start, start + 1} : nil
    end

    def slot(pid : PatternID, group_index : Int32) : Int32?
      return nil if group_index < 0 || group_index >= group_len(pid)

      pattern_index = pid.to_i
      if group_index == 0
        pattern_index * 2
      else
        @explicit_slot_starts[pattern_index] + ((group_index - 1) * 2)
      end
    end

    def pattern_len : Int32
      @names_by_pattern.size.to_i32
    end

    def group_len(pid : PatternID) : Int32
      (@names_by_pattern[pid.to_i]?.try(&.size) || 0).to_i32
    end

    def all_group_len : Int32
      @names_by_pattern.sum(&.size).to_i32
    end

    def slot_len : Int32
      all_group_len * 2
    end

    def implicit_slot_len : Int32
      pattern_len * 2
    end

    def explicit_slot_len : Int32
      slot_len - implicit_slot_len
    end

    def memory_usage : Int32
      names_bytes = @names_by_pattern.sum do |pattern|
        pattern.sum { |name| name.try(&.bytesize) || 0 }
      end
      hash_entries = @name_to_index_by_pattern.sum(&.size) * 12
      (names_bytes + hash_entries + @explicit_slot_starts.size * 4).to_i32
    end

    private def validate! : Nil
      @names_by_pattern.each_with_index do |names, pattern_index|
        pid = PatternID.new(pattern_index.to_i32)
        if names.empty?
          raise GroupInfoError.new(
            "no capturing groups found for pattern #{pid.to_i} " \
            "(either all patterns have zero groups or all patterns have at least one group)"
          )
        end
        if names[0]?
          raise GroupInfoError.new(
            "first capture group (at index 0) for pattern #{pid.to_i} has a name (it must be unnamed)"
          )
        end

        seen = Set(String).new
        names.each_with_index do |name, group_index|
          next unless name
          if seen.includes?(name)
            raise GroupInfoError.new("duplicate capture group name '#{name}' found for pattern #{pid.to_i}")
          end
          if group_index == 0
            raise GroupInfoError.new(
              "first capture group (at index 0) for pattern #{pid.to_i} has a name (it must be unnamed)"
            )
          end
          seen << name
        end
      end
    end

    private def build_indexes! : Nil
      @name_to_index_by_pattern = @names_by_pattern.map do |names|
        indices = {} of String => Int32
        names.each_with_index do |name, group_index|
          next unless name
          indices[name] = group_index.to_i32
        end
        indices
      end
    end

    private def build_slot_starts! : Nil
      start = implicit_slot_len
      @explicit_slot_starts = Array(Int32).new(@names_by_pattern.size, 0)
      @names_by_pattern.each_with_index do |names, pattern_index|
        @explicit_slot_starts[pattern_index] = start
        start += ((names.size - 1) * 2).to_i32
      end
    end
  end

  class GroupInfoPatternNames
    include Iterator(String?)

    def self.empty : GroupInfoPatternNames
      new([] of String?)
    end

    def initialize(@names : Array(String?))
      @index = 0
    end

    def next
      return stop if @index >= @names.size

      name = @names[@index]
      @index += 1
      name
    end
  end

  class GroupInfoAllNames
    include Iterator(Tuple(PatternID, Int32, String?))

    def initialize(@group_info : GroupInfo)
      @pattern_index = 0
      @group_index = 0
    end

    def next
      while @pattern_index < @group_info.names_by_pattern.size
        names = @group_info.names_by_pattern[@pattern_index]
        if @group_index < names.size
          tuple = {
            PatternID.new(@pattern_index.to_i32),
            @group_index.to_i32,
            names[@group_index],
          }
          @group_index += 1
          return tuple
        end
        @pattern_index += 1
        @group_index = 0
      end
      stop
    end
  end

  class Captures
    struct CaptureNameRef
      getter name : String

      def initialize(@name : String)
      end
    end

    getter group_info : GroupInfo
    getter slots : Array(Int32?)

    def self.all(group_info : GroupInfo) : Captures
      new(group_info, Array(Int32?).new(group_info.slot_len, nil))
    end

    def self.matches(group_info : GroupInfo) : Captures
      new(group_info, Array(Int32?).new(group_info.pattern_len * 2, nil))
    end

    def self.empty(group_info : GroupInfo) : Captures
      new(group_info, [] of Int32?)
    end

    def initialize(@group_info : GroupInfo, @slots : Array(Int32?))
      @pid = nil.as(PatternID?)
    end

    def clone : Captures
      duplicated = Captures.new(@group_info, @slots.dup)
      duplicated.set_pattern(@pid)
      duplicated
    end

    def is_match : Bool
      !@pid.nil?
    end

    def pattern : PatternID?
      @pid
    end

    def pattern_len : Int32
      @group_info.pattern_len
    end

    def get_match : Match?
      pid = pattern
      span = get_group(0)
      return nil unless pid && span

      Match.new(pid, span.start, span.end)
    end

    def get_group(index : Int32) : Span?
      pid = pattern
      return nil unless pid

      slots = if @group_info.pattern_len == 1
                {index * 2, (index * 2) + 1}
              else
                @group_info.slots(pid, index)
              end
      return nil unless slots
      slot_start, slot_end = slots

      start = @slots[slot_start]?
      finish = @slots[slot_end]?
      return nil unless start && finish

      Span.new(start, finish)
    end

    def get_group_by_name(name : String) : Span?
      pid = pattern
      return nil unless pid

      index = @group_info.to_index(pid, name)
      index ? get_group(index) : nil
    end

    def iter : CapturesPatternIter
      CapturesPatternIter.new(self)
    end

    def group_len : Int32
      pid = pattern
      pid ? @group_info.group_len(pid) : 0
    end

    def interpolate_string(haystack : String, replacement : String) : String
      String.build do |io|
        interpolate_tokens(replacement) do |token|
          case token
          when String
            io << token
          when Int32
            if span = get_group(token)
              io.write(haystack.to_slice[span.start, span.length])
            end
          when CaptureNameRef
            if span = get_group_by_name(token.name)
              io.write(haystack.to_slice[span.start, span.length])
            end
          end
        end
      end
    end

    def interpolate_string_into(haystack : String, replacement : String, dst : String) : Nil
      dst << interpolate_string(haystack, replacement)
    end

    def interpolate_bytes(haystack : Bytes, replacement : Bytes) : Bytes
      dst = [] of UInt8
      interpolate_bytes_into(haystack, replacement, dst)
      Bytes.new(dst.size) { |i| dst[i] }
    end

    def interpolate_bytes_into(haystack : Bytes, replacement : Bytes, dst : Array(UInt8)) : Nil
      interpolate_tokens(String.new(replacement)) do |token|
        case token
        when String
          token.each_byte { |byte| dst << byte }
        when Int32
          if span = get_group(token)
            haystack[span.start, span.length].each { |byte| dst << byte }
          end
        when CaptureNameRef
          if span = get_group_by_name(token.name)
            haystack[span.start, span.length].each { |byte| dst << byte }
          end
        end
      end
    end

    def clear : Nil
      @pid = nil
      @slots.map! { nil }
    end

    def set_pattern(pid : PatternID?) : Nil
      @pid = pid
    end

    def slots_mut : Array(Int32?)
      @slots
    end

    def slot_len : Int32
      @slots.size.to_i32
    end

    def memory_usage : Int32
      @group_info.memory_usage + (@slots.size * sizeof(Int32)).to_i32
    end

    private def interpolate_tokens(replacement : String, & : String | Int32 | CaptureNameRef ->) : Nil
      bytes = replacement.to_slice
      literal_start = 0
      i = 0
      while i < bytes.size
        if bytes[i] == '$'.ord.to_u8
          if parsed = parse_capture_reference(bytes, i + 1)
            token, next_index = parsed
            if literal_start < i
              yield String.new(bytes[literal_start, i - literal_start])
            end
            yield token
            i = next_index
            literal_start = i
            next
          end
        end
        i += 1
      end
      if literal_start < bytes.size
        yield String.new(bytes[literal_start, bytes.size - literal_start])
      end
    end

    private def parse_capture_reference(bytes : Bytes, start_index : Int32) : Tuple(Int32 | CaptureNameRef, Int32)?
      return nil if start_index >= bytes.size

      if bytes[start_index] == '{'.ord.to_u8
        finish = start_index + 1
        while finish < bytes.size && bytes[finish] != '}'.ord.to_u8
          finish += 1
        end
        return nil if finish >= bytes.size || finish == start_index + 1

        name = String.new(bytes[start_index + 1, finish - start_index - 1])
        token = reference_token(name)
        return nil unless token
        return {token, finish + 1}
      end

      finish = start_index
      while finish < bytes.size && ascii_word?(bytes[finish])
        finish += 1
      end
      return nil if finish == start_index

      name = String.new(bytes[start_index, finish - start_index])
      token = reference_token(name)
      return nil unless token
      {token, finish}
    end

    private def reference_token(name : String) : Int32 | CaptureNameRef
      if name.each_char.all?(&.ascii_number?)
        name.to_i32
      else
        CaptureNameRef.new(name)
      end
    end

    private def ascii_word?(byte : UInt8) : Bool
      (byte >= '0'.ord.to_u8 && byte <= '9'.ord.to_u8) ||
        (byte >= 'A'.ord.to_u8 && byte <= 'Z'.ord.to_u8) ||
        (byte >= 'a'.ord.to_u8 && byte <= 'z'.ord.to_u8) ||
        byte == '_'.ord.to_u8
    end
  end

  class CapturesPatternIter
    include Iterator(Span?)

    def initialize(@captures : Captures)
      @index = 0
    end

    def next
      return stop if @index >= @captures.group_len

      span = @captures.get_group(@index)
      @index += 1
      span
    end
  end
end
