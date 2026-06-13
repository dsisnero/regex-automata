require "./meta_error"
require "./meta_limited"
require "./meta_stopat"
require "./captures"
require "./dfa"
require "./nfa"
require "./pikevm"
require "./pool"
require "./search"
require "./syntax"

module Regex::Automata::Meta
  class Cache
    @cache : ::Regex::Automata::NFA::PikeVM::Cache

    def initialize(regex : Regex)
      @cache = regex.pikevm.create_cache
    end

    def reset(regex : Regex) : Nil
      regex.pikevm.reset_cache(@cache)
    end

    def memory_usage : Int32
      @cache.memory_usage
    end

    getter raw_cache : ::Regex::Automata::NFA::PikeVM::Cache do
      @cache
    end
  end

  class Config
    @match_kind : ::Regex::Automata::MatchKind?
    @utf8_empty : Bool?
    @auto_prefilter : Bool?
    @prefilter : ::Regex::Automata::Prefilter?
    @prefilter_explicit : Bool
    @which_captures : ::Regex::Automata::NFA::WhichCaptures?
    @nfa_size_limit : Int64?
    @onepass_size_limit : Int64?
    @hybrid_cache_capacity : Int32?
    @hybrid : Bool?
    @dfa : Bool?
    @dfa_size_limit : Int64?
    @dfa_state_limit : Int64?
    @onepass : Bool?
    @backtrack : Bool?
    @byte_classes : Bool?
    @line_terminator : UInt8?

    def initialize(
      *,
      @match_kind : ::Regex::Automata::MatchKind? = nil,
      @utf8_empty : Bool? = nil,
      @auto_prefilter : Bool? = nil,
      @prefilter : ::Regex::Automata::Prefilter? = nil,
      @prefilter_explicit : Bool = false,
      @which_captures : ::Regex::Automata::NFA::WhichCaptures? = nil,
      @nfa_size_limit : Int64? = nil,
      @onepass_size_limit : Int64? = nil,
      @hybrid_cache_capacity : Int32? = nil,
      @hybrid : Bool? = nil,
      @dfa : Bool? = nil,
      @dfa_size_limit : Int64? = nil,
      @dfa_state_limit : Int64? = nil,
      @onepass : Bool? = nil,
      @backtrack : Bool? = nil,
      @byte_classes : Bool? = nil,
      @line_terminator : UInt8? = nil,
    )
    end

    def match_kind(kind : ::Regex::Automata::MatchKind) : Config
      copy(match_kind: kind)
    end

    def utf8_empty(yes : Bool) : Config
      copy(utf8_empty: yes)
    end

    def auto_prefilter(yes : Bool) : Config
      copy(auto_prefilter: yes)
    end

    def prefilter(prefilter : ::Regex::Automata::Prefilter?) : Config
      copy(prefilter: prefilter, prefilter_explicit: true)
    end

    def which_captures(which : ::Regex::Automata::NFA::WhichCaptures) : Config
      copy(which_captures: which)
    end

    def nfa_size_limit(limit : Int64?) : Config
      copy(nfa_size_limit: limit)
    end

    def onepass_size_limit(limit : Int64?) : Config
      copy(onepass_size_limit: limit)
    end

    def hybrid_cache_capacity(capacity : Int32) : Config
      copy(hybrid_cache_capacity: capacity)
    end

    def hybrid(yes : Bool) : Config
      copy(hybrid: yes)
    end

    def dfa(yes : Bool) : Config
      copy(dfa: yes)
    end

    def dfa_size_limit(limit : Int64?) : Config
      copy(dfa_size_limit: limit)
    end

    def dfa_state_limit(limit : Int64?) : Config
      copy(dfa_state_limit: limit)
    end

    def onepass(yes : Bool) : Config
      copy(onepass: yes)
    end

    def backtrack(yes : Bool) : Config
      copy(backtrack: yes)
    end

    def byte_classes(yes : Bool) : Config
      copy(byte_classes: yes)
    end

    def line_terminator(byte : UInt8) : Config
      copy(line_terminator: byte)
    end

    def get_match_kind : ::Regex::Automata::MatchKind
      @match_kind || ::Regex::Automata::MatchKind::LeftmostFirst
    end

    def get_utf8_empty : Bool
      @utf8_empty.nil? ? true : @utf8_empty.not_nil!
    end

    def get_auto_prefilter : Bool
      @auto_prefilter.nil? ? true : @auto_prefilter.not_nil!
    end

    def get_prefilter : ::Regex::Automata::Prefilter?
      @prefilter_explicit ? @prefilter : nil
    end

    def get_which_captures : ::Regex::Automata::NFA::WhichCaptures
      @which_captures || ::Regex::Automata::NFA::WhichCaptures::All
    end

    def get_nfa_size_limit : Int64?
      @nfa_size_limit
    end

    def get_onepass_size_limit : Int64?
      @onepass_size_limit
    end

    def get_hybrid_cache_capacity : Int32
      @hybrid_cache_capacity || 2_097_152
    end

    def get_hybrid : Bool
      @hybrid.nil? ? true : @hybrid.not_nil!
    end

    def get_dfa : Bool
      @dfa.nil? ? true : @dfa.not_nil!
    end

    def get_dfa_size_limit : Int64?
      @dfa_size_limit
    end

    def get_dfa_state_limit : Int64?
      @dfa_state_limit
    end

    def get_onepass : Bool
      @onepass.nil? ? true : @onepass.not_nil!
    end

    def get_backtrack : Bool
      @backtrack.nil? ? true : @backtrack.not_nil!
    end

    def get_byte_classes : Bool
      @byte_classes.nil? ? true : @byte_classes.not_nil!
    end

    def get_line_terminator : UInt8
      @line_terminator || '\n'.ord.to_u8
    end

    def overwrite(other : Config) : Config
      Config.new(
        match_kind: other.@match_kind.nil? ? @match_kind : other.@match_kind,
        utf8_empty: other.@utf8_empty.nil? ? @utf8_empty : other.@utf8_empty,
        auto_prefilter: other.@auto_prefilter.nil? ? @auto_prefilter : other.@auto_prefilter,
        prefilter: other.@prefilter_explicit ? other.@prefilter : @prefilter,
        prefilter_explicit: other.@prefilter_explicit || @prefilter_explicit,
        which_captures: other.@which_captures.nil? ? @which_captures : other.@which_captures,
        nfa_size_limit: other.@nfa_size_limit.nil? ? @nfa_size_limit : other.@nfa_size_limit,
        onepass_size_limit: other.@onepass_size_limit.nil? ? @onepass_size_limit : other.@onepass_size_limit,
        hybrid_cache_capacity: other.@hybrid_cache_capacity.nil? ? @hybrid_cache_capacity : other.@hybrid_cache_capacity,
        hybrid: other.@hybrid.nil? ? @hybrid : other.@hybrid,
        dfa: other.@dfa.nil? ? @dfa : other.@dfa,
        dfa_size_limit: other.@dfa_size_limit.nil? ? @dfa_size_limit : other.@dfa_size_limit,
        dfa_state_limit: other.@dfa_state_limit.nil? ? @dfa_state_limit : other.@dfa_state_limit,
        onepass: other.@onepass.nil? ? @onepass : other.@onepass,
        backtrack: other.@backtrack.nil? ? @backtrack : other.@backtrack,
        byte_classes: other.@byte_classes.nil? ? @byte_classes : other.@byte_classes,
        line_terminator: other.@line_terminator.nil? ? @line_terminator : other.@line_terminator
      )
    end

    private def copy(
      *,
      match_kind : ::Regex::Automata::MatchKind? = @match_kind,
      utf8_empty : Bool? = @utf8_empty,
      auto_prefilter : Bool? = @auto_prefilter,
      prefilter : ::Regex::Automata::Prefilter? = @prefilter,
      prefilter_explicit : Bool = @prefilter_explicit,
      which_captures : ::Regex::Automata::NFA::WhichCaptures? = @which_captures,
      nfa_size_limit : Int64? = @nfa_size_limit,
      onepass_size_limit : Int64? = @onepass_size_limit,
      hybrid_cache_capacity : Int32? = @hybrid_cache_capacity,
      hybrid : Bool? = @hybrid,
      dfa : Bool? = @dfa,
      dfa_size_limit : Int64? = @dfa_size_limit,
      dfa_state_limit : Int64? = @dfa_state_limit,
      onepass : Bool? = @onepass,
      backtrack : Bool? = @backtrack,
      byte_classes : Bool? = @byte_classes,
      line_terminator : UInt8? = @line_terminator,
    ) : Config
      Config.new(
        match_kind: match_kind,
        utf8_empty: utf8_empty,
        auto_prefilter: auto_prefilter,
        prefilter: prefilter,
        prefilter_explicit: prefilter_explicit,
        which_captures: which_captures,
        nfa_size_limit: nfa_size_limit,
        onepass_size_limit: onepass_size_limit,
        hybrid_cache_capacity: hybrid_cache_capacity,
        hybrid: hybrid,
        dfa: dfa,
        dfa_size_limit: dfa_size_limit,
        dfa_state_limit: dfa_state_limit,
        onepass: onepass,
        backtrack: backtrack,
        byte_classes: byte_classes,
        line_terminator: line_terminator
      )
    end
  end

  class Builder
    @config : Config
    @syntax_config : ::Regex::Automata::Syntax::Config

    def initialize
      @config = Config.new
      @syntax_config = ::Regex::Automata::Syntax::Config.new
    end

    def configure(config : Config) : Builder
      @config = @config.overwrite(config)
      self
    end

    def syntax(config : ::Regex::Automata::Syntax::Config) : Builder
      @syntax_config = config
      self
    end

    def build(pattern : String) : Regex
      build_many([pattern])
    end

    def build_many(patterns : Enumerable(String)) : Regex
      hirs = [] of ::Regex::Syntax::Hir::Hir
      parser = effective_syntax_config.apply(::Regex::Syntax::ParserBuilder.new).build
      patterns.each_with_index do |pattern, index|
        begin
          hirs << parser.parse(pattern)
        rescue ex : ::Regex::Syntax::AST::Error | ::Regex::Syntax::Hir::Error
          raise BuildError.syntax_error(::Regex::Automata::PatternID.new(index.to_i32), ex)
        end
      end
      build_many_from_hir(hirs)
    end

    def build_from_hir(hir : ::Regex::Syntax::Hir::Hir) : Regex
      build_many_from_hir([hir])
    end

    def build_many_from_hir(hirs : Enumerable(::Regex::Syntax::Hir::Hir)) : Regex
      hirs_array = hirs.to_a
      props_union = ::Regex::Syntax::Hir::Properties.union(hirs_array.map(&.properties))
      hir_syntax_config = ::Regex::Automata::Syntax::Config.new
      compile_config = ::Regex::Automata::HirCompilerConfig.new(
        utf8: props_union.utf8?,
        nfa_size_limit: @config.get_nfa_size_limit,
        which_captures: effective_which_captures,
        look_matcher: ::Regex::Automata::LookMatcher.new(@config.get_line_terminator)
      )
      nfa = ::Regex::Automata::HirCompiler.new(compile_config, hir_syntax_config).build_many_from_hir(hirs_array)
      core_prefilter = build_core_prefilter(hirs_array, props_union)
      pike_config = ::Regex::Automata::NFA::PikeVM::Config.new
        .match_kind(@config.get_match_kind)
        .prefilter(core_prefilter)
        .utf8_empty(@config.get_utf8_empty)
      pikevm = ::Regex::Automata::NFA::PikeVM::Builder.new
        .configure(pike_config)
        .build_from_nfa(nfa)
      literal_prefilter, literal_pattern_ids = exact_literal_strategy(hirs_array, nfa.group_info)
      reverse_suffix_prefilter, reverse_suffix_dfa = build_reverse_suffix_strategy(hirs_array, props_union, core_prefilter, literal_prefilter)
      reverse_inner_prefilter, reverse_inner_dfa, reverse_inner_forward_dfa = build_reverse_inner_strategy(hirs_array, props_union, core_prefilter, literal_prefilter, reverse_suffix_prefilter)
      reverse_anchored_dfa = build_reverse_anchored_dfa(hirs_array, props_union)
      Regex.new(
        @config,
        hir_syntax_config,
        nfa,
        pikevm,
        core_prefilter,
        literal_prefilter,
        literal_pattern_ids,
        reverse_anchored_dfa,
        reverse_suffix_prefilter,
        reverse_suffix_dfa,
        reverse_inner_prefilter,
        reverse_inner_dfa,
        reverse_inner_forward_dfa,
        props_union
      )
    rescue ex : ::Regex::Automata::BuildError
      if ex.is_size_limit_exceeded && (limit = @config.get_nfa_size_limit)
        raise BuildError.size_limit(limit, ex)
      end
      raise BuildError.new(message: "error building NFA", syntax_error: ex.message, size_limit_exceeded: ex.is_size_limit_exceeded)
    end

    private def effective_which_captures : ::Regex::Automata::NFA::WhichCaptures
      case @config.get_which_captures
      when ::Regex::Automata::NFA::WhichCaptures::None
        ::Regex::Automata::NFA::WhichCaptures::Implicit
      else
        @config.get_which_captures
      end
    end

    private def effective_syntax_config : ::Regex::Automata::Syntax::Config
      @syntax_config.line_terminator(@config.get_line_terminator)
    end

    private def exact_literal_strategy(
      hirs : Array(::Regex::Syntax::Hir::Hir),
      group_info : ::Regex::Automata::GroupInfo,
    ) : {::Regex::Automata::Prefilter?, Array(::Regex::Automata::PatternID)?}
      return {nil, nil} unless @config.get_auto_prefilter
      return {nil, nil} if @config.get_prefilter
      return {nil, nil} unless group_info.explicit_slot_len == 0
      return {nil, nil} if hirs.size > 1 && @config.get_match_kind != ::Regex::Automata::MatchKind::LeftmostFirst

      literals = [] of Bytes
      pattern_ids = [] of ::Regex::Automata::PatternID
      hirs.each_with_index do |hir, index|
        return {nil, nil} unless hir.properties.look_set.empty?

        exact_literals = exact_literals_for_hir(hir)
        return {nil, nil} unless exact_literals

        pid = ::Regex::Automata::PatternID.new(index.to_i32)
        exact_literals.each do |literal|
          literals << literal
          pattern_ids << pid
        end
      end
      return {nil, nil} if literals.empty?

      {::Regex::Automata::Prefilter.new(@config.get_match_kind, literals), pattern_ids}
    end

    private def exact_literals_for_hir(
      hir : ::Regex::Syntax::Hir::Hir,
    ) : Array(Bytes)?
      extractor = ::Regex::Syntax::Hir::LiteralExtraction::Extractor.new
      extractor.kind(::Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Prefix)
      prefixes = extractor.extract(hir)
      if prefixes.finite? && prefixes.exact?
        literals = prefixes.literals
        return nil unless literals && !literals.empty?

        return literals.map do |literal|
          Bytes.new(literal.bytes.size) { |i| literal.bytes[i] }
        end
      end

      alternation_literals(hir)
    end

    private def alternation_literals(
      hir : ::Regex::Syntax::Hir::Hir,
    ) : Array(Bytes)?
      return nil unless hir.properties.alternation_literal?

      literals = extract_alternation_literals(hir.node)
      return nil unless literals
      return nil if literals.empty?

      literals
    end

    private def extract_alternation_literals(
      node : ::Regex::Syntax::Hir::Node,
    ) : Array(Bytes)?
      case node
      when ::Regex::Syntax::Hir::Literal
        literal = node.bytes
        return nil if literal.empty?
        [literal]
      when ::Regex::Syntax::Hir::Concat
        bytes = Bytes.empty
        node.children.each do |child|
          part = extract_literal_term(child)
          return nil unless part
          bytes = bytes + part
        end
        return nil if bytes.empty?
        [bytes]
      when ::Regex::Syntax::Hir::Alternation
        literals = [] of Bytes
        node.children.each do |child|
          parts = extract_alternation_literals(child)
          return nil unless parts
          literals.concat(parts)
        end
        literals
      else
        nil
      end
    end

    private def extract_literal_term(
      node : ::Regex::Syntax::Hir::Node,
    ) : Bytes?
      case node
      when ::Regex::Syntax::Hir::Literal
        bytes = node.bytes
        bytes.empty? ? nil : bytes
      when ::Regex::Syntax::Hir::Concat
        parts = [] of UInt8
        node.children.each do |child|
          bytes = extract_literal_term(child)
          return nil unless bytes
          parts.concat(bytes)
        end
        return nil if parts.empty?
        Bytes.new(parts.size) { |i| parts[i] }
      else
        nil
      end
    end

    private def build_core_prefilter(
      hirs : Array(::Regex::Syntax::Hir::Hir),
      props_union : ::Regex::Syntax::Hir::Properties,
    ) : ::Regex::Automata::Prefilter?
      return nil if props_union.look_set_prefix.contains(::Regex::Syntax::Hir::Look::Kind::StartText)
      if prefilter = @config.get_prefilter
        return prefilter
      end
      return nil unless @config.get_auto_prefilter

      ::Regex::Automata::Prefilter.from_hirs_prefix(@config.get_match_kind, hirs)
    end

    private def build_reverse_anchored_dfa(
      hirs : Array(::Regex::Syntax::Hir::Hir),
      props_union : ::Regex::Syntax::Hir::Properties,
    ) : ::Regex::Automata::DFA::DFA?
      return nil unless @config.get_dfa
      return nil unless props_union.look_set_suffix.contains(::Regex::Syntax::Hir::Look::Kind::EndText)
      return nil if props_union.look_set_prefix.contains(::Regex::Syntax::Hir::Look::Kind::StartText)
      build_reverse_dense_dfa(hirs)
    rescue ex : ::Regex::Automata::BuildError
      nil
    end

    private def build_reverse_suffix_strategy(
      hirs : Array(::Regex::Syntax::Hir::Hir),
      props_union : ::Regex::Syntax::Hir::Properties,
      core_prefilter : ::Regex::Automata::Prefilter?,
      literal_prefilter : ::Regex::Automata::Prefilter?,
    ) : Tuple(::Regex::Automata::Prefilter?, ::Regex::Automata::DFA::DFA?)
      return {nil, nil} unless @config.get_auto_prefilter
      return {nil, nil} unless @config.get_dfa
      return {nil, nil} if props_union.look_set_prefix.contains(::Regex::Syntax::Hir::Look::Kind::StartText)
      return {nil, nil} if core_prefilter.try(&.is_fast)
      return {nil, nil} if literal_prefilter.try(&.is_fast)

      extractor = ::Regex::Syntax::Hir::LiteralExtraction::Extractor.new
      extractor.kind(::Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Suffix)
      suffixes = ::Regex::Syntax::Hir::LiteralExtraction::Seq.empty
      hirs.each do |hir|
        suffixes.union(extractor.extract(hir))
      end
      case @config.get_match_kind
      when ::Regex::Automata::MatchKind::All
        suffixes.sort
        suffixes.dedup
      when ::Regex::Automata::MatchKind::LeftmostFirst
        suffixes.optimize_for_suffix_by_preference
      end

      lcs = suffixes.longest_common_suffix
      return {nil, nil} unless lcs && !lcs.empty?

      pre = ::Regex::Automata::Prefilter.new(@config.get_match_kind, [lcs])
      return {nil, nil} unless pre && pre.is_fast

      dfa = build_reverse_dense_dfa(hirs)
      return {nil, nil} unless dfa

      {pre, dfa}
    rescue ex : ::Regex::Automata::BuildError
      {nil, nil}
    end

    private def build_reverse_inner_strategy(
      hirs : Array(::Regex::Syntax::Hir::Hir),
      props_union : ::Regex::Syntax::Hir::Properties,
      core_prefilter : ::Regex::Automata::Prefilter?,
      literal_prefilter : ::Regex::Automata::Prefilter?,
      reverse_suffix_prefilter : ::Regex::Automata::Prefilter?,
    ) : Tuple(::Regex::Automata::Prefilter?, ::Regex::Automata::DFA::DFA?, ::Regex::Automata::DFA::DFA?)
      return {nil, nil, nil} unless @config.get_auto_prefilter
      return {nil, nil, nil} unless @config.get_dfa
      return {nil, nil, nil} unless @config.get_match_kind == ::Regex::Automata::MatchKind::LeftmostFirst
      return {nil, nil, nil} if props_union.look_set_prefix.contains(::Regex::Syntax::Hir::Look::Kind::StartText)
      return {nil, nil, nil} if core_prefilter.try(&.is_fast)
      return {nil, nil, nil} if literal_prefilter.try(&.is_fast)
      return {nil, nil, nil} if reverse_suffix_prefilter.try(&.is_fast)
      return {nil, nil, nil} unless hirs.size == 1

      concat_prefix, preinner = extract_reverse_inner_strategy(hirs.first)
      return {nil, nil, nil} unless concat_prefix && preinner

      dfa = build_reverse_dense_dfa([concat_prefix])
      fwd = build_forward_dense_dfa(hirs)
      {preinner, dfa, fwd}
    rescue ex : ::Regex::Automata::BuildError
      {nil, nil, nil}
    end

    private def extract_reverse_inner_strategy(
      hir : ::Regex::Syntax::Hir::Hir,
    ) : Tuple(::Regex::Syntax::Hir::Hir?, ::Regex::Automata::Prefilter?)
      concat = reverse_inner_top_concat(hir)
      return {nil, nil} unless concat

      i = 1
      while i < concat.size
        sub_hir = ::Regex::Syntax::Hir::Hir.new(concat[i])
        pre = reverse_inner_prefilter(sub_hir)
        if pre && pre.is_fast
          concat_suffix = ::Regex::Syntax::Hir::Hir.concat(concat[i..])
          concat_prefix = ::Regex::Syntax::Hir::Hir.concat(concat[0...i])
          better = reverse_inner_prefilter(concat_suffix)
          pre = better if better && better.is_fast
          return {concat_prefix, pre}
        end
        i += 1
      end
      {nil, nil}
    end

    private def reverse_inner_prefilter(hir : ::Regex::Syntax::Hir::Hir) : ::Regex::Automata::Prefilter?
      extractor = ::Regex::Syntax::Hir::LiteralExtraction::Extractor.new
      extractor.kind(::Regex::Syntax::Hir::LiteralExtraction::ExtractKind::Prefix)
      prefixes = extractor.extract(hir)
      prefixes.make_inexact
      prefixes.optimize_for_prefix_by_preference
      literals = prefixes.literals
      return nil unless literals

      ::Regex::Automata::Prefilter.new(::Regex::Automata::MatchKind::LeftmostFirst, literals.map(&.bytes))
    end

    private def reverse_inner_top_concat(hir : ::Regex::Syntax::Hir::Hir) : Array(::Regex::Syntax::Hir::Node)?
      current = hir.node
      loop do
        case current
        when ::Regex::Syntax::Hir::Capture
          current = current.sub
        when ::Regex::Syntax::Hir::Concat
          flattened = ::Regex::Syntax::Hir::Hir.concat(current.children.map { |child| reverse_inner_flatten(child) })
          kind = flattened.into_kind
          return kind.children if kind.is_a?(::Regex::Syntax::Hir::Concat)
          return nil
        else
          return nil
        end
      end
    end

    private def reverse_inner_flatten(node : ::Regex::Syntax::Hir::Node) : ::Regex::Syntax::Hir::Node
      case node
      when ::Regex::Syntax::Hir::Capture
        reverse_inner_flatten(node.sub)
      when ::Regex::Syntax::Hir::Alternation
        ::Regex::Syntax::Hir::Hir.alternation(node.children.map { |child| reverse_inner_flatten(child) }).node
      when ::Regex::Syntax::Hir::Concat
        ::Regex::Syntax::Hir::Hir.concat(node.children.map { |child| reverse_inner_flatten(child) }).node
      when ::Regex::Syntax::Hir::Repetition
        ::Regex::Syntax::Hir::Hir.repetition(reverse_inner_flatten(node.sub), node.min, node.max, node.greedy?).node
      else
        node
      end
    end

    private def build_reverse_dense_dfa(
      hirs : Array(::Regex::Syntax::Hir::Hir),
    ) : ::Regex::Automata::DFA::DFA
      build_dense_dfa(hirs, reverse: true)
    end

    private def build_forward_dense_dfa(
      hirs : Array(::Regex::Syntax::Hir::Hir),
    ) : ::Regex::Automata::DFA::DFA
      build_dense_dfa(hirs, reverse: false)
    end

    private def build_dense_dfa(
      hirs : Array(::Regex::Syntax::Hir::Hir),
      *,
      reverse : Bool,
    ) : ::Regex::Automata::DFA::DFA
      props_union = ::Regex::Syntax::Hir::Properties.union(hirs.map(&.properties))
      compile_config = ::Regex::Automata::HirCompilerConfig.new(
        utf8: props_union.utf8?,
        reverse: reverse,
        nfa_size_limit: @config.get_nfa_size_limit,
        which_captures: ::Regex::Automata::NFA::WhichCaptures::None,
        look_matcher: ::Regex::Automata::LookMatcher.new(@config.get_line_terminator),
        unanchored_prefix: false
      )
      nfa = ::Regex::Automata::HirCompiler.new(compile_config, ::Regex::Automata::Syntax::Config.new).build_many_from_hir(hirs)

      size_limit = @config.get_dfa_size_limit.try { |limit| limit // 2 }
      dfa_config = ::Regex::Automata::Config.new
        .match_kind(::Regex::Automata::MatchKind::All)
        .prefilter(nil)
        .accelerate(false)
        .start_kind(::Regex::Automata::StartKind::Anchored)
        .starts_for_each_pattern(false)
        .byte_classes(@config.get_byte_classes)
        .unicode_word_boundary(true)
        .specialize_start_states(false)
        .determinize_size_limit(size_limit)
        .dfa_size_limit(size_limit)
      ::Regex::Automata::DFA::Builder.from_nfa(nfa, dfa_config).build
    end
  end

  class Regex
    getter pikevm : ::Regex::Automata::NFA::PikeVM
    getter nfa : ::Regex::Automata::NFA::NFA
    getter group_info : ::Regex::Automata::GroupInfo
    getter syntax_config : ::Regex::Automata::Syntax::Config

    @config : Config
    @static_captures_len : Int32?
    @core_prefilter : ::Regex::Automata::Prefilter?
    @literal_prefilter : ::Regex::Automata::Prefilter?
    @literal_pattern_ids : Array(::Regex::Automata::PatternID)?
    @reverse_anchored_dfa : ::Regex::Automata::DFA::DFA?
    @reverse_suffix_prefilter : ::Regex::Automata::Prefilter?
    @reverse_suffix_dfa : ::Regex::Automata::DFA::DFA?
    @reverse_inner_prefilter : ::Regex::Automata::Prefilter?
    @reverse_inner_dfa : ::Regex::Automata::DFA::DFA?
    @reverse_inner_forward_dfa : ::Regex::Automata::DFA::DFA?
    @always_anchored_start : Bool
    @always_anchored_end : Bool

    def initialize(
      @config : Config,
      @syntax_config : ::Regex::Automata::Syntax::Config,
      @nfa : ::Regex::Automata::NFA::NFA,
      @pikevm : ::Regex::Automata::NFA::PikeVM,
      @core_prefilter : ::Regex::Automata::Prefilter? = nil,
      @literal_prefilter : ::Regex::Automata::Prefilter? = nil,
      @literal_pattern_ids : Array(::Regex::Automata::PatternID)? = nil,
      @reverse_anchored_dfa : ::Regex::Automata::DFA::DFA? = nil,
      @reverse_suffix_prefilter : ::Regex::Automata::Prefilter? = nil,
      @reverse_suffix_dfa : ::Regex::Automata::DFA::DFA? = nil,
      @reverse_inner_prefilter : ::Regex::Automata::Prefilter? = nil,
      @reverse_inner_dfa : ::Regex::Automata::DFA::DFA? = nil,
      @reverse_inner_forward_dfa : ::Regex::Automata::DFA::DFA? = nil,
      props_union : ::Regex::Syntax::Hir::Properties = ::Regex::Syntax::Hir::Properties.union([] of ::Regex::Syntax::Hir::Properties),
    )
      @group_info = @nfa.group_info
      @static_captures_len = props_union.static_explicit_captures_len.try { |len| len + 1 }
      @always_anchored_start = props_union.look_set_prefix.contains(::Regex::Syntax::Hir::Look::Kind::StartText)
      @always_anchored_end = props_union.look_set_suffix.contains(::Regex::Syntax::Hir::Look::Kind::EndText)
    end

    def self.new(pattern : String) : Regex
      builder.build(pattern)
    end

    def self.new_many(patterns : Enumerable(String)) : Regex
      builder.build_many(patterns)
    end

    def self.config : Config
      Config.new
    end

    def self.builder : Builder
      Builder.new
    end

    def get_config : Config
      @config
    end

    def pattern_len : Int32
      @nfa.pattern_len
    end

    def captures_len : Int32
      total = 0
      pid = 0
      while pid < pattern_len
        total += @group_info.group_len(::Regex::Automata::PatternID.new(pid))
        pid += 1
      end
      total.to_i32
    end

    def static_captures_len : Int32?
      @static_captures_len
    end

    def memory_usage : Int32
      @pikevm.memory_usage +
        (@core_prefilter.try(&.memory_usage) || 0) +
        (@literal_prefilter.try(&.memory_usage) || 0) +
        (@reverse_anchored_dfa.try(&.memory_usage) || 0) +
        (@reverse_suffix_prefilter.try(&.memory_usage) || 0) +
        (@reverse_suffix_dfa.try(&.memory_usage) || 0) +
        (@reverse_inner_prefilter.try(&.memory_usage) || 0) +
        (@reverse_inner_dfa.try(&.memory_usage) || 0) +
        (@reverse_inner_forward_dfa.try(&.memory_usage) || 0)
    end

    def is_accelerated : Bool
      @core_prefilter.try(&.is_fast) == true ||
        literal_strategy? ||
        !@reverse_anchored_dfa.nil? ||
        @reverse_suffix_prefilter.try(&.is_fast) == true ||
        @reverse_inner_prefilter.try(&.is_fast) == true
    end

    def byte_classes : Bool
      @config.get_byte_classes
    end

    def create_cache : Cache
      Cache.new(self)
    end

    def reset(cache : Cache) : Nil
      cache.reset(self)
    end

    def create_captures : ::Regex::Automata::Captures
      ::Regex::Automata::Captures.all(@group_info)
    end

    def search(input : ::Regex::Automata::Input) : ::Regex::Automata::Match?
      cache = create_cache
      search_with(cache, input)
    end

    def search_half(input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch?
      cache = create_cache
      search_half_with(cache, input)
    end

    def search_captures(input : ::Regex::Automata::Input, caps : ::Regex::Automata::Captures) : Nil
      cache = create_cache
      search_captures_with(cache, input, caps)
    end

    def search_slots(input : ::Regex::Automata::Input, slots : Array(::Regex::Automata::NonMaxUsize?)) : ::Regex::Automata::PatternID?
      cache = create_cache
      search_slots_with(cache, input, slots)
    end

    def search_slots(input : ::Regex::Automata::Input, slots : Array(Int32?)) : ::Regex::Automata::PatternID?
      cache = create_cache
      search_slots_with(cache, input, slots)
    end

    def which_overlapping_matches(input : ::Regex::Automata::Input, patset : ::Regex::Automata::PatternSet) : Nil
      cache = create_cache
      which_overlapping_matches_with(cache, input, patset)
    end

    def search_with(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::Match?
      return nil if impossible_input?(input)
      if reverse_match = reverse_anchored_search(input)
        return reverse_match
      end
      if literal = literal_search(input)
        return literal
      end
      if suffix_match = reverse_suffix_search(cache, input)
        return suffix_match
      end
      if inner_match = reverse_inner_search(cache, input)
        return inner_match
      end
      @pikevm.find(cache.raw_cache, input)
    end

    def search_half_with(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch?
      return nil if impossible_input?(input)
      if reverse_match = reverse_anchored_search(input)
        return ::Regex::Automata::HalfMatch.new(reverse_match.pattern, input.end)
      end
      search_with(cache, input).try { |match| ::Regex::Automata::HalfMatch.new(match.pattern, match.end) }
    end

    def search_captures_with(cache : Cache, input : ::Regex::Automata::Input, caps : ::Regex::Automata::Captures) : Nil
      if impossible_input?(input)
        caps.clear
        return
      end
      if reverse_match = reverse_anchored_search(input)
        search_captures_from_match(cache, input, caps, reverse_match)
        return
      end
      if literal = literal_search(input)
        set_match_captures(caps, literal)
        return
      end
      if suffix_match = reverse_suffix_search(cache, input)
        search_captures_from_match(cache, input, caps, suffix_match)
        return
      end
      if inner_match = reverse_inner_search(cache, input)
        search_captures_from_match(cache, input, caps, inner_match)
        return
      end
      if literal_strategy?
        caps.clear
        return
      end
      @pikevm.search(cache.raw_cache, input, caps)
    end

    def search_slots_with(cache : Cache, input : ::Regex::Automata::Input, slots : Array(::Regex::Automata::NonMaxUsize?)) : ::Regex::Automata::PatternID?
      if impossible_input?(input)
        clear_slots(slots)
        return nil
      end
      if reverse_match = reverse_anchored_search(input)
        return search_slots_from_match(cache, input, slots, reverse_match)
      end
      if literal = literal_search(input)
        set_match_slots(slots, literal)
        return literal.pattern
      end
      if suffix_match = reverse_suffix_search(cache, input)
        return search_slots_from_match(cache, input, slots, suffix_match)
      end
      if inner_match = reverse_inner_search(cache, input)
        return search_slots_from_match(cache, input, slots, inner_match)
      end
      clear_slots(slots) if literal_strategy?
      @pikevm.search_slots(cache.raw_cache, input, slots)
    end

    def search_slots_with(cache : Cache, input : ::Regex::Automata::Input, slots : Array(Int32?)) : ::Regex::Automata::PatternID?
      if impossible_input?(input)
        clear_slots(slots)
        return nil
      end
      if reverse_match = reverse_anchored_search(input)
        return search_slots_from_match(cache, input, slots, reverse_match)
      end
      if literal = literal_search(input)
        set_match_slots(slots, literal)
        return literal.pattern
      end
      if suffix_match = reverse_suffix_search(cache, input)
        return search_slots_from_match(cache, input, slots, suffix_match)
      end
      if inner_match = reverse_inner_search(cache, input)
        return search_slots_from_match(cache, input, slots, inner_match)
      end
      clear_slots(slots) if literal_strategy?
      @pikevm.search_slots(cache.raw_cache, input, slots)
    end

    def which_overlapping_matches_with(cache : Cache, input : ::Regex::Automata::Input, patset : ::Regex::Automata::PatternSet) : Nil
      return if impossible_input?(input)
      if literal_strategy?
        literal_overlapping_matches(input, patset)
        return
      end
      @pikevm.which_overlapping_matches(cache.raw_cache, input, patset)
    end

    def is_match(haystack : String | Bytes | ::Regex::Automata::Input) : Bool
      input = normalize_input(haystack)
      input.earliest(true)
      !search(input).nil?
    end

    def find(haystack : String | Bytes | ::Regex::Automata::Input) : ::Regex::Automata::Match?
      search(normalize_input(haystack))
    end

    def captures(haystack : String | Bytes | ::Regex::Automata::Input, caps : ::Regex::Automata::Captures) : Nil
      search_captures(normalize_input(haystack), caps)
    end

    def find_iter(haystack : String | Bytes | ::Regex::Automata::Input) : FindMatches
      FindMatches.new(self, create_cache, ::Regex::Automata::Searcher.new(normalize_input(haystack)))
    end

    def captures_iter(haystack : String | Bytes | ::Regex::Automata::Input) : CapturesMatches
      CapturesMatches.new(self, create_cache, create_captures, ::Regex::Automata::Searcher.new(normalize_input(haystack)))
    end

    def split(haystack : String | Bytes | ::Regex::Automata::Input) : Split
      Split.new(self, normalize_input(haystack))
    end

    def splitn(limit : Int32, haystack : String | Bytes | ::Regex::Automata::Input) : SplitN
      SplitN.new(self, normalize_input(haystack), limit)
    end

    private def normalize_input(input : ::Regex::Automata::Input) : ::Regex::Automata::Input
      input.clone
    end

    private def normalize_input(haystack : String) : ::Regex::Automata::Input
      ::Regex::Automata::Input.new(haystack)
    end

    private def normalize_input(haystack : Bytes) : ::Regex::Automata::Input
      ::Regex::Automata::Input.new(haystack)
    end

    private def literal_search(input : ::Regex::Automata::Input) : ::Regex::Automata::Match?
      candidate = literal_search_candidate(input)
      return nil unless candidate

      pattern_ids = @literal_pattern_ids.not_nil!
      ::Regex::Automata::Match.new(pattern_ids[candidate[0]], candidate[1].start, candidate[1].end)
    end

    private def literal_strategy? : Bool
      !@literal_prefilter.nil? && !@literal_pattern_ids.nil?
    end

    private def literal_search_candidate(
      input : ::Regex::Automata::Input,
    ) : Tuple(Int32, ::Regex::Automata::Span)?
      prefilter = @literal_prefilter
      pattern_ids = @literal_pattern_ids
      return nil unless prefilter && pattern_ids

      needles = prefilter.needles
      span = ::Regex::Automata::Span.new(input.start, input.end)
      case input.anchored
      when ::Regex::Automata::Anchored::No
        literal_find_candidate(input.haystack, span, needles, pattern_ids, nil)
      when ::Regex::Automata::Anchored::Yes
        literal_prefix_candidate(input.haystack, span, needles, pattern_ids, nil)
      when ::Regex::Automata::Anchored::Pattern
        pattern = input.pattern
        return nil unless pattern
        literal_prefix_candidate(input.haystack, span, needles, pattern_ids, pattern)
      else
        nil
      end
    end

    private def literal_find_candidate(
      haystack : Bytes,
      span : ::Regex::Automata::Span,
      needles : Array(Bytes),
      pattern_ids : Array(::Regex::Automata::PatternID),
      target_pattern : ::Regex::Automata::PatternID?,
    ) : Tuple(Int32, ::Regex::Automata::Span)?
      best_span = nil.as(::Regex::Automata::Span?)
      best_index = Int32::MAX
      needles.each_with_index do |needle, index|
        next if target_pattern && pattern_ids[index] != target_pattern
        next unless start = literal_find_needle(haystack, needle, span)

        candidate = ::Regex::Automata::Span.new(start, start + needle.size)
        if better_literal_match?(candidate, index.to_i32, best_span, best_index)
          best_span = candidate
          best_index = index.to_i32
        end
      end
      return nil unless best_span

      {best_index, best_span}
    end

    private def literal_prefix_candidate(
      haystack : Bytes,
      span : ::Regex::Automata::Span,
      needles : Array(Bytes),
      pattern_ids : Array(::Regex::Automata::PatternID),
      target_pattern : ::Regex::Automata::PatternID?,
    ) : Tuple(Int32, ::Regex::Automata::Span)?
      best_index = Int32::MAX
      best_span = nil.as(::Regex::Automata::Span?)
      needles.each_with_index do |needle, index|
        next if target_pattern && pattern_ids[index] != target_pattern
        next if needle.size > span.length
        next unless literal_starts_with?(haystack, span.start, needle)

        candidate = ::Regex::Automata::Span.new(span.start, span.start + needle.size)
        if better_literal_match?(candidate, index.to_i32, best_span, best_index)
          best_span = candidate
          best_index = index.to_i32
        end
      end
      return nil unless best_span

      {best_index, best_span}
    end

    private def literal_overlapping_matches(
      input : ::Regex::Automata::Input,
      patset : ::Regex::Automata::PatternSet,
    ) : Nil
      candidate = literal_search_candidate(input)
      return unless candidate

      prefilter = @literal_prefilter.not_nil!
      pattern_ids = @literal_pattern_ids.not_nil!
      needles = prefilter.needles
      match_start = candidate[1].start
      limit = input.end
      needles.each_with_index do |needle, index|
        case input.anchored
        when ::Regex::Automata::Anchored::Pattern
          next unless input.pattern == pattern_ids[index]
        end
        next unless literal_matches_at?(input.haystack, needle, match_start, limit)

        patset.insert(pattern_ids[index])
      end
    end

    private def better_literal_match?(
      candidate : ::Regex::Automata::Span,
      index : Int32,
      current : ::Regex::Automata::Span?,
      current_index : Int32,
    ) : Bool
      return true unless current
      return true if candidate.start < current.start
      return false if candidate.start > current.start

      index < current_index
    end

    private def literal_find_needle(
      haystack : Bytes,
      needle : Bytes,
      span : ::Regex::Automata::Span,
    ) : Int32?
      limit = span.end - needle.size
      at = span.start
      while at <= limit
        return at if literal_starts_with?(haystack, at, needle)
        at += 1
      end
      nil
    end

    private def literal_matches_at?(
      haystack : Bytes,
      needle : Bytes,
      offset : Int32,
      limit : Int32,
    ) : Bool
      return false if offset < 0 || offset + needle.size > limit

      literal_starts_with?(haystack, offset, needle)
    end

    private def literal_starts_with?(haystack : Bytes, offset : Int32, needle : Bytes) : Bool
      return false if offset < 0 || offset + needle.size > haystack.size

      i = 0
      while i < needle.size
        return false if haystack[offset + i] != needle[i]
        i += 1
      end
      true
    end

    private def impossible_input?(input : ::Regex::Automata::Input) : Bool
      return true if @always_anchored_start && input.start > 0
      return true if @always_anchored_end && input.end < input.haystack.size

      false
    end

    private def reverse_anchored_search(input : ::Regex::Automata::Input) : ::Regex::Automata::Match?
      dfa = @reverse_anchored_dfa
      return nil unless dfa
      return nil if input.anchored.is_anchored

      reverse_match_from_dfa(dfa, input).try { |match| ::Regex::Automata::Match.new(match.pattern, match.start, input.end) }
    end

    private def reverse_suffix_search(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::Match?
      prefilter = @reverse_suffix_prefilter
      return nil unless prefilter
      return nil if input.anchored.is_anchored

      hm_start = reverse_suffix_start(input)
      case hm_start
      when ::Regex::Automata::Meta::RetryError
        return @pikevm.find(cache.raw_cache, input)
      when Nil
        return nil
      end

      scoped = input.clone
        .span(hm_start.offset...input.end)
        .anchored(::Regex::Automata::Anchored::Pattern, hm_start.pattern)
      @pikevm.find(cache.raw_cache, scoped)
    end

    private def reverse_suffix_start(input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch? | ::Regex::Automata::Meta::RetryError
      prefilter = @reverse_suffix_prefilter
      dfa = @reverse_suffix_dfa
      return nil unless prefilter && dfa

      span = ::Regex::Automata::Span.new(input.start, input.end)
      min_start = input.start
      loop do
        litmatch = prefilter.find(input.haystack, span)
        return nil unless litmatch

        revinput = input.clone
          .span(min_start...litmatch.end)
          .anchored(::Regex::Automata::Anchored::Yes)
        start_match = ::Regex::Automata::Meta::Limited.dfa_try_search_half_rev(dfa, revinput, min_start)
        case start_match
        when ::Regex::Automata::Meta::RetryError
          return start_match
        when ::Regex::Automata::HalfMatch
          return start_match
        end

        break if span.start >= span.end

        next_start = litmatch.start + 1
        break if next_start > span.end

        span = ::Regex::Automata::Span.new(next_start, span.end)
        min_start = litmatch.end
      end
      nil
    end

    private def reverse_inner_search(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::Match?
      prefilter = @reverse_inner_prefilter
      dfa = @reverse_inner_dfa
      fwd = @reverse_inner_forward_dfa
      return nil unless prefilter && dfa && fwd
      return nil if input.anchored.is_anchored

      span = ::Regex::Automata::Span.new(input.start, input.end)
      min_match_start = input.start
      min_pre_start = input.start
      loop do
        litmatch = prefilter.find(input.haystack, span)
        return nil unless litmatch
        return @pikevm.find(cache.raw_cache, input) if litmatch.start < min_pre_start

        revinput = input.clone
          .span(input.start...litmatch.start)
          .anchored(::Regex::Automata::Anchored::Yes)
        start_match = ::Regex::Automata::Meta::Limited.dfa_try_search_half_rev(dfa, revinput, min_match_start)
        case start_match
        when ::Regex::Automata::Meta::RetryError
          return @pikevm.find(cache.raw_cache, input)
        when ::Regex::Automata::HalfMatch
          scoped = input.clone
            .span(start_match.offset...input.end)
            .anchored(::Regex::Automata::Anchored::Yes)
          stop_match = ::Regex::Automata::Meta::StopAt.dfa_try_search_half_fwd(fwd, scoped)
          case stop_match
          when ::Regex::Automata::Meta::RetryFailError
            return @pikevm.find(cache.raw_cache, input)
          when ::Regex::Automata::HalfMatch
            return ::Regex::Automata::Match.new(start_match.pattern, start_match.offset, stop_match.offset)
          when Int32
            min_pre_start = stop_match
          end
        end

        break if span.start >= span.end

        next_start = litmatch.start + 1
        break if next_start > span.end

        span = ::Regex::Automata::Span.new(next_start, span.end)
        min_match_start = litmatch.end
      end
      nil
    end

    private def reverse_match_from_dfa(
      dfa : ::Regex::Automata::DFA::DFA,
      input : ::Regex::Automata::Input,
    ) : ::Regex::Automata::Match?
      slice = input.haystack[input.start, input.end - input.start]
      result = dfa.try_search_rev(slice)
      return nil unless result.is_a?(Tuple(Int32, Array(::Regex::Automata::PatternID)))

      start_offset, pattern_ids = result
      pattern_id = pattern_ids.first?
      return nil unless pattern_id

      ::Regex::Automata::Match.new(pattern_id, input.start + start_offset, input.end)
    end

    private def search_captures_from_match(
      cache : Cache,
      input : ::Regex::Automata::Input,
      caps : ::Regex::Automata::Captures,
      match : ::Regex::Automata::Match,
    ) : Nil
      if capture_search_needed?(caps.slot_len)
        scoped = input.clone
          .span(match.start...match.end)
          .anchored(::Regex::Automata::Anchored::Pattern, match.pattern)
        @pikevm.search(cache.raw_cache, scoped, caps)
      else
        set_match_captures(caps, match)
      end
    end

    private def search_slots_from_match(
      cache : Cache,
      input : ::Regex::Automata::Input,
      slots : Array(::Regex::Automata::NonMaxUsize?),
      match : ::Regex::Automata::Match,
    ) : ::Regex::Automata::PatternID?
      if capture_search_needed?(slots.size)
        clear_slots(slots)
        scoped = input.clone
          .span(match.start...match.end)
          .anchored(::Regex::Automata::Anchored::Pattern, match.pattern)
        @pikevm.search_slots(cache.raw_cache, scoped, slots)
      else
        set_match_slots(slots, match)
        match.pattern
      end
    end

    private def search_slots_from_match(
      cache : Cache,
      input : ::Regex::Automata::Input,
      slots : Array(Int32?),
      match : ::Regex::Automata::Match,
    ) : ::Regex::Automata::PatternID?
      if capture_search_needed?(slots.size)
        clear_slots(slots)
        scoped = input.clone
          .span(match.start...match.end)
          .anchored(::Regex::Automata::Anchored::Pattern, match.pattern)
        @pikevm.search_slots(cache.raw_cache, scoped, slots)
      else
        set_match_slots(slots, match)
        match.pattern
      end
    end

    private def capture_search_needed?(slot_len : Int32) : Bool
      slot_len > @group_info.implicit_slot_len
    end

    private def set_match_captures(caps : ::Regex::Automata::Captures, match : ::Regex::Automata::Match) : Nil
      caps.clear
      caps.set_pattern(match.pattern)
      slots = caps.slots_mut
      slot_pair = @group_info.slots(match.pattern, 0)
      return unless slot_pair

      slot_start, slot_end = slot_pair
      return if slot_end >= slots.size

      slots[slot_start] = match.start
      slots[slot_end] = match.end
    end

    private def clear_slots(slots : Array(::Regex::Automata::NonMaxUsize?)) : Nil
      slots.map! { nil }
    end

    private def clear_slots(slots : Array(Int32?)) : Nil
      slots.map! { nil }
    end

    private def set_match_slots(slots : Array(::Regex::Automata::NonMaxUsize?), match : ::Regex::Automata::Match) : Nil
      clear_slots(slots)
      slot_pair = @group_info.slots(match.pattern, 0)
      return unless slot_pair

      slot_start, slot_end = slot_pair
      return if slot_end >= slots.size

      slots[slot_start] = ::Regex::Automata::NonMaxUsize.new(match.start)
      slots[slot_end] = ::Regex::Automata::NonMaxUsize.new(match.end)
    end

    private def set_match_slots(slots : Array(Int32?), match : ::Regex::Automata::Match) : Nil
      clear_slots(slots)
      slot_pair = @group_info.slots(match.pattern, 0)
      return unless slot_pair

      slot_start, slot_end = slot_pair
      return if slot_end >= slots.size

      slots[slot_start] = match.start
      slots[slot_end] = match.end
    end
  end

  class FindMatches
    include Enumerable(::Regex::Automata::Match)

    getter regex : Regex

    def initialize(@regex : Regex, @cache : Cache, @it : ::Regex::Automata::Searcher)
    end

    def next : ::Regex::Automata::Match?
      @it.advance { |input| @regex.search_with(@cache, input) }
    end

    def each(&block : ::Regex::Automata::Match ->) : Nil
      while match = self.next
        yield match
      end
    end
  end

  class CapturesMatches
    include Enumerable(::Regex::Automata::Captures)

    getter regex : Regex

    def initialize(@regex : Regex, @cache : Cache, @caps : ::Regex::Automata::Captures, @it : ::Regex::Automata::Searcher)
    end

    def next : ::Regex::Automata::Captures?
      @it.advance do |input|
        @regex.search_captures_with(@cache, input, @caps)
        @caps.get_match
      end
      return nil unless @caps.is_match

      @caps.clone
    end

    def each(&block : ::Regex::Automata::Captures ->) : Nil
      while caps = self.next
        yield caps
      end
    end
  end

  class Split
    include Iterator(::Regex::Automata::Span)

    def initialize(@regex : Regex, @input : ::Regex::Automata::Input)
      @matches = @regex.find_iter(@input)
      @last_end = @input.start
      @done = false
    end

    def next
      return stop if @done

      if match = @matches.next
        span = ::Regex::Automata::Span.new(@last_end, match.start)
        @last_end = match.end
        return span
      end

      @done = true
      ::Regex::Automata::Span.new(@last_end, @input.end)
    end
  end

  class SplitN
    include Iterator(::Regex::Automata::Span)

    def initialize(@regex : Regex, @input : ::Regex::Automata::Input, limit : Int32)
      @remaining = limit
      @split = Split.new(@regex, @input)
      @done = limit <= 0
      @last_end = @input.start
    end

    def next
      return stop if @done
      if @remaining == 1
        @done = true
        return ::Regex::Automata::Span.new(@last_end, @input.end)
      end

      span = @split.next
      return stop if span.is_a?(Iterator::Stop)

      typed = span.as(::Regex::Automata::Span)
      @last_end = typed.end
      @remaining -= 1 if @remaining > 0
      typed
    end
  end
end
