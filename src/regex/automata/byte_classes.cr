require "./byte_set"
require "./errors"

module Regex::Automata
  struct Unit
    @kind : Symbol
    @value : UInt16

    private def initialize(@kind : Symbol, @value : UInt16)
    end

    def self.u8(byte : UInt8) : Unit
      new(:u8, byte.to_u16)
    end

    def self.eoi(num_byte_equiv_classes : Int) : Unit
      raise "max number of byte-based equivalent classes is 256, but got #{num_byte_equiv_classes}" if num_byte_equiv_classes > 256

      new(:eoi, num_byte_equiv_classes.to_u16)
    end

    def as_u8 : UInt8?
      @kind == :u8 ? @value.to_u8 : nil
    end

    def as_eoi : UInt16?
      @kind == :eoi ? @value : nil
    end

    def as_usize : Int32
      @value.to_i
    end

    def is_byte(byte : UInt8) : Bool
      as_u8 == byte
    end

    def is_eoi : Bool
      @kind == :eoi
    end

    def is_word_byte : Bool
      as_u8.try { |byte| Regex::Automata::Utf8.is_word_byte(byte) } || false
    end

    def inspect(io : IO) : Nil
      if byte = as_u8
        if byte == ' '.ord.to_u8
          io << "' '"
        elsif byte >= 0x20_u8 && byte <= 0x7E_u8
          io << byte.chr
        else
          io << "\\x"
          io << '0' if byte < 16
          byte.to_s(io, 16, upcase: true)
        end
      else
        io << "EOI"
      end
    end
  end

  struct ByteClasses
    @classes : StaticArray(UInt8, 256)

    def initialize
      @classes = StaticArray(UInt8, 256).new(0_u8)
    end

    private def initialize(@classes : StaticArray(UInt8, 256))
    end

    def self.empty : ByteClasses
      new
    end

    def self.singletons : ByteClasses
      classes = empty
      256.times do |byte|
        classes.set(byte.to_u8, byte.to_u8)
      end
      classes
    end

    def self.identity : ByteClasses
      singletons
    end

    def self.from_bytes(slice : Bytes, _endian : Symbol = :little) : Tuple(ByteClasses, Int32)
      raise DeserializeError.new("buffer too small for byte class map") if slice.size < 256

      classes = ByteClasses.empty
      256.times do |byte|
        classes.set(byte.to_u8, slice[byte])
      end
      256.times do |byte|
        if classes.get(byte.to_u8) >= classes.alphabet_len - 1
          raise DeserializeError.new("found equivalence class greater than alphabet len")
        end
      end
      {classes, 256}
    end

    def self.from_dfa(dfa : DFA::DFA) : ByteClasses
      signatures = {} of Array(Int32) => UInt8
      classes = StaticArray(UInt8, 256).new(0_u8)
      next_class = 0

      256.times do |byte|
        old_class = dfa.byte_classifier[byte]
        signature = dfa.states.map { |state| state.next[old_class].to_i }
        class_id = signatures[signature]?
        if class_id.nil?
          class_id = next_class.to_u8
          signatures[signature] = class_id
          next_class += 1
        end
        classes[byte] = class_id
      end

      new(classes)
    end

    def self.from_mapping(mapping : Array(Int32), byte_class_count : Int32) : ByteClasses
      raise "byte class mapping must have 256 entries" unless mapping.size == 256

      classes = StaticArray(UInt8, 256).new(0_u8)
      mapping.each_with_index do |klass, byte|
        classes[byte] = klass.to_u8
      end
      byte_classes = new(classes)
      expected_alphabet_len = byte_class_count + 1
      if byte_classes.alphabet_len != expected_alphabet_len
        raise DeserializeError.new("byte class count mismatch: expected #{expected_alphabet_len}, got #{byte_classes.alphabet_len}")
      end
      byte_classes
    end

    def self.with_quitset(quitset : ByteSet) : ByteClasses
      return singletons if quitset.empty?

      classes = StaticArray(UInt8, 256).new(0_u8)
      next_class = 1
      256.times do |byte|
        if quitset.contains(byte.to_u8)
          classes[byte] = 0_u8
        else
          classes[byte] = next_class.to_u8
          next_class += 1
        end
      end
      new(classes)
    end

    def to_bytes(_endian : Symbol = :little) : Bytes
      bytes = Bytes.new(256)
      256.times { |byte| bytes[byte] = @classes[byte] }
      bytes
    end

    def write_to_len : Int32
      256
    end

    def set(byte : UInt8, klass : UInt8) : Nil
      @classes[byte] = klass
    end

    def get(byte : UInt8) : UInt8
      @classes[byte]
    end

    def [](byte : UInt8) : Int32
      get(byte).to_i
    end

    def [](byte : Int32) : Int32
      get(byte.to_u8).to_i
    end

    def get_by_unit(unit : Unit) : Int32
      if byte = unit.as_u8
        get(byte).to_i
      else
        unit.as_usize
      end
    end

    def eoi : Unit
      Unit.eoi(alphabet_len - 1)
    end

    def alphabet_len : Int32
      max_class = 0_u8
      256.times do |byte|
        value = @classes[byte]
        max_class = value if value > max_class
      end
      max_class.to_i + 2
    end

    def stride2 : Int32
      stride = 1
      power = 0
      while stride < alphabet_len
        stride <<= 1
        power += 1
      end
      power
    end

    def is_singleton : Bool
      alphabet_len == 257
    end

    def iter : ByteClassIter
      ByteClassIter.new(self)
    end

    def representatives(start_byte : Int32 = 0, end_byte : Int32? = nil, *, inclusive_end : Bool = false, include_eoi : Bool = true) : ByteClassRepresentatives
      start_index = start_byte.clamp(0, 256)
      final_end = if end_byte.nil?
                    nil
                  elsif inclusive_end
                    (end_byte + 1).clamp(0, 256)
                  else
                    end_byte.clamp(0, 256)
                  end
      ByteClassRepresentatives.new(self, start_index, final_end, include_eoi && final_end.nil?)
    end

    def elements(klass : Unit) : ByteClassElements
      ByteClassElements.new(self, klass)
    end

    def representative(klass : Int32) : UInt8
      256.times do |byte|
        return byte.to_u8 if @classes[byte] == klass.to_u8
      end
      raise "Byte class #{klass} has no bytes"
    end

    def inspect(io : IO) : Nil
      if is_singleton
        io << "ByteClasses({singletons})"
        return
      end

      io << "ByteClasses("
      first = true
      iter.each do |klass|
        next if klass.is_eoi

        io << ", " unless first
        first = false
        io << klass.as_usize
        io << " => ["
        ranges = element_ranges(klass)
        ranges.each_with_index do |range, i|
          io << ", " if i > 0
          start, finish = range
          if start == finish
            start.inspect(io)
          else
            start.inspect(io)
            io << "-"
            finish.inspect(io)
          end
        end
        io << "]"
      end
      io << ")"
    end

    private def element_ranges(klass : Unit) : ByteClassElementRanges
      ByteClassElementRanges.new(elements(klass))
    end
  end

  class ByteClassIter
    include Iterator(Unit)

    def initialize(@classes : ByteClasses, @index : Int32 = 0)
    end

    def next
      if @index + 1 == @classes.alphabet_len
        @index += 1
        @classes.eoi
      elsif @index < @classes.alphabet_len
        current = Unit.u8(@index.to_u8)
        @index += 1
        current
      else
        stop
      end
    end
  end

  class ByteClassRepresentatives
    include Iterator(Unit)

    def initialize(@classes : ByteClasses, @cur_byte : Int32, @end_byte : Int32?, @include_eoi : Bool, @last_class : UInt8? = nil)
    end

    def next
      while @cur_byte < (@end_byte || 256)
        byte = @cur_byte.to_u8
        klass = @classes.get(byte)
        @cur_byte += 1
        if @last_class != klass
          @last_class = klass
          return Unit.u8(byte)
        end
      end
      if @include_eoi
        @include_eoi = false
        return @classes.eoi
      end
      stop
    end
  end

  class ByteClassElements
    include Iterator(Unit)

    def initialize(@classes : ByteClasses, @klass : Unit, @byte : Int32 = 0)
    end

    def next
      while @byte < 256
        current = @byte.to_u8
        @byte += 1
        if @klass.is_byte(@classes.get(current))
          return Unit.u8(current)
        end
      end
      if @byte < 257
        @byte += 1
        return Unit.eoi(256) if @klass.is_eoi
      end
      stop
    end
  end

  private class ByteClassElementRanges
    include Iterator(Tuple(Unit, Unit))

    def initialize(@elements : ByteClassElements, @range : Tuple(Unit, Unit)? = nil)
    end

    def next
      loop do
        element = @elements.next
        if element.is_a?(Iterator::Stop) && !@range.nil?
          range = @range.not_nil!
          @range = nil
          return range
        end
        return stop if element.is_a?(Iterator::Stop)

        current = element.as(Unit)
        case range = @range
        when Nil
          @range = {current, current}
        else
          start_unit, end_unit = range
          if end_unit.as_usize + 1 != current.as_usize || current.is_eoi
            @range = {current, current}
            return {start_unit, end_unit}
          end
          @range = {start_unit, current}
        end
      end
    end
  end

  class ByteClassSet
    def self.empty : ByteClassSet
      new(ByteSet.empty)
    end

    private def initialize(@set : ByteSet)
    end

    def set_range(start : UInt8, finish : UInt8) : Nil
      if start > 0
        @set.add(start - 1)
      end
      @set.add(finish)
    end

    def add_set(set : ByteSet) : Nil
      set.iter_ranges.each do |range|
        start, finish = range
        set_range(start, finish)
      end
    end

    def byte_classes : ByteClasses
      classes = ByteClasses.empty
      klass = 0_u8
      byte = 0_u8
      loop do
        classes.set(byte, klass)
        break if byte == 255_u8

        klass += 1_u8 if @set.contains(byte)
        byte += 1_u8
      end
      classes
    end
  end
end
