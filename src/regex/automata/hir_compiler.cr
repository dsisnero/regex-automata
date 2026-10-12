require "./nfa"
require "./syntax"
require "set"

module Regex::Automata
  class HirCompilerConfig
    getter utf8 : Bool
    getter reverse : Bool
    getter nfa_size_limit : Int64?
    getter shrink : Bool
    getter which_captures : NFA::WhichCaptures
    getter look_matcher : LookMatcher
    getter unanchored_prefix : Bool
    @overrides : Set(Symbol)

    def initialize(
      @utf8 : Bool = true,
      @reverse : Bool = false,
      @nfa_size_limit : Int64? = nil,
      @shrink : Bool = false,
      @which_captures : NFA::WhichCaptures = NFA::WhichCaptures::All,
      @look_matcher : LookMatcher = LookMatcher.new,
      @unanchored_prefix : Bool = true,
    )
      @overrides = Set(Symbol).new
    end

    def utf8(utf8 : Bool) : HirCompilerConfig
      copy = copy_for_override; copy.set_utf8_override(utf8); copy
    end

    def reverse(reverse : Bool) : HirCompilerConfig
      copy = copy_for_override; copy.set_reverse_override(reverse); copy
    end

    def nfa_size_limit(limit : Int64?) : HirCompilerConfig
      copy = copy_for_override; copy.set_nfa_size_limit_override(limit); copy
    end

    def shrink(shrink : Bool) : HirCompilerConfig
      copy = copy_for_override; copy.set_shrink_override(shrink); copy
    end

    def which_captures(which_captures : NFA::WhichCaptures) : HirCompilerConfig
      copy = copy_for_override; copy.set_which_captures_override(which_captures); copy
    end

    def captures(yes : Bool) : HirCompilerConfig
      which_captures(yes ? NFA::WhichCaptures::All : NFA::WhichCaptures::None)
    end

    def look_matcher(look_matcher : LookMatcher) : HirCompilerConfig
      copy = copy_for_override; copy.set_look_matcher_override(look_matcher); copy
    end

    def unanchored_prefix(yes : Bool) : HirCompilerConfig
      copy = copy_for_override; copy.set_unanchored_prefix_override(yes); copy
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
      copy = copy_for_override
      other.@overrides.each do |option|
        case option
        when :utf8              then copy.set_utf8_override(other.@utf8)
        when :reverse           then copy.set_reverse_override(other.@reverse)
        when :nfa_size_limit    then copy.set_nfa_size_limit_override(other.@nfa_size_limit)
        when :shrink            then copy.set_shrink_override(other.@shrink)
        when :which_captures    then copy.set_which_captures_override(other.@which_captures)
        when :look_matcher      then copy.set_look_matcher_override(other.@look_matcher)
        when :unanchored_prefix then copy.set_unanchored_prefix_override(other.@unanchored_prefix)
        end
      end
      copy
    end

    protected def set_utf8_override(value : Bool)
      @utf8 = value; @overrides.add(:utf8)
    end

    protected def set_reverse_override(value : Bool)
      @reverse = value; @overrides.add(:reverse)
    end

    protected def set_nfa_size_limit_override(value : Int64?)
      @nfa_size_limit = value; @overrides.add(:nfa_size_limit)
    end

    protected def set_shrink_override(value : Bool)
      @shrink = value; @overrides.add(:shrink)
    end

    protected def set_which_captures_override(value : NFA::WhichCaptures)
      @which_captures = value; @overrides.add(:which_captures)
    end

    protected def set_look_matcher_override(value : LookMatcher)
      @look_matcher = value; @overrides.add(:look_matcher)
    end

    protected def set_unanchored_prefix_override(value : Bool)
      @unanchored_prefix = value; @overrides.add(:unanchored_prefix)
    end

    private def copy_for_override : HirCompilerConfig
      copy = HirCompilerConfig.new(
        utf8: @utf8, reverse: @reverse, nfa_size_limit: @nfa_size_limit,
        shrink: @shrink, which_captures: @which_captures,
        look_matcher: @look_matcher, unanchored_prefix: @unanchored_prefix
      )
      copy.copy_overrides_from(self)
      copy
    end

    protected def copy_overrides_from(other : HirCompilerConfig) : Nil
      @overrides = other.@overrides.dup
    end
  end

  class HirCompiler
    @builder : NFA::Builder
    @pattern_id : PatternID
    @config : HirCompilerConfig
    @group_info : GroupInfo
    @syntax_config : Regex::Automata::Syntax::Config

    getter config : HirCompilerConfig

    def initialize(config : HirCompilerConfig = HirCompilerConfig.new, syntax_config : Regex::Automata::Syntax::Config = Regex::Automata::Syntax::Config.new)
      @config = config
      @syntax_config = syntax_config
      @builder = NFA::Builder.new(utf8: config.utf8, reverse: config.reverse, shrink: config.shrink, size_limit: config.nfa_size_limit)
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
      raise NFA::BuildError.syntax(ex)
    end

    def build_many(patterns : Enumerable(String)) : NFA::NFA
      build_many_from_hir(patterns.map { |pattern| syntax_parser.parse(pattern) }.to_a)
    rescue ex : ::Regex::Syntax::AST::Error | ::Regex::Syntax::Hir::Error
      raise NFA::BuildError.syntax(ex)
    end

    def build_from_hir(hir : Regex::Syntax::Hir::Hir) : NFA::NFA
      raise NFA::BuildError.unsupported_captures if @config.reverse && @config.which_captures.is_any

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
    rescue ex : GroupInfoError
      raise NFA::BuildError.captures(ex)
    rescue ex : UnicodeWordBoundaryError
      raise NFA::BuildError.word(ex)
    end

    def build_many_from_hir(hirs : Enumerable(Regex::Syntax::Hir::Hir)) : NFA::NFA
      hirs_array = hirs.to_a
      raise NFA::BuildError.unsupported_captures if @config.reverse && @config.which_captures.is_any
      return finalize_build(NFA::NFA.never_match) if hirs_array.empty?
      raise NFA::BuildError.too_many_patterns(hirs_array.size.to_i64) if hirs_array.size.to_i64 >= PatternID::LIMIT

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
    rescue ex : GroupInfoError
      raise NFA::BuildError.captures(ex)
    rescue ex : UnicodeWordBoundaryError
      raise NFA::BuildError.word(ex)
    end

    def compile(hir : Regex::Syntax::Hir::Hir, pattern_id : PatternID = PatternID.new(0)) : NFA::NFA
      reset_builder
      @pattern_id = pattern_id
      @group_info = build_group_info([{pattern_id, hir}] of Tuple(PatternID, Regex::Syntax::Hir::Hir))
      ref = finish_compiled_ref(compile_node(hir.node), pattern_id)
      @builder.add_pattern_start(ref.start)
      @builder.set_start_unanchored(ref.start)
      @builder.set_start_anchored(ref.start)

      finalize_build(@builder.build(@group_info))
    rescue ex : GroupInfoError
      raise NFA::BuildError.captures(ex)
    rescue ex : UnicodeWordBoundaryError
      raise NFA::BuildError.word(ex)
    end

    def compile_multi(hirs : Array(Regex::Syntax::Hir::Hir)) : NFA::NFA
      reset_builder
      return finalize_build(NFA::NFA.never_match) if hirs.empty?
      raise NFA::BuildError.too_many_patterns(hirs.size.to_i64) if hirs.size.to_i64 >= PatternID::LIMIT

      pattern_hirs = hirs.map_with_index { |hir, i| {PatternID.new(i.to_i32), hir} }
      @group_info = build_group_info(pattern_hirs)

      pattern_starts = [] of StateID
      hirs.each_with_index do |hir, i|
        pattern_id = PatternID.new(i.to_i32)
        @pattern_id = pattern_id
        ref = finish_compiled_ref(compile_node(hir.node), pattern_id)
        @builder.add_pattern_start(ref.start)
        pattern_starts << ref.start
      end

      start_id = combine_starts(pattern_starts)
      @builder.set_start_anchored(start_id)
      @builder.set_start_unanchored(start_id)

      finalize_build(@builder.build(@group_info))
    rescue ex : GroupInfoError
      raise NFA::BuildError.captures(ex)
    rescue ex : UnicodeWordBoundaryError
      raise NFA::BuildError.word(ex)
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

      finish_compiled_ref(ref, pattern_id)
    end

    private def finish_compiled_ref(ref : NFA::ThompsonRef, pattern_id : PatternID) : NFA::ThompsonRef
      return ref if @builder.state(ref.end).is_a?(NFA::Match)

      match_id = @builder.add_state(NFA::Match.new(pattern_id))
      compiler_patch(ref.end, match_id)
      NFA::ThompsonRef.new(ref.start, match_id)
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
          raise NFA::BuildError.exceeded_size_limit(limit)
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
             when Regex::Syntax::Hir::Look::Kind::WordAscii
               NFA::Look::Kind::WordBoundaryAscii
             when Regex::Syntax::Hir::Look::Kind::WordUnicode
               NFA::Look::Kind::WordBoundaryUnicode
             when Regex::Syntax::Hir::Look::Kind::WordAsciiNegate
               NFA::Look::Kind::NonWordBoundaryAscii
             when Regex::Syntax::Hir::Look::Kind::WordUnicodeNegate
               NFA::Look::Kind::NonWordBoundaryUnicode
             when Regex::Syntax::Hir::Look::Kind::WordStartAscii
               NFA::Look::Kind::WordStartAscii
             when Regex::Syntax::Hir::Look::Kind::WordEndAscii
               NFA::Look::Kind::WordEndAscii
             when Regex::Syntax::Hir::Look::Kind::WordStartUnicode
               NFA::Look::Kind::WordStartUnicode
             when Regex::Syntax::Hir::Look::Kind::WordEndUnicode
               NFA::Look::Kind::WordEndUnicode
             when Regex::Syntax::Hir::Look::Kind::WordStartHalfAscii
               NFA::Look::Kind::WordStartHalfAscii
             when Regex::Syntax::Hir::Look::Kind::WordEndHalfAscii
               NFA::Look::Kind::WordEndHalfAscii
             when Regex::Syntax::Hir::Look::Kind::WordStartHalfUnicode
               NFA::Look::Kind::WordStartHalfUnicode
             when Regex::Syntax::Hir::Look::Kind::WordEndHalfUnicode
               NFA::Look::Kind::WordEndHalfUnicode
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
      when NFA::Look::Kind::WordStartAscii
        NFA::Look::Kind::WordEndAscii
      when NFA::Look::Kind::WordEndAscii
        NFA::Look::Kind::WordStartAscii
      when NFA::Look::Kind::WordStartUnicode
        NFA::Look::Kind::WordEndUnicode
      when NFA::Look::Kind::WordEndUnicode
        NFA::Look::Kind::WordStartUnicode
      when NFA::Look::Kind::WordStartHalfAscii
        NFA::Look::Kind::WordEndHalfAscii
      when NFA::Look::Kind::WordEndHalfAscii
        NFA::Look::Kind::WordStartHalfAscii
      when NFA::Look::Kind::WordStartHalfUnicode
        NFA::Look::Kind::WordEndHalfUnicode
      when NFA::Look::Kind::WordEndHalfUnicode
        NFA::Look::Kind::WordStartHalfUnicode
      else
        kind
      end
    end

    private def compile_repetition(node : Regex::Syntax::Hir::Repetition) : NFA::ThompsonRef
      min = checked_u32_to_i32(node.min, "repetition min")
      max = node.max.try { |value| checked_u32_to_i32(value, "repetition max") }
      if min == 0 && max == 1
        compile_zero_or_one(node.sub, node.greedy?)
      elsif max.nil?
        compile_at_least(node.sub, node.greedy?, min)
      elsif min == max
        compile_exactly(node.sub, min)
      else
        compile_bounded(node.sub, node.greedy?, min, max)
      end
    end

    private def compile_zero_or_one(sub : Regex::Syntax::Hir::Node, greedy : Bool) : NFA::ThompsonRef
      union = repetition_union(greedy)
      compiled = compile_node(sub)
      ending = @builder.add_empty
      compiler_patch(union, compiled.start)
      compiler_patch(union, ending)
      compiler_patch(compiled.end, ending)
      NFA::ThompsonRef.new(union, ending)
    end

    private def compile_at_least(sub : Regex::Syntax::Hir::Node, greedy : Bool, min : Int32) : NFA::ThompsonRef
      if min == 0
        minimum_len = Regex::Syntax::Hir::Hir.new(sub).properties.minimum_len
        if minimum_len && minimum_len > 0
          union = repetition_union(greedy)
          compiled = compile_node(sub)
          compiler_patch(union, compiled.start)
          compiler_patch(compiled.end, union)
          return NFA::ThompsonRef.new(union, union)
        end

        compiled = compile_node(sub)
        plus = repetition_union(greedy)
        compiler_patch(compiled.end, plus)
        compiler_patch(plus, compiled.start)
        question = repetition_union(greedy)
        ending = @builder.add_empty
        compiler_patch(question, compiled.start)
        compiler_patch(question, ending)
        compiler_patch(plus, ending)
        return NFA::ThompsonRef.new(question, ending)
      end

      if min == 1
        compiled = compile_node(sub)
        union = repetition_union(greedy)
        compiler_patch(compiled.end, union)
        compiler_patch(union, compiled.start)
        return NFA::ThompsonRef.new(compiled.start, union)
      end

      prefix = compile_exactly(sub, min - 1)
      last = compile_node(sub)
      union = repetition_union(greedy)
      compiler_patch(prefix.end, last.start)
      compiler_patch(last.end, union)
      compiler_patch(union, last.start)
      NFA::ThompsonRef.new(prefix.start, union)
    end

    private def compile_exactly(sub : Regex::Syntax::Hir::Node, count : Int32) : NFA::ThompsonRef
      return compile_empty if count == 0

      first = compile_node(sub)
      ending = first.end
      (count - 1).times do
        compiled = compile_node(sub)
        compiler_patch(ending, compiled.start)
        ending = compiled.end
      end
      NFA::ThompsonRef.new(first.start, ending)
    end

    private def compile_bounded(sub : Regex::Syntax::Hir::Node, greedy : Bool, min : Int32, max : Int32) : NFA::ThompsonRef
      prefix = compile_exactly(sub, min)
      ending = @builder.add_empty
      previous_end = prefix.end
      (min...max).each do
        union = repetition_union(greedy)
        compiled = compile_node(sub)
        compiler_patch(previous_end, union)
        compiler_patch(union, compiled.start)
        compiler_patch(union, ending)
        previous_end = compiled.end
      end
      compiler_patch(previous_end, ending)
      NFA::ThompsonRef.new(prefix.start, ending)
    end

    private def repetition_union(greedy : Bool) : StateID
      if greedy
        @builder.add_union([] of StateID)
      else
        @builder.add_union_reverse([] of StateID)
      end
    end

    private def compiler_patch(from : StateID, to : StateID) : Nil
      if @builder.state(from).is_a?(NFA::Match)
        @builder.update_transition_target(from, to)
      else
        @builder.patch(from, to)
      end
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

      capture_start = @builder.add_state(
        NFA::Capture.new(StateID::ZERO, @pattern_id, node.index, start_slot)
      )
      child_ref = compile_node(node.sub)
      capture_end = @builder.add_state(
        NFA::Capture.new(StateID::ZERO, @pattern_id, node.index, end_slot)
      )
      compiler_patch(capture_start, child_ref.start)
      compiler_patch(child_ref.end, capture_end)
      NFA::ThompsonRef.new(capture_start, capture_end)
    end

    private def reset_builder : Nil
      @builder = NFA::Builder.new(utf8: @config.utf8, reverse: @config.reverse, shrink: @config.shrink, size_limit: @config.nfa_size_limit)
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
      children = node.children
      return compile_empty if children.empty?

      if @config.reverse
        first = compile_node(children.last)
        ending = first.end
        (children.size - 2).downto(0) do |index|
          compiled = compile_node(children[index])
          compiler_patch(ending, compiled.start)
          ending = compiled.end
        end
      else
        first = compile_node(children.first)
        ending = first.end
        (1...children.size).each do |index|
          compiled = compile_node(children[index])
          compiler_patch(ending, compiled.start)
          ending = compiled.end
        end
      end
      NFA::ThompsonRef.new(first.start, ending)
    end

    private def compile_alternation(node : Regex::Syntax::Hir::Alternation) : NFA::ThompsonRef
      literals = node.children
      if literals.size > 1 && literals.all? { |child| child.is_a?(Regex::Syntax::Hir::Literal) }
        if singleton = compile_singleton_alternation(literals)
          return singleton
        end
        trie = @config.reverse ? NFA::LiteralTrie.reverse : NFA::LiteralTrie.forward
        literals.each { |child| trie.add(child.as(Regex::Syntax::Hir::Literal).bytes) }
        return trie.compile(@builder)
      end

      children = node.children
      if children.empty?
        fail_id = @builder.add_fail
        return NFA::ThompsonRef.new(fail_id, fail_id)
      end

      first = compile_node(children.first)
      return first if children.size == 1

      second = compile_node(children[1])
      union = @builder.add_union([] of StateID)
      ending = @builder.add_empty
      compiler_patch(union, first.start)
      compiler_patch(first.end, ending)
      compiler_patch(union, second.start)
      compiler_patch(second.end, ending)
      (2...children.size).each do |index|
        compiled = compile_node(children[index])
        compiler_patch(union, compiled.start)
        compiler_patch(compiled.end, ending)
      end
      NFA::ThompsonRef.new(union, ending)
    end

    private def compile_singleton_alternation(children : Array(Regex::Syntax::Hir::Node)) : NFA::ThompsonRef?
      codepoints = [] of UInt32
      all_chars = children.all? do |child|
        bytes = child.as(Regex::Syntax::Hir::Literal).bytes
        if bytes.size == 1 && bytes[0] < 0x80_u8
          codepoints << bytes[0].to_u32
          true
        elsif bytes.empty? || bytes.size > 4
          false
        else
          text = String.new(bytes)
          decoded = text.valid_encoding? ? text.codepoints : [] of Int32
          if decoded.size == 1
            codepoints << decoded.first.to_u32
            true
          else
            false
          end
        end
      end
      if all_chars
        ranges = codepoints.map { |codepoint| codepoint..codepoint }
        return compile_unicode_class(Regex::Syntax::Hir::UnicodeClass.new(false, ranges))
      end

      return nil unless children.all? { |child| child.as(Regex::Syntax::Hir::Literal).bytes.size == 1 }

      ranges = children.map do |child|
        byte = child.as(Regex::Syntax::Hir::Literal).bytes[0]
        byte..byte
      end
      compile_char_class(Regex::Syntax::Hir::CharClass.new(false, ranges))
    end

    private def syntax_parser : ::Regex::Syntax::Parser
      @syntax_config.apply(::Regex::Syntax::ParserBuilder.new).build
    end
  end
end
