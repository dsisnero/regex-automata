require "./search"

@[Link(ldflags: "-O3 #{__DIR__}/teddy_native.c")]
lib LibTeddyNative
  fun available = ra_teddy_neon_available : Int32
  fun capabilities = ra_teddy_capabilities : Int32
  fun find = ra_teddy_neon_find(
    hay : UInt8*, start : LibC::SizeT, finish : LibC::SizeT,
    masks : UInt8*, mask_len : Int32,
    patterns : UInt8**, lengths : LibC::SizeT*,
    bucket_ids : Int32*, bucket_offsets : Int32*,
    out_start : LibC::SizeT*, out_id : Int32*,
  ) : Int32
  fun x86_find = ra_teddy_x86_find(
    hay : UInt8*, start : LibC::SizeT, finish : LibC::SizeT,
    masks : UInt8*, mask_len : Int32, mode : Int32,
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
    getter backend_name : Symbol

    def self.available? : Bool
      LibTeddyNative.capabilities != 0
    end

    # The pinned builder chooses AVX2 first, then SSSE3; AArch64 NEON has
    # only slim Teddy. Its >16 warning for one-byte masks is not a rejection.
    def self.backend_for(count : Int32, min_len : Int32, *, neon : Bool, ssse3 : Bool, avx2 : Bool, only_256bit : Bool? = nil) : Symbol?
      return nil if count > 64 || count < 1 || min_len < 1
      if neon
        return nil if only_256bit == true
        return :slim_neon
      end
      return nil if min_len == 1 && count > 16
      use_avx2 = only_256bit.nil? ? avx2 : only_256bit
      return count > 32 ? :fat_avx2 : :slim_avx2 if use_avx2 && avx2
      return :slim_ssse3 if !use_avx2 && ssse3
      nil
    end

    def self.backend_for(count : Int32, min_len : Int32, *, only_256bit : Bool? = nil) : Symbol?
      caps = LibTeddyNative.capabilities
      backend_for(count, min_len,
        neon: (caps & 1) != 0, ssse3: (caps & 2) != 0, avx2: (caps & 4) != 0,
        only_256bit: only_256bit)
    end

    def self.memory_usage_for(count : Int32, bytes : Int32, backend : Symbol) : Int32
      verifier_copies = backend == :slim_avx2 ? 2 : 1
      (count * (sizeof(UInt32) + 3 * sizeof(Pointer(Void))) + bytes +
        RK_BUCKETS * 3 * sizeof(Pointer(Void)) + count * (sizeof(UInt64) + sizeof(UInt32) + sizeof(UInt32)) +
        count * sizeof(UInt32) * verifier_copies).to_i32
    end

    def initialize(@needles : Array(Bytes), *, only_256bit : Bool? = nil)
      @min_len = @needles.min_of(&.size).to_i32
      @mask_len = Math.min(4, @min_len)
      @backend_name = self.class.backend_for(@needles.size.to_i32, @min_len, only_256bit: only_256bit) ||
                      raise ArgumentError.new("Teddy is unavailable for these needles")
      num_buckets = @backend_name == :fat_avx2 ? 16 : NUM_BUCKETS
      mask_stride = @backend_name == :slim_neon || @backend_name == :slim_ssse3 ? 32 : 64
      buckets = Array.new(num_buckets) { [] of Int32 }
      by_prefix = {} of Array(UInt8) => Int32
      @needles.each_with_index do |needle, id|
        prefix = Array.new(@mask_len) { |i| needle[i] & 0x0f_u8 }
        bucket = by_prefix[prefix]?
        unless bucket
          bucket = (num_buckets - 1 - id % num_buckets).to_i32
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

      @masks = Bytes.new(@mask_len * mask_stride, 0_u8)
      buckets.each_with_index do |bucket, bucket_index|
        bucket.each do |id|
          needle = @needles[id]
          @mask_len.times do |i|
            byte = needle[i]
            base = i * mask_stride
            bit = 1_u8 << (bucket_index % 8)
            if @backend_name == :fat_avx2
              half = bucket_index < 8 ? 0 : 16
              @masks[base + half + (byte & 0x0f_u8)] |= bit
              @masks[base + 32 + half + (byte >> 4)] |= bit
            elsif @backend_name == :slim_avx2
              low = (byte & 0x0f_u8).to_i
              high = (byte >> 4).to_i
              @masks[base + low] |= bit
              @masks[base + 16 + low] |= bit
              @masks[base + 32 + high] |= bit
              @masks[base + 48 + high] |= bit
            else
              @masks[base + (byte & 0x0f_u8)] |= bit
              @masks[base + 16 + (byte >> 4)] |= bit
            end
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
      found = if @backend_name == :slim_neon
                LibTeddyNative.find(
                  haystack.to_unsafe, LibC::SizeT.new(span.start), LibC::SizeT.new(span.end),
                  @masks.to_unsafe, @mask_len,
                  @pattern_ptrs.to_unsafe, @pattern_lens.to_unsafe,
                  @bucket_ids.to_unsafe, @bucket_offsets.to_unsafe,
                  pointerof(start), pointerof(id)
                )
              else
                mode = case @backend_name
                       when :slim_ssse3 then 2
                       when :slim_avx2  then span.length < 32 + @mask_len - 1 ? 5 : 3
                       else                  4
                       end
                LibTeddyNative.x86_find(
                  haystack.to_unsafe, LibC::SizeT.new(span.start), LibC::SizeT.new(span.end),
                  @masks.to_unsafe, @mask_len, mode,
                  @pattern_ptrs.to_unsafe, @pattern_lens.to_unsafe,
                  @bucket_ids.to_unsafe, @bucket_offsets.to_unsafe,
                  pointerof(start), pointerof(id)
                )
              end
      return nil if found == 0
      at = start.to_i32
      {id, Span.new(at, at + @needles[id].size)}
    end

    # aho-corasick 1.1.4 packed::Searcher counts shared pattern storage,
    # 64 Rabin-Karp buckets, one hash/PID pair per pattern, and Teddy bucket
    # IDs. SlimNeon has one copy of the eight-bucket Teddy verifier.
    def memory_usage : Int32
      self.class.memory_usage_for(@needles.size.to_i32, @needles.sum(&.size).to_i32, @backend_name)
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
