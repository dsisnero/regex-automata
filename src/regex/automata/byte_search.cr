{% if flag?(:byte_search_scalar) %}
  @[Link(ldflags: "-O3 -DRA_BYTE_FORCE_SCALAR #{__DIR__}/byte_search_native.c")]
{% elsif flag?(:byte_search_sse2) %}
  @[Link(ldflags: "-O3 -DRA_BYTE_FORCE_SSE2 #{__DIR__}/byte_search_native.c")]
{% else %}
  @[Link(ldflags: "-O3 #{__DIR__}/byte_search_native.c")]
{% end %}
lib LibByteSearchNative
  fun width = ra_byte_vector_width : Int32
  fun find = ra_byte_find(hay : UInt8*, len : LibC::SizeT, a : UInt8, b : UInt8, c : UInt8, count : Int32, reverse : Int32) : Int64
  fun pair = ra_pair_find(hay : UInt8*, len : LibC::SizeT, needle : UInt8*, needle_len : LibC::SizeT, a : LibC::SizeT, b : LibC::SizeT, verify : Int32) : Int64
end

module Regex::Automata::ByteSearch
  extend self
  VECTOR_WIDTH = LibByteSearchNative.width

  def find(needles : Bytes, haystack : Bytes, reverse : Bool = false) : Int32?
    raise ArgumentError.new("expected one to three needle bytes") unless 1 <= needles.size <= 3
    find(needles[0], needles[1]? || 0_u8, needles[2]? || 0_u8, needles.size, haystack, reverse)
  end

  def find(a : UInt8, b : UInt8, c : UInt8, count : Int32, haystack : Bytes, reverse : Bool = false) : Int32?
    return haystack.index(a) if count == 1 && !reverse
    {% if flag?(:x86_64) && !flag?(:byte_search_sse2) && !flag?(:byte_search_scalar) %}
      # The x86 runner found libc faster for two forward needles and
      # comparable for three. Reverse scans still use the combined kernel.
      unless reverse
        found = first_offset(haystack.index(a), haystack.index(b))
        return found if count == 2
        return first_offset(found, haystack.index(c)) if count == 3
      end
    {% end %}
    offset = LibByteSearchNative.find(haystack.to_unsafe, haystack.size.to_u64, a, b, c, count, reverse ? 1 : 0)
    offset < 0 ? nil : offset.to_i32
  end

  private def first_offset(a : Int32?, b : Int32?) : Int32?
    return b unless a
    b ? Math.min(a, b) : a
  end

  def pair(needle : Bytes, a : Int32, b : Int32, haystack : Bytes, verify : Bool) : Int32?
    return nil if a < 0 || b < 0 || a == b || a >= needle.size || b >= needle.size
    return nil if haystack.size < needle.size
    offset = LibByteSearchNative.pair(haystack.to_unsafe, haystack.size.to_u64, needle.to_unsafe, needle.size.to_u64, a.to_u64, b.to_u64, verify ? 1 : 0)
    offset < 0 ? nil : offset.to_i32
  end
end
