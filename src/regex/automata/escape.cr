module Regex::Automata
  # A debug wrapper for a single byte that prints ASCII escapes instead of a
  # decimal integer.
  struct DebugByte
    getter byte : UInt8

    def initialize(@byte : UInt8)
    end

    def inspect(io : IO) : Nil
      if @byte == ' '.ord.to_u8
        io << "' '"
        return
      end

      case @byte
      when '\n'.ord.to_u8
        io << "\\n"
      when '\r'.ord.to_u8
        io << "\\r"
      when '\t'.ord.to_u8
        io << "\\t"
      when '\\'.ord.to_u8
        io << "\\\\"
      when '\''.ord.to_u8
        io << "\\'"
      else
        if printable_ascii?(@byte)
          io.write_byte(@byte)
        else
          io << "\\x"
          append_hex(io, @byte, upcase: true)
        end
      end
    end

    private def printable_ascii?(byte : UInt8) : Bool
      byte >= 0x21 && byte <= 0x7E
    end

    private def append_hex(io : IO, byte : UInt8, *, upcase : Bool) : Nil
      value = byte.to_i
      hi = ((value >> 4) & 0x0F).to_u8
      lo = (value & 0x0F).to_u8
      io.write_byte(hex_digit(hi, upcase))
      io.write_byte(hex_digit(lo, upcase))
    end

    private def hex_digit(value : UInt8, upcase : Bool) : UInt8
      if value < 10
        ('0'.ord + value).to_u8
      else
        base = upcase ? 'A'.ord : 'a'.ord
        (base + value - 10).to_u8
      end
    end
  end

  # A debug wrapper for haystack bytes that prints mostly-UTF-8 data as a
  # quoted string, escaping invalid bytes as hex sequences.
  struct DebugHaystack
    getter bytes : Bytes

    def initialize(@bytes : Bytes)
    end

    def inspect(io : IO) : Nil
      io << '"'
      index = 0
      while index < @bytes.size
        decoded = Utf8.decode(@bytes[index...])
        break if decoded.nil?

        case value = decoded
        when Char
          append_char(io, value)
          index += value.bytesize
        when UInt8
          io << "\\x"
          append_hex(io, value, upcase: false)
          index += 1
        end
      end
      io << '"'
    end

    private def append_char(io : IO, char : Char) : Nil
      case char
      when '\0'
        io << "\\0"
      when '\n'
        io << "\\n"
      when '\r'
        io << "\\r"
      when '\t'
        io << "\\t"
      when '"'
        io << "\\\""
      when '\\'
        io << "\\\\"
      else
        codepoint = char.ord
        if (codepoint >= 0x01 && codepoint <= 0x08) ||
           codepoint == 0x0B ||
           codepoint == 0x0C ||
           (codepoint >= 0x0E && codepoint <= 0x19) ||
           codepoint == 0x7F
          io << "\\x"
          append_hex(io, codepoint.to_u8, upcase: false)
        else
          io << char
        end
      end
    end

    private def append_hex(io : IO, byte : UInt8, *, upcase : Bool) : Nil
      value = byte.to_i
      hi = ((value >> 4) & 0x0F).to_u8
      lo = (value & 0x0F).to_u8
      io.write_byte(hex_digit(hi, upcase))
      io.write_byte(hex_digit(lo, upcase))
    end

    private def hex_digit(value : UInt8, upcase : Bool) : UInt8
      if value < 10
        ('0'.ord + value).to_u8
      else
        base = upcase ? 'A'.ord : 'a'.ord
        (base + value - 10).to_u8
      end
    end
  end
end
