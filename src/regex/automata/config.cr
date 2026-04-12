require "./byte_set"

module Regex::Automata
  # Configuration for building a DFA
  class Config
    @accelerate : Bool?
    @prefilter : Bool?
    @minimize : Bool?
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

    # Get the quit set
    def quitset : ByteSet
      @quitset || ByteSet.empty
    end

    # Check if Unicode word boundaries are enabled
    def unicode_word_boundary? : Bool
      @unicode_word_boundary || false
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
      @byte_classes = other.@byte_classes
      @unicode_word_boundary = other.@unicode_word_boundary
      @quitset = other.@quitset
      @specialize_start_states = other.@specialize_start_states
      @dfa_size_limit = other.@dfa_size_limit
      @determinize_size_limit = other.@determinize_size_limit
    end
  end
end
