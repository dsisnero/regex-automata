require "./search"

@[Link(ldflags: "-O3 #{__DIR__}/teddy_native.c")]
lib LibTeddyNative
  fun available = ra_teddy_neon_available : Int32
  fun find = ra_teddy_neon_find(
    hay : UInt8*, start : LibC::SizeT, finish : LibC::SizeT,
    masks : UInt8*, mask_len : Int32,
    patterns : UInt8**, lengths : LibC::SizeT*,
    bucket_ids : Int32*, bucket_offsets : Int32*,
    out_start : LibC::SizeT*, out_id : Int32*,
  ) : Int32
end

module Regex::Automata
  # The 8-bucket SlimNeon choice from aho-corasick 1.1.4's packed searcher.
  # The packed searcher's short-span Rabin-Karp path is kept here as well.
  class TeddyMatcher
    MIN_VECTOR_BYTES = 16
    NUM_BUCKETS      =  8
    RK_BUCKETS       = 64

    @needles : Array(Bytes)
    @mask_len : Int32
    @min_len : Int32
    @masks : Bytes
    @bucket_offsets : Array(Int32)
    @bucket_ids : Array(Int32)
    @pattern_ptrs : Array(Pointer(UInt8))
    @pattern_lens : Array(LibC::SizeT)
    @rk_buckets : Array(Array(Tuple(UInt64, Int32)))
    @rk_factor : UInt64

    def self.available? : Bool
      LibTeddyNative.available != 0
    end

    def initialize(@needles : Array(Bytes))
      @min_len = @needles.min_of(&.size).to_i32
      @mask_len = Math.min(4, @min_len)
      buckets = Array.new(NUM_BUCKETS) { [] of Int32 }
      by_prefix = {} of Array(UInt8) => Int32
      @needles.each_with_index do |needle, id|
        prefix = Array.new(@mask_len) { |i| needle[i] & 0x0f_u8 }
        bucket = by_prefix[prefix]?
        unless bucket
          bucket = (NUM_BUCKETS - 1 - id % NUM_BUCKETS).to_i32
          by_prefix[prefix] = bucket
        end
        buckets[bucket] << id.to_i32
      end

      @bucket_offsets = [0_i32]
      @bucket_ids = [] of Int32
      buckets.each do |bucket|
        @bucket_ids.concat(bucket)
        @bucket_offsets << @bucket_ids.size.to_i32
      end

      @masks = Bytes.new(@mask_len * 32, 0_u8)
      buckets.each_with_index do |bucket, bucket_index|
        bucket.each do |id|
          needle = @needles[id]
          @mask_len.times do |i|
            byte = needle[i]
            base = i * 32
            @masks[base + (byte & 0x0f_u8)] |= (1_u8 << bucket_index)
            @masks[base + 16 + (byte >> 4)] |= (1_u8 << bucket_index)
          end
        end
      end

      @pattern_ptrs = @needles.map(&.to_unsafe)
      @pattern_lens = @needles.map { |needle| LibC::SizeT.new(needle.size) }
      @rk_factor = 1_u64
      (@min_len - 1).times { @rk_factor = @rk_factor &* 2_u64 }
      @rk_buckets = Array.new(RK_BUCKETS) { [] of Tuple(UInt64, Int32) }
      @needles.each_with_index do |needle, id|
        hash = hash_at(needle, 0)
        @rk_buckets[(hash & 63_u64).to_i] << {hash, id.to_i32}
      end
    end

    def find(haystack : Bytes, span : Span) : Tuple(Int32, Span)?
      return nil if span.length < @min_len
      if span.length < MIN_VECTOR_BYTES + @mask_len - 1
        return find_rabin_karp(haystack, span)
      end
      start = LibC::SizeT.new(0)
      id = 0_i32
      found = LibTeddyNative.find(
        haystack.to_unsafe, LibC::SizeT.new(span.start), LibC::SizeT.new(span.end),
        @masks.to_unsafe, @mask_len,
        @pattern_ptrs.to_unsafe, @pattern_lens.to_unsafe,
        @bucket_ids.to_unsafe, @bucket_offsets.to_unsafe,
        pointerof(start), pointerof(id)
      )
      return nil if found == 0
      at = start.to_i32
      {id, Span.new(at, at + @needles[id].size)}
    end

    private def find_rabin_karp(haystack : Bytes, span : Span) : Tuple(Int32, Span)?
      at = span.start
      hash = hash_at(haystack, at)
      loop do
        @rk_buckets[(hash & 63_u64).to_i].each do |pattern_hash, id|
          next unless pattern_hash == hash
          needle = @needles[id]
          next if needle.size > span.end - at
          return {id, Span.new(at, at + needle.size)} if haystack[at, needle.size] == needle
        end
        return nil if at + @min_len >= span.end
        hash = ((hash &- (haystack[at].to_u64 &* @rk_factor)) &* 2_u64) &+
               haystack[at + @min_len].to_u64
        at += 1
      end
    end

    private def hash_at(bytes : Bytes, at : Int32) : UInt64
      hash = 0_u64
      @min_len.times do |i|
        hash = (hash &* 2_u64) &+ bytes[at + i].to_u64
      end
      hash
    end
  end
end
