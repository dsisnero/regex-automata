require "./errors"

module Regex::Automata
  # Look-around assertion.
  #
  # An assertion matches at a position between characters in a haystack.
  # Namely, it does not actually "consume" any input as most parts of a regular
  # expression do. Assertions are a way of stating that some property must be
  # true at a particular point during matching.
  enum Look : UInt32
    Start                = 1 << 0
    End                  = 1 << 1
    StartLF              = 1 << 2
    EndLF                = 1 << 3
    StartCRLF            = 1 << 4
    EndCRLF              = 1 << 5
    WordAscii            = 1 << 6
    WordAsciiNegate      = 1 << 7
    WordUnicode          = 1 << 8
    WordUnicodeNegate    = 1 << 9
    WordStartAscii       = 1 << 10
    WordEndAscii         = 1 << 11
    WordStartUnicode     = 1 << 12
    WordEndUnicode       = 1 << 13
    WordStartHalfAscii   = 1 << 14
    WordEndHalfAscii     = 1 << 15
    WordStartHalfUnicode = 1 << 16
    WordEndHalfUnicode   = 1 << 17

    def reversed : Look
      case self
      when Start                then End
      when End                  then Start
      when StartLF              then EndLF
      when EndLF                then StartLF
      when StartCRLF            then EndCRLF
      when EndCRLF              then StartCRLF
      when WordAscii            then WordAscii
      when WordAsciiNegate      then WordAsciiNegate
      when WordUnicode          then WordUnicode
      when WordUnicodeNegate    then WordUnicodeNegate
      when WordStartAscii       then WordEndAscii
      when WordEndAscii         then WordStartAscii
      when WordStartUnicode     then WordEndUnicode
      when WordEndUnicode       then WordStartUnicode
      when WordStartHalfAscii   then WordEndHalfAscii
      when WordEndHalfAscii     then WordStartHalfAscii
      when WordStartHalfUnicode then WordEndHalfUnicode
      when WordEndHalfUnicode   then WordStartHalfUnicode
      else
        self
      end
    end

    def as_repr : UInt32
      value
    end

    def self.from_repr(repr : UInt32) : Look?
      case repr
      when 0b00_0000_0000_0000_0001_u32 then Start
      when 0b00_0000_0000_0000_0010_u32 then End
      when 0b00_0000_0000_0000_0100_u32 then StartLF
      when 0b00_0000_0000_0000_1000_u32 then EndLF
      when 0b00_0000_0000_0001_0000_u32 then StartCRLF
      when 0b00_0000_0000_0010_0000_u32 then EndCRLF
      when 0b00_0000_0000_0100_0000_u32 then WordAscii
      when 0b00_0000_0000_1000_0000_u32 then WordAsciiNegate
      when 0b00_0000_0001_0000_0000_u32 then WordUnicode
      when 0b00_0000_0010_0000_0000_u32 then WordUnicodeNegate
      when 0b00_0000_0100_0000_0000_u32 then WordStartAscii
      when 0b00_0000_1000_0000_0000_u32 then WordEndAscii
      when 0b00_0001_0000_0000_0000_u32 then WordStartUnicode
      when 0b00_0010_0000_0000_0000_u32 then WordEndUnicode
      when 0b00_0100_0000_0000_0000_u32 then WordStartHalfAscii
      when 0b00_1000_0000_0000_0000_u32 then WordEndHalfAscii
      when 0b01_0000_0000_0000_0000_u32 then WordStartHalfUnicode
      when 0b10_0000_0000_0000_0000_u32 then WordEndHalfUnicode
      else
        nil
      end
    end

    def as_char : Char
      case self
      when Start                then 'A'
      when End                  then 'z'
      when StartLF              then '^'
      when EndLF                then '$'
      when StartCRLF            then 'r'
      when EndCRLF              then 'R'
      when WordAscii            then 'b'
      when WordAsciiNegate      then 'B'
      when WordUnicode          then '𝛃'
      when WordUnicodeNegate    then '𝚩'
      when WordStartAscii       then '<'
      when WordEndAscii         then '>'
      when WordStartUnicode     then '〈'
      when WordEndUnicode       then '〉'
      when WordStartHalfAscii   then '◁'
      when WordEndHalfAscii     then '▷'
      when WordStartHalfUnicode then '◀'
      when WordEndHalfUnicode   then '▶'
      else
        raise "unreachable look assertion: #{self}"
      end
    end
  end

  struct LookSet
    include Enumerable(Look)

    getter bits : UInt32

    def initialize(@bits : UInt32 = 0_u32)
    end

    def self.empty : LookSet
      new(0_u32)
    end

    def self.full : LookSet
      new(UInt32::MAX)
    end

    def self.singleton(look : Look) : LookSet
      empty.insert(look)
    end

    def self.from_look(look : Look) : LookSet
      singleton(look)
    end

    def len : Int32
      @bits.popcount.to_i32
    end

    def size : Int32
      len
    end

    def is_empty : Bool
      @bits == 0_u32
    end

    def empty? : Bool
      is_empty
    end

    def contains(look : Look) : Bool
      (@bits & look.as_repr) != 0_u32
    end

    def includes?(look : Look) : Bool
      contains(look)
    end

    def contains_anchor : Bool
      contains_anchor_haystack || contains_anchor_line
    end

    def contains_anchor? : Bool
      contains_anchor
    end

    def contains_anchor_haystack : Bool
      contains(Look::Start) || contains(Look::End)
    end

    def contains_anchor_line : Bool
      contains(Look::StartLF) ||
        contains(Look::EndLF) ||
        contains(Look::StartCRLF) ||
        contains(Look::EndCRLF)
    end

    def contains_anchor_line? : Bool
      contains_anchor_line
    end

    def contains_anchor_lf : Bool
      contains(Look::StartLF) || contains(Look::EndLF)
    end

    def contains_anchor_crlf : Bool
      contains(Look::StartCRLF) || contains(Look::EndCRLF)
    end

    def contains_anchor_crlf? : Bool
      contains_anchor_crlf
    end

    def contains_word : Bool
      contains_word_unicode || contains_word_ascii
    end

    def contains_word? : Bool
      contains_word
    end

    def contains_word_unicode : Bool
      contains(Look::WordUnicode) ||
        contains(Look::WordUnicodeNegate) ||
        contains(Look::WordStartUnicode) ||
        contains(Look::WordEndUnicode) ||
        contains(Look::WordStartHalfUnicode) ||
        contains(Look::WordEndHalfUnicode)
    end

    def contains_word_unicode? : Bool
      contains_word_unicode
    end

    def contains_word_ascii : Bool
      contains(Look::WordAscii) ||
        contains(Look::WordAsciiNegate) ||
        contains(Look::WordStartAscii) ||
        contains(Look::WordEndAscii) ||
        contains(Look::WordStartHalfAscii) ||
        contains(Look::WordEndHalfAscii)
    end

    def contains_word_ascii? : Bool
      contains_word_ascii
    end

    def iter : LookSetIter
      LookSetIter.new(self)
    end

    def each(& : Look ->) : Nil
      iterator = iter
      iterator.each do |look|
        yield look
      end
    end

    def insert(look : Look) : LookSet
      LookSet.new(@bits | look.as_repr)
    end

    def set_insert(look : Look) : Nil
      @bits |= look.as_repr
    end

    def remove(look : Look) : LookSet
      LookSet.new(@bits & ~look.as_repr)
    end

    def set_remove(look : Look) : Nil
      @bits &= ~look.as_repr
    end

    def subtract(other : LookSet) : LookSet
      LookSet.new(@bits & ~other.bits)
    end

    def difference(other : LookSet) : LookSet
      subtract(other)
    end

    def set_subtract(other : LookSet) : Nil
      @bits &= ~other.bits
    end

    def union(other : LookSet) : LookSet
      LookSet.new(@bits | other.bits)
    end

    def set_union(other : LookSet) : Nil
      @bits |= other.bits
    end

    def intersect(other : LookSet) : LookSet
      LookSet.new(@bits & other.bits)
    end

    def intersection(other : LookSet) : LookSet
      intersect(other)
    end

    def set_intersect(other : LookSet) : Nil
      @bits &= other.bits
    end

    def symmetric_difference(other : LookSet) : LookSet
      LookSet.new(@bits ^ other.bits)
    end

    def subset?(other : LookSet) : Bool
      (@bits & ~other.bits) == 0_u32
    end

    def superset?(other : LookSet) : Bool
      other.subset?(self)
    end

    def |(other : LookSet) : LookSet
      union(other)
    end

    def &(other : LookSet) : LookSet
      intersect(other)
    end

    def -(other : LookSet) : LookSet
      subtract(other)
    end

    def ^(other : LookSet) : LookSet
      symmetric_difference(other)
    end

    def to_u32 : UInt32
      @bits
    end

    def to_u64 : UInt64
      @bits.to_u64
    end

    def self.from_u32(bits : UInt32) : LookSet
      new(bits)
    end

    def self.new(bits : UInt64)
      new(bits.to_u32)
    end

    def self.read_repr(slice : Bytes) : LookSet
      raise IndexError.new if slice.size < 4

      LookSet.new(IO::ByteFormat::SystemEndian.decode(UInt32, slice[0, 4]))
    end

    def write_repr(slice : Bytes) : Nil
      raise IndexError.new if slice.size < 4

      IO::ByteFormat::SystemEndian.encode(@bits, slice[0, 4])
    end

    def available : Nil
      UnicodeWordBoundaryError.check if contains_word_unicode
    end

    def inspect(io : IO) : Nil
      if is_empty
        io << "∅"
        return
      end

      each do |look|
        io << look.as_char
      end
    end

    def to_s(io : IO) : Nil
      inspect(io)
    end
  end

  class LookSetIter
    include Iterator(Look)

    def initialize(@set : LookSet)
    end

    def next
      return stop if @set.is_empty

      mask = @set.bits
      bit = 0
      while (mask & 1_u32) == 0_u32
        mask >>= 1
        bit += 1
      end
      look = Look.from_repr(1_u32 << bit)
      return stop if look.nil?

      @set = @set.remove(look)
      look
    end
  end

  struct LookMatcher
    @line_terminator : UInt8

    def initialize(@line_terminator : UInt8 = '\n'.ord.to_u8)
    end

    def set_line_terminator(byte : UInt8) : self
      @line_terminator = byte
      self
    end

    def get_line_terminator : UInt8
      @line_terminator
    end

    def matches(look : Look, haystack : Bytes, at : Int32) : Bool
      case look
      when Look::Start                then is_start(haystack, at)
      when Look::End                  then is_end(haystack, at)
      when Look::StartLF              then is_start_lf(haystack, at)
      when Look::EndLF                then is_end_lf(haystack, at)
      when Look::StartCRLF            then is_start_crlf(haystack, at)
      when Look::EndCRLF              then is_end_crlf(haystack, at)
      when Look::WordAscii            then is_word_ascii(haystack, at)
      when Look::WordAsciiNegate      then is_word_ascii_negate(haystack, at)
      when Look::WordUnicode          then is_word_unicode(haystack, at)
      when Look::WordUnicodeNegate    then is_word_unicode_negate(haystack, at)
      when Look::WordStartAscii       then is_word_start_ascii(haystack, at)
      when Look::WordEndAscii         then is_word_end_ascii(haystack, at)
      when Look::WordStartUnicode     then is_word_start_unicode(haystack, at)
      when Look::WordEndUnicode       then is_word_end_unicode(haystack, at)
      when Look::WordStartHalfAscii   then is_word_start_half_ascii(haystack, at)
      when Look::WordEndHalfAscii     then is_word_end_half_ascii(haystack, at)
      when Look::WordStartHalfUnicode then is_word_start_half_unicode(haystack, at)
      when Look::WordEndHalfUnicode   then is_word_end_half_unicode(haystack, at)
      else
        raise "unreachable look assertion: #{look}"
      end
    end

    def matches_set(set : LookSet, haystack : Bytes, at : Int32) : Bool
      if set.contains(Look::Start) && !is_start(haystack, at)
        return false
      end
      if set.contains(Look::End) && !is_end(haystack, at)
        return false
      end
      if set.contains(Look::StartLF) && !is_start_lf(haystack, at)
        return false
      end
      if set.contains(Look::EndLF) && !is_end_lf(haystack, at)
        return false
      end
      if set.contains(Look::StartCRLF) && !is_start_crlf(haystack, at)
        return false
      end
      if set.contains(Look::EndCRLF) && !is_end_crlf(haystack, at)
        return false
      end
      if set.contains(Look::WordAscii) && !is_word_ascii(haystack, at)
        return false
      end
      if set.contains(Look::WordAsciiNegate) && !is_word_ascii_negate(haystack, at)
        return false
      end
      if set.contains(Look::WordUnicode) && !is_word_unicode(haystack, at)
        return false
      end
      if set.contains(Look::WordUnicodeNegate) && !is_word_unicode_negate(haystack, at)
        return false
      end
      if set.contains(Look::WordStartAscii) && !is_word_start_ascii(haystack, at)
        return false
      end
      if set.contains(Look::WordEndAscii) && !is_word_end_ascii(haystack, at)
        return false
      end
      if set.contains(Look::WordStartUnicode) && !is_word_start_unicode(haystack, at)
        return false
      end
      if set.contains(Look::WordEndUnicode) && !is_word_end_unicode(haystack, at)
        return false
      end
      if set.contains(Look::WordStartHalfAscii) && !is_word_start_half_ascii(haystack, at)
        return false
      end
      if set.contains(Look::WordEndHalfAscii) && !is_word_end_half_ascii(haystack, at)
        return false
      end
      if set.contains(Look::WordStartHalfUnicode) && !is_word_start_half_unicode(haystack, at)
        return false
      end
      if set.contains(Look::WordEndHalfUnicode) && !is_word_end_half_unicode(haystack, at)
        return false
      end
      true
    end

    def is_start(_haystack : Bytes, at : Int32) : Bool
      at == 0
    end

    def is_end(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      at == haystack.size
    end

    def is_start_lf(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      is_start(haystack, at) || haystack[at - 1] == @line_terminator
    end

    def is_end_lf(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      is_end(haystack, at) || haystack[at] == @line_terminator
    end

    def is_start_crlf(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      is_start(haystack, at) ||
        haystack[at - 1] == '\n'.ord.to_u8 ||
        (haystack[at - 1] == '\r'.ord.to_u8 && (at >= haystack.size || haystack[at] != '\n'.ord.to_u8))
    end

    def is_end_crlf(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      is_end(haystack, at) ||
        haystack[at] == '\r'.ord.to_u8 ||
        (haystack[at] == '\n'.ord.to_u8 && (at == 0 || haystack[at - 1] != '\r'.ord.to_u8))
    end

    def is_word_ascii(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      word_before = at > 0 && Regex::Automata.is_word_byte(haystack[at - 1])
      word_after = at < haystack.size && Regex::Automata.is_word_byte(haystack[at])
      word_before != word_after
    end

    def is_word_ascii_negate(haystack : Bytes, at : Int32) : Bool
      !is_word_ascii(haystack, at)
    end

    def is_word_unicode(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      word_before = IsWordChar.rev(haystack, at)
      word_after = IsWordChar.fwd(haystack, at)
      word_before != word_after
    end

    def is_word_unicode_negate(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)

      word_before = if at > 0
                      return false unless Regex::Automata::Utf8.decode_last(haystack[0, at]).is_a?(Char)
                      IsWordChar.rev(haystack, at)
                    else
                      false
                    end
      word_after = if at < haystack.size
                     return false unless Regex::Automata::Utf8.decode(haystack[at, haystack.size - at]).is_a?(Char)
                     IsWordChar.fwd(haystack, at)
                   else
                     false
                   end
      word_before == word_after
    end

    def is_word_start_ascii(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      word_before = at > 0 && Regex::Automata.is_word_byte(haystack[at - 1])
      word_after = at < haystack.size && Regex::Automata.is_word_byte(haystack[at])
      !word_before && word_after
    end

    def is_word_end_ascii(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      word_before = at > 0 && Regex::Automata.is_word_byte(haystack[at - 1])
      word_after = at < haystack.size && Regex::Automata.is_word_byte(haystack[at])
      word_before && !word_after
    end

    def is_word_start_unicode(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      word_before = IsWordChar.rev(haystack, at)
      word_after = IsWordChar.fwd(haystack, at)
      !word_before && word_after
    end

    def is_word_end_unicode(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      word_before = IsWordChar.rev(haystack, at)
      word_after = IsWordChar.fwd(haystack, at)
      word_before && !word_after
    end

    def is_word_start_half_ascii(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      word_before = at > 0 && Regex::Automata.is_word_byte(haystack[at - 1])
      !word_before
    end

    def is_word_end_half_ascii(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      word_after = at < haystack.size && Regex::Automata.is_word_byte(haystack[at])
      !word_after
    end

    def is_word_start_half_unicode(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      word_before = if at > 0
                      return false unless Regex::Automata::Utf8.decode_last(haystack[0, at]).is_a?(Char)
                      IsWordChar.rev(haystack, at)
                    else
                      false
                    end
      !word_before
    end

    def is_word_end_half_unicode(haystack : Bytes, at : Int32) : Bool
      ensure_valid_offset!(haystack, at)
      word_after = if at < haystack.size
                     return false unless Regex::Automata::Utf8.decode(haystack[at, haystack.size - at]).is_a?(Char)
                     IsWordChar.fwd(haystack, at)
                   else
                     false
                   end
      !word_after
    end

    private def ensure_valid_offset!(haystack : Bytes, at : Int32) : Nil
      raise IndexError.new if at < 0 || at > haystack.size
    end
  end

  class UnicodeWordBoundaryError < Error
    MESSAGE = "Unicode-aware \\b and \\B are unavailable because the requisite data tables are missing, please enable the unicode-word-boundary feature"

    def initialize
      super(MESSAGE)
    end

    def self.check : Nil
    end
  end

  private module IsWordChar
    def self.fwd(haystack : Bytes, at : Int32) : Bool
      case result = Regex::Automata::Utf8.decode(haystack[at, haystack.size - at])
      when Char
        Regex::Syntax.try_is_word_character(result)
      else
        false
      end
    end

    def self.rev(haystack : Bytes, at : Int32) : Bool
      case result = Regex::Automata::Utf8.decode_last(haystack[0, at])
      when Char
        Regex::Syntax.try_is_word_character(result)
      else
        false
      end
    end
  end

  def self.is_word_byte(byte : UInt8) : Bool
    Utf8.is_word_byte(byte)
  end
end
