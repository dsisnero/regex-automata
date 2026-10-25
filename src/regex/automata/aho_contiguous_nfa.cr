module Regex::Automata
  # Packed Aho-Corasick NFA for the pinned wrapper's >500-needle choice.
  # The layout and search branches follow aho-corasick 1.1.4 contiguous.rs.
  private class AhoContiguousNfa
    DEAD  =    0_u32
    FAIL  =    1_u32
    DENSE = 0xff_u32
    ONE   = 0xfe_u32

    private class Node
      getter edges = {} of UInt8 => Int32
      getter outputs = [] of Int32
      getter depth : Int32
      property failure = 0

      def initialize(@depth : Int32)
      end
    end

    @repr : Array(UInt32)
    @classes : Bytes
    @pattern_lens : Array(Int32)
    @alphabet_len : Int32
    @max_needle_len : Int32
    @start_unanchored : Int32
    @start_anchored : Int32
    @max_match_sid : Int32

    def initialize(needles : Array(Bytes), @max_needle_len : Int32)
      nodes = [Node.new(0)]
      @pattern_lens = needles.map(&.size.to_i32)
      needles.each_with_index do |needle, index|
        state = 0
        shadowed = false
        needle.each do |byte|
          if !nodes[state].outputs.empty?
            shadowed = true
            break
          end
          unless child = nodes[state].edges[byte]?
            child = nodes.size.to_i32
            nodes[state].edges[byte] = child
            nodes << Node.new(nodes[state].depth + 1)
          end
          state = child
        end
        next if shadowed
        nodes[state].outputs << index.to_i32
      end
      fill_failures(nodes)
      @classes, @alphabet_len = build_classes(nodes)
      @repr = [] of UInt32
      offsets = Array(UInt32).new(nodes.size + 3, 0_u32)
      records = [] of Tuple(Int32, UInt32, Int32)

      # DEAD is a real dense state at offset 0; FAIL is a sentinel at offset
      # 1, inside DEAD's encoding, as in the pinned dependency.
      @repr << DENSE << DEAD
      @alphabet_len.times { @repr << DEAD }
      records << {0, DENSE, @alphabet_len}
      offsets[1] = FAIL

      match_ids = [] of Int32
      other_ids = [] of Int32
      nodes.each_with_index do |node, id|
        next if id == 0
        (node.outputs.empty? ? other_ids : match_ids) << id.to_i32
      end
      match_ids.each { |id| encode_node(nodes[id], id, offsets, records) }
      @max_match_sid = match_ids.empty? ? 0 : offsets[match_ids.last + 2].to_i32
      encode_node(nodes[0], 0, offsets, records)
      encode_node(nodes[0], nodes.size.to_i32, offsets, records, anchored_root: true)
      other_ids.each { |id| encode_node(nodes[id], id, offsets, records) }
      @start_unanchored = offsets[2].to_i32
      @start_anchored = offsets[nodes.size + 2].to_i32
      remap_states(offsets, records)
    end

    def find(haystack : Bytes, span : Span) : Tuple(Int32, Span)?
      state = @start_unanchored
      best_index = Int32::MAX
      best_span = nil.as(Span?)
      at = span.start
      while at < span.end
        state = next_state(state, @classes[haystack[at]], false)
        break if state == 0
        if state <= @max_match_sid
          index = first_match(state)
          start = at + 1 - @pattern_lens[index]
          if start >= span.start && (best_span.nil? || start < best_span.start || (start == best_span.start && index < best_index))
            best_index = index
            best_span = Span.new(start, at + 1)
          end
        end
        break if best_span && at - best_span.start + 1 >= @max_needle_len
        at += 1
      end
      best_span.try { |found| {best_index, found} }
    end

    def prefix(haystack : Bytes, span : Span) : Tuple(Int32, Span)?
      state = @start_anchored
      best_index = Int32::MAX
      best_end = -1
      at = span.start
      limit = Math.min(span.end, span.start + @max_needle_len)
      while at < limit
        state = next_state(state, @classes[haystack[at]], true)
        break if state == 0
        if state <= @max_match_sid
          index = first_match(state)
          if at + 1 - @pattern_lens[index] == span.start && index < best_index
            best_index = index
            best_end = at + 1
          end
        end
        at += 1
      end
      return nil if best_end < 0
      {best_index, Span.new(span.start, best_end)}
    end

    def memory_usage : Int32
      ((@repr.size + @pattern_lens.size) * sizeof(UInt32)).to_i32
    end

    private def fill_failures(nodes : Array(Node)) : Nil
      queue = [] of Int32
      nodes[0].edges.each_value do |child|
        nodes[child].failure = -1 unless nodes[child].outputs.empty?
        queue << child
      end
      head = 0
      while head < queue.size
        state = queue[head]
        head += 1
        nodes[state].edges.each do |byte, child|
          if !nodes[child].outputs.empty?
            nodes[child].failure = -1
          else
            failure = nodes[state].failure
            while failure > 0 && !nodes[failure].edges.has_key?(byte)
              failure = nodes[failure].failure
            end
            if failure < 0
              nodes[child].failure = -1
            else
              nodes[child].failure = nodes[failure].edges[byte]? || 0
              nodes[child].outputs.concat(nodes[nodes[child].failure].outputs)
            end
          end
          queue << child
        end
      end
    end

    private def build_classes(nodes : Array(Node)) : Tuple(Bytes, Int32)
      boundary = Array(Bool).new(256, false)
      nodes.each do |node|
        node.edges.each_key do |byte|
          boundary[byte - 1] = true if byte > 0
          boundary[byte] = true
        end
      end
      classes = Bytes.new(256, 0_u8)
      byte_class = 0
      (0..255).each do |byte|
        classes[byte] = byte_class.to_u8
        byte_class += 1 if boundary[byte] && byte < 255
      end
      {classes, byte_class.to_i32 + 1}
    end

    private def encode_node(node : Node, id : Int32, offsets : Array(UInt32),
                            records : Array(Tuple(Int32, UInt32, Int32)), anchored_root = false) : Nil
      ordinal = id + 2
      sid = @repr.size.to_i32
      offsets[ordinal] = sid.to_u32
      edges = node.edges.to_a.sort_by(&.[0])
      # The noncontiguous builder measures depth from the first trie state,
      # after its start state: both first- and second-byte states are dense.
      dense = node.depth <= 2 || edges.size > 127
      kind = if dense
               DENSE
             elsif edges.size == 1 && node.outputs.empty?
               ONE
             else
               edges.size.to_u32
             end
      fail = if anchored_root || node.failure < 0
               DEAD
             else
               (node.failure + 2).to_u32
             end
      if dense
        @repr << DENSE << fail
        @alphabet_len.times { @repr << (id == 0 && !anchored_root ? 2_u32 : FAIL) }
        edges.each { |byte, child| @repr[sid + 2 + @classes[byte]] = (child + 2).to_u32 }
      elsif kind == ONE
        byte, child = edges[0]
        @repr << (ONE | (@classes[byte].to_u32 << 8)) << fail << (child + 2).to_u32
      else
        @repr << kind << fail
        classes = edges.map { |byte, _| @classes[byte] }
        classes.each_slice(4) do |slice|
          last = slice.last
          packed = 0_u32
          4.times do |at|
            packed |= (slice[at]? || last).to_u32 << (at * 8)
          end
          @repr << packed
        end
        edges.each { |_, child| @repr << (child + 2).to_u32 }
      end
      unless node.outputs.empty?
        if node.outputs.size == 1
          @repr << (0x80000000_u32 | node.outputs[0].to_u32)
        else
          @repr << node.outputs.size.to_u32
          node.outputs.each { |index| @repr << index.to_u32 }
        end
      end
      records << {sid, kind, edges.size.to_i32}
    end

    private def remap_states(offsets : Array(UInt32), records : Array(Tuple(Int32, UInt32, Int32))) : Nil
      records.each do |sid, kind, count|
        @repr[sid + 1] = offsets[@repr[sid + 1]] unless @repr[sid + 1] == FAIL
        if kind == DENSE
          @alphabet_len.times do |byte_class|
            at = sid + 2 + byte_class
            @repr[at] = offsets[@repr[at]] unless @repr[at] == FAIL
          end
        elsif kind == ONE
          @repr[sid + 2] = offsets[@repr[sid + 2]]
        else
          start = sid + 2 + (count + 3) // 4
          count.times do |i|
            at = start + i
            @repr[at] = offsets[@repr[at]]
          end
        end
      end
    end

    private def next_state(state : Int32, byte_class : UInt8, anchored : Bool) : Int32
      sid = state
      loop do
        kind_word = @repr[sid]
        kind = kind_word & 0xff_u32
        if kind == DENSE
          next_id = @repr[sid + 2 + byte_class].to_i32
          return next_id if next_id != 1
        elsif kind == ONE
          if ((kind_word >> 8) & 0xff_u32) == byte_class
            return @repr[sid + 2].to_i32
          end
        else
          count = kind.to_i32
          chunks = (count + 3) // 4
          next_start = sid + 2 + chunks
          chunks.times do |chunk_index|
            packed = @repr[sid + 2 + chunk_index]
            4.times do |at|
              if ((packed >> (at * 8)) & 0xff_u32) == byte_class
                return @repr[next_start + chunk_index * 4 + at].to_i32
              end
            end
          end
        end
        return 0 if anchored
        sid = @repr[sid + 1].to_i32
      end
    end

    private def first_match(sid : Int32) : Int32
      kind = @repr[sid] & 0xff_u32
      at = if kind == DENSE
             sid + 2 + @alphabet_len
           else
             count = kind.to_i32
             sid + 2 + (count + 3) // 4 + count
           end
      packed = @repr[at]
      if (packed & 0x80000000_u32) != 0
        (packed & 0x7fffffff_u32).to_i32
      else
        @repr[at + 1].to_i32
      end
    end
  end
end
