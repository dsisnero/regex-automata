module Regex::Automata
  module Wire
    struct AlignAs(B, T)
      @align : StaticArray(T, 0)
      getter bytes : B

      def initialize(@bytes : B)
        @align = StaticArray(T, 0).new(uninitialized)
      end
    end

    def self.skip_initial_padding(slice : Bytes) : Int32
      nread = 0
      while nread < 7 && nread < slice.size && slice[nread] == 0
        nread += 1
      end
      nread
    end

    def self.read_label(slice : Bytes, expected_label : String) : Int32
      search_len = Math.min(slice.size, 256)
      first_nul = slice[0, search_len].index(0_u8)
      raise DeserializeError.generic("could not find NUL terminated label at start of serialized object") if first_nul.nil?

      nul_index = first_nul.not_nil!
      total_len = nul_index + 1 + padding_len(nul_index + 1)
      if slice.size < total_len
        raise DeserializeError.generic("could not find properly sized label at start of serialized object")
      end
      if slice[0, nul_index] != expected_label.to_slice
        raise DeserializeError.label_mismatch(expected_label)
      end
      total_len.to_i32
    end

    def self.write_label(label : String, dst : Bytes) : Int32
      nwrite = write_label_len(label)
      raise SerializeError.buffer_too_small("label") if dst.size < nwrite

      dst[0, label.bytesize].copy_from(label.to_slice)
      (label.bytesize...nwrite).each do |i|
        dst[i] = 0_u8
      end
      nwrite.to_i32
    end

    def self.write_label_len(label : String) : Int32
      raise ArgumentError.new("label must not be longer than 255 bytes") if label.bytesize > 255
      raise ArgumentError.new("label must not contain NUL bytes") if label.to_slice.includes?(0_u8)

      label_len = label.bytesize + 1
      (label_len + padding_len(label_len)).to_i32
    end

    def self.padding_len(non_padding_len : Int) : Int32
      ((4 - (non_padding_len & 0b11)) & 0b11).to_i32
    end
  end

  class SerializeError
    def self.buffer_too_small(what : String) : self
      new("destination buffer is too small to write #{what}")
    end
  end

  class DeserializeError
    def self.generic(message : String) : self
      new(message)
    end

    def self.label_mismatch(expected_label : String) : self
      new("label mismatch: start of serialized object should contain a NUL terminated #{expected_label.inspect} label, but a different label was found")
    end
  end
end
