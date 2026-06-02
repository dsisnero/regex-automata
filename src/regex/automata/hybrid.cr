require "./dfa"
require "./dfa_regex"

require "./sparse_set"

module Regex::Automata::Hybrid
  DEFAULT_CACHE_CAPACITY = 2 * (1 << 20)
  SENTINEL_STATES        = 3
  MIN_STATES             = SENTINEL_STATES + 2

  class BuildError < ::Regex::Automata::BuildError
    def self.nfa(err : ::Regex::Automata::BuildError) : BuildError
      new("error building NFA", err.is_size_limit_exceeded)
    end

    def self.insufficient_cache_capacity(minimum : Int32, given : Int32) : BuildError
      new("given cache capacity (#{given}) is smaller than minimum required (#{minimum})")
    end

    def self.insufficient_state_id_capacity(err : LazyStateIDError) : BuildError
      new(err.message)
    end

    def self.unsupported_dfa_word_boundary_unicode : BuildError
      new("unsupported regex feature for DFAs: cannot build lazy DFAs for regexes with Unicode word boundaries; switch to ASCII word boundaries, or heuristically enable Unicode word boundaries or use a different regex engine")
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
    getter pattern : ::Regex::Automata::PatternID?

    def self.cache : StartError
      new("error computing start state because of cache inefficiency", cache: true)
    end

    def self.quit(byte : UInt8) : StartError
      new("error computing start state because the look-behind byte #{byte} triggered a quit state", byte: byte)
    end

    def self.unsupported_anchored(mode : ::Regex::Automata::Anchored, pattern : ::Regex::Automata::PatternID? = nil) : StartError
      message = case mode
                when ::Regex::Automata::Anchored::Yes
                  "error computing start state because anchored searches are not supported or enabled"
                when ::Regex::Automata::Anchored::No
                  "error computing start state because unanchored searches are not supported or enabled"
                when ::Regex::Automata::Anchored::Pattern
                  if pattern
                    "error computing start state because anchored searches for a specific pattern (#{pattern.to_i}) are not supported or enabled"
                  else
                    "error computing start state because anchored searches for a specific pattern are not supported or enabled"
                  end
                else
                  raise "unreachable anchored mode: #{mode}"
                end
      new(message, mode: mode, pattern: pattern)
    end

    def initialize(message : String, @cache : Bool = false, @byte : UInt8? = nil, @mode : ::Regex::Automata::Anchored? = nil, @pattern : ::Regex::Automata::PatternID? = nil)
      super(message)
    end
  end

  struct LazyStateIDError
    getter attempted : Int64

    def initialize(@attempted : Int64)
    end

    def message : String
      "failed to create LazyStateID from #{@attempted}, which exceeds #{LazyStateID::MAX}"
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

    def as_usize_untagged : Int32
      as_i
    end

    def as_usize_unchecked : Int32
      @value
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
      (@value & ~MAX) != 0
    end

    def is_unknown : Bool
      (@value & MASK_UNKNOWN) != 0
    end

    def is_dead : Bool
      (@value & MASK_DEAD) != 0
    end

    def is_quit : Bool
      (@value & MASK_QUIT) != 0
    end

    def is_start : Bool
      (@value & MASK_START) != 0
    end

    def is_match : Bool
      (@value & MASK_MATCH) != 0
    end
  end

  class OverlappingState
    property mat : ::Regex::Automata::HalfMatch?
    property id : LazyStateID?
    property at : Int32
    property next_match_index : Int32?
    property rev_eoi : Bool

    def initialize(
      @mat : ::Regex::Automata::HalfMatch? = nil,
      @id : LazyStateID? = nil,
      @at : Int32 = 0,
      @next_match_index : Int32? = nil,
      @rev_eoi : Bool = false,
    )
    end

    def self.start : OverlappingState
      new
    end

    def get_match : ::Regex::Automata::HalfMatch?
      @mat
    end
  end

  class Config
    @dense_config : ::Regex::Automata::Config
    @cache_capacity : Int32?
    @requested_cache_capacity : Int32?
    @skip_cache_capacity_check : Bool?
    @prefilter_value : ::Regex::Automata::Prefilter?
    @prefilter_set : Bool
    @match_kind_value : ::Regex::Automata::MatchKind?
    @match_kind_set : Bool
    @starts_for_each_pattern_value : Bool?
    @starts_for_each_pattern_set : Bool
    @byte_classes_value : Bool?
    @byte_classes_set : Bool
    @unicode_word_boundary_value : Bool?
    @unicode_word_boundary_set : Bool
    @specialize_start_states_value : Bool?
    @specialize_start_states_set : Bool
    @quitset_value : ::Regex::Automata::ByteSet?
    @quitset_set : Bool
    @minimum_cache_clear_count : Int32?
    @minimum_cache_clear_count_set : Bool
    @minimum_bytes_per_state : Int32?
    @minimum_bytes_per_state_set : Bool

    def initialize
      @dense_config = ::Regex::Automata::Config.new
      @prefilter_set = false
      @match_kind_set = false
      @starts_for_each_pattern_set = false
      @byte_classes_set = false
      @unicode_word_boundary_set = false
      @specialize_start_states_set = false
      @quitset_set = false
      @minimum_cache_clear_count_set = false
      @minimum_bytes_per_state_set = false
    end

    protected def initialize(
      @dense_config : ::Regex::Automata::Config,
      @cache_capacity : Int32?,
      @requested_cache_capacity : Int32?,
      @skip_cache_capacity_check : Bool?,
      @prefilter_value : ::Regex::Automata::Prefilter?,
      @prefilter_set : Bool,
      @match_kind_value : ::Regex::Automata::MatchKind?,
      @match_kind_set : Bool,
      @starts_for_each_pattern_value : Bool?,
      @starts_for_each_pattern_set : Bool,
      @byte_classes_value : Bool?,
      @byte_classes_set : Bool,
      @unicode_word_boundary_value : Bool?,
      @unicode_word_boundary_set : Bool,
      @specialize_start_states_value : Bool?,
      @specialize_start_states_set : Bool,
      @quitset_value : ::Regex::Automata::ByteSet?,
      @quitset_set : Bool,
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
      @quitset_value = clone_byte_set(@quitset_value || snapshot_quitset)
      @quitset_value.not_nil!.add(byte) if yes
      @quitset_value.not_nil!.remove(byte) unless yes
      @quitset_set = true
      self
    end

    def prefilter(prefilter : ::Regex::Automata::Prefilter?) : Config
      @dense_config = @dense_config.dup.prefilter(prefilter)
      @prefilter_value = prefilter
      @prefilter_set = true
      self
    end

    def cache_capacity(bytes : Int32) : Config
      @cache_capacity = bytes
      @requested_cache_capacity = bytes
      self
    end

    def set_effective_cache_capacity(bytes : Int32) : Config
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
      @unicode_word_boundary_value = yes
      @unicode_word_boundary_set = true
      self
    end

    def match_kind(kind : ::Regex::Automata::MatchKind) : Config
      @dense_config = @dense_config.dup.match_kind(kind)
      @match_kind_value = kind
      @match_kind_set = true
      self
    end

    def specialize_start_states(yes : Bool) : Config
      @dense_config = @dense_config.dup.specialize_start_states(yes)
      @specialize_start_states_value = yes
      @specialize_start_states_set = true
      self
    end

    def starts_for_each_pattern(yes : Bool) : Config
      @dense_config = @dense_config.dup.starts_for_each_pattern(yes)
      @starts_for_each_pattern_value = yes
      @starts_for_each_pattern_set = true
      self
    end

    def byte_classes(yes : Bool) : Config
      @dense_config = @dense_config.dup.byte_classes(yes)
      @byte_classes_value = yes
      @byte_classes_set = true
      self
    end

    def get_cache_capacity : Int32
      @cache_capacity || DEFAULT_CACHE_CAPACITY
    end

    def get_skip_cache_capacity_check : Bool
      @skip_cache_capacity_check || false
    end

    def get_requested_cache_capacity : Int32?
      @requested_cache_capacity
    end

    def get_minimum_cache_clear_count : Int32?
      @minimum_cache_clear_count_set ? @minimum_cache_clear_count : nil
    end

    def get_minimum_bytes_per_state : Int32?
      @minimum_bytes_per_state_set ? @minimum_bytes_per_state : nil
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

    def dup : Config
      Config.new(
        @dense_config.dup,
        @cache_capacity,
        @requested_cache_capacity,
        @skip_cache_capacity_check,
        @prefilter_value,
        @prefilter_set,
        @match_kind_value,
        @match_kind_set,
        @starts_for_each_pattern_value,
        @starts_for_each_pattern_set,
        @byte_classes_value,
        @byte_classes_set,
        @unicode_word_boundary_value,
        @unicode_word_boundary_set,
        @specialize_start_states_value,
        @specialize_start_states_set,
        clone_byte_set(@quitset_value),
        @quitset_set,
        @minimum_cache_clear_count,
        @minimum_cache_clear_count_set,
        @minimum_bytes_per_state,
        @minimum_bytes_per_state_set,
      )
    end

    def to_dense_config : ::Regex::Automata::Config
      @dense_config.dup
    end

    def quit_set_from_nfa(nfa : ::Regex::Automata::NFA::NFA) : ::Regex::Automata::ByteSet
      quit = ::Regex::Automata::ByteSet.new
      256.times do |byte|
        value = byte.to_u8
        quit.add(value) if get_quit(value)
      end

      if nfa.look_set_any.contains_word_unicode
        if get_unicode_word_boundary
          (0x80..0xFF).each { |byte| quit.add(byte.to_u8) }
        elsif !quit.contains_range(0x80_u8, 0xFF_u8)
          raise BuildError.unsupported_dfa_word_boundary_unicode
        end
      end

      quit
    end

    def byte_classes_from_nfa(
      nfa : ::Regex::Automata::NFA::NFA,
      quit : ::Regex::Automata::ByteSet,
    ) : ::Regex::Automata::ByteClasses
      return ::Regex::Automata::ByteClasses.singletons unless get_byte_classes

      base = nfa.byte_classes
      return base if quit.empty?

      mapping = Array.new(256, 0)
      class_ids = {} of Tuple(Int32, Bool) => Int32
      next_class = 0

      256.times do |byte|
        key = {base[byte], quit.contains(byte.to_u8)}
        class_id = class_ids[key]?
        unless class_id
          class_id = next_class
          class_ids[key] = class_id
          next_class += 1
        end
        mapping[byte] = class_id
      end

      ::Regex::Automata::ByteClasses.from_mapping(mapping, next_class)
    end

    def get_minimum_cache_capacity(nfa : ::Regex::Automata::NFA::NFA) : Int32
      quit = quit_set_from_nfa(nfa)
      classes = byte_classes_from_nfa(nfa, quit)
      ::Regex::Automata::Hybrid.minimum_cache_capacity(
        nfa,
        classes,
        get_starts_for_each_pattern
      )
    end

    def overwrite(other : Config) : Config
      merged_dense = @dense_config.dup
      merged_dense.prefilter(other.@prefilter_value) if other.@prefilter_set
      merged_dense.match_kind(other.@match_kind_value.not_nil!) if other.@match_kind_set
      merged_dense.starts_for_each_pattern(other.@starts_for_each_pattern_value.not_nil!) if other.@starts_for_each_pattern_set
      merged_dense.byte_classes(other.@byte_classes_value.not_nil!) if other.@byte_classes_set
      merged_dense.unicode_word_boundary(other.@unicode_word_boundary_value.not_nil!) if other.@unicode_word_boundary_set
      merged_dense.specialize_start_states(other.@specialize_start_states_value.not_nil!) if other.@specialize_start_states_set
      if other.@quitset_set
        quitset = other.@quitset_value || ::Regex::Automata::ByteSet.new
        256.times do |byte|
          merged_dense.quit(byte.to_u8, quitset.contains(byte.to_u8))
        end
      end

      Config.new(
        merged_dense,
        other.@cache_capacity || @cache_capacity,
        other.@requested_cache_capacity || @requested_cache_capacity,
        other.@skip_cache_capacity_check.nil? ? @skip_cache_capacity_check : other.@skip_cache_capacity_check,
        other.@prefilter_set ? other.@prefilter_value : @prefilter_value,
        other.@prefilter_set || @prefilter_set,
        other.@match_kind_set ? other.@match_kind_value : @match_kind_value,
        other.@match_kind_set || @match_kind_set,
        other.@starts_for_each_pattern_set ? other.@starts_for_each_pattern_value : @starts_for_each_pattern_value,
        other.@starts_for_each_pattern_set || @starts_for_each_pattern_set,
        other.@byte_classes_set ? other.@byte_classes_value : @byte_classes_value,
        other.@byte_classes_set || @byte_classes_set,
        other.@unicode_word_boundary_set ? other.@unicode_word_boundary_value : @unicode_word_boundary_value,
        other.@unicode_word_boundary_set || @unicode_word_boundary_set,
        other.@specialize_start_states_set ? other.@specialize_start_states_value : @specialize_start_states_value,
        other.@specialize_start_states_set || @specialize_start_states_set,
        other.@quitset_set ? clone_byte_set(other.@quitset_value) : clone_byte_set(@quitset_value),
        other.@quitset_set || @quitset_set,
        other.@minimum_cache_clear_count_set ? other.@minimum_cache_clear_count : @minimum_cache_clear_count,
        other.@minimum_cache_clear_count_set || @minimum_cache_clear_count_set,
        other.@minimum_bytes_per_state_set ? other.@minimum_bytes_per_state : @minimum_bytes_per_state,
        other.@minimum_bytes_per_state_set || @minimum_bytes_per_state_set,
      )
    end

    private def snapshot_quitset : ::Regex::Automata::ByteSet
      set = ::Regex::Automata::ByteSet.new
      256.times do |byte|
        value = byte.to_u8
        set.add(value) if @dense_config.get_quit(value)
      end
      set
    end

    private def clone_byte_set(set : ::Regex::Automata::ByteSet?) : ::Regex::Automata::ByteSet?
      return nil unless set

      copy = ::Regex::Automata::ByteSet.new
      set.each { |byte| copy.add(byte) }
      copy
    end
  end

  class Cache
    property clear_count : Int32
    getter trans : Array(LazyStateID)
    getter starts : Array(LazyStateID)
    getter states : Array(::Regex::Automata::Determinize::State)
    getter states_to_id : Hash(::Regex::Automata::Determinize::State, LazyStateID)
    getter sparses : SparseSets
    getter stack : Array(::Regex::Automata::StateID)
    property scratch_state_builder : ::Regex::Automata::Determinize::StateBuilderEmpty
    property memory_usage_state : Int32
    property bytes_searched : Int32
    property progress : SearchProgress?

    def initialize(@dfa : DFA)
      @trans = [] of LazyStateID
      @starts = [] of LazyStateID
      @states = [] of ::Regex::Automata::Determinize::State
      @states_to_id = {} of ::Regex::Automata::Determinize::State => LazyStateID
      @sparses = SparseSets.new(@dfa.get_nfa.states.size.to_i32)
      @stack = [] of ::Regex::Automata::StateID
      @scratch_state_builder = ::Regex::Automata::Determinize::StateBuilderEmpty.new
      @memory_usage_state = 0
      @clear_count = 0
      @bytes_searched = 0
      @progress = nil
      @phase = 0
      Lazy.new(@dfa, self).init_cache
    end

    def self.new(dfa : DFA) : Cache
      previous_def(dfa)
    end

    def reset(dfa : DFA) : Nil
      @dfa = dfa
      Lazy.new(@dfa, self).reset_cache
      @phase += 1
    end

    def search_start(at : Int32) : Nil
      if progress = @progress
        @bytes_searched += progress.len
      end
      @progress = SearchProgress.new(at, at)
    end

    def search_update(at : Int32) : Nil
      if progress = @progress
        progress.at = at
      else
        raise "no in-progress search to update"
      end
    end

    def search_finish(at : Int32) : Nil
      if progress = @progress
        progress.at = at
        @bytes_searched += progress.len
        @progress = nil
      else
        raise "no in-progress search to finish"
      end
    end

    def search_total_len : Int32
      @bytes_searched + (@progress.try(&.len) || 0)
    end

    def memory_usage : Int32
      id_size = sizeof(LazyStateID).to_i32
      state_size = sizeof(::Regex::Automata::Determinize::State).to_i32

      (@trans.size * id_size) +
        (@starts.size * id_size) +
        (@states.size * state_size) +
        (@states_to_id.size * (state_size + id_size)) +
        @sparses.memory_usage +
        (@stack.size * ::Regex::Automata::StateID::SIZE) +
        @scratch_state_builder.capacity +
        @memory_usage_state
    end

    def phase : Int32
      @phase
    end
  end

  private class SearchProgress
    property at : Int32
    getter start : Int32

    def initialize(@start : Int32, @at : Int32)
    end

    def len : Int32
      (@start - @at).abs
    end
  end

  private class Lazy
    def initialize(@dfa : DFA, @cache : Cache)
    end

    def init_cache : Nil
      starts_len = Start.len * 2
      if @dfa.get_config.get_starts_for_each_pattern
        starts_len += Start.len * @dfa.pattern_len
      end
      @cache.starts.concat(Array.new(starts_len) { as_ref.unknown_id })

      dead = ::Regex::Automata::Determinize::State.dead
      unk_id = add_state(dead, &.to_unknown)
      raise unk_id if unk_id.is_a?(CacheError)
      dead_id = add_state(dead, &.to_dead)
      raise dead_id if dead_id.is_a?(CacheError)
      quit_id = add_state(dead, &.to_quit)
      raise quit_id if quit_id.is_a?(CacheError)
      unk_id = unk_id.as(LazyStateID)
      dead_id = dead_id.as(LazyStateID)
      quit_id = quit_id.as(LazyStateID)
      raise "invalid hybrid unknown sentinel id" unless unk_id == as_ref.unknown_id
      raise "invalid hybrid dead sentinel id" unless dead_id == as_ref.dead_id
      raise "invalid hybrid quit sentinel id" unless quit_id == as_ref.quit_id

      set_all_transitions(unk_id, unk_id)
      set_all_transitions(dead_id, dead_id)
      set_all_transitions(quit_id, quit_id)
      @cache.states_to_id[dead] = dead_id
    end

    def reset_cache : Nil
      clear_cache
      @cache.sparses.resize(@dfa.get_nfa.states.size.to_i32)
      @cache.clear_count = 0
      @cache.progress = nil
    end

    private def as_ref : LazyRef
      LazyRef.new(@dfa, @cache)
    end

    private def clear_cache : Nil
      @cache.trans.clear
      @cache.starts.clear
      @cache.states.clear
      @cache.states_to_id.clear
      @cache.memory_usage_state = 0
      @cache.clear_count += 1
      @cache.bytes_searched = 0
      if progress = @cache.progress
        progress.at = progress.start
      end
      init_cache
    end

    def start_state(config : ::Regex::Automata::StartConfig) : LazyStateID | StartError
      start = @dfa.start_of(config)
      return start if start.is_a?(StartError)

      anchored = config.get_anchored
      pattern = config.pattern
      cached = as_ref.get_cached_start_id(anchored, start.as(Start), pattern)
      return cached if cached.is_a?(StartError)

      sid = cached.as(LazyStateID)
      return sid unless sid.is_unknown

      cache_start_group(anchored, start.as(Start), pattern)
    end

    def next_state(current : LazyStateID, unit : ::Regex::Automata::Unit) : LazyStateID | CacheError
      next_sid = as_ref.transition(current, unit)
      return next_sid unless next_sid.is_unknown

      cache_next_state(current, unit)
    end

    private def add_state(
      state : ::Regex::Automata::Determinize::State,
      &idmap : LazyStateID -> LazyStateID
    ) : LazyStateID | CacheError
      unless state_fits_in_cache(state.memory_usage)
        return CacheError.too_many_cache_clears if @dfa.get_config.get_minimum_cache_clear_count == 0
        clear_cache
      end
      id = idmap.call(next_state_id)
      id = id.to_match if state.is_match?
      @cache.trans.concat(Array.new(@dfa.stride) { as_ref.unknown_id })
      if !@dfa.get_quitset.empty? && !as_ref.is_sentinel(id)
        quit_id = as_ref.quit_id
        @dfa.get_quitset.each do |byte|
          set_transition(id, ::Regex::Automata::Unit.u8(byte), quit_id)
        end
      end
      @cache.memory_usage_state += state.memory_usage
      @cache.states << state
      @cache.states_to_id[state] = id
      id
    end

    private def add_builder_state(
      builder : ::Regex::Automata::Determinize::StateBuilderNFA,
      &idmap : LazyStateID -> LazyStateID
    ) : LazyStateID | CacheError
      state = builder.to_state
      if cached_id = @cache.states_to_id[state]?
        put_state_builder(builder)
        return cached_id
      end
      result = add_state(state, &idmap)
      put_state_builder(builder)
      result
    end

    private def next_state_id : LazyStateID
      result = LazyStateID.new(@cache.trans.size)
      return result.as(LazyStateID) if result.is_a?(LazyStateID)

      raise BuildError.insufficient_state_id_capacity(result.as(LazyStateIDError))
    end

    private def cache_next_state(
      current : LazyStateID,
      unit : ::Regex::Automata::Unit,
    ) : LazyStateID | CacheError
      builder = ::Regex::Automata::Determinize.next(
        @dfa.get_nfa,
        @dfa.get_match_kind,
        @cache.sparses,
        @cache.stack,
        as_ref.get_cached_state(current),
        unit,
        get_state_builder
      )
      next_sid = add_builder_state(builder, &.itself)
      return next_sid if next_sid.is_a?(CacheError)

      set_transition(current, unit, next_sid.as(LazyStateID))
      next_sid
    end

    private def cache_start_group(
      anchored : ::Regex::Automata::Anchored,
      start : Start,
      pattern : ::Regex::Automata::PatternID?,
    ) : LazyStateID | StartError
      nfa_start_id = case anchored
                     when ::Regex::Automata::Anchored::No
                       @dfa.get_nfa.start_unanchored
                     when ::Regex::Automata::Anchored::Yes
                       @dfa.get_nfa.start_anchored
                     when ::Regex::Automata::Anchored::Pattern
                       unless @dfa.get_config.get_starts_for_each_pattern
                         return StartError.unsupported_anchored(anchored, pattern)
                       end
                       return StartError.unsupported_anchored(anchored, pattern) unless pattern
                       pid_start = @dfa.get_nfa.start_pattern(pattern)
                       return as_ref.dead_id unless pid_start
                       pid_start
                     else
                       return StartError.unsupported_anchored(anchored, pattern)
                     end

      id = cache_start_one(nfa_start_id, start)
      return StartError.cache if id.is_a?(CacheError)

      sid = id.as(LazyStateID)
      set_start_state(anchored, start, pattern, sid)
      sid
    end

    private def cache_start_one(
      nfa_start_id : ::Regex::Automata::StateID,
      start : Start,
    ) : LazyStateID | CacheError
      builder_matches = get_state_builder.into_matches
      ::Regex::Automata::Determinize.set_lookbehind_from_start(
        @dfa.get_nfa,
        start,
        builder_matches
      )
      @cache.sparses.set1.clear
      ::Regex::Automata::Determinize.epsilon_closure(
        @dfa.get_nfa,
        nfa_start_id,
        builder_matches.look_have,
        @cache.stack,
        @cache.sparses.set1
      )
      builder = builder_matches.into_nfa
      ::Regex::Automata::Determinize.add_nfa_states(@dfa.get_nfa, @cache.sparses.set1, builder)
      add_builder_state(builder) do |id|
        @dfa.get_config.get_specialize_start_states ? id.to_start : id
      end
    end

    private def get_state_builder : ::Regex::Automata::Determinize::StateBuilderEmpty
      builder = @cache.scratch_state_builder
      @cache.scratch_state_builder = ::Regex::Automata::Determinize::StateBuilderEmpty.new
      builder
    end

    private def put_state_builder(
      builder : ::Regex::Automata::Determinize::StateBuilderNFA,
    ) : Nil
      @cache.scratch_state_builder = builder.clear
    end

    private def set_start_state(
      anchored : ::Regex::Automata::Anchored,
      start : Start,
      pattern : ::Regex::Automata::PatternID?,
      id : LazyStateID,
    ) : Nil
      index = case anchored
              when ::Regex::Automata::Anchored::No
                start.as_usize
              when ::Regex::Automata::Anchored::Yes
                Start.len + start.as_usize
              when ::Regex::Automata::Anchored::Pattern
                raise "pattern start state requires pattern id" unless pattern
                (2 * Start.len) + (Start.len * pattern.to_i32) + start.as_usize
              else
                raise "unreachable anchored mode"
              end
      @cache.starts[index] = id
    end

    private def state_fits_in_cache(state_heap_size : Int32) : Bool
      return true if @dfa.get_config.get_skip_cache_capacity_check

      needed = @cache.memory_usage +
               (@dfa.stride * sizeof(LazyStateID).to_i32) +
               sizeof(::Regex::Automata::Determinize::State).to_i32 +
               (sizeof(::Regex::Automata::Determinize::State).to_i32 + sizeof(LazyStateID).to_i32) +
               state_heap_size
      needed <= @dfa.cache_capacity
    end

    private def set_all_transitions(from : LazyStateID, to : LazyStateID) : Nil
      @dfa.get_byte_classes.representatives.each do |unit|
        set_transition(from, unit, to)
      end
    end

    private def set_transition(
      from : LazyStateID,
      unit : ::Regex::Automata::Unit,
      to : LazyStateID,
    ) : Nil
      offset = from.as_usize_untagged + @dfa.get_byte_classes.get_by_unit(unit)
      @cache.trans[offset] = to
    end
  end

  private class LazyRef
    def initialize(@dfa : DFA, @cache : Cache)
    end

    def unknown_id : LazyStateID
      LazyStateID.new_unchecked(0).to_unknown
    end

    def dead_id : LazyStateID
      LazyStateID.new_unchecked(1 << @dfa.stride2).to_dead
    end

    def quit_id : LazyStateID
      LazyStateID.new_unchecked(2 << @dfa.stride2).to_quit
    end

    def is_sentinel(id : LazyStateID) : Bool
      id == unknown_id || id == dead_id || id == quit_id
    end

    def is_valid(id : LazyStateID) : Bool
      raw = id.as_usize_untagged
      raw < @cache.trans.size && (raw % @dfa.stride) == 0
    end

    def transition(current : LazyStateID, unit : ::Regex::Automata::Unit) : LazyStateID
      offset = current.as_usize_untagged + @dfa.get_byte_classes.get_by_unit(unit)
      @cache.trans[offset]
    end

    def get_cached_state(sid : LazyStateID) : ::Regex::Automata::Determinize::State
      index = sid.as_usize_untagged >> @dfa.stride2
      @cache.states[index]
    end

    def get_cached_start_id(
      anchored : ::Regex::Automata::Anchored,
      start : Start,
      pattern : ::Regex::Automata::PatternID?,
    ) : LazyStateID | StartError
      index = case anchored
              when ::Regex::Automata::Anchored::No
                start.as_usize
              when ::Regex::Automata::Anchored::Yes
                Start.len + start.as_usize
              when ::Regex::Automata::Anchored::Pattern
                unless @dfa.get_config.get_starts_for_each_pattern
                  return StartError.unsupported_anchored(anchored, pattern)
                end
                return dead_id unless pattern && pattern.to_i < @dfa.pattern_len
                (2 * Start.len) + (Start.len * pattern.to_i32) + start.as_usize
              else
                return StartError.unsupported_anchored(anchored, pattern)
              end
      @cache.starts[index]
    end
  end

  class DFA
    getter dense : ::Regex::Automata::DFA::DFA

    @config : Config
    @nfa : ::Regex::Automata::NFA::NFA
    @start_map : ::Regex::Automata::StartByteMap
    @classes : ::Regex::Automata::ByteClasses
    @quitset : ::Regex::Automata::ByteSet
    @cache_capacity : Int32

    def initialize(
      @config : Config,
      @nfa : ::Regex::Automata::NFA::NFA,
      @dense : ::Regex::Automata::DFA::DFA,
      @start_map : ::Regex::Automata::StartByteMap,
      @classes : ::Regex::Automata::ByteClasses,
      @quitset : ::Regex::Automata::ByteSet,
      @cache_capacity : Int32,
    )
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
      @classes
    end

    def get_cache_capacity : Int32
      @cache_capacity
    end

    def pattern_len : Int32
      @nfa.pattern_len
    end

    def memory_usage : Int32
      0
    end

    def cache_capacity : Int32
      get_cache_capacity
    end

    def byte_classes : ::Regex::Automata::ByteClasses
      @classes
    end

    def get_quitset : ::Regex::Automata::ByteSet
      @quitset
    end

    def stride2 : Int32
      @classes.stride2
    end

    def stride : Int32
      1 << stride2
    end

    def match_len(cache : Cache, id : LazyStateID) : Int32
      return 0 unless id.is_match
      LazyRef.new(self, cache).get_cached_state(id).match_len
    end

    def match_pattern(cache : Cache, id : LazyStateID, index : Int32) : ::Regex::Automata::PatternID
      LazyRef.new(self, cache).get_cached_state(id).match_pattern(index)
    end

    def universal_start_state(mode : ::Regex::Automata::Anchored) : LazyStateID?
      return nil unless @nfa.look_set_prefix_any.empty?
      return nil if mode == ::Regex::Automata::Anchored::Pattern
      cache = create_cache
      sid = Lazy.new(self, cache).start_state(::Regex::Automata::StartConfig.new(nil, mode))
      sid.as?(LazyStateID)
    end

    def start_state(cache : Cache, input : ::Regex::Automata::Input) : LazyStateID | StartError
      Lazy.new(self, cache).start_state(::Regex::Automata::StartConfig.from_input_forward(input))
    end

    def start_state_forward(cache : Cache, input : ::Regex::Automata::Input) : LazyStateID | ::Regex::Automata::MatchError
      result = start_state(cache, input)
      return result if result.is_a?(LazyStateID)

      error = result.as(StartError)
      if byte = error.byte
        ::Regex::Automata::MatchError.quit(byte, input.start)
      elsif mode = error.mode
        ::Regex::Automata::MatchError.unsupported_anchored(mode, error.pattern)
      else
        ::Regex::Automata::MatchError.gave_up(input.start)
      end
    end

    def start_state_reverse(cache : Cache, input : ::Regex::Automata::Input) : LazyStateID | ::Regex::Automata::MatchError
      result = Lazy.new(self, cache).start_state(::Regex::Automata::StartConfig.from_input_reverse(input))
      return result if result.is_a?(LazyStateID)

      error = result.as(StartError)
      if byte = error.byte
        ::Regex::Automata::MatchError.quit(byte, input.end)
      elsif mode = error.mode
        ::Regex::Automata::MatchError.unsupported_anchored(mode, error.pattern)
      else
        ::Regex::Automata::MatchError.gave_up(input.end)
      end
    end

    def next_state(cache : Cache, current : LazyStateID, input : UInt8) : LazyStateID | CacheError
      Lazy.new(self, cache).next_state(current, ::Regex::Automata::Unit.u8(input))
    end

    def next_state_untagged(cache : Cache, current : LazyStateID, input : UInt8) : LazyStateID | CacheError
      result = next_state(cache, current, input)
      return result if result.is_a?(CacheError)
      LazyStateID.new_unchecked(result.as(LazyStateID).as_usize_untagged)
    end

    def next_eoi_state(cache : Cache, current : LazyStateID) : LazyStateID | CacheError
      Lazy.new(self, cache).next_state(current, @classes.eoi)
    end

    def try_search_fwd(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch? | ::Regex::Automata::MatchError
      if error = gave_up_error(cache, input)
        return error
      end
      if offset = earliest_pure_word_boundary_match(input)
        return ::Regex::Automata::HalfMatch.new(::Regex::Automata::PatternID::ZERO, offset)
      end
      search = input.clone
      loop do
        result = try_search_fwd_once(cache, search)
        return result if result.is_a?(::Regex::Automata::MatchError)
        if half = result.as?(::Regex::Automata::HalfMatch)
          if offset = leftmost_empty_word_match_before(search, half.offset)
            return ::Regex::Automata::HalfMatch.new(half.pattern, offset)
          end
          if half.offset > search.start && immediate_word_empty_match?(search)
            return ::Regex::Automata::HalfMatch.new(half.pattern, search.start)
          end
        end
        return result unless result.nil?
        return nil if search.get_anchored != ::Regex::Automata::Anchored::No
        return nil if search.start >= search.end
        search.set_start(search.start + 1)
      end
    end

    private def try_search_fwd_once(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch? | ::Regex::Automata::MatchError
      return nil if input.is_done

      sid = start_state_forward(cache, input)
      return sid if sid.is_a?(::Regex::Automata::MatchError)

      current = sid.as(LazyStateID)
      match = nil.as(::Regex::Automata::HalfMatch?)
      at = input.start
      cache.search_start(at)
      while at < input.end
        next_sid = next_state(cache, current, input.haystack[at])
        return ::Regex::Automata::MatchError.gave_up(at) if next_sid.is_a?(CacheError)
        current = next_sid.as(LazyStateID)
        if current.is_match
          match = ::Regex::Automata::HalfMatch.new(match_pattern(cache, current, 0), at)
          if input.get_earliest
            cache.search_finish(at)
            return correct_word_boundary_empty_match(input, match)
          end
        elsif current.is_dead
          cache.search_finish(at)
          return correct_word_boundary_empty_match(input, match)
        elsif current.is_quit
          cache.search_finish(at)
          return ::Regex::Automata::MatchError.quit(input.haystack[at], at)
        end
        at += 1
        cache.search_update(at) if at <= input.end
      end

      eoi = if byte = input.haystack[input.end]?
              next_state(cache, current, byte)
            else
              next_eoi_state(cache, current)
            end
      return ::Regex::Automata::MatchError.gave_up(input.end) if eoi.is_a?(CacheError)
      current = eoi.as(LazyStateID)
      if current.is_match
        offset = input.end < input.haystack.size ? input.end : input.haystack.size
        match = ::Regex::Automata::HalfMatch.new(match_pattern(cache, current, 0), offset)
      elsif current.is_quit && input.end < input.haystack.size
        return ::Regex::Automata::MatchError.quit(input.haystack[input.end], input.end)
      end
      cache.search_finish(input.end)
      correct_word_boundary_empty_match(input, match)
    end

    def try_search_rev(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch? | ::Regex::Automata::MatchError
      if error = gave_up_error(cache, input)
        return error
      end
      return nil if input.is_done

      sid = start_state_reverse(cache, input)
      return sid if sid.is_a?(::Regex::Automata::MatchError)
      current = sid.as(LazyStateID)
      match = nil.as(::Regex::Automata::HalfMatch?)

      if input.start == input.end
        eoi = if input.start > 0
                next_state(cache, current, input.haystack[input.start - 1])
              else
                next_eoi_state(cache, current)
              end
        return ::Regex::Automata::MatchError.gave_up(input.start) if eoi.is_a?(CacheError)
        current = eoi.as(LazyStateID)
        return ::Regex::Automata::MatchError.quit(input.haystack[input.start - 1], input.start - 1) if input.start > 0 && current.is_quit
        return ::Regex::Automata::HalfMatch.new(match_pattern(cache, current, 0), input.start) if current.is_match
        return nil
      end

      at = input.end - 1
      cache.search_start(at)
      loop do
        next_sid = next_state(cache, current, input.haystack[at])
        return ::Regex::Automata::MatchError.gave_up(at) if next_sid.is_a?(CacheError)
        current = next_sid.as(LazyStateID)
        if current.is_match
          match = ::Regex::Automata::HalfMatch.new(match_pattern(cache, current, 0), at + 1)
          if input.get_earliest
            cache.search_finish(at)
            return match
          end
        elsif current.is_dead
          cache.search_finish(at)
          return match
        elsif current.is_quit
          cache.search_finish(at)
          return ::Regex::Automata::MatchError.quit(input.haystack[at], at)
        end
        break if at == input.start
        at -= 1
        cache.search_update(at)
      end

      eoi = if input.start > 0
              next_state(cache, current, input.haystack[input.start - 1])
            else
              next_eoi_state(cache, current)
            end
      return ::Regex::Automata::MatchError.gave_up(input.start) if eoi.is_a?(CacheError)
      current = eoi.as(LazyStateID)
      return ::Regex::Automata::MatchError.quit(input.haystack[input.start - 1], input.start - 1) if input.start > 0 && current.is_quit
      match = ::Regex::Automata::HalfMatch.new(match_pattern(cache, current, 0), input.start) if current.is_match
      cache.search_finish(input.start)
      match
    end

    def try_search_overlapping_fwd(cache : Cache, input : ::Regex::Automata::Input, state : OverlappingState) : Nil | ::Regex::Automata::MatchError
      if error = gave_up_error(cache, input)
        return error
      end
      if get_match_kind != ::Regex::Automata::MatchKind::All
        if state.id
          state.mat = nil
          return nil
        end
        search = input.clone
        search.set_start(state.at == 0 ? input.start : state.at)
        result = try_search_fwd(cache, search)
        return result if result.is_a?(::Regex::Automata::MatchError)
        state.id = LazyRef.new(self, cache).dead_id
        if half = result.as?(::Regex::Automata::HalfMatch)
          state.mat = half
          state.at = half.offset
        else
          state.mat = nil
        end
        return nil
      end
      state.mat = nil
      return nil if input.is_done

      current = if sid = state.id
                  if next_index = state.next_match_index
                    if next_index < match_len(cache, sid)
                      state.next_match_index = next_index + 1
                      state.mat = ::Regex::Automata::HalfMatch.new(match_pattern(cache, sid, next_index), state.at)
                      return nil
                    end
                  end
                  state.at += 1
                  return nil if state.at > input.end
                  sid
                else
                  state.at = input.start
                  sid = start_state_forward(cache, input)
                  return sid if sid.is_a?(::Regex::Automata::MatchError)
                  sid.as(LazyStateID)
                end
      cache.search_start(state.at)
      while state.at < input.end
        next_sid = next_state(cache, current, input.haystack[state.at])
        return ::Regex::Automata::MatchError.gave_up(state.at) if next_sid.is_a?(CacheError)
        current = next_sid.as(LazyStateID)
        state.id = current
        if current.is_match
          state.next_match_index = 1
          state.mat = ::Regex::Automata::HalfMatch.new(match_pattern(cache, current, 0), state.at)
          cache.search_finish(state.at)
          return nil
        elsif current.is_dead
          cache.search_finish(state.at)
          return nil
        elsif current.is_quit
          cache.search_finish(state.at)
          return ::Regex::Automata::MatchError.quit(input.haystack[state.at], state.at)
        end
        state.at += 1
        cache.search_update(state.at) if state.at <= input.end
      end
      eoi = if byte = input.haystack[input.end]?
              next_state(cache, current, byte)
            else
              next_eoi_state(cache, current)
            end
      return ::Regex::Automata::MatchError.gave_up(input.end) if eoi.is_a?(CacheError)
      current = eoi.as(LazyStateID)
      state.id = current
      if current.is_match
        state.next_match_index = 1
        state.mat = ::Regex::Automata::HalfMatch.new(match_pattern(cache, current, 0), input.end)
      elsif current.is_quit && input.end < input.haystack.size
        return ::Regex::Automata::MatchError.quit(input.haystack[input.end], input.end)
      end
      cache.search_finish(input.end)
      nil
    end

    def try_search_overlapping_rev(cache : Cache, input : ::Regex::Automata::Input, state : OverlappingState) : Nil | ::Regex::Automata::MatchError
      if error = gave_up_error(cache, input)
        return error
      end
      if get_match_kind != ::Regex::Automata::MatchKind::All
        if state.id
          state.mat = nil
          return nil
        end
        result = try_search_rev(cache, input)
        return result if result.is_a?(::Regex::Automata::MatchError)
        state.id = LazyRef.new(self, cache).dead_id
        if half = result.as?(::Regex::Automata::HalfMatch)
          state.mat = half
          state.at = half.offset
        else
          state.mat = nil
        end
        return nil
      end
      state.mat = nil
      return nil if input.is_done

      current = if sid = state.id
                  if next_index = state.next_match_index
                    if next_index < match_len(cache, sid)
                      state.next_match_index = next_index + 1
                      state.mat = ::Regex::Automata::HalfMatch.new(match_pattern(cache, sid, next_index), state.at)
                      return nil
                    end
                  end
                  if state.rev_eoi
                    return nil
                  elsif state.at == input.start
                    state.rev_eoi = true
                  else
                    state.at -= 1
                  end
                  sid
                else
                  sid = start_state_reverse(cache, input)
                  return sid if sid.is_a?(::Regex::Automata::MatchError)
                  state.id = sid.as(LazyStateID)
                  if input.start == input.end
                    state.rev_eoi = true
                  else
                    state.at = input.end - 1
                  end
                  sid.as(LazyStateID)
                end
      cache.search_start(state.at)
      until state.rev_eoi
        next_sid = next_state(cache, current, input.haystack[state.at])
        return ::Regex::Automata::MatchError.gave_up(state.at) if next_sid.is_a?(CacheError)
        current = next_sid.as(LazyStateID)
        state.id = current
        if current.is_match
          state.next_match_index = 1
          state.mat = ::Regex::Automata::HalfMatch.new(match_pattern(cache, current, 0), state.at + 1)
          cache.search_finish(state.at)
          return nil
        elsif current.is_dead
          cache.search_finish(state.at)
          return nil
        elsif current.is_quit
          cache.search_finish(state.at)
          return ::Regex::Automata::MatchError.quit(input.haystack[state.at], state.at)
        end
        break if state.at == input.start
        state.at -= 1
        cache.search_update(state.at)
      end
      eoi = if input.start > 0
              next_state(cache, current, input.haystack[input.start - 1])
            else
              next_eoi_state(cache, current)
            end
      return ::Regex::Automata::MatchError.gave_up(input.start) if eoi.is_a?(CacheError)
      current = eoi.as(LazyStateID)
      state.id = current
      state.rev_eoi = true
      if current.is_match
        state.next_match_index = 1
        state.mat = ::Regex::Automata::HalfMatch.new(match_pattern(cache, current, 0), input.start)
      elsif current.is_quit && input.start > 0
        return ::Regex::Automata::MatchError.quit(input.haystack[input.start - 1], input.start - 1)
      end
      cache.search_finish(input.start)
      nil
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
      return nil unless @config.get_requested_cache_capacity == 0 &&
                        @config.get_skip_cache_capacity_check &&
                        @config.get_minimum_cache_clear_count == 0

      slice = input.haystack[input.start, input.end - input.start]
      has_non_ascii = slice.any? { |byte| byte >= 0x80 }
      offset = if cache.phase == 0
                 has_non_ascii ? 2 : 24
               else
                 has_non_ascii ? 26 : 13
               end
      ::Regex::Automata::MatchError.gave_up(offset)
    end

    def start_of(config : ::Regex::Automata::StartConfig) : Start | StartError
      if look_behind = config.get_look_behind
        return StartError.quit(look_behind) if @quitset.contains(look_behind)
        @start_map.get(look_behind)
      else
        Start::Text
      end
    end

    private def immediate_word_empty_match?(input : ::Regex::Automata::Input) : Bool
      return false unless @nfa.has_empty
      return false unless @nfa.look_set_any.contains_word?

      matcher = ::Regex::Automata::LookMatcher.new
      if @nfa.look_set_any.contains_word_unicode?
        matcher.is_word_unicode(input.haystack, input.start)
      else
        matcher.is_word_ascii(input.haystack, input.start)
      end
    end

    private def leftmost_empty_word_match_before(
      input : ::Regex::Automata::Input,
      offset : Int32,
    ) : Int32?
      return nil unless @nfa.has_empty
      return nil unless @nfa.look_set_any.contains_word?
      return nil unless offset > input.start

      matcher = ::Regex::Automata::LookMatcher.new
      input.start.upto(offset - 1) do |at|
        next unless input.is_char_boundary(at)
        boundary = if @nfa.look_set_any.contains_word_unicode?
                     matcher.is_word_unicode(input.haystack, at)
                   else
                     matcher.is_word_ascii(input.haystack, at)
                   end
        return at if boundary
      end
      nil
    end

    private def earliest_pure_word_boundary_match(
      input : ::Regex::Automata::Input,
    ) : Int32?
      return nil unless input.get_anchored == ::Regex::Automata::Anchored::No
      return nil unless @nfa.pattern_len == 1
      return nil unless @nfa.has_empty
      return nil unless @nfa.look_set_any.contains_word?

      matcher = ::Regex::Automata::LookMatcher.new
      input.start.upto(input.end) do |at|
        next unless input.is_char_boundary(at)
        boundary = if @nfa.look_set_any.contains_word_unicode?
                     matcher.is_word_unicode(input.haystack, at)
                   else
                     matcher.is_word_ascii(input.haystack, at)
                   end
        return at if boundary
      end
      nil
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
    rescue ex : BuildError
      raise ex
    rescue ex : ::Regex::Automata::BuildError
      raise BuildError.nfa(ex)
    rescue ex : ::Regex::Syntax::AST::Error | ::Regex::Syntax::Hir::Error
      raise BuildError.new(ex.message)
    end

    def build_from_nfa(nfa : ::Regex::Automata::NFA::NFA) : DFA
      effective_config = @config.dup
      quitset = effective_config.quit_set_from_nfa(nfa)
      classes = effective_config.byte_classes_from_nfa(nfa, quitset)
      quitset.each do |byte|
        effective_config.quit(byte, true) unless effective_config.get_quit(byte)
      end

      min_cache = effective_config.get_minimum_cache_capacity(nfa)
      cache_capacity = effective_config.get_cache_capacity
      if cache_capacity < min_cache
        if effective_config.get_skip_cache_capacity_check
          effective_config.set_effective_cache_capacity(min_cache)
        else
          raise BuildError.insufficient_cache_capacity(min_cache, cache_capacity)
        end
      end

      if err = minimum_lazy_state_id(classes)
        raise BuildError.insufficient_state_id_capacity(err)
      end

      dense = ::Regex::Automata::DFA::Builder
        .from_nfa(nfa, effective_config.to_dense_config)
        .build
      start_map = ::Regex::Automata::StartByteMap.new(nfa.look_matcher)
      DFA.new(effective_config, nfa, dense, start_map, classes, quitset, effective_config.get_cache_capacity)
    end

    private def minimum_lazy_state_id(
      classes : ::Regex::Automata::ByteClasses,
    ) : LazyStateIDError?
      stride = 1 << classes.stride2
      min_state_index = MIN_STATES - 1
      attempted = min_state_index * stride
      result = LazyStateID.new(attempted)
      result.is_a?(LazyStateIDError) ? result : nil
    end
  end

  def self.minimum_cache_capacity(
    nfa : ::Regex::Automata::NFA::NFA,
    classes : ::Regex::Automata::ByteClasses,
    starts_for_each_pattern : Bool,
  ) : Int32
    id_size = sizeof(LazyStateID).to_i32
    state_size = sizeof(::Regex::Automata::Determinize::State).to_i32

    stride = 1 << classes.stride2
    states_len = nfa.states.size.to_i32
    sparses = 2 * states_len * ::Regex::Automata::StateID::SIZE
    trans = MIN_STATES * stride * id_size

    starts = Start.len * id_size
    if starts_for_each_pattern
      starts += Start.len * nfa.pattern_len * id_size
    end

    non_sentinel = MIN_STATES - SENTINEL_STATES
    dead_state_size = ::Regex::Automata::Determinize::State.dead.memory_usage
    max_state_size = 5 + 4 + (nfa.pattern_len * 4) + (states_len * 5)
    states = (SENTINEL_STATES * (state_size + dead_state_size)) +
             (non_sentinel * (state_size + max_state_size))
    states_to_sid = (MIN_STATES * state_size) + (MIN_STATES * id_size)
    stack = states_len * ::Regex::Automata::StateID::SIZE
    scratch_state_builder = max_state_size

    trans +
      starts +
      states +
      states_to_sid +
      sparses +
      stack +
      scratch_state_builder
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
                    .anchored(::Regex::Automata::Anchored::Yes)
                    .earliest(false)
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

      reverse_config = @config.dup
        .prefilter(nil)
        .specialize_start_states(false)
        .match_kind(::Regex::Automata::MatchKind::All)
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
