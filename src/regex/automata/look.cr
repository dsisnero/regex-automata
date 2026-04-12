module Regex::Automata
  # Look-around assertion.
  #
  # An assertion matches at a position between characters in a haystack.
  # Namely, it does not actually "consume" any input as most parts of a regular
  # expression do. Assertions are a way of stating that some property must be
  # true at a particular point during matching.
  #
  # For example, `(?m)^[a-z]+$` is a pattern that:
  #
  # * Scans the haystack for a position at which `(?m:^)` is satisfied. That
  # occurs at either the beginning of the haystack, or immediately following
  # a `\n` character.
  # * Looks for one or more occurrences of `[a-z]`.
  # * Once `[a-z]+` has matched as much as it can, an overall match is only
  # reported when `[a-z]+` stops just before a `\n`.
  #
  # So in this case, `abc` and `\nabc\n` match, but `\nabc1\n` does not.
  #
  # Assertions are also called "look-around," "look-behind" and "look-ahead."
  # Specifically, some assertions are look-behind (like `^`), other assertions
  # are look-ahead (like `$`) and yet other assertions are both look-ahead and
  # look-behind (like `\b`).
  enum Look : UInt32
    # Match the beginning of text. Specifically, this matches at the starting
    # position of the input.
    Start = 1 << 0

    # Match the end of text. Specifically, this matches at the ending
    # position of the input.
    End = 1 << 1

    # Match the beginning of a line or the beginning of text. Specifically,
    # this matches at the starting position of the input, or at the position
    # immediately following a `\n` character.
    StartLF = 1 << 2

    # Match the end of a line or the end of text. Specifically, this matches
    # at the end position of the input, or at the position immediately
    # preceding a `\n` character.
    EndLF = 1 << 3

    # Match the beginning of a line or the beginning of text. Specifically,
    # this matches at the starting position of the input, or at the position
    # immediately following either a `\r` or `\n` character, but never after
    # a `\r` when a `\n` follows.
    StartCRLF = 1 << 4

    # Match the end of a line or the end of text. Specifically, this matches
    # at the end position of the input, or at the position immediately
    # preceding a `\r` or `\n` character, but never before a `\n` when a `\r`
    # precedes it.
    EndCRLF = 1 << 5

    # Match an ASCII-only word boundary. That is, this matches a position
    # where the left adjacent character and right adjacent character
    # correspond to a word and non-word or a non-word and word character.
    WordAscii = 1 << 6

    # Match an ASCII-only negation of a word boundary.
    WordAsciiNegate = 1 << 7

    # Match a Unicode-aware word boundary. That is, this matches a position
    # where the left adjacent character and right adjacent character
    # correspond to a word and non-word or a non-word and word character.
    WordUnicode = 1 << 8

    # Match a Unicode-aware negation of a word boundary.
    WordUnicodeNegate = 1 << 9

    # Match the start of an ASCII-only word boundary. That is, this matches a
    # position at either the beginning of the haystack or where the previous
    # character is not a word character and the following character is a word
    # character.
    WordStartAscii = 1 << 10

    # Match the end of an ASCII-only word boundary. That is, this matches a
    # position at either the end of the haystack or where the previous
    # character is a word character and the following character is not a word
    # character.
    WordEndAscii = 1 << 11

    # Match the start of a Unicode word boundary. That is, this matches a
    # position at either the beginning of the haystack or where the previous
    # character is not a word character and the following character is a word
    # character.
    WordStartUnicode = 1 << 12

    # Match the end of a Unicode word boundary. That is, this matches a
    # position at either the end of the haystack or where the previous
    # character is a word character and the following character is not a word
    # character.
    WordEndUnicode = 1 << 13

    # Match the start half of an ASCII-only word boundary. That is, this
    # matches a position at either the beginning of the haystack or where the
    # previous character is not a word character.
    WordStartHalfAscii = 1 << 14

    # Match the end half of an ASCII-only word boundary. That is, this matches
    # a position at either the end of the haystack or where the following
    # character is not a word character.
    WordEndHalfAscii = 1 << 15

    # Match the start half of a Unicode word boundary. That is, this matches
    # a position at either the beginning of the haystack or where the
    # previous character is not a word character.
    WordStartHalfUnicode = 1 << 16

    # Match the end half of a Unicode word boundary. That is, this matches
    # a position at either the end of the haystack or where the following
    # character is not a word character.
    WordEndHalfUnicode = 1 << 17

    # Flip the look-around assertion to its equivalent for reverse searches.
    # For example, `StartLF` gets translated to `EndLF`.
    #
    # Some assertions, such as `WordUnicode`, remain the same since they
    # match the same positions regardless of the direction of the search.
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

    # Return the underlying representation of this look-around enumeration
    # as an integer.
    def as_repr : UInt32
      self.value
    end

    # Given the underlying representation of a `Look` value, return the
    # corresponding `Look` value if the representation is valid.
    def self.from_repr(repr : UInt32) : Look?
      case repr
      when 0b00_0000_0000_0000_0001 then Start
      when 0b00_0000_0000_0000_0010 then End
      when 0b00_0000_0000_0000_0100 then StartLF
      when 0b00_0000_0000_0000_1000 then EndLF
      when 0b00_0000_0000_0001_0000 then StartCRLF
      when 0b00_0000_0000_0010_0000 then EndCRLF
      when 0b00_0000_0000_0100_0000 then WordAscii
      when 0b00_0000_0000_1000_0000 then WordAsciiNegate
      when 0b00_0000_0001_0000_0000 then WordUnicode
      when 0b00_0000_0010_0000_0000 then WordUnicodeNegate
      when 0b00_0000_0100_0000_0000 then WordStartAscii
      when 0b00_0000_1000_0000_0000 then WordEndAscii
      when 0b00_0001_0000_0000_0000 then WordStartUnicode
      when 0b00_0010_0000_0000_0000 then WordEndUnicode
      when 0b00_0100_0000_0000_0000 then WordStartHalfAscii
      when 0b00_1000_0000_0000_0000 then WordEndHalfAscii
      when 0b01_0000_0000_0000_0000 then WordStartHalfUnicode
      when 0b10_0000_0000_0000_0000 then WordEndHalfUnicode
      else
        nil
      end
    end
  end

  # A set of look-around assertions.
  #
  # This set is represented as a bitmask where each bit corresponds to a
  # particular `Look` assertion. Bit i is set if and only if the corresponding
  # `Look` assertion is in the set.
  struct LookSet
    include Enumerable(Look)

    @mask : UInt32

    def initialize(@mask : UInt32 = 0)
    end

    # Create a LookSet from a single Look value.
    def self.from_look(look : Look) : LookSet
      new(look.as_repr)
    end

    # Returns true if and only if this set is empty.
    def empty? : Bool
      @mask == 0
    end

    # Returns the number of assertions in this set.
    def size : Int32
      @mask.popcount.to_i32
    end

    # Returns an iterator over the assertions in this set.
    def each(& : Look ->) : Nil
      mask = @mask
      bit = 0
      while mask != 0
        if (mask & 1) != 0
          if look = Look.from_repr(1_u32 << bit)
            yield look
          end
        end
        mask >>= 1
        bit += 1
      end
    end

    # Returns true if and only if this set contains the given assertion.
    def includes?(look : Look) : Bool
      (@mask & look.as_repr) != 0
    end

    # Returns a new set with the given assertion added.
    def insert(look : Look) : LookSet
      LookSet.new(@mask | look.as_repr)
    end

    # Returns a new set with the given assertion removed.
    def remove(look : Look) : LookSet
      LookSet.new(@mask & ~look.as_repr)
    end

    # Returns the union of this set and the other set.
    def union(other : LookSet) : LookSet
      LookSet.new(@mask | other.@mask)
    end

    # Returns the intersection of this set and the other set.
    def intersection(other : LookSet) : LookSet
      LookSet.new(@mask & other.@mask)
    end

    # Returns the difference of this set and the other set.
    def difference(other : LookSet) : LookSet
      LookSet.new(@mask & ~other.@mask)
    end

    # Returns the symmetric difference of this set and the other set.
    def symmetric_difference(other : LookSet) : LookSet
      LookSet.new(@mask ^ other.@mask)
    end

    # Returns true if this set is a subset of the other set.
    def subset?(other : LookSet) : Bool
      (@mask & ~other.@mask) == 0
    end

    # Returns true if this set is a superset of the other set.
    def superset?(other : LookSet) : Bool
      other.subset?(self)
    end

    # Alias for `union`.
    def |(other : LookSet) : LookSet
      union(other)
    end

    # Alias for `intersection`.
    def &(other : LookSet) : LookSet
      intersection(other)
    end

    # Alias for `difference`.
    def -(other : LookSet) : LookSet
      difference(other)
    end

    # Alias for `symmetric_difference`.
    def ^(other : LookSet) : LookSet
      symmetric_difference(other)
    end

    # Convert to a bitmask representation.
    def to_u32 : UInt32
      @mask
    end

    # Create from a bitmask representation.
    def self.from_u32(mask : UInt32) : LookSet
      new(mask)
    end

    # Helper methods for checking specific assertion categories

    # Returns true if this set contains any anchor assertions (^, $, \A, \z, etc.)
    def contains_anchor? : Bool
      (@mask & 0b0000_0000_0000_0011_u32) != 0 # Start or End
    end

    # Returns true if this set contains any line anchor assertions (^ or $ in multiline mode)
    def contains_anchor_line? : Bool
      (@mask & 0b0000_0000_0000_1100_u32) != 0 # StartLF or EndLF
    end

    # Returns true if this set contains any CRLF-aware line anchor assertions
    def contains_anchor_crlf? : Bool
      (@mask & 0b0000_0000_0011_0000_u32) != 0 # StartCRLF or EndCRLF
    end

    # Returns true if this set contains any word boundary assertions
    def contains_word? : Bool
      (@mask & 0b1111_1111_1100_0000_u32) != 0 # Any word assertion (bits 6-17)
    end

    # Returns true if this set contains any ASCII word boundary assertions
    def contains_word_ascii? : Bool
      (@mask & 0b0000_1111_1100_0000_u32) != 0 # ASCII word assertions (bits 6-11, 14-15)
    end

    # Returns true if this set contains any Unicode word boundary assertions
    def contains_word_unicode? : Bool
      (@mask & 0b1111_0000_0000_0000_u32) != 0 # Unicode word assertions (bits 8-9, 12-13, 16-17)
    end

    # Debug string representation
    def to_s(io : IO) : Nil
      io << "LookSet["
      first = true
      each do |look|
        io << ", " unless first
        first = false
        io << look
      end
      io << "]"
    end

    def inspect(io : IO) : Nil
      to_s(io)
    end
  end

  # Lookup table for ASCII word bytes (letters, digits, underscore)
  private WORD_BYTE_TABLE = begin
    table = StaticArray(Bool, 256).new(false)
    # underscore
    table['_'.ord.to_u8] = true
    # digits 0-9
    ('0'.ord..'9'.ord).each { |ord| table[ord.to_u8] = true }
    # uppercase A-Z
    ('A'.ord..'Z'.ord).each { |ord| table[ord.to_u8] = true }
    # lowercase a-z
    ('a'.ord..'z'.ord).each { |ord| table[ord.to_u8] = true }
    table
  end

  # Returns true if the given byte is an ASCII word character.
  # Word characters are ASCII letters (A-Z, a-z), digits (0-9), and underscore (_).
  def self.is_word_byte(byte : UInt8) : Bool
    WORD_BYTE_TABLE[byte]
  end
end
