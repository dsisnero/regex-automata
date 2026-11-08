require "./byte_search"
require "./memmem_rank"

module Regex::Automata
  # Internal owned-needle counterpart of memchr 2.8.1's substring finder.
  # The critical factorization and periodic memory follow arch/all/twoway.rs.
  class MemmemFinder
    getter needle : Bytes
    @byteset : UInt64
    @critical_pos : Int32
    @period : Int32
    @small_period : Bool
    @hash : UInt32
    @pair_a : Int32
    @pair_b : Int32
    @pair_min_len : Int32
    @pair_enabled : Bool
    @packed : Bool
    @hash_power : UInt32

    {% if flag?(:substring_diagnostics) %}
      getter comparisons : UInt64 = 0_u64
      getter prefilter_calls : Int32 = 0
    {% end %}

    def initialize(@needle : Bytes)
      @byteset = 0_u64
      @hash = 0_u32
      @hash_power = 1_u32
      @needle.each_with_index do |byte, index|
        @byteset |= 1_u64 << (byte & 63)
        @hash = (@hash << 1) &+ byte.to_u32
        @hash_power <<= 1 if index > 0
      end
      min_pos, min_period = suffix(@needle, true)
      max_pos, max_period = suffix(@needle, false)
      lower, @critical_pos = min_pos > max_pos ? {min_period, min_pos} : {max_period, max_pos}
      @small_period = @critical_pos < @needle.size - @critical_pos &&
                      @critical_pos <= lower &&
                      @needle[0, @critical_pos] == @needle[lower, @critical_pos]
      @period = @small_period ? lower : Math.max(@critical_pos, @needle.size - @critical_pos)
      @pair_a, @pair_b = pair_offsets
      width = ByteSearch::VECTOR_WIDTH
      @pair_min_len = Math.max(@needle.size, Math.max(@pair_a, @pair_b) + width)
      @pair_enabled = @needle.size >= 2 && (width > 0 || FREQUENCY_RANK[@needle[@pair_a]] <= 250)
      @packed = width > 0 && 2 <= @needle.size <= 32
    end

    def find(haystack : Bytes) : Int32?
      {% if flag?(:substring_diagnostics) %}
        @comparisons = 0_u64
        @prefilter_calls = 0
      {% end %}
      return nil if haystack.size < @needle.size
      return 0 if @needle.empty?
      return haystack.index(@needle[0]) if @needle.size == 1
      if @packed
        return rabin_karp(haystack) if haystack.size < @pair_min_len
        return ByteSearch.pair(@needle, @pair_a, @pair_b, haystack, verify: true)
      end
      return rabin_karp(haystack) if haystack.size < 16
      @small_period ? find_small(haystack) : find_large(haystack)
    end

    private def pair_offsets : Tuple(Int32, Int32)
      return {0, 0} if @needle.size < 2
      a = 0
      b = 1
      a, b = b, a if FREQUENCY_RANK[@needle[b]] < FREQUENCY_RANK[@needle[a]]
      i = 2
      while i < Math.min(@needle.size, 255)
        byte = @needle[i]
        if FREQUENCY_RANK[byte] < FREQUENCY_RANK[@needle[a]]
          b = a
          a = i
        elsif byte != @needle[a] && FREQUENCY_RANK[byte] < FREQUENCY_RANK[@needle[b]]
          b = i
        end
        i += 1
      end
      {a, b}
    end

    private def candidate(haystack : Bytes, pos : Int32) : Int32?
      {% if flag?(:substring_diagnostics) %}
        @prefilter_calls += 1
      {% end %}
      tail = haystack[pos, haystack.size - pos]
      if ByteSearch::VECTOR_WIDTH > 0 && tail.size < @pair_min_len
        # memmem::Prefilter::find_simple may return a false positive at zero.
        return tail.index(@needle[@pair_a]).try { |at| Math.max(0, at - @pair_a) }
      end
      ByteSearch.pair(@needle, @pair_a, @pair_b, tail, verify: false)
    end

    # memchr's forward minimal/maximal suffix, including its period tie break.
    private def suffix(needle : Bytes, minimal : Bool) : Tuple(Int32, Int32)
      pos = 0
      period = 1
      candidate = 1
      offset = 0
      while candidate + offset < needle.size
        current = needle[pos + offset]
        byte = needle[candidate + offset]
        if minimal ? byte < current : byte > current
          pos = candidate
          period = 1
          candidate += 1
          offset = 0
        elsif byte != current
          candidate += offset + 1
          offset = 0
          period = candidate - pos
        elsif offset + 1 == period
          candidate += period
          offset = 0
        else
          offset += 1
        end
      end
      {pos, period}
    end

    private def find_small(haystack : Bytes) : Int32?
      pos = 0
      memory = 0
      len = @needle.size
      skips = 0_i64
      skipped = 0_i64
      effective = @pair_enabled
      while pos <= haystack.size - len
        effective = false if skips >= 50 && skipped < 8 * skips
        if effective
          offset = candidate(haystack, pos)
          return nil unless offset
          pos += offset
          skips += 1
          skipped += offset
          memory = 0
          return nil if pos > haystack.size - len
        end
        unless includes_byte?(haystack[pos + len - 1])
          pos += len
          memory = 0
          next
        end
        i = Math.max(@critical_pos, memory)
        while i < len && equal_byte?(@needle[i], haystack[pos + i])
          i += 1
        end
        if i < len
          pos += i - @critical_pos + 1
          memory = 0
        else
          j = @critical_pos
          while j > memory && equal_byte?(@needle[j], haystack[pos + j])
            j -= 1
          end
          return pos if j <= memory && equal_byte?(@needle[memory], haystack[pos + memory])
          pos += @period
          memory = len - @period
        end
      end
      nil
    end

    private def find_large(haystack : Bytes) : Int32?
      pos = 0
      len = @needle.size
      skips = 0_i64
      skipped = 0_i64
      effective = @pair_enabled
      while pos <= haystack.size - len
        effective = false if skips >= 50 && skipped < 8 * skips
        if effective
          offset = candidate(haystack, pos)
          return nil unless offset
          pos += offset
          skips += 1
          skipped += offset
          return nil if pos > haystack.size - len
        end
        unless includes_byte?(haystack[pos + len - 1])
          pos += len
          next
        end
        i = @critical_pos
        while i < len && equal_byte?(@needle[i], haystack[pos + i])
          i += 1
        end
        if i < len
          pos += i - @critical_pos + 1
          next
        end
        j = @critical_pos - 1
        while j >= 0 && equal_byte?(@needle[j], haystack[pos + j])
          j -= 1
        end
        return pos if j < 0
        pos += @period
      end
      nil
    end

    private def rabin_karp(haystack : Bytes) : Int32?
      len = @needle.size
      hash = 0_u32
      len.times { |i| hash = (hash << 1) &+ haystack[i].to_u32 }
      pos = 0
      loop do
        if hash == @hash
          i = 0
          while i < len && equal_byte?(@needle[i], haystack[pos + i])
            i += 1
          end
          return pos if i == len
        end
        return nil if pos >= haystack.size - len
        hash = hash &- (haystack[pos].to_u32 &* @hash_power)
        hash = (hash << 1) &+ haystack[pos + len].to_u32
        pos += 1
      end
    end

    @[AlwaysInline]
    private def includes_byte?(byte : UInt8) : Bool
      @byteset & (1_u64 << (byte & 63)) != 0
    end

    @[AlwaysInline]
    private def equal_byte?(left : UInt8, right : UInt8) : Bool
      {% if flag?(:substring_diagnostics) %}
        @comparisons += 1
      {% end %}
      left == right
    end
  end
end
