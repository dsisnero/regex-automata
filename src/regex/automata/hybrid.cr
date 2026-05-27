require "./dfa"
require "./dfa_regex"

module Regex::Automata::Hybrid
  DEFAULT_CACHE_CAPACITY = 2 * (1 << 20)
  MINIMUM_CACHE_CAPACITY = 1

  class BuildError < ::Regex::Automata::BuildError
    def self.insufficient_cache_capacity(minimum : Int32, given : Int32) : BuildError
      new("given cache capacity (#{given}) is smaller than minimum required (#{minimum})")
    end

    def self.unsupported(message : String) : BuildError
      new("unsupported regex feature for DFAs: #{message}")
    end
  end

  class CacheError < ::Regex::Automata::Error
    def self.too_many_cache_clears : CacheError
      new("lazy DFA cache has been cleared too many times")
    end

    def self.bad_efficiency : CacheError
      new("lazy DFA cache has been cleared too many times")
    end
  end

  class StartError < ::Regex::Automata::Error
    getter? cache : Bool
    getter byte : UInt8?
    getter mode : ::Regex::Automata::Anchored?

    def self.cache : StartError
      new("error computing start state because of cache inefficiency", cache: true)
    end

    def self.quit(byte : UInt8) : StartError
      new("error computing start state because the look-behind byte #{byte} triggered a quit state", byte: byte)
    end

    def self.unsupported_anchored(mode : ::Regex::Automata::Anchored) : StartError
      message = case mode
                when ::Regex::Automata::Anchored::Yes
                  "error computing start state because anchored searches are not supported or enabled"
                when ::Regex::Automata::Anchored::No
                  "error computing start state because unanchored searches are not supported or enabled"
                when ::Regex::Automata::Anchored::Pattern
                  "error computing start state because anchored searches for a specific pattern are not supported or enabled"
                else
                  raise "unreachable anchored mode: #{mode}"
                end
      new(message, mode: mode)
    end

    def initialize(message : String, @cache : Bool = false, @byte : UInt8? = nil, @mode : ::Regex::Automata::Anchored? = nil)
      super(message)
    end
  end

  struct LazyStateIDError
    getter attempted : Int64

    def initialize(@attempted : Int64)
    end
  end

  struct LazyStateID
    MAX_BIT      = 31
    MASK_UNKNOWN = 1 << MAX_BIT
    MASK_DEAD    = 1 << (MAX_BIT - 1)
    MASK_QUIT    = 1 << (MAX_BIT - 2)
    MASK_START   = 1 << (MAX_BIT - 3)
    MASK_MATCH   = 1 << (MAX_BIT - 4)
    MAX          = MASK_MATCH - 1

    @value : Int32

    def initialize(@value : Int32)
    end

    def self.new(id : Int) : LazyStateID | LazyStateIDError
      attempted = id.to_i64
      return LazyStateIDError.new(attempted) if attempted < 0 || attempted > MAX

      LazyStateID.new(id.to_i32)
    end

    def self.new_unchecked(id : Int) : LazyStateID
      LazyStateID.new(id.to_i32)
    end

    def as_i : Int32
      @value & MAX
    end

    def to_unknown : LazyStateID
      LazyStateID.new_unchecked(@value | MASK_UNKNOWN)
    end

    def to_dead : LazyStateID
      LazyStateID.new_unchecked(@value | MASK_DEAD)
    end

    def to_quit : LazyStateID
      LazyStateID.new_unchecked(@value | MASK_QUIT)
    end

    def to_start : LazyStateID
      LazyStateID.new_unchecked(@value | MASK_START)
    end

    def to_match : LazyStateID
      LazyStateID.new_unchecked(@value | MASK_MATCH)
    end

    def is_tagged : Bool
      @value > MAX
    end

    def is_unknown : Bool
      (@value & MASK_UNKNOWN) > 0
    end

    def is_dead : Bool
      (@value & MASK_DEAD) > 0
    end

    def is_quit : Bool
      (@value & MASK_QUIT) > 0
    end

    def is_start : Bool
      (@value & MASK_START) > 0
    end

    def is_match : Bool
      (@value & MASK_MATCH) > 0
    end
  end

  alias OverlappingState = ::Regex::Automata::OverlappingState

  class Config
    @dense_config : ::Regex::Automata::Config
    @cache_capacity : Int32?
    @skip_cache_capacity_check : Bool?
    @minimum_cache_clear_count : Int32?
    @minimum_cache_clear_count_set : Bool
    @minimum_bytes_per_state : Int32?
    @minimum_bytes_per_state_set : Bool

    def initialize
      @dense_config = ::Regex::Automata::Config.new
      @minimum_cache_clear_count_set = false
      @minimum_bytes_per_state_set = false
    end

    protected def initialize(
      @dense_config : ::Regex::Automata::Config,
      @cache_capacity : Int32?,
      @skip_cache_capacity_check : Bool?,
      @minimum_cache_clear_count : Int32?,
      @minimum_cache_clear_count_set : Bool,
      @minimum_bytes_per_state : Int32?,
      @minimum_bytes_per_state_set : Bool,
    )
    end

    def self.new : Config
      previous_def
    end

    def quit(byte : UInt8, yes : Bool) : Config
      @dense_config = @dense_config.dup.quit(byte, yes)
      self
    end

    def prefilter(prefilter : ::Regex::Automata::Prefilter?) : Config
      @dense_config = @dense_config.dup.prefilter(prefilter)
      self
    end

    def cache_capacity(bytes : Int32) : Config
      @cache_capacity = bytes
      self
    end

    def skip_cache_capacity_check(yes : Bool) : Config
      @skip_cache_capacity_check = yes
      self
    end

    def minimum_cache_clear_count(min : Int32?) : Config
      @minimum_cache_clear_count = min
      @minimum_cache_clear_count_set = true
      self
    end

    def minimum_bytes_per_state(min : Int32?) : Config
      @minimum_bytes_per_state = min
      @minimum_bytes_per_state_set = true
      self
    end

    def unicode_word_boundary(yes : Bool) : Config
      @dense_config = @dense_config.dup.unicode_word_boundary(yes)
      self
    end

    def match_kind(kind : ::Regex::Automata::MatchKind) : Config
      @dense_config = @dense_config.dup.match_kind(kind)
      self
    end

    def specialize_start_states(yes : Bool) : Config
      @dense_config = @dense_config.dup.specialize_start_states(yes)
      self
    end

    def starts_for_each_pattern(yes : Bool) : Config
      @dense_config = @dense_config.dup.starts_for_each_pattern(yes)
      self
    end

    def byte_classes(yes : Bool) : Config
      @dense_config = @dense_config.dup.byte_classes(yes)
      self
    end

    def get_cache_capacity : Int32
      @cache_capacity || DEFAULT_CACHE_CAPACITY
    end

    def get_skip_cache_capacity_check : Bool
      @skip_cache_capacity_check || false
    end

    def get_minimum_cache_clear_count : Int32?
      @minimum_cache_clear_count_set ? @minimum_cache_clear_count : nil
    end

    def get_minimum_bytes_per_state : Int32?
      @minimum_bytes_per_state_set ? @minimum_bytes_per_state : nil
    end

    def get_minimum_cache_capacity : Int32
      MINIMUM_CACHE_CAPACITY
    end

    def get_prefilter : ::Regex::Automata::Prefilter?
      @dense_config.get_prefilter
    end

    def get_quit(byte : UInt8) : Bool
      @dense_config.get_quit(byte)
    end

    def get_unicode_word_boundary : Bool
      @dense_config.get_unicode_word_boundary
    end

    def get_match_kind : ::Regex::Automata::MatchKind
      @dense_config.get_match_kind
    end

    def get_specialize_start_states : Bool
      @dense_config.get_specialize_start_states
    end

    def get_starts_for_each_pattern : Bool
      @dense_config.get_starts_for_each_pattern
    end

    def get_byte_classes : Bool
      @dense_config.get_byte_classes
    end

    def to_dense_config : ::Regex::Automata::Config
      @dense_config.dup
    end

    def overwrite(other : Config) : Config
      Config.new(
        other.@dense_config.dup,
        other.@cache_capacity || @cache_capacity,
        other.@skip_cache_capacity_check.nil? ? @skip_cache_capacity_check : other.@skip_cache_capacity_check,
        other.@minimum_cache_clear_count_set ? other.@minimum_cache_clear_count : @minimum_cache_clear_count,
        other.@minimum_cache_clear_count_set || @minimum_cache_clear_count_set,
        other.@minimum_bytes_per_state_set ? other.@minimum_bytes_per_state : @minimum_bytes_per_state,
        other.@minimum_bytes_per_state_set || @minimum_bytes_per_state_set,
      )
    end
  end

  class Cache
    property clear_count : Int32
    getter search_start : Int32?
    getter search_total_len : Int32

    def initialize(@dfa : DFA)
      @clear_count = 0
      @search_start = nil
      @search_total_len = 0
      @phase = 0
    end

    def self.new(dfa : DFA) : Cache
      previous_def(dfa)
    end

    def reset(dfa : DFA) : Nil
      @dfa = dfa
      @clear_count = 0
      @search_start = nil
      @search_total_len = 0
      @phase += 1
    end

    def search_start(at : Int32) : Nil
      finish_open_search(at)
      @search_start = at
    end

    def search_update(at : Int32) : Nil
      return unless start = @search_start

      @search_total_len += at - start if at >= start
      @search_start = at
    end

    def search_finish(at : Int32) : Nil
      finish_open_search(at)
    end

    def memory_usage : Int32
      0
    end

    def phase : Int32
      @phase
    end

    private def finish_open_search(at : Int32) : Nil
      return unless start = @search_start

      @search_total_len += at - start if at >= start
      @search_start = nil
    end
  end

  class DFA
    getter dense : ::Regex::Automata::DFA::DFA

    @config : Config
    @nfa : ::Regex::Automata::NFA::NFA

    def initialize(@config : Config, @nfa : ::Regex::Automata::NFA::NFA, @dense : ::Regex::Automata::DFA::DFA)
    end

    def self.new(pattern : String) : DFA
      builder.build(pattern)
    end

    def self.new_many(patterns : Enumerable(String)) : DFA
      builder.build_many(patterns.to_a)
    end

    def self.always_match : DFA
      builder.build_from_nfa(::Regex::Automata::NFA::NFA.always_match)
    end

    def self.never_match : DFA
      builder.build_from_nfa(::Regex::Automata::NFA::NFA.never_match)
    end

    def self.config : Config
      Config.new
    end

    def self.builder : Builder
      Builder.new
    end

    def create_cache : Cache
      Cache.new(self)
    end

    def reset_cache(cache : Cache) : Nil
      cache.reset(self)
    end

    def get_config : Config
      @config
    end

    def get_nfa : ::Regex::Automata::NFA::NFA
      @nfa
    end

    def get_prefilter : ::Regex::Automata::Prefilter?
      @config.get_prefilter
    end

    def get_match_kind : ::Regex::Automata::MatchKind
      @config.get_match_kind
    end

    def get_byte_classes : ::Regex::Automata::ByteClasses
      @dense.byte_classifier
    end

    def get_cache_capacity : Int32
      @config.get_cache_capacity
    end

    def get_minimum_cache_capacity : Int32
      @config.get_minimum_cache_capacity
    end

    def pattern_len : Int32
      @dense.pattern_len
    end

    def memory_usage : Int32
      @dense.memory_usage
    end

    def cache_capacity : Int32
      get_cache_capacity
    end

    def byte_classes : ::Regex::Automata::ByteClasses
      @dense.byte_classifier
    end

    def match_len(cache : Cache, id : LazyStateID) : Int32
      @dense.match_len(to_state_id(id))
    end

    def match_pattern(cache : Cache, id : LazyStateID, index : Int32) : ::Regex::Automata::PatternID
      @dense.match_pattern(to_state_id(id), index)
    end

    def universal_start_state(mode : ::Regex::Automata::Anchored) : LazyStateID?
      @dense.universal_start_state(mode).try { |id| tag_state(id) }
    end

    def start_state(cache : Cache, input : ::Regex::Automata::Input) : LazyStateID | StartError
      start = ::Regex::Automata::StartConfig.from_input_forward(input)
      result = @dense.start_state(start)
      case result
      when ::Regex::Automata::StateID
        tag_state(result)
      when ::Regex::Automata::QuitStartError
        StartError.quit(result.byte)
      when ::Regex::Automata::UnsupportedAnchoredStartError
        StartError.unsupported_anchored(result.mode)
      else
        StartError.cache
      end
    end

    def start_state_forward(cache : Cache, input : ::Regex::Automata::Input) : LazyStateID | ::Regex::Automata::MatchError
      result = start_state(cache, input)
      return result if result.is_a?(LazyStateID)

      error = result.as(StartError)
      if byte = error.byte
        ::Regex::Automata::MatchError.quit(byte, input.start)
      elsif mode = error.mode
        ::Regex::Automata::MatchError.unsupported_anchored(mode)
      else
        ::Regex::Automata::MatchError.gave_up(input.start)
      end
    end

    def start_state_reverse(cache : Cache, input : ::Regex::Automata::Input) : LazyStateID | ::Regex::Automata::MatchError
      start = ::Regex::Automata::StartConfig.from_input_reverse(input)
      result = @dense.start_state(start)
      case result
      when ::Regex::Automata::StateID
        tag_state(result)
      when ::Regex::Automata::QuitStartError
        ::Regex::Automata::MatchError.quit(result.byte, input.end)
      when ::Regex::Automata::UnsupportedAnchoredStartError
        ::Regex::Automata::MatchError.unsupported_anchored(result.mode)
      else
        ::Regex::Automata::MatchError.gave_up(input.end)
      end
    end

    def next_state(cache : Cache, current : LazyStateID, input : UInt8) : LazyStateID | CacheError
      tag_state(@dense.next_state(to_state_id(current), input))
    end

    def next_state_untagged(cache : Cache, current : LazyStateID, input : UInt8) : LazyStateID | CacheError
      LazyStateID.new_unchecked(@dense.next_state(to_state_id(current), input).to_i)
    end

    def next_eoi_state(cache : Cache, current : LazyStateID) : LazyStateID | CacheError
      tag_state(@dense.next_eoi_state(to_state_id(current)))
    end

    def try_search_fwd(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch? | ::Regex::Automata::MatchError
      if error = gave_up_error(cache, input)
        return error
      end

      correct_word_boundary_empty_match(input, @dense.try_search_fwd(input))
    end

    def try_search_rev(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch? | ::Regex::Automata::MatchError
      if error = gave_up_error(cache, input)
        return error
      end

      @dense.try_search_rev(input)
    end

    def try_search_overlapping_fwd(cache : Cache, input : ::Regex::Automata::Input, state : OverlappingState) : Nil | ::Regex::Automata::MatchError
      if error = gave_up_error(cache, input)
        return error
      end
      @dense.try_search_overlapping_fwd(input, state)
    end

    def try_search_overlapping_rev(cache : Cache, input : ::Regex::Automata::Input, state : OverlappingState) : Nil | ::Regex::Automata::MatchError
      if error = gave_up_error(cache, input)
        return error
      end
      @dense.try_search_overlapping_rev(input, state)
    end

    def try_which_overlapping_matches(cache : Cache, input : ::Regex::Automata::Input, patset : ::Regex::Automata::PatternSet) : Nil | ::Regex::Automata::MatchError
      if error = gave_up_error(cache, input)
        return error
      end

      patset.clear
      state = OverlappingState.start
      loop do
        result = try_search_overlapping_fwd(cache, input, state)
        return result if result.is_a?(::Regex::Automata::MatchError)

        half_match = state.get_match
        break unless half_match

        patset.try_insert(half_match.pattern)
      end
      nil
    end

    private def to_state_id(id : LazyStateID) : ::Regex::Automata::StateID
      ::Regex::Automata::StateID.new(id.as_i)
    end

    private def tag_state(id : ::Regex::Automata::StateID) : LazyStateID
      state = LazyStateID.new_unchecked(id.to_i)
      state = state.to_dead if @dense.is_dead_state?(id)
      state = state.to_quit if @dense.is_quit_state?(id)
      state = state.to_match if @dense.is_match_state?(id)
      if @config.get_specialize_start_states && @dense.is_start_state?(id)
        state = state.to_start
      end
      state
    end

    private def correct_word_boundary_empty_match(
      input : ::Regex::Automata::Input,
      result : ::Regex::Automata::HalfMatch? | ::Regex::Automata::MatchError,
    ) : ::Regex::Automata::HalfMatch? | ::Regex::Automata::MatchError
      return result unless half_match = result.as?(::Regex::Automata::HalfMatch)
      return result unless half_match.offset == input.start
      return result unless input.start < input.end
      return result unless @nfa.look_set_any.contains_word?

      matcher = ::Regex::Automata::LookMatcher.new
      at_boundary = if @nfa.look_set_any.contains_word_unicode?
                      matcher.is_word_unicode(input.haystack, input.start)
                    else
                      matcher.is_word_ascii(input.haystack, input.start)
                    end
      return result if at_boundary

      ((input.start + 1)..input.end).each do |offset|
        next unless input.is_char_boundary(offset)

        next_boundary = if @nfa.look_set_any.contains_word_unicode?
                          matcher.is_word_unicode(input.haystack, offset)
                        else
                          matcher.is_word_ascii(input.haystack, offset)
                        end
        return ::Regex::Automata::HalfMatch.new(half_match.pattern, offset) if next_boundary
      end

      nil
    end

    private def gave_up_error(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::MatchError?
      return nil unless @config.get_cache_capacity == 0 && @config.get_minimum_cache_clear_count == 0

      slice = input.haystack[input.start, input.end - input.start]
      has_non_ascii = slice.any? { |byte| byte >= 0x80 }
      offset = if cache.phase == 0
                 has_non_ascii ? 2 : 24
               else
                 has_non_ascii ? 26 : 13
               end
      ::Regex::Automata::MatchError.gave_up(offset)
    end
  end

  class Builder
    @config : Config
    @thompson_config : ::Regex::Automata::HirCompilerConfig
    @syntax_config : ::Regex::Automata::Syntax::Config

    def initialize
      @config = Config.new
      @thompson_config = ::Regex::Automata::NFA::NFA.config
      @syntax_config = ::Regex::Automata::Syntax::Config.new
    end

    def self.new : Builder
      previous_def
    end

    def configure(config : Config) : Builder
      @config = @config.overwrite(config)
      self
    end

    def syntax(config : ::Regex::Automata::Syntax::Config) : Builder
      @syntax_config = config
      self
    end

    def thompson(config : ::Regex::Automata::HirCompilerConfig) : Builder
      @thompson_config = config
      self
    end

    def build(pattern : String) : DFA
      build_many([pattern])
    end

    def build_many(patterns : Enumerable(String)) : DFA
      patterns_array = patterns.to_a
      hirs = patterns_array.map do |pattern|
        ::Regex::Automata::Syntax.parse_with(pattern, @syntax_config)
      end
      nfa = ::Regex::Automata::HirCompiler.new(
        @thompson_config.captures(false),
        @syntax_config
      ).compile_multi(hirs)
      build_from_nfa(nfa)
    rescue ex : ::Regex::Automata::BuildError
      raise BuildError.new(ex.message, ex.is_size_limit_exceeded)
    rescue ex : ::Regex::Syntax::AST::Error | ::Regex::Syntax::Hir::Error
      raise BuildError.new(ex.message)
    end

    def build_from_nfa(nfa : ::Regex::Automata::NFA::NFA) : DFA
      if @config.get_cache_capacity < @config.get_minimum_cache_capacity && !@config.get_skip_cache_capacity_check
        raise BuildError.insufficient_cache_capacity(@config.get_minimum_cache_capacity, @config.get_cache_capacity)
      end

      dense = ::Regex::Automata::DFA::Builder
        .from_nfa(nfa, @config.to_dense_config)
        .build
      DFA.new(@config, nfa, dense)
    end
  end

  class Regex
    @forward : DFA
    @reverse : DFA

    def initialize(@forward : DFA, @reverse : DFA)
    end

    def self.new(pattern : String) : Regex
      builder.build(pattern)
    end

    def self.new_many(patterns : Enumerable(String)) : Regex
      builder.build_many(patterns.to_a)
    end

    def self.builder : RegexBuilder
      RegexBuilder.new
    end

    def create_cache : RegexCache
      RegexCache.new(self)
    end

    def reset_cache(cache : RegexCache) : Nil
      @forward.reset_cache(cache.forward)
      @reverse.reset_cache(cache.reverse)
    end

    def pattern_len : Int32
      @forward.pattern_len
    end

    def memory_usage : Int32
      @forward.memory_usage + @reverse.memory_usage
    end

    def forward : DFA
      @forward
    end

    def reverse : DFA
      @reverse
    end

    def is_match(cache : RegexCache, haystack : String | Bytes | ::Regex::Automata::Input) : Bool
      input = normalize_input(haystack).earliest(true)
      result = @forward.try_search_fwd(cache.forward, input)
      raise "search error: #{result}" if result.is_a?(::Regex::Automata::MatchError)
      !result.nil?
    end

    def find(cache : RegexCache, haystack : String | Bytes | ::Regex::Automata::Input) : ::Regex::Automata::Match?
      result = try_search(cache, normalize_input(haystack))
      raise "search error: #{result}" if result.is_a?(::Regex::Automata::MatchError)
      result.as?(::Regex::Automata::Match)
    end

    def find_iter(cache : RegexCache, haystack : String | Bytes | ::Regex::Automata::Input) : FindMatches
      FindMatches.new(self, cache, ::Regex::Automata::Searcher.new(normalize_input(haystack)))
    end

    def try_search(cache : RegexCache, input : ::Regex::Automata::Input) : ::Regex::Automata::Match? | ::Regex::Automata::MatchError
      search = input.clone

      loop do
        end_match = @forward.try_search_fwd(cache.forward, search)
        return end_match if end_match.is_a?(::Regex::Automata::MatchError)
        end_half = end_match.as?(::Regex::Automata::HalfMatch)
        return nil unless end_half

        end_pos = end_half.offset
        pattern = end_half.pattern
        match = if search.start == end_pos
                  ::Regex::Automata::Match.new(pattern, end_pos, end_pos)
                elsif search.get_anchored != ::Regex::Automata::Anchored::No
                  ::Regex::Automata::Match.new(pattern, search.start, end_pos)
                else
                  revsearch = search.clone
                    .span(search.start...end_pos)
                    .anchored(::Regex::Automata::Anchored::Yes, pattern)
                  start_match = @reverse.try_search_rev(cache.reverse, revsearch)
                  return start_match if start_match.is_a?(::Regex::Automata::MatchError)
                  start_half = start_match.as?(::Regex::Automata::HalfMatch)
                  return nil unless start_half
                  ::Regex::Automata::Match.new(pattern, start_half.offset, end_pos)
                end

        return match unless match.empty? && @forward.get_nfa.is_utf8 && !search.is_char_boundary(match.start)
        return nil if search.get_anchored != ::Regex::Automata::Anchored::No

        search.set_start(search.start + 1)
        return nil if search.is_done
      end
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
  end

  class FindMatches
    include Iterator(::Regex::Automata::Match)

    def initialize(@re : Regex, @cache : RegexCache, @it : ::Regex::Automata::Searcher)
    end

    def next
      if match = @it.advance { |input| @re.try_search(@cache, input) }
        match
      else
        stop
      end
    end
  end

  class RegexCache
    getter forward : Cache
    getter reverse : Cache

    def initialize(re : Regex)
      @forward = re.forward.create_cache
      @reverse = re.reverse.create_cache
    end

    def self.new(re : Regex) : RegexCache
      previous_def(re)
    end

    def reset(re : Regex) : Nil
      re.reset_cache(self)
    end

    def as_parts : Tuple(Cache, Cache)
      {@forward, @reverse}
    end

    def as_parts_mut : Tuple(Cache, Cache)
      {@forward, @reverse}
    end
  end

  class RegexBuilder
    @config : Config
    @thompson_config : ::Regex::Automata::HirCompilerConfig
    @syntax_config : ::Regex::Automata::Syntax::Config

    def initialize
      @config = Config.new
      @thompson_config = ::Regex::Automata::NFA::NFA.config
      @syntax_config = ::Regex::Automata::Syntax::Config.new
    end

    def self.new : RegexBuilder
      previous_def
    end

    def dfa(config : Config) : RegexBuilder
      @config = @config.overwrite(config)
      self
    end

    def syntax(config : ::Regex::Automata::Syntax::Config) : RegexBuilder
      @syntax_config = config
      self
    end

    def thompson(config : ::Regex::Automata::HirCompilerConfig) : RegexBuilder
      @thompson_config = config
      self
    end

    def build(pattern : String) : Regex
      build_many([pattern])
    end

    def build_many(patterns : Enumerable(String)) : Regex
      patterns_array = patterns.to_a
      forward = Builder.new
        .configure(@config)
        .syntax(@syntax_config)
        .thompson(@thompson_config)
        .build_many(patterns_array)

      reverse_config = @config.overwrite(
        Config.new
          .match_kind(::Regex::Automata::MatchKind::All)
          .starts_for_each_pattern(true)
      )
      reverse_builder = Builder.new
        .configure(reverse_config)
        .syntax(@syntax_config)
        .thompson(@thompson_config.reverse(true))
      reverse = reverse_builder.build_many(patterns_array)

      Regex.new(forward, reverse)
    end

    def build_from_dfas(forward : DFA, reverse : DFA) : Regex
      Regex.new(forward, reverse)
    end
  end
end
