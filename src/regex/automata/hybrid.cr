require "./dfa"
require "./dfa_regex"

require "./sparse_set"

module Regex::Automata::Hybrid
  DEFAULT_CACHE_CAPACITY = 2 * (1 << 20)
  SENTINEL_STATES        = 3
  MIN_STATES             = SENTINEL_STATES + 2

  class BuildError < ::Regex::Automata::BuildError
    getter source : ::Regex::Automata::BuildError?

    def initialize(message : String, size_limit_exceeded : Bool = false, size_limit : Int64? = nil, @source : ::Regex::Automata::BuildError? = nil)
      super(message, size_limit_exceeded, size_limit)
    end

    def self.nfa(err : ::Regex::Automata::BuildError) : BuildError
      new("error building NFA", err.is_size_limit_exceeded, err.size_limit, err)
    end

    def self.insufficient_cache_capacity(minimum : UInt64, given : UInt64) : BuildError
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
    getter source : CacheError?

    def self.cache(source : CacheError = CacheError.too_many_cache_clears) : StartError
      new("error computing start state because of cache inefficiency", cache: true, source: source)
    end

    def self.quit(byte : UInt8) : StartError
      new("error computing start state because the look-behind byte #{::Regex::Automata::DebugByte.new(byte).inspect} triggered a quit state", byte: byte)
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

    def initialize(message : String, @cache : Bool = false, @byte : UInt8? = nil, @mode : ::Regex::Automata::Anchored? = nil, @pattern : ::Regex::Automata::PatternID? = nil, @source : CacheError? = nil)
      super(message)
    end
  end

  struct LazyStateIDError
    getter attempted : Int64 | UInt64

    def initialize(@attempted : Int64 | UInt64)
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
      return LazyStateIDError.new(id.to_i64) if id < 0
      attempted = id.to_u64
      return LazyStateIDError.new(attempted) if attempted > MAX

      LazyStateID.new(id.to_i32)
    end

    def self.new_unchecked(id : Int) : LazyStateID
      LazyStateID.new(id.to_i32!)
    end

    def as_i : Int32
      @value & MAX
    end

    def as_usize_untagged : Int32
      as_i
    end

    def as_usize_unchecked : Int64
      @value.to_u32!.to_i64
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
    @cache_capacity : UInt64?
    @requested_cache_capacity : UInt64?
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
    @minimum_cache_clear_count : UInt64?
    @minimum_cache_clear_count_set : Bool
    @minimum_bytes_per_state : UInt64?
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
      @cache_capacity : UInt64?,
      @requested_cache_capacity : UInt64?,
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
      @minimum_cache_clear_count : UInt64?,
      @minimum_cache_clear_count_set : Bool,
      @minimum_bytes_per_state : UInt64?,
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
      unless @specialize_start_states_set
        @specialize_start_states_value = @dense_config.get_specialize_start_states
        @specialize_start_states_set = true
      end
      self
    end

    def cache_capacity(bytes : Int) : Config
      @cache_capacity = bytes.to_u64
      @requested_cache_capacity = bytes.to_u64
      self
    end

    def skip_cache_capacity_check(yes : Bool) : Config
      @skip_cache_capacity_check = yes
      self
    end

    def minimum_cache_clear_count(min : Int?) : Config
      @minimum_cache_clear_count = min.try(&.to_u64)
      @minimum_cache_clear_count_set = true
      self
    end

    def minimum_bytes_per_state(min : Int?) : Config
      @minimum_bytes_per_state = min.try(&.to_u64)
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

    def get_cache_capacity : UInt64
      @cache_capacity || DEFAULT_CACHE_CAPACITY.to_u64
    end

    def get_skip_cache_capacity_check : Bool
      @skip_cache_capacity_check || false
    end

    def get_requested_cache_capacity : UInt64?
      @requested_cache_capacity
    end

    def get_minimum_cache_clear_count : UInt64?
      @minimum_cache_clear_count_set ? @minimum_cache_clear_count : nil
    end

    def get_minimum_bytes_per_state : UInt64?
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

      # Rust's ByteClassSet adds boundaries for every contiguous quit range.
      # Equal signatures on opposite sides of a boundary stay distinct.
      mapping = Array.new(256, 0)
      class_id = 0
      previous_base = base[0]
      previous_quit = quit.contains(0_u8)
      (1...256).each do |byte|
        current_base = base[byte]
        current_quit = quit.contains(byte.to_u8)
        class_id += 1 if current_base != previous_base || current_quit != previous_quit
        mapping[byte] = class_id
        previous_base = current_base
        previous_quit = current_quit
      end

      ::Regex::Automata::ByteClasses.from_mapping(mapping, class_id + 1)
    end

    def get_minimum_cache_capacity(nfa : ::Regex::Automata::NFA::NFA) : UInt64
      quit = quit_set_from_nfa(nfa)
      classes = byte_classes_from_nfa(nfa, quit)
      ::Regex::Automata::Hybrid.minimum_cache_capacity(
        nfa,
        classes,
        get_starts_for_each_pattern
      )
    end

    def overwrite(other : Config) : Config
      merged_dense = ::Regex::Automata::Config.new
      prefilter_set = other.@prefilter_set || @prefilter_set
      prefilter_value = other.@prefilter_set ? other.@prefilter_value : @prefilter_value
      merged_dense.prefilter(prefilter_value) if prefilter_set
      match_kind = other.@match_kind_set ? other.@match_kind_value : @match_kind_value
      merged_dense.match_kind(match_kind.not_nil!) if other.@match_kind_set || @match_kind_set
      starts_for_each_pattern = other.@starts_for_each_pattern_set ? other.@starts_for_each_pattern_value : @starts_for_each_pattern_value
      merged_dense.starts_for_each_pattern(starts_for_each_pattern.not_nil!) if other.@starts_for_each_pattern_set || @starts_for_each_pattern_set
      byte_classes = other.@byte_classes_set ? other.@byte_classes_value : @byte_classes_value
      merged_dense.byte_classes(byte_classes.not_nil!) if other.@byte_classes_set || @byte_classes_set
      unicode_word_boundary = other.@unicode_word_boundary_set ? other.@unicode_word_boundary_value : @unicode_word_boundary_value
      merged_dense.unicode_word_boundary(unicode_word_boundary.not_nil!) if other.@unicode_word_boundary_set || @unicode_word_boundary_set
      specialize_start_states = other.@specialize_start_states_set ? other.@specialize_start_states_value : @specialize_start_states_value
      merged_dense.specialize_start_states(specialize_start_states.not_nil!) if other.@specialize_start_states_set || @specialize_start_states_set
      quitset = other.@quitset_set ? other.@quitset_value : @quitset_value
      quitset.try &.each { |byte| merged_dense.quit(byte, true) }

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
    property clear_count : UInt64
    getter trans : Array(LazyStateID)
    getter starts : Array(LazyStateID)
    getter states : Array(::Regex::Automata::Determinize::State)
    getter states_to_id : Hash(::Regex::Automata::Determinize::State, LazyStateID)
    getter sparses : SparseSets
    getter stack : Array(::Regex::Automata::StateID)
    property scratch_state_builder : ::Regex::Automata::Determinize::StateBuilderEmpty
    property memory_usage_state : UInt64
    property bytes_searched : UInt64
    property progress : SearchProgress?
    property state_saver : StateSaver

    def initialize(@dfa : DFA)
      @trans = [] of LazyStateID
      @starts = [] of LazyStateID
      @states = [] of ::Regex::Automata::Determinize::State
      @states_to_id = {} of ::Regex::Automata::Determinize::State => LazyStateID
      @sparses = SparseSets.new(@dfa.get_nfa.states.size.to_i32)
      @stack = [] of ::Regex::Automata::StateID
      @scratch_state_builder = ::Regex::Automata::Determinize::StateBuilderEmpty.new
      @memory_usage_state = 0_u64
      @clear_count = 0_u64
      @bytes_searched = 0_u64
      @progress = nil
      @state_saver = StateSaver.none
      Lazy.new(@dfa, self).init_cache
    end

    def self.new(dfa : DFA) : Cache
      previous_def(dfa)
    end

    def reset(dfa : DFA) : Nil
      @dfa = dfa
      Lazy.new(@dfa, self).reset_cache
    end

    def search_start(at : Int) : Nil
      if progress = @progress
        @bytes_searched += progress.len
      end
      position = at.to_u64
      @progress = SearchProgress.new(position, position)
    end

    def search_update(at : Int) : Nil
      if progress = @progress
        progress.at = at.to_u64
      else
        raise "no in-progress search to update"
      end
    end

    def search_finish(at : Int) : Nil
      if progress = @progress
        progress.at = at.to_u64
        @bytes_searched += progress.len
        @progress = nil
      else
        raise "no in-progress search to finish"
      end
    end

    def search_total_len : UInt64
      @bytes_searched + (@progress.try(&.len) || 0)
    end

    def memory_usage : UInt64
      id_size = sizeof(LazyStateID).to_u64
      state_size = sizeof(::Regex::Automata::Determinize::State).to_u64

      (@trans.size.to_u64 * id_size) +
        (@starts.size.to_u64 * id_size) +
        (@states.size.to_u64 * state_size) +
        (@states_to_id.size.to_u64 * (state_size + id_size)) +
        @sparses.memory_usage +
        (@stack.@capacity.to_u64 * ::Regex::Automata::StateID::SIZE.to_u64) +
        @scratch_state_builder.capacity.to_u64 +
        @memory_usage_state
    end
  end

  private class SearchProgress
    property at : UInt64
    property start : UInt64

    def initialize(@start : UInt64, @at : UInt64)
    end

    def len : UInt64
      @start <= @at ? @at - @start : @start - @at
    end
  end

  # Carries the currently executing state through a cache clear. This mirrors
  # Rust's StateSaver: the cold cache-clear path preserves the state whose
  # transition triggered the clear, so the next transition remains cached.
  private class StateSaver
    def initialize(
      @to_save : Tuple(LazyStateID, ::Regex::Automata::Determinize::State)? = nil,
      @saved : LazyStateID? = nil,
    )
    end

    def self.none : StateSaver
      new
    end

    def save(id : LazyStateID, state : ::Regex::Automata::Determinize::State) : Nil
      @to_save = {id, state}
      @saved = nil
    end

    def save_id(id : LazyStateID) : Nil
      @to_save = nil
      @saved = id
    end

    def take_to_save : Tuple(LazyStateID, ::Regex::Automata::Determinize::State)?
      result = @to_save
      @to_save = nil
      @saved = nil
      result
    end

    def take_saved : LazyStateID?
      result = @saved || @to_save.try(&.[0])
      @to_save = nil
      @saved = nil
      result
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
      @cache.state_saver = StateSaver.none
      clear_cache
      @cache.sparses.resize(@dfa.get_nfa.states.size.to_i32)
      @cache.clear_count = 0_u64
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
      @cache.memory_usage_state = 0_u64
      @cache.clear_count += 1
      @cache.bytes_searched = 0_u64
      if progress = @cache.progress
        progress.start = progress.at
      end
      init_cache
      if saved = @cache.state_saver.take_to_save
        old_id, state = saved
        raise "cannot save hybrid sentinel state" if as_ref.is_sentinel(old_id)
        new_id = add_state(state) { |id| old_id.is_start ? id.to_start : id }
        raise new_id if new_id.is_a?(CacheError)
        @cache.state_saver.save_id(new_id.as(LazyStateID))
      end
    end

    private def try_clear_cache : Nil | CacheError
      config = @dfa.get_config
      if minimum = config.get_minimum_cache_clear_count
        if @cache.clear_count >= minimum
          if bytes_per_state = config.get_minimum_bytes_per_state
            state_count = @cache.states.size.to_u64
            minimum_bytes = if state_count > 0 && bytes_per_state > UInt64::MAX // state_count
                              UInt64::MAX
                            else
                              bytes_per_state * state_count
                            end
            return CacheError.bad_efficiency if @cache.search_total_len < minimum_bytes
          else
            return CacheError.too_many_cache_clears
          end
        end
      end
      clear_cache
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
        result = try_clear_cache
        return result if result.is_a?(CacheError)
      end
      next_id = next_state_id
      return next_id if next_id.is_a?(CacheError)
      id = idmap.call(next_id)
      id = id.to_match if state.is_match?
      @cache.trans.concat(Array.new(@dfa.stride) { as_ref.unknown_id })
      if !@dfa.get_quitset.empty? && !as_ref.is_sentinel(id)
        quit_id = as_ref.quit_id
        @dfa.get_quitset.each do |byte|
          set_transition(id, ::Regex::Automata::Unit.u8(byte), quit_id)
        end
      end
      @cache.memory_usage_state += state.memory_usage.to_u64
      @cache.states << state
      @cache.states_to_id[state] = id
      id
    end

    private def add_builder_state(
      builder : ::Regex::Automata::Determinize::StateBuilderNFA,
      &idmap : LazyStateID -> LazyStateID
    ) : LazyStateID | CacheError
      if cached_id = @cache.states_to_id[::Regex::Automata::Determinize::State.new(builder.as_bytes)]?
        put_state_builder(builder)
        return cached_id
      end
      result = add_state(builder.to_state, &idmap)
      put_state_builder(builder)
      result
    end

    private def next_state_id : LazyStateID | CacheError
      result = LazyStateID.new(@cache.trans.size)
      return result.as(LazyStateID) if result.is_a?(LazyStateID)

      cleared = try_clear_cache
      return cleared if cleared.is_a?(CacheError)
      LazyStateID.new(@cache.trans.size).as(LazyStateID)
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
      save_state = !state_builder_fits_in_cache(builder)
      save_state ||= @cache.trans.size >= LazyStateID::MAX
      self.save_state(current) if save_state
      next_sid = add_builder_state(builder, &.itself)
      return next_sid if next_sid.is_a?(CacheError)

      current = saved_state_id if save_state

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
      return StartError.cache(id.as(CacheError)) if id.is_a?(CacheError)

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
      raise "invalid hybrid start state id: #{id.inspect}" unless as_ref.is_valid(id)
      if anchored == ::Regex::Automata::Anchored::Pattern && !@dfa.get_config.get_starts_for_each_pattern
        raise "attempted to search for a specific pattern without enabling starts_for_each_pattern"
      end
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
      needed = @cache.memory_usage +
               memory_usage_for_one_more_state(state_heap_size)
      needed <= @dfa.cache_capacity
    end

    private def state_builder_fits_in_cache(builder : ::Regex::Automata::Determinize::StateBuilderNFA) : Bool
      needed = @cache.memory_usage + memory_usage_for_one_more_state(builder.as_bytes.size.to_i32)
      needed <= @dfa.cache_capacity
    end

    private def memory_usage_for_one_more_state(state_heap_size : Int32) : UInt64
      (@dfa.stride.to_u64 * sizeof(LazyStateID).to_u64) +
        sizeof(::Regex::Automata::Determinize::State).to_u64 +
        (sizeof(::Regex::Automata::Determinize::State).to_u64 + sizeof(LazyStateID).to_u64) +
        state_heap_size.to_u64
    end

    private def save_state(id : LazyStateID) : Nil
      @cache.state_saver.save(id, as_ref.get_cached_state(id))
    end

    private def saved_state_id : LazyStateID
      @cache.state_saver.take_saved || raise "hybrid state saver has no saved state ID"
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
      raise "invalid 'from' id: #{from.inspect}" unless as_ref.is_valid(from)
      raise "invalid 'to' id: #{to.inspect}" unless as_ref.is_valid(to)
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
    @config : Config
    @nfa : ::Regex::Automata::NFA::NFA
    @dense : ::Regex::Automata::DFA::DFA?
    @start_map : ::Regex::Automata::StartByteMap
    @classes : ::Regex::Automata::ByteClasses
    @quitset : ::Regex::Automata::ByteSet
    @cache_capacity : UInt64

    def initialize(
      @config : Config,
      @nfa : ::Regex::Automata::NFA::NFA,
      @start_map : ::Regex::Automata::StartByteMap,
      @classes : ::Regex::Automata::ByteClasses,
      @quitset : ::Regex::Automata::ByteSet,
      @cache_capacity : UInt64,
      @dense : ::Regex::Automata::DFA::DFA? = nil,
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

    def dense : ::Regex::Automata::DFA::DFA
      @dense ||= ::Regex::Automata::DFA::Builder
        .from_nfa(@nfa, @config.to_dense_config)
        .build
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

    def get_cache_capacity : UInt64
      @cache_capacity
    end

    def pattern_len : Int32
      @nfa.pattern_len
    end

    def memory_usage : UInt64
      0_u64
    end

    def cache_capacity : UInt64
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
      raise "hybrid state is not a match state" unless id.is_match
      LazyRef.new(self, cache).get_cached_state(id).match_len
    end

    def match_pattern(cache : Cache, id : LazyStateID, index : Int32) : ::Regex::Automata::PatternID
      return ::Regex::Automata::PatternID::ZERO if pattern_len == 1
      LazyRef.new(self, cache).get_cached_state(id).match_pattern(index)
    end

    def universal_start_state(mode : ::Regex::Automata::Anchored) : LazyStateID?
      return nil unless @nfa.look_set_prefix_any.empty?
      return nil if mode == ::Regex::Automata::Anchored::Pattern
      cache = create_cache
      sid = Lazy.new(self, cache).start_state(::Regex::Automata::StartConfig.new(nil, mode))
      sid.as?(LazyStateID)
    end

    def start_state(cache : Cache, config : ::Regex::Automata::StartConfig) : LazyStateID | StartError
      Lazy.new(self, cache).start_state(config)
    end

    def start_state(cache : Cache, input : ::Regex::Automata::Input) : LazyStateID | StartError
      start_state(cache, ::Regex::Automata::StartConfig.from_input_forward(input))
    end

    def start_state_forward(cache : Cache, input : ::Regex::Automata::Input) : LazyStateID | ::Regex::Automata::MatchError
      result = start_state(cache, input)
      return result if result.is_a?(LazyStateID)

      error = result.as(StartError)
      if byte = error.byte
        raise "no quit in start without look-behind" if input.start == 0
        ::Regex::Automata::MatchError.quit(byte, input.start - 1)
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
      offset = current.as_usize_untagged + @classes.get(input).to_i
      next_sid = cache.trans[offset]
      return next_sid unless next_sid.is_unknown

      Lazy.new(self, cache).next_state(current, ::Regex::Automata::Unit.u8(input))
    end

    def next_state_untagged(cache : Cache, current : LazyStateID, input : UInt8) : LazyStateID
      offset = current.as_usize_unchecked.to_i32! + @classes.get(input).to_i
      cache.trans[offset]
    end

    # The caller must supply an untagged state ID from this cache's current
    # generation. As in Rust, invalid IDs may read beyond the transition row.
    def next_state_untagged_unchecked(cache : Cache, current : LazyStateID, input : UInt8) : LazyStateID
      offset = current.as_usize_unchecked.to_i32! + @classes.get(input).to_i
      cache.trans.unsafe_fetch(offset)
    end

    def next_eoi_state(cache : Cache, current : LazyStateID) : LazyStateID | CacheError
      Lazy.new(self, cache).next_state(current, @classes.eoi)
    end

    def try_search_fwd(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch? | ::Regex::Automata::MatchError
      result = try_search_fwd_raw(cache, input)
      return result unless @nfa.has_empty && @nfa.is_utf8
      return result unless result.is_a?(::Regex::Automata::HalfMatch)
      ::Regex::Automata::Empty.skip_splits_fwd(input, result) do |search|
        try_search_fwd_raw(cache, search)
      end
    end

    private def try_search_fwd_raw(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch? | ::Regex::Automata::MatchError
      pre = input.get_anchored == ::Regex::Automata::Anchored::No ? get_prefilter : nil
      try_search_fwd_once(cache, input, pre)
    end

    private def try_search_fwd_once(cache : Cache, input : ::Regex::Automata::Input, pre : ::Regex::Automata::Prefilter?) : ::Regex::Automata::HalfMatch? | ::Regex::Automata::MatchError
      return nil if input.is_done

      sid = start_state_forward(cache, input)
      return sid if sid.is_a?(::Regex::Automata::MatchError)

      current = sid.as(LazyStateID)
      match = nil.as(::Regex::Automata::HalfMatch?)
      at = input.start
      universal_start = @nfa.look_set_prefix_any.empty?
      if pre
        candidate = pre.find(input.haystack, ::Regex::Automata::Span.new(at, input.end))
        return nil unless candidate

        if candidate.start > at
          at = candidate.start
          unless universal_start
            restarted = input.clone
            restarted.set_start(at)
            sid = start_state_forward(cache, restarted)
            return sid if sid.is_a?(::Regex::Automata::MatchError)
            current = sid.as(LazyStateID)
          end
        end
      end
      cache.search_start(at)
      while at < input.end
        if current.is_tagged
          cache.search_update(at)
          next_sid = next_state(cache, current, input.haystack[at])
          return ::Regex::Automata::MatchError.gave_up(at) if next_sid.is_a?(CacheError)
          current = next_sid.as(LazyStateID)
        else
          previous = current
          loop do
            # Rust groups cached untagged transitions and leaves unknown
            # transitions for the state-building slow path below. Unlike its
            # unsafe lookup, Crystal's Array access remains bounds checked.
            current = cache.trans[previous.as_usize_untagged + @classes.get(input.haystack[at]).to_i]
            break if current.is_tagged || input.end - at <= 3
            at += 1

            previous = current
            current = cache.trans[previous.as_usize_untagged + @classes.get(input.haystack[at]).to_i]
            break if current.is_tagged
            at += 1

            previous = current
            current = cache.trans[previous.as_usize_untagged + @classes.get(input.haystack[at]).to_i]
            break if current.is_tagged
            at += 1

            previous = current
            current = cache.trans[previous.as_usize_untagged + @classes.get(input.haystack[at]).to_i]
            break if current.is_tagged
            at += 1
            break if at >= input.end
            previous = current
          end
          if current.is_unknown
            cache.search_update(at)
            next_sid = next_state(cache, previous, input.haystack[at])
            return ::Regex::Automata::MatchError.gave_up(at) if next_sid.is_a?(CacheError)
            current = next_sid.as(LazyStateID)
          end
        end
        if current.is_start && pre
          unless match
            candidate = pre.find(input.haystack, ::Regex::Automata::Span.new(at, input.end))
            unless candidate
              cache.search_finish(input.end)
              return match
            end
            if candidate.start > at
              at = candidate.start
              unless universal_start
                restarted = input.clone
                restarted.set_start(at)
                sid = start_state_forward(cache, restarted)
                return sid if sid.is_a?(::Regex::Automata::MatchError)
                current = sid.as(LazyStateID)
              end
              next
            end
          end
        elsif current.is_match
          match = ::Regex::Automata::HalfMatch.new(match_pattern(cache, current, 0), at)
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
        at += 1
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
      match
    end

    def try_search_rev(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch? | ::Regex::Automata::MatchError
      result = try_search_rev_raw(cache, input)
      return result unless @nfa.has_empty && @nfa.is_utf8
      return result unless result.is_a?(::Regex::Automata::HalfMatch)
      ::Regex::Automata::Empty.skip_splits_rev(input, result) do |search|
        try_search_rev_raw(cache, search)
      end
    end

    private def try_search_rev_raw(cache : Cache, input : ::Regex::Automata::Input) : ::Regex::Automata::HalfMatch? | ::Regex::Automata::MatchError
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
        if current.is_tagged
          cache.search_update(at)
          next_sid = next_state(cache, current, input.haystack[at])
          return ::Regex::Automata::MatchError.gave_up(at) if next_sid.is_a?(CacheError)
          current = next_sid.as(LazyStateID)
        else
          previous = current
          loop do
            # As in Rust's reverse search, consume four cached untagged
            # transitions per iteration and only enter the checked builder
            # path on an unknown transition. The index is guarded by `at`.
            current = cache.trans[previous.as_usize_untagged + @classes.get(input.haystack[at]).to_i]
            break if current.is_tagged || at - input.start <= 3
            at -= 1

            previous = current
            current = cache.trans[previous.as_usize_untagged + @classes.get(input.haystack[at]).to_i]
            break if current.is_tagged
            at -= 1

            previous = current
            current = cache.trans[previous.as_usize_untagged + @classes.get(input.haystack[at]).to_i]
            break if current.is_tagged
            at -= 1

            previous = current
            current = cache.trans[previous.as_usize_untagged + @classes.get(input.haystack[at]).to_i]
            break if current.is_tagged
            at -= 1
            previous = current
          end
          if current.is_unknown
            cache.search_update(at)
            next_sid = next_state(cache, previous, input.haystack[at])
            return ::Regex::Automata::MatchError.gave_up(at) if next_sid.is_a?(CacheError)
            current = next_sid.as(LazyStateID)
          end
        end
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
      result = try_search_overlapping_fwd_raw(cache, input, state)
      return result if result.is_a?(::Regex::Automata::MatchError)
      skip_empty_utf8_splits_overlapping(cache, input, state, true)
    end

    private def try_search_overlapping_fwd_raw(cache : Cache, input : ::Regex::Automata::Input, state : OverlappingState) : Nil | ::Regex::Automata::MatchError
      state.mat = nil
      return nil if input.is_done
      pre = input.get_anchored == ::Regex::Automata::Anchored::No ? get_prefilter : nil
      universal_start = @nfa.look_set_prefix_any.empty?

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
        if current.is_start && pre
          candidate = pre.find(input.haystack, ::Regex::Automata::Span.new(state.at, input.end))
          unless candidate
            return nil
          end

          if candidate.start > state.at
            state.at = candidate.start
            unless universal_start
              restarted_input = input.clone
              restarted_input.set_start(state.at)
              restarted = start_state_forward(cache, restarted_input)
              return restarted if restarted.is_a?(::Regex::Automata::MatchError)
              current = restarted.as(LazyStateID)
            end
            next
          end
        elsif current.is_match
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
      result = try_search_overlapping_rev_raw(cache, input, state)
      return result if result.is_a?(::Regex::Automata::MatchError)
      skip_empty_utf8_splits_overlapping(cache, input, state, false)
    end

    private def try_search_overlapping_rev_raw(cache : Cache, input : ::Regex::Automata::Input, state : OverlappingState) : Nil | ::Regex::Automata::MatchError
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

    private def skip_empty_utf8_splits_overlapping(cache : Cache, input : ::Regex::Automata::Input,
                                                   state : OverlappingState, forward : Bool) : Nil | ::Regex::Automata::MatchError
      return nil unless @nfa.has_empty && @nfa.is_utf8
      return nil unless match = state.get_match
      if input.get_anchored != ::Regex::Automata::Anchored::No
        state.mat = nil unless input.is_char_boundary(match.offset)
        return nil
      end
      until input.is_char_boundary(match.offset)
        result = if forward
                   try_search_overlapping_fwd_raw(cache, input, state)
                 else
                   try_search_overlapping_rev_raw(cache, input, state)
                 end
        return result if result.is_a?(::Regex::Automata::MatchError)
        return nil unless match = state.get_match
      end
      nil
    end

    def try_which_overlapping_matches(cache : Cache, input : ::Regex::Automata::Input, patset : ::Regex::Automata::PatternSet) : Nil | ::Regex::Automata::MatchError
      state = OverlappingState.start
      loop do
        result = try_search_overlapping_fwd(cache, input, state)
        return result if result.is_a?(::Regex::Automata::MatchError)

        half_match = state.get_match
        break unless half_match

        patset.try_insert(half_match.pattern)
        break if patset.is_full || input.get_earliest
      end
      nil
    end

    def start_of(config : ::Regex::Automata::StartConfig) : Start | StartError
      if look_behind = config.get_look_behind
        return StartError.quit(look_behind) if @quitset.contains(look_behind)
        @start_map.get(look_behind)
      else
        Start::Text
      end
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
      @thompson_config = @thompson_config.overwrite(config)
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
      ).build_many_from_hir(hirs)
      build_from_nfa(nfa)
    rescue ex : BuildError
      raise ex
    rescue ex : ::Regex::Automata::BuildError
      raise BuildError.nfa(ex)
    rescue ex : ::Regex::Syntax::AST::Error | ::Regex::Syntax::Hir::Error
      raise BuildError.nfa(::Regex::Automata::NFA::BuildError.syntax(ex))
    end

    def build_from_nfa(nfa : ::Regex::Automata::NFA::NFA) : DFA
      effective_config = @config.dup
      quitset = effective_config.quit_set_from_nfa(nfa)
      classes = effective_config.byte_classes_from_nfa(nfa, quitset)

      min_cache = effective_config.get_minimum_cache_capacity(nfa)
      cache_capacity = effective_config.get_cache_capacity
      if cache_capacity < min_cache
        if effective_config.get_skip_cache_capacity_check
          cache_capacity = min_cache
        else
          raise BuildError.insufficient_cache_capacity(min_cache, cache_capacity)
        end
      end

      if err = minimum_lazy_state_id(classes)
        raise BuildError.insufficient_state_id_capacity(err)
      end

      start_map = ::Regex::Automata::StartByteMap.new(nfa.look_matcher)
      DFA.new(effective_config, nfa, start_map, classes, quitset, cache_capacity, nil)
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
  ) : UInt64
    id_size = sizeof(LazyStateID).to_u64
    state_size = sizeof(::Regex::Automata::Determinize::State).to_u64

    stride = 1_u64 << classes.stride2
    states_len = nfa.states.size.to_u64
    sparses = 2_u64 * states_len * ::Regex::Automata::StateID::SIZE.to_u64
    trans = MIN_STATES.to_u64 * stride * id_size

    starts = Start.len.to_u64 * id_size
    if starts_for_each_pattern
      starts += Start.len.to_u64 * nfa.pattern_len.to_u64 * id_size
    end

    non_sentinel = (MIN_STATES - SENTINEL_STATES).to_u64
    dead_state_size = ::Regex::Automata::Determinize::State.dead.memory_usage.to_u64
    max_state_size = 5_u64 + 4_u64 + (nfa.pattern_len.to_u64 * 4_u64) + (states_len * 5_u64)
    states = (SENTINEL_STATES.to_u64 * (state_size + dead_state_size)) +
             (non_sentinel * (state_size + max_state_size))
    states_to_sid = (MIN_STATES.to_u64 * state_size) + (MIN_STATES.to_u64 * id_size)
    stack = states_len * ::Regex::Automata::StateID::SIZE.to_u64
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

    def memory_usage : UInt64
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
      end_match = @forward.try_search_fwd(cache.forward, input)
      return end_match if end_match.is_a?(::Regex::Automata::MatchError)
      end_half = end_match.as?(::Regex::Automata::HalfMatch)
      return nil unless end_half

      end_pos = end_half.offset
      pattern = end_half.pattern
      if input.start == end_pos
        return ::Regex::Automata::Match.new(pattern, end_pos, end_pos)
      end

      if is_anchored?(input)
        return ::Regex::Automata::Match.new(pattern, input.start, end_pos)
      end

      revsearch = input.clone
        .span(input.start...end_pos)
        .anchored(::Regex::Automata::Anchored::Yes)
        .earliest(false)
      start_match = @reverse.try_search_rev(cache.reverse, revsearch)
      return start_match if start_match.is_a?(::Regex::Automata::MatchError)
      start_half = start_match.as?(::Regex::Automata::HalfMatch)
      raise "reverse search must match if forward search does" unless start_half

      ::Regex::Automata::Match.new(pattern, start_half.offset, end_pos)
    end

    private def is_anchored?(input : ::Regex::Automata::Input) : Bool
      case input.get_anchored
      when ::Regex::Automata::Anchored::No
        @forward.get_nfa.is_always_start_anchored
      when ::Regex::Automata::Anchored::Yes, ::Regex::Automata::Anchored::Pattern
        true
      else
        false
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

    def memory_usage : UInt64
      @forward.memory_usage + @reverse.memory_usage
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
