require "./nfa"

module Regex::Automata
  # Configuration for HirCompiler
  class HirCompilerConfig
    getter utf8 : Bool
    getter reverse : Bool

    def initialize(@utf8 : Bool = true, @reverse : Bool = false)
    end

    # Set UTF-8 mode
    def utf8(utf8 : Bool) : HirCompilerConfig
      HirCompilerConfig.new(utf8: utf8, reverse: @reverse)
    end

    # Set reverse mode
    def reverse(reverse : Bool) : HirCompilerConfig
      HirCompilerConfig.new(utf8: @utf8, reverse: reverse)
    end
  end

  # Compiler that converts HIR (High-level Intermediate Representation)
  # to Thompson NFA
  class HirCompiler
    @builder : NFA::Builder
    @pattern_id : PatternID
    @config : HirCompilerConfig

    def initialize(config : HirCompilerConfig = HirCompilerConfig.new)
      @config = config
      @builder = NFA::Builder.new(utf8: config.utf8, reverse: config.reverse)
      @pattern_id = PatternID.new(0)
    end

    # Compile a Hir::Hir to NFA
    def compile(hir : Regex::Syntax::Hir::Hir, pattern_id : PatternID = PatternID.new(0)) : NFA::NFA
      @pattern_id = pattern_id
      ref = compile_node(hir.node)
      @builder.add_pattern_start(ref.start)
      @builder.set_start_unanchored(ref.start)
      @builder.set_start_anchored(ref.start)
      @builder.build
    end

    # Compile multiple patterns into a single NFA
    def compile_multi(hirs : Array(Regex::Syntax::Hir::Hir)) : NFA::NFA
      pattern_starts = [] of StateID

      hirs.each_with_index do |hir, i|
        @pattern_id = PatternID.new(i)
        ref = compile_node(hir.node)
        @builder.add_pattern_start(ref.start)
        pattern_starts << ref.start
      end

      # Create union start state that epsilon-transitions to all pattern starts
      if pattern_starts.empty?
        # No patterns - create empty match state
        empty_match = @builder.add_state(NFA::Match.new(PatternID.new(0)))
        @builder.set_start_unanchored(empty_match)
        @builder.set_start_anchored(empty_match)
      elsif pattern_starts.size == 1
        # Single pattern - use its start directly
        @builder.set_start_unanchored(pattern_starts.first)
        @builder.set_start_anchored(pattern_starts.first)
      else
        # Multiple patterns - create union state
        union_start = @builder.add_state(NFA::Union.new(pattern_starts))
        @builder.set_start_unanchored(union_start)
        @builder.set_start_anchored(union_start)
      end

      @builder.build
    end

    private def compile_node(node : Regex::Syntax::Hir::Node) : NFA::ThompsonRef
      case node
      when Regex::Syntax::Hir::Empty
        compile_empty(node)
      when Regex::Syntax::Hir::Literal
        compile_literal(node)
      when Regex::Syntax::Hir::CharClass
        compile_char_class(node)
      when Regex::Syntax::Hir::UnicodeClass
        compile_unicode_class(node)
      when Regex::Syntax::Hir::Look
        compile_look(node)
      when Regex::Syntax::Hir::Repetition
        compile_repetition(node)
      when Regex::Syntax::Hir::Capture
        compile_capture(node)
      when Regex::Syntax::Hir::Concat
        compile_concat(node)
      when Regex::Syntax::Hir::Alternation
        compile_alternation(node)
      when Regex::Syntax::Hir::DotNode
        compile_dot(node)
      else
        raise "Unsupported HIR node type: #{node.class}"
      end
    end

    private def compile_empty(node : Regex::Syntax::Hir::Empty) : NFA::ThompsonRef
      # Empty pattern matches nothing - create a match state
      match_id = @builder.add_state(NFA::Match.new(@pattern_id))
      NFA::ThompsonRef.new(match_id, match_id)
    end

    private def compile_literal(node : Regex::Syntax::Hir::Literal) : NFA::ThompsonRef
      bytes = if @config.reverse
                reversed = Bytes.new(node.bytes.size)
                last = node.bytes.size - 1
                node.bytes.each_with_index do |byte, index|
                  reversed[last - index] = byte
                end
                reversed
              else
                node.bytes
              end
      @builder.build_literal(bytes, @pattern_id)
    end

    private def compile_char_class(node : Regex::Syntax::Hir::CharClass) : NFA::ThompsonRef
      @builder.build_class(node.intervals, node.negated?, @pattern_id)
    end

    private def compile_unicode_class(node : Regex::Syntax::Hir::UnicodeClass) : NFA::ThompsonRef
      @builder.build_unicode_class(node.intervals, node.negated?, @pattern_id)
    end

    private def compile_dot(node : Regex::Syntax::Hir::DotNode) : NFA::ThompsonRef
      @builder.build_dot(node.kind, @pattern_id)
    end

    private def compile_look(node : Regex::Syntax::Hir::Look) : NFA::ThompsonRef
      # Collapse the richer regex-syntax look space onto the smaller internal
      # NFA look representation currently implemented by this port.
      kind = case node.kind
             when Regex::Syntax::Hir::Look::Kind::StartLF,
                  Regex::Syntax::Hir::Look::Kind::StartCRLF
               NFA::Look::Kind::Start
             when Regex::Syntax::Hir::Look::Kind::EndLF,
                  Regex::Syntax::Hir::Look::Kind::EndCRLF
               NFA::Look::Kind::End
             when Regex::Syntax::Hir::Look::Kind::WordAscii,
                  Regex::Syntax::Hir::Look::Kind::WordUnicode,
                  Regex::Syntax::Hir::Look::Kind::WordStartAscii,
                  Regex::Syntax::Hir::Look::Kind::WordEndAscii,
                  Regex::Syntax::Hir::Look::Kind::WordStartUnicode,
                  Regex::Syntax::Hir::Look::Kind::WordEndUnicode,
                  Regex::Syntax::Hir::Look::Kind::WordStartHalfAscii,
                  Regex::Syntax::Hir::Look::Kind::WordEndHalfAscii,
                  Regex::Syntax::Hir::Look::Kind::WordStartHalfUnicode,
                  Regex::Syntax::Hir::Look::Kind::WordEndHalfUnicode
               NFA::Look::Kind::WordBoundary
             when Regex::Syntax::Hir::Look::Kind::WordAsciiNegate,
                  Regex::Syntax::Hir::Look::Kind::WordUnicodeNegate
               NFA::Look::Kind::NonWordBoundary
             when Regex::Syntax::Hir::Look::Kind::StartText
               NFA::Look::Kind::StartText
             when Regex::Syntax::Hir::Look::Kind::EndText
               NFA::Look::Kind::EndText
             when Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF
               NFA::Look::Kind::EndTextWithNewline
             else
               raise "Unsupported look kind: #{node.kind}"
             end

      # Reverse look assertion if in reverse mode
      if @config.reverse
        kind = reverse_look_kind(kind)
      end

      # Create look state with placeholder next
      look_id = @builder.add_state(NFA::Look.new(kind, StateID.new(0)))
      # Create match state
      match_id = @builder.add_state(NFA::Match.new(@pattern_id))
      # Update look to point to match
      @builder.update_transition_target(look_id, match_id)
      NFA::ThompsonRef.new(look_id, match_id)
    end

    private def reverse_look_kind(kind : NFA::Look::Kind) : NFA::Look::Kind
      case kind
      when NFA::Look::Kind::Start
        NFA::Look::Kind::End
      when NFA::Look::Kind::End
        NFA::Look::Kind::Start
      when NFA::Look::Kind::StartText
        NFA::Look::Kind::EndText
      when NFA::Look::Kind::EndText
        NFA::Look::Kind::StartText
      when NFA::Look::Kind::EndTextWithNewline
        NFA::Look::Kind::StartText
      else
        # WordBoundary, NonWordBoundary don't change
        kind
      end
    end

    private def compile_repetition(node : Regex::Syntax::Hir::Repetition) : NFA::ThompsonRef
      child_ref = compile_node(node.sub)
      min = checked_u32_to_i32(node.min, "repetition min")
      max = node.max.try { |value| checked_u32_to_i32(value, "repetition max") }
      @builder.build_repetition(child_ref, min, max, node.greedy?, @pattern_id)
    end

    private def compile_capture(node : Regex::Syntax::Hir::Capture) : NFA::ThompsonRef
      child_ref = compile_node(node.sub)

      # Wrap child with capture start/end epsilon states.
      # Slot layout follows regex-automata convention:
      # start slot = 2 * group_index, end slot = 2 * group_index + 1.
      start_slot = node.index * 2
      end_slot = start_slot + 1

      capture_start = @builder.add_state(
        NFA::Capture.new(child_ref.start, @pattern_id, node.index, start_slot)
      )
      capture_match_end = @builder.add_state(NFA::Match.new(@pattern_id))
      capture_end = @builder.add_state(
        NFA::Capture.new(capture_match_end, @pattern_id, node.index, end_slot)
      )
      @builder.update_transition_target(child_ref.end, capture_end)

      NFA::ThompsonRef.new(capture_start, capture_match_end)
    end

    private def checked_u32_to_i32(value : UInt32, label : String) : Int32
      raise "#{label} exceeds Int32: #{value}" if value > Int32::MAX.to_u32

      value.to_i32
    end

    private def compile_concat(node : Regex::Syntax::Hir::Concat) : NFA::ThompsonRef
      # Build concatenation of children
      refs = node.children.map { |child| compile_node(child) }

      if refs.empty?
        compile_empty(Regex::Syntax::Hir::Empty.new)
      else
        if @config.reverse
          # In reverse mode, concatenations are built in reverse order
          result = refs.last
          refs[0...-1].reverse_each do |prev_ref|
            result = @builder.build_concatenation(result, prev_ref)
          end
          result
        else
          # Chain refs together in forward order
          result = refs.first
          refs[1..].each do |next_ref|
            result = @builder.build_concatenation(result, next_ref)
          end
          result
        end
      end
    end

    private def compile_alternation(node : Regex::Syntax::Hir::Alternation) : NFA::ThompsonRef
      # Build alternation of children
      refs = node.children.map { |child| compile_node(child) }

      if refs.empty?
        compile_empty(Regex::Syntax::Hir::Empty.new)
      elsif refs.size == 1
        refs.first
      else
        # Build binary tree of alternations
        result = refs.first
        refs[1..].each do |next_ref|
          result = @builder.build_alternation(result, next_ref, @pattern_id)
        end
        result
      end
    end
  end
end
