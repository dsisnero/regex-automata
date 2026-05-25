require "./search"
require "./types"
require "./interpolate"

module Regex::Automata
  class GroupInfoError < Error
  end

  class GroupInfo
    getter names_by_pattern : Array(Array(String?))

    @name_to_index_by_pattern : Array(Hash(String, Int32))
    @slot_starts_by_pattern : Array(Array(Int32?))
    @allow_empty_patterns : Bool

    def self.empty : GroupInfo
      new([] of Array(String?), allow_empty_patterns: true)
    end

    def initialize(@names_by_pattern : Array(Array(String?)), @allow_empty_patterns : Bool = false)
      @name_to_index_by_pattern = [] of Hash(String, Int32)
      @slot_starts_by_pattern = [] of Array(Int32?)
      validate!
      build_indexes!
      build_slot_table!
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

      @slot_starts_by_pattern[pid.to_i]?.try(&.[group_index]?)
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
      @slot_starts_by_pattern.sum(&.count(&.itself)) * 2
    end

    def implicit_slot_len : Int32
      @names_by_pattern.count { |names| !names.empty? }.to_i32 * 2
    end

    def explicit_slot_len : Int32
      slot_len - implicit_slot_len
    end

    def memory_usage : Int32
      names_bytes = @names_by_pattern.sum do |pattern|
        pattern.sum { |name| name.try(&.bytesize) || 0 }
      end
      hash_entries = @name_to_index_by_pattern.sum(&.size) * 12
      slot_entries = @slot_starts_by_pattern.sum(&.size) * 4
      (names_bytes + hash_entries + slot_entries).to_i32
    end

    private def validate! : Nil
      @names_by_pattern.each_with_index do |names, pattern_index|
        pid = PatternID.new(pattern_index.to_i32)
        if names.empty?
          next if @allow_empty_patterns
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

    private def build_slot_table! : Nil
      @slot_starts_by_pattern = @names_by_pattern.map { |names| Array(Int32?).new(names.size, nil) }

      next_implicit_slot = 0
      @names_by_pattern.each_with_index do |names, pattern_index|
        next if names.empty?

        @slot_starts_by_pattern[pattern_index][0] = next_implicit_slot
        next_implicit_slot += 2
      end

      next_explicit_slot = next_implicit_slot
      @names_by_pattern.each_with_index do |names, pattern_index|
        (1...names.size).each do |group_index|
          @slot_starts_by_pattern[pattern_index][group_index] = next_explicit_slot
          next_explicit_slot += 2
        end
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
    getter group_info : GroupInfo
    getter slots : Array(Int32?)

    def self.all(group_info : GroupInfo) : Captures
      new(group_info, Array(Int32?).new(group_info.slot_len, nil))
    end

    def self.matches(group_info : GroupInfo) : Captures
      new(group_info, Array(Int32?).new(group_info.implicit_slot_len, nil))
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

      slots = @group_info.slots(pid, index)
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
      String.build do |dst|
        Interpolate.string(
          replacement,
          ->(index : Int32, io : IO) do
            if span = get_group(index)
              if match = haystack.byte_slice(span.start, span.length)
                io << match
              end
            end
            nil
          end,
          ->(name : String) { @group_info.to_index(pattern.not_nil!, name) if pattern },
          dst
        )
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
      Interpolate.bytes(
        replacement,
        ->(index : Int32, out : Array(UInt8)) do
          if span = get_group(index)
            haystack[span.start, span.length].each { |byte| out << byte }
          end
          nil
        end,
        ->(name : String) { @group_info.to_index(pattern.not_nil!, name) if pattern },
        dst
      )
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
