require "./byte_set"

module Regex::Automata
  # Configuration for building a DFA
  class Config
    @accelerate : Bool?
    @prefilter : Prefilter?
    @minimize : Bool?
    @match_kind : MatchKind?
    @start_kind : StartKind?
    @starts_for_each_pattern : Bool?
    @byte_classes : Bool?
    @unicode_word_boundary : Bool?
    @quitset : ByteSet?
    @specialize_start_states : Bool?
    @dfa_size_limit : Int64?
    @determinize_size_limit : Int64?

    # Create a new default configuration
    def initialize
      # All options start as nil to distinguish between "default" and "not set"
    end

    # Add a "quit" byte to the DFA
    #
    # When a quit byte is seen during search time, then search will return
    # a `MatchError::quit` error indicating the offset at which the search stopped.
    #
    # A quit byte will always overrule any other aspects of a regex. For
    # example, if the `x` byte is added as a quit byte and the regex `\w` is
    # used, then observing `x` will cause the search to quit immediately
    # despite the fact that `x` is in the `\w` class.
    #
    # By default, there are no quit bytes set.
    def quit(byte : UInt8, yes : Bool) : Config
      # If Unicode word boundaries are enabled and we're trying to mark
      # a non-ASCII byte as NOT a quit byte, that's an error.
      if @unicode_word_boundary == true && !yes && byte >= 0x80
        raise "cannot mark non-ASCII byte 0x#{byte.to_s(16)} as non-quit when Unicode word boundaries are enabled"
      end

      quitset = @quitset || ByteSet.empty
      if yes
        @quitset = quitset.add(byte)
      else
        @quitset = quitset.remove(byte)
      end
      self
    end

    # Enable or disable state acceleration
    #
    # When enabled, DFA construction will analyze each state to determine
    # whether it is eligible for simple acceleration. Acceleration typically
    # occurs when most of a state's transitions loop back to itself, leaving
    # only a select few bytes that will exit the state. When this occurs,
    # other routines like `memchr` can be used to look for those bytes which
    # may be much faster than traversing the DFA.
    #
    # Callers may elect to disable this if consistent performance is more
    # desirable than variable performance. Namely, acceleration can sometimes
    # make searching slower than it otherwise would be if the transitions
    # that leave accelerated states are traversed frequently.
    #
    # This is enabled by default.
    def accelerate(yes : Bool) : Config
      @accelerate = yes
      self
    end

    # Returns whether this configuration has enabled simple state acceleration.
    def accelerate? : Bool
      @accelerate.nil? ? true : @accelerate.not_nil!
    end

    # Set or clear the prefilter attached to DFAs built with this config.
    def prefilter(prefilter : Prefilter?) : Config
      @prefilter = prefilter
      if @specialize_start_states.nil?
        @specialize_start_states = !prefilter.nil?
      end
      self
    end

    # Returns the prefilter attached to this configuration, if any.
    def prefilter : Prefilter?
      @prefilter
    end

    # Enable or disable Unicode word boundaries
    #
    # When enabled, the DFA will support Unicode word boundaries. When
    # disabled, the DFA will only support ASCII word boundaries.
    #
    # Enabling this option may cause the DFA construction to fail if the
    # pattern contains a Unicode word boundary and the DFA would exceed
    # size limits.
    def unicode_word_boundary(yes : Bool) : Config
      @unicode_word_boundary = yes
      self
    end

    # Set the match kind
    def match_kind(kind : MatchKind) : Config
      @match_kind = kind
      self
    end

    # Get the match kind
    def match_kind : MatchKind
      @match_kind || MatchKind::LeftmostFirst
    end

    # Set the start kind
    def start_kind(kind : StartKind) : Config
      @start_kind = kind
      self
    end

    # Get the start kind
    def start_kind : StartKind
      @start_kind || StartKind::Both
    end

    # Enable or disable start state specialization
    #
    # When enabled (the default), DFA construction will attempt to shuffle
    # start states to the beginning of the DFA such that they are part of
    # a contiguous region of "special" states. This makes it very fast to
    # determine whether a state is a start state or not by a single
    # comparison.
    #
    # The only time one might want to disable this is when there is no
    # prefilter. In that case, there's no benefit to specializing start
    # states. But when a prefilter is active, specializing start states
    # enables the prefilter to be used at search time. Specifically, a
    # prefilter can only run when in a start state.
    def specialize_start_states(yes : Bool) : Config
      @specialize_start_states = yes
      self
    end

    # Get whether start states are specialized
    def specialize_start_states? : Bool
      @specialize_start_states.nil? ? false : @specialize_start_states.not_nil!
    end

    # Enable or disable start states for each pattern
    def starts_for_each_pattern(yes : Bool) : Config
      @starts_for_each_pattern = yes
      self
    end

    # Check if start states for each pattern are enabled
    def starts_for_each_pattern? : Bool
      @starts_for_each_pattern || false
    end

    # Get the quit set
    def quitset : ByteSet
      @quitset || ByteSet.empty
    end

    # Check if Unicode word boundaries are enabled
    def unicode_word_boundary? : Bool
      @unicode_word_boundary || false
    end

    # Enable or disable DFA minimization.
    def minimize(yes : Bool) : Config
      @minimize = yes
      self
    end

    # Enable or disable byte class compression.
    def byte_classes(yes : Bool) : Config
      @byte_classes = yes
      self
    end

    # Set an optional size limit for the final DFA.
    def dfa_size_limit(bytes : Int64?) : Config
      @dfa_size_limit = bytes
      self
    end

    # Set an optional size limit for determinization scratch space.
    def determinize_size_limit(bytes : Int64?) : Config
      @determinize_size_limit = bytes
      self
    end

    # Upstream compatibility getter aliases.
    def get_accelerate : Bool
      accelerate?
    end

    def get_minimize : Bool
      @minimize || false
    end

    def get_match_kind : MatchKind
      match_kind
    end

    def get_starts : StartKind
      start_kind
    end

    def get_starts_for_each_pattern : Bool
      starts_for_each_pattern?
    end

    def get_byte_classes : Bool
      @byte_classes.nil? ? true : @byte_classes.not_nil!
    end

    def get_unicode_word_boundary : Bool
      unicode_word_boundary?
    end

    def get_quit(byte : UInt8) : Bool
      quitset.includes?(byte)
    end

    def get_specialize_start_states : Bool
      specialize_start_states?
    end

    def get_dfa_size_limit : Int64?
      @dfa_size_limit
    end

    def get_determinize_size_limit : Int64?
      @determinize_size_limit
    end

    def get_prefilter : Prefilter?
      @prefilter
    end

    # Create a copy of this configuration
    def dup : Config
      # Create a new config
      config = Config.new

      # Copy instance variables using unsafe methods
      # This is not ideal but works for our use case
      config.copy_from(self)
      config
    end

    # Copy configuration from another config (internal use only)
    protected def copy_from(other : Config)
      @accelerate = other.@accelerate
      @prefilter = other.@prefilter
      @minimize = other.@minimize
      @match_kind = other.@match_kind
      @start_kind = other.@start_kind
      @starts_for_each_pattern = other.@starts_for_each_pattern
      @byte_classes = other.@byte_classes
      @unicode_word_boundary = other.@unicode_word_boundary
      @quitset = other.@quitset
      @specialize_start_states = other.@specialize_start_states
      @dfa_size_limit = other.@dfa_size_limit
      @determinize_size_limit = other.@determinize_size_limit
    end
  end
end
