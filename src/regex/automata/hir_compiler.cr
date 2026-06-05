require "./nfa"
require "./syntax"

module Regex::Automata
  class HirCompilerConfig
    getter utf8 : Bool
    getter reverse : Bool
    getter nfa_size_limit : Int64?
    getter shrink : Bool
    getter which_captures : NFA::WhichCaptures
    getter look_matcher : LookMatcher
    getter unanchored_prefix : Bool

    def initialize(
      @utf8 : Bool = true,
      @reverse : Bool = false,
      @nfa_size_limit : Int64? = nil,
      @shrink : Bool = false,
      @which_captures : NFA::WhichCaptures = NFA::WhichCaptures::All,
      @look_matcher : LookMatcher = LookMatcher.new,
      @unanchored_prefix : Bool = true,
    )
    end

    def utf8(utf8 : Bool) : HirCompilerConfig
      HirCompilerConfig.new(
        utf8: utf8,
        reverse: @reverse,
        nfa_size_limit: @nfa_size_limit,
        shrink: @shrink,
        which_captures: @which_captures,
        look_matcher: @look_matcher,
        unanchored_prefix: @unanchored_prefix
      )
    end

    def reverse(reverse : Bool) : HirCompilerConfig
      HirCompilerConfig.new(
        utf8: @utf8,
        reverse: reverse,
        nfa_size_limit: @nfa_size_limit,
        shrink: @shrink,
        which_captures: @which_captures,
        look_matcher: @look_matcher,
        unanchored_prefix: @unanchored_prefix
      )
    end

    def nfa_size_limit(limit : Int64?) : HirCompilerConfig
      HirCompilerConfig.new(
        utf8: @utf8,
        reverse: @reverse,
        nfa_size_limit: limit,
        shrink: @shrink,
        which_captures: @which_captures,
        look_matcher: @look_matcher,
        unanchored_prefix: @unanchored_prefix
      )
    end

    def shrink(shrink : Bool) : HirCompilerConfig
      HirCompilerConfig.new(
        utf8: @utf8,
        reverse: @reverse,
        nfa_size_limit: @nfa_size_limit,
        shrink: shrink,
        which_captures: @which_captures,
        look_matcher: @look_matcher,
        unanchored_prefix: @unanchored_prefix
      )
    end

    def which_captures(which_captures : NFA::WhichCaptures) : HirCompilerConfig
      HirCompilerConfig.new(
        utf8: @utf8,
        reverse: @reverse,
        nfa_size_limit: @nfa_size_limit,
        shrink: @shrink,
        which_captures: which_captures,
        look_matcher: @look_matcher,
        unanchored_prefix: @unanchored_prefix
      )
    end

    def captures(yes : Bool) : HirCompilerConfig
      which_captures(yes ? NFA::WhichCaptures::All : NFA::WhichCaptures::None)
    end

    def look_matcher(look_matcher : LookMatcher) : HirCompilerConfig
      HirCompilerConfig.new(
        utf8: @utf8,
        reverse: @reverse,
        nfa_size_limit: @nfa_size_limit,
        shrink: @shrink,
        which_captures: @which_captures,
        look_matcher: look_matcher,
        unanchored_prefix: @unanchored_prefix
      )
    end

    def unanchored_prefix(yes : Bool) : HirCompilerConfig
      HirCompilerConfig.new(
        utf8: @utf8,
        reverse: @reverse,
        nfa_size_limit: @nfa_size_limit,
        shrink: @shrink,
        which_captures: @which_captures,
        look_matcher: @look_matcher,
        unanchored_prefix: yes
      )
    end

    def get_utf8 : Bool
      @utf8
    end

    def get_reverse : Bool
      @reverse
    end

    def get_nfa_size_limit : Int64?
      @nfa_size_limit
    end

    def get_shrink : Bool
      @shrink
    end

    def get_which_captures : NFA::WhichCaptures
      @which_captures
    end

    def get_captures : Bool
      @which_captures.is_any
    end

    def get_look_matcher : LookMatcher
      @look_matcher
    end

    def get_unanchored_prefix : Bool
      @unanchored_prefix
    end

    def overwrite(other : HirCompilerConfig) : HirCompilerConfig
      other
    end
  end

  class HirCompiler
    @builder : NFA::Builder
    @pattern_id : PatternID
    @config : HirCompilerConfig
    @group_info : GroupInfo
    @syntax_config : Regex::Automata::Syntax::Config

    def initialize(config : HirCompilerConfig = HirCompilerConfig.new, syntax_config : Regex::Automata::Syntax::Config = Regex::Automata::Syntax::Config.new)
      @config = config
      @syntax_config = syntax_config
      @builder = NFA::Builder.new(utf8: config.utf8, reverse: config.reverse)
      @pattern_id = PatternID.new(0)
      @group_info = GroupInfo.empty
    end

    def configure(config : HirCompilerConfig) : HirCompiler
      @config = @config.overwrite(config)
      self
    end

    def syntax(config : Regex::Automata::Syntax::Config) : HirCompiler
      @syntax_config = config
      self
    end

    def build(pattern : String) : NFA::NFA
      build_from_hir(syntax_parser.parse(pattern))
    rescue ex : ::Regex::Syntax::AST::Error | ::Regex::Syntax::Hir::Error
      raise BuildError.new(ex.message)
    end

    def build_many(patterns : Enumerable(String)) : NFA::NFA
      build_many_from_hir(patterns.map { |pattern| syntax_parser.parse(pattern) }.to_a)
    rescue ex : ::Regex::Syntax::AST::Error | ::Regex::Syntax::Hir::Error
      raise BuildError.new(ex.message)
    end

    def build_from_hir(hir : Regex::Syntax::Hir::Hir) : NFA::NFA
      raise BuildError.new("reverse Thompson NFAs do not support capture states yet") if @config.reverse && @config.which_captures.is_any

      reset_builder
      @group_info = build_group_info([{PatternID.new(0), hir}] of Tuple(PatternID, Regex::Syntax::Hir::Hir))

      prefix_start, prefix_loop = build_unanchored_prefix_placeholder unless anchored_for_all?([hir])
      ref = compile_pattern(hir, PatternID.new(0))

      @builder.add_pattern_start(ref.start)
      @builder.set_start_anchored(ref.start)
      if prefix_start && prefix_loop
        @builder.set_state(prefix_start, NFA::BinaryUnion.new(ref.start, prefix_loop))
        @builder.set_start_unanchored(prefix_start)
      else
        @builder.set_start_unanchored(ref.start)
      end

      finalize_build(@builder.build(@group_info))
    end

    def build_many_from_hir(hirs : Enumerable(Regex::Syntax::Hir::Hir)) : NFA::NFA
      hirs_array = hirs.to_a
      raise BuildError.new("reverse Thompson NFAs do not support capture states yet") if @config.reverse && @config.which_captures.is_any
      return finalize_build(NFA::NFA.never_match) if hirs_array.empty?

      reset_builder
      pattern_hirs = hirs_array.map_with_index { |hir, i| {PatternID.new(i.to_i32), hir} }
      @group_info = build_group_info(pattern_hirs)

      prefix_start, prefix_loop = build_unanchored_prefix_placeholder unless anchored_for_all?(hirs_array)

      pattern_starts = [] of StateID
      hirs_array.each_with_index do |hir, i|
        pattern_id = PatternID.new(i.to_i32)
        ref = compile_pattern(hir, pattern_id)
        @builder.add_pattern_start(ref.start)
        pattern_starts << ref.start
      end

      start_id = combine_starts(pattern_starts)
      @builder.set_start_anchored(start_id)
      if prefix_start && prefix_loop
        @builder.set_state(prefix_start, NFA::BinaryUnion.new(start_id, prefix_loop))
        @builder.set_start_unanchored(prefix_start)
      else
        @builder.set_start_unanchored(start_id)
      end

      finalize_build(@builder.build(@group_info))
    end

    def compile(hir : Regex::Syntax::Hir::Hir, pattern_id : PatternID = PatternID.new(0)) : NFA::NFA
      reset_builder
      @pattern_id = pattern_id
      @group_info = build_group_info([{pattern_id, hir}] of Tuple(PatternID, Regex::Syntax::Hir::Hir))
      ref = compile_node(hir.node)
      @builder.add_pattern_start(ref.start)
      @builder.set_start_unanchored(ref.start)
      @builder.set_start_anchored(ref.start)

      finalize_build(@builder.build(@group_info))
    end

    def compile_multi(hirs : Array(Regex::Syntax::Hir::Hir)) : NFA::NFA
      reset_builder
      return finalize_build(NFA::NFA.never_match) if hirs.empty?

      pattern_hirs = hirs.map_with_index { |hir, i| {PatternID.new(i.to_i32), hir} }
      @group_info = build_group_info(pattern_hirs)

      pattern_starts = [] of StateID
      hirs.each_with_index do |hir, i|
        pattern_id = PatternID.new(i.to_i32)
        @pattern_id = pattern_id
        ref = compile_node(hir.node)
        @builder.add_pattern_start(ref.start)
        pattern_starts << ref.start
      end

      start_id = combine_starts(pattern_starts)
      @builder.set_start_anchored(start_id)
      @builder.set_start_unanchored(start_id)

      finalize_build(@builder.build(@group_info))
    end

    private def compile_pattern(hir : Regex::Syntax::Hir::Hir, pattern_id : PatternID) : NFA::ThompsonRef
      @pattern_id = pattern_id

      start_capture = nil.as(StateID?)
      if @config.which_captures.is_any
        start_slot = @group_info.slot(pattern_id, 0) || raise "missing implicit capture slot for pattern #{pattern_id.to_i}"
        start_capture = @builder.add_state(
          NFA::Capture.new(StateID.new(0), pattern_id, 0, start_slot)
        )
      end

      ref = compile_node(hir.node)

      if start_capture
        @builder.update_transition_target(start_capture, ref.start)
        @builder.replace_match_with_empty(ref.end)
        end_slot = (@group_info.slot(pattern_id, 0) || 0) + 1
        end_capture = @builder.add_state(
          NFA::Capture.new(StateID.new(0), pattern_id, 0, end_slot)
        )
        @builder.update_transition_target(ref.end, end_capture)
        ref = NFA::ThompsonRef.new(start_capture, end_capture)
      end

      unless @builder.state(ref.end).is_a?(NFA::Match)
        match_id = @builder.add_state(NFA::Match.new(pattern_id))
        @builder.update_transition_target(ref.end, match_id)
        ref = NFA::ThompsonRef.new(ref.start, match_id)
      end

      ref
    end

    private def anchored_for_all?(hirs : Array(Regex::Syntax::Hir::Hir)) : Bool
      return true unless @config.unanchored_prefix

      hirs.all? do |hir|
        props = hir.properties
        if @config.reverse
          props.look_set_suffix.includes?(::Regex::Syntax::Hir::Look::Kind::EndText)
        else
          props.look_set_prefix.includes?(::Regex::Syntax::Hir::Look::Kind::StartText)
        end
      end
    end

    private def build_unanchored_prefix_placeholder : Tuple(StateID, StateID)
      union_id = @builder.add_state(NFA::BinaryUnion.new(StateID.new(0), StateID.new(0)))
      loop_id = @builder.add_state(
        NFA::ByteRange.new(NFA::Transition.new(0_u8, 255_u8, union_id))
      )
      {union_id, loop_id}
    end

    private def combine_starts(pattern_starts : Array(StateID)) : StateID
      case pattern_starts.size
      when 0
        fail_id = @builder.add_state(NFA::Fail.new)
        fail_id
      when 1
        pattern_starts.first
      when 2
        @builder.add_state(NFA::BinaryUnion.new(pattern_starts[0], pattern_starts[1]))
      else
        @builder.add_state(NFA::Union.new(pattern_starts))
      end
    end

    private def finalize_build(nfa : NFA::NFA) : NFA::NFA
      if limit = @config.nfa_size_limit
        if nfa.memory_usage > limit
          raise BuildError.new("NFA exceeded size limit of #{limit} bytes", size_limit_exceeded: true, size_limit: limit)
        end
      end
      nfa
    end

    private def compile_node(node : Regex::Syntax::Hir::Node) : NFA::ThompsonRef
      case node
      when Regex::Syntax::Hir::Empty
        compile_empty
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

    private def compile_empty : NFA::ThompsonRef
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
      if !node.negated? && node.intervals.all? { |range| range.begin <= 0x7F_u32 && range.end <= 0x7F_u32 }
        byte_ranges = node.intervals.map { |range| range.begin.to_u8..range.end.to_u8 }
        return @builder.build_class(byte_ranges, false, @pattern_id)
      end
      @builder.build_unicode_class(node.intervals, node.negated?, @pattern_id)
    end

    private def compile_dot(node : Regex::Syntax::Hir::DotNode) : NFA::ThompsonRef
      @builder.build_dot(node.kind, @pattern_id)
    end

    private def compile_look(node : Regex::Syntax::Hir::Look) : NFA::ThompsonRef
      kind = case node.kind
             when Regex::Syntax::Hir::Look::Kind::StartLF
               NFA::Look::Kind::StartLF
             when Regex::Syntax::Hir::Look::Kind::StartCRLF
               NFA::Look::Kind::StartCRLF
             when Regex::Syntax::Hir::Look::Kind::EndLF
               NFA::Look::Kind::EndLF
             when Regex::Syntax::Hir::Look::Kind::EndCRLF
               NFA::Look::Kind::EndCRLF
             when Regex::Syntax::Hir::Look::Kind::WordAscii,
                  Regex::Syntax::Hir::Look::Kind::WordStartAscii,
                  Regex::Syntax::Hir::Look::Kind::WordEndAscii,
                  Regex::Syntax::Hir::Look::Kind::WordStartHalfAscii,
                  Regex::Syntax::Hir::Look::Kind::WordEndHalfAscii
               NFA::Look::Kind::WordBoundaryAscii
             when Regex::Syntax::Hir::Look::Kind::WordUnicode,
                  Regex::Syntax::Hir::Look::Kind::WordStartUnicode,
                  Regex::Syntax::Hir::Look::Kind::WordEndUnicode,
                  Regex::Syntax::Hir::Look::Kind::WordStartHalfUnicode,
                  Regex::Syntax::Hir::Look::Kind::WordEndHalfUnicode
               NFA::Look::Kind::WordBoundaryUnicode
             when Regex::Syntax::Hir::Look::Kind::WordAsciiNegate
               NFA::Look::Kind::NonWordBoundaryAscii
             when Regex::Syntax::Hir::Look::Kind::WordUnicodeNegate
               NFA::Look::Kind::NonWordBoundaryUnicode
             when Regex::Syntax::Hir::Look::Kind::StartText
               NFA::Look::Kind::StartText
             when Regex::Syntax::Hir::Look::Kind::EndText
               NFA::Look::Kind::EndText
             when Regex::Syntax::Hir::Look::Kind::EndTextOptionalLF
               NFA::Look::Kind::EndTextWithNewline
             else
               raise "Unsupported look kind: #{node.kind}"
             end
      kind = kind.not_nil!

      kind = reverse_look_kind(kind) if @config.reverse
      look_id = @builder.add_state(NFA::Look.new(kind, StateID.new(0)))
      match_id = @builder.add_state(NFA::Match.new(@pattern_id))
      @builder.update_transition_target(look_id, match_id)
      NFA::ThompsonRef.new(look_id, match_id)
    end

    private def reverse_look_kind(kind : NFA::Look::Kind) : NFA::Look::Kind
      case kind
      when NFA::Look::Kind::StartLF
        NFA::Look::Kind::EndLF
      when NFA::Look::Kind::EndLF
        NFA::Look::Kind::StartLF
      when NFA::Look::Kind::StartCRLF
        NFA::Look::Kind::EndCRLF
      when NFA::Look::Kind::EndCRLF
        NFA::Look::Kind::StartCRLF
      when NFA::Look::Kind::StartText
        NFA::Look::Kind::EndText
      when NFA::Look::Kind::EndText
        NFA::Look::Kind::StartText
      when NFA::Look::Kind::EndTextWithNewline
        NFA::Look::Kind::StartText
      else
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
      case @config.which_captures
      when NFA::WhichCaptures::None
        return compile_node(node.sub)
      when NFA::WhichCaptures::Implicit
        return compile_node(node.sub) if node.index > 0
      else
      end

      start_slot = @group_info.slot(@pattern_id, node.index) ||
                   raise "missing capture slot for pattern #{@pattern_id.to_i}, group #{node.index}"
      end_slot = start_slot + 1

      child_ref = compile_node(node.sub)
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

    private def reset_builder : Nil
      @builder = NFA::Builder.new(utf8: @config.utf8, reverse: @config.reverse)
      @builder.set_look_matcher(@config.look_matcher)
    end

    private def build_group_info(entries : Array(Tuple(PatternID, Regex::Syntax::Hir::Hir))) : GroupInfo
      max_pattern = entries.max_of? { |pid, _| pid.to_i } || -1
      names_by_pattern = Array.new(max_pattern + 1) { [] of String? }
      entries.each do |pid, hir|
        names_by_pattern[pid.to_i] = capture_names(hir.node)
      end
      GroupInfo.new(names_by_pattern, allow_empty_patterns: true)
    end

    private def capture_names(node : Regex::Syntax::Hir::Node) : Array(String?)
      names = case @config.which_captures
              when NFA::WhichCaptures::None
                [] of String?
              when NFA::WhichCaptures::Implicit
                [nil] of String?
              else
                [nil] of String?
              end
      collect_capture_names(node, names) if @config.which_captures == NFA::WhichCaptures::All
      names
    end

    private def collect_capture_names(node : Regex::Syntax::Hir::Node, names : Array(String?)) : Nil
      if node.is_a?(Regex::Syntax::Hir::Capture)
        while names.size <= node.index
          names << nil
        end
        names[node.index] = node.name
      end
      node.subs.each do |child|
        collect_capture_names(child, names)
      end
    end

    private def checked_u32_to_i32(value : UInt32, label : String) : Int32
      raise "#{label} exceeds Int32: #{value}" if value > Int32::MAX.to_u32

      value.to_i32
    end

    private def compile_concat(node : Regex::Syntax::Hir::Concat) : NFA::ThompsonRef
      refs = node.children.map { |child| compile_node(child) }

      if refs.empty?
        compile_empty
      else
        if @config.reverse
          result = refs.last
          refs[0...-1].reverse_each do |prev_ref|
            result = @builder.build_concatenation(result, prev_ref)
          end
          result
        else
          result = refs.first
          refs[1..].each do |next_ref|
            result = @builder.build_concatenation(result, next_ref)
          end
          result
        end
      end
    end

    private def compile_alternation(node : Regex::Syntax::Hir::Alternation) : NFA::ThompsonRef
      refs = node.children.map { |child| compile_node(child) }

      if refs.empty?
        compile_empty
      elsif refs.size == 1
        refs.first
      else
        result = refs.first
        refs[1..].each do |next_ref|
          result = @builder.build_alternation(result, next_ref, @pattern_id)
        end
        result
      end
    end

    private def syntax_parser : ::Regex::Syntax::Parser
      @syntax_config.apply(::Regex::Syntax::ParserBuilder.new).build
    end
  end
end
