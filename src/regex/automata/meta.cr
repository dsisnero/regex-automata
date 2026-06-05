require "./meta_error"
require "./captures"
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
      compile_config = ::Regex::Automata::HirCompilerConfig.new(
        utf8: effective_syntax_config.get_utf8,
        nfa_size_limit: @config.get_nfa_size_limit,
        which_captures: effective_which_captures,
        look_matcher: ::Regex::Automata::LookMatcher.new(@config.get_line_terminator)
      )
      nfa = ::Regex::Automata::HirCompiler.new(compile_config, effective_syntax_config).build_many_from_hir(hirs)
      pike_config = ::Regex::Automata::NFA::PikeVM::Config.new
        .match_kind(@config.get_match_kind)
        .prefilter(@config.get_prefilter)
        .utf8_empty(@config.get_utf8_empty)
      pikevm = ::Regex::Automata::NFA::PikeVM::Builder.new
        .configure(pike_config)
        .build_from_nfa(nfa)
      Regex.new(@config, effective_syntax_config, nfa, pikevm)
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
  end

  class Regex
    getter pikevm : ::Regex::Automata::NFA::PikeVM
    getter nfa : ::Regex::Automata::NFA::NFA
    getter group_info : ::Regex::Automata::GroupInfo
    getter syntax_config : ::Regex::Automata::Syntax::Config

    @config : Config
    @static_captures_len : Int32?

    def initialize(
      @config : Config,
      @syntax_config : ::Regex::Automata::Syntax::Config,
      @nfa : ::Regex::Automata::NFA::NFA,
      @pikevm : ::Regex::Automata::NFA::PikeVM,
    )
      @group_info = @nfa.group_info
      @static_captures_len = compute_static_captures_len
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
      @pikevm.memory_usage
    end

    def is_accelerated : Bool
      false
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
      @pikevm.find(cache.raw_cache, input)
    end

    def search_half_with(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch?
      search_with(cache, input).try { |match| ::Regex::Automata::HalfMatch.new(match.pattern, match.end) }
    end

    def search_captures_with(cache : Cache, input : ::Regex::Automata::Input, caps : ::Regex::Automata::Captures) : Nil
      @pikevm.search(cache.raw_cache, input, caps)
    end

    def search_slots_with(cache : Cache, input : ::Regex::Automata::Input, slots : Array(::Regex::Automata::NonMaxUsize?)) : ::Regex::Automata::PatternID?
      @pikevm.search_slots(cache.raw_cache, input, slots)
    end

    def search_slots_with(cache : Cache, input : ::Regex::Automata::Input, slots : Array(Int32?)) : ::Regex::Automata::PatternID?
      @pikevm.search_slots(cache.raw_cache, input, slots)
    end

    def which_overlapping_matches_with(cache : Cache, input : ::Regex::Automata::Input, patset : ::Regex::Automata::PatternSet) : Nil
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

    private def compute_static_captures_len : Int32?
      return nil if pattern_len <= 0

      expected = @group_info.group_len(::Regex::Automata::PatternID.new(0))
      pid = 1
      while pid < pattern_len
        return nil if @group_info.group_len(::Regex::Automata::PatternID.new(pid)) != expected
        pid += 1
      end
      expected
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
