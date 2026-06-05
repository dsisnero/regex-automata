module Regex::Automata
  module Interpolate
    private struct CaptureNameRef
      getter name : String

      def initialize(@name : String)
      end
    end

    private alias Ref = Int32 | CaptureNameRef

    private struct CaptureRef
      getter cap : Ref
      getter end : Int32

      def initialize(@cap : Ref, @end : Int32)
      end
    end

    def self.string(
      replacement : String,
      append : Int32, IO -> Nil,
      name_to_index : String -> Int32?,
      dst : IO,
    ) : Nil
      each_part(replacement.to_slice) do |part|
        case part
        when Bytes
          dst << String.new(part)
        when CaptureRef
          case cap = part.cap
          when Int32
            append.call(cap, dst)
          when CaptureNameRef
            if index = name_to_index.call(cap.name)
              append.call(index, dst)
            end
          end
        end
      end
    end

    def self.bytes(
      replacement : Bytes,
      append : Int32, Array(UInt8) -> Nil,
      name_to_index : String -> Int32?,
      dst : Array(UInt8),
    ) : Nil
      each_part(replacement) do |part|
        case part
        when Bytes
          part.each { |byte| dst << byte }
        when CaptureRef
          case cap = part.cap
          when Int32
            append.call(cap, dst)
          when CaptureNameRef
            if index = name_to_index.call(cap.name)
              append.call(index, dst)
            end
          end
        end
      end
    end

    private def self.each_part(replacement : Bytes, & : Bytes | CaptureRef ->) : Nil
      remaining = replacement
      until remaining.empty?
        dollar = memchr(remaining, '$'.ord.to_u8)
        break unless dollar

        literal = remaining[0, dollar]
        yield literal unless literal.empty?
        remaining = remaining[dollar, remaining.size - dollar]

        if remaining.size > 1 && remaining[1] == '$'.ord.to_u8
          yield Bytes['$'.ord.to_u8]
          remaining = remaining[2, remaining.size - 2]
          next
        end

        cap_ref = find_cap_ref(remaining)
        unless cap_ref
          yield Bytes['$'.ord.to_u8]
          remaining = remaining[1, remaining.size - 1]
          next
        end

        yield cap_ref
        remaining = remaining[cap_ref.end, remaining.size - cap_ref.end]
      end
      yield remaining unless remaining.empty?
    end

    private def self.find_cap_ref(replacement : Bytes) : CaptureRef?
      return nil if replacement.size <= 1 || replacement[0] != '$'.ord.to_u8

      if replacement[1] == '{'.ord.to_u8
        return find_cap_ref_braced(replacement, 2)
      end

      cap_end = 1
      while cap_end < replacement.size && valid_cap_letter?(replacement[cap_end])
        cap_end += 1
      end
      return nil if cap_end == 1

      cap = String.new(replacement[1, cap_end - 1])
      CaptureRef.new(ref_from_name(cap), cap_end)
    end

    private def self.find_cap_ref_braced(replacement : Bytes, index : Int32) : CaptureRef?
      finish = index
      while finish < replacement.size && replacement[finish] != '}'.ord.to_u8
        finish += 1
      end
      return nil if finish >= replacement.size || replacement[finish] != '}'.ord.to_u8

      cap = String.new(replacement[index, finish - index], "UTF-8", invalid: nil)
      return nil unless cap

      CaptureRef.new(ref_from_name(cap), finish + 1)
    end

    private def self.ref_from_name(name : String) : Ref
      if name.each_char.all?(&.ascii_number?)
        if value = name.to_i64?
          return value.to_i32 if value <= Int32::MAX
        end
      end
      CaptureNameRef.new(name)
    end

    private def self.valid_cap_letter?(byte : UInt8) : Bool
      (byte >= '0'.ord.to_u8 && byte <= '9'.ord.to_u8) ||
        (byte >= 'a'.ord.to_u8 && byte <= 'z'.ord.to_u8) ||
        (byte >= 'A'.ord.to_u8 && byte <= 'Z'.ord.to_u8) ||
        byte == '_'.ord.to_u8
    end

    private def self.memchr(bytes : Bytes, needle : UInt8) : Int32?
      index = 0
      while index < bytes.size
        return index if bytes[index] == needle
        index += 1
      end
      nil
    end
  end
end
