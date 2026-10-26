module Regex::Automata
  # Dense, byte-classed Aho automaton for the pinned prefilter's DFA choice.
  # The transition table stores pre-multiplied state offsets, as in
  # aho-corasick 1.1.4's dfa.rs; failure transitions are resolved at build time.
  private class AhoDfa
    private class Node
      getter edges = {} of UInt8 => Int32
      getter outputs = [] of Int32
      property failure = 0
    end

    @first_match : Array(Int32)
    @needle_lens : Array(Int32)
    @max_needle_len : Int32
    @classes : Bytes
    @stride : Int32
    @stride2 : Int32
    @trans : Array(Int32)
    @start_unanchored : Int32
    @start_anchored : Int32
    @max_match_sid : Int32
    @memory_usage : Int32

    def initialize(needles : Array(Bytes), @max_needle_len : Int32, *, anchored_only = false)
      nodes = [Node.new]
      @needle_lens = needles.map(&.size.to_i32)
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
            nodes << Node.new
          end
          state = child
        end
        next if shadowed
        nodes[state].outputs << index.to_i32
      end
      queue = [] of Int32
      nodes[0].edges.each_value do |child|
        nodes[child].failure = -1 if !nodes[child].outputs.empty?
        queue << child
      end
      head = 0
      while head < queue.size
        state = queue[head]
        head += 1
        nodes[state].edges.each do |byte, child|
          if !nodes[child].outputs.empty?
            nodes[child].failure = -1
            queue << child
            next
          end
          failure = nodes[state].failure
          if failure < 0
            nodes[child].failure = -1
            queue << child
            next
          end
          while failure > 0 && !nodes[failure].edges.has_key?(byte)
            failure = nodes[failure].failure
            break if failure < 0
          end
          if failure < 0
            nodes[child].failure = -1
          else
            nodes[child].failure = nodes[failure].edges[byte]? || 0
            nodes[child].outputs.concat(nodes[nodes[child].failure].outputs)
          end
          queue << child
        end
      end

      used = Array(Bool).new(256, false)
      nodes.each { |node| node.edges.each_key { |byte| used[byte] = true } }
      # ByteClassSet::set_range(byte, byte): each pattern byte splits the
      # contiguous class on either side. Rust deliberately does not merge
      # disjoint ranges of unused bytes.
      boundary = Array(Bool).new(256, false)
      used.each_with_index do |present, byte|
        next unless present
        boundary[byte - 1] = true if byte > 0
        boundary[byte] = true
      end
      @classes = Bytes.new(256, 0_u8)
      representatives = [] of UInt8
      byte_class = 0
      (0..255).each do |byte|
        representatives << byte.to_u8 if byte == 0 || boundary[byte - 1]
        @classes[byte] = byte_class.to_u8
        byte_class += 1 if boundary[byte] && byte < 255
      end
      @stride = 1
      @stride2 = 0
      while @stride < representatives.size
        @stride <<= 1
        @stride2 += 1
      end
      # Rust shuffles match states before ordinary states so the search loop
      # can identify them with one state-ID comparison, without an extra
      # match-metadata load on the common non-match path.
      match_ids = [] of Int32
      other_ids = [] of Int32
      nodes.each_with_index do |node, state|
        (node.outputs.empty? ? other_ids : match_ids) << state.to_i32
      end
      ordered = match_ids + other_ids
      old_to_new = Array(Int32).new(nodes.size, 0)
      ordered.each_with_index { |old, new_id| old_to_new[old] = new_id.to_i32 }
      if anchored_only
        @max_match_sid = match_ids.empty? ? -1 : (match_ids.size - 1) * @stride
        @start_unanchored = -1
        @start_anchored = old_to_new[0] * @stride
        @trans = Array(Int32).new(nodes.size * @stride, -1)
        nodes.each_with_index do |node, state|
          representatives.each_with_index do |byte, byte_class|
            direct = node.edges[byte]?
            @trans[old_to_new[state] * @stride + byte_class] = direct ? old_to_new[direct] * @stride : -1
          end
        end
        @first_match = ordered.map { |old| nodes[old].outputs.first? || -1 }
      else
        @max_match_sid = match_ids.empty? ? -1 : (match_ids.size * 2 - 1) * @stride
        @start_unanchored = old_to_new[0] * 2 * @stride
        @start_anchored = @start_unanchored + @stride
        # Interleave unanchored and anchored states in one dense table, as
        # dfa.rs does for StartKind::Both. Each transition is pre-multiplied.
        @trans = Array(Int32).new(nodes.size * 2 * @stride, -1)
        nodes.each_with_index do |node, state|
          representatives.each_with_index do |byte, byte_class|
            direct = node.edges[byte]?
            anchored_at = (old_to_new[state] * 2 + 1) * @stride + byte_class
            @trans[anchored_at] = direct ? (old_to_new[direct] * 2 + 1) * @stride : -1
            next_state = direct
            unless next_state
              failure = node.failure
              while failure > 0 && !nodes[failure].edges.has_key?(byte)
                failure = nodes[failure].failure
              end
              next_state = failure < 0 ? -1 : (nodes[failure].edges[byte]? || 0)
            end
            @trans[old_to_new[state] * 2 * @stride + byte_class] = next_state < 0 ? -1 : old_to_new[next_state] * 2 * @stride
          end
        end
        @first_match = ordered.flat_map do |old|
          node = nodes[old]
          first = node.outputs.first? || -1
          [first, first]
        end
      end
      # Rust counts the DEAD/FAIL/start states omitted from Crystal's table,
      # plus per-match Vec headers, pattern IDs and pattern lengths.
      starts = anchored_only ? 1 : 2
      state_len = anchored_only ? nodes.size + 3 : nodes.size * 2 + 2
      match_outputs = match_ids.sum { |id| nodes[id].outputs.size }
      @memory_usage = (state_len * @stride * sizeof(UInt32) +
                       match_ids.size * starts * sizeof(Pointer(Void)) * 3 +
                       match_outputs * starts * sizeof(UInt32) +
                       needles.size * sizeof(UInt32)).to_i32
    end

    def find(haystack : Bytes, span : Span) : Tuple(Int32, Span)?
      return nil if @start_unanchored < 0
      state = @start_unanchored
      best_index = Int32::MAX
      best_span = nil.as(Span?)
      at = span.start
      while at < span.end
        state = @trans[state + @classes[haystack[at]].to_i32]
        break if state < 0
        if state <= @max_match_sid
          index = @first_match[state >> @stride2]
          start = at + 1 - @needle_lens[index]
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
        state = @trans[state + @classes[haystack[at]].to_i32]
        break if state < 0
        if state <= @max_match_sid
          index = @first_match[state >> @stride2]
          if at + 1 - @needle_lens[index] == span.start && index < best_index
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
      @memory_usage
    end
  end
end
