module Regex::Automata
  # Base error type for regex-automata
  class Error < Exception
  end

  # Error returned when building a DFA/NFA fails
  class BuildError < Error
    getter? size_limit_exceeded : Bool
    getter size_limit : Int64?

    def initialize(message : String? = nil, @size_limit_exceeded : Bool = false, @size_limit : Int64? = nil)
      super(message)
    end

    def is_size_limit_exceeded : Bool
      @size_limit_exceeded
    end
  end

  # Error returned when deserialization fails
  class DeserializeError < Error
  end

  # Error returned when serialization fails
  class SerializeError < Error
  end

  # Match error returned when a search fails
  class MatchError < Error
    enum Kind
      # The search saw a "quit" byte at which it was instructed to stop searching
      Quit
      # The search, based on heuristics, determined that it would be better to stop
      GaveUp
      # The haystack given to the regex engine was too long to be searched
      HaystackTooLong
      # The caller requested a search with an anchor mode that is not supported
      UnsupportedAnchored
    end

    getter kind : Kind
    getter byte : UInt8?
    getter offset : Int32?
    getter len : Int32?
    getter mode : Anchored?
    getter pattern : PatternID?

    def initialize(@kind : Kind, @byte : UInt8? = nil, @offset : Int32? = nil, @len : Int32? = nil, @mode : Anchored? = nil, @pattern : PatternID? = nil)
      message = case @kind
                when Kind::Quit
                  "quit search after observing byte #{@byte.not_nil!} at offset #{@offset.not_nil!}"
                when Kind::GaveUp
                  "gave up searching at offset #{@offset.not_nil!}"
                when Kind::HaystackTooLong
                  "haystack of length #{@len.not_nil!} is too long"
                when Kind::UnsupportedAnchored
                  case @mode
                  when Anchored::Yes
                    "anchored searches are not supported or enabled"
                  when Anchored::No
                    "unanchored searches are not supported or enabled"
                  when Anchored::Pattern
                    if pattern = @pattern
                      "anchored searches for a specific pattern (#{pattern.to_i}) are not supported or enabled"
                    else
                      "anchored searches for a specific pattern are not supported or enabled"
                    end
                  else
                    "unsupported anchored mode"
                  end
                else
                  "match error"
                end
      super(message)
    end

    # Create a new "quit" error
    def self.quit(byte : UInt8, offset : Int32) : MatchError
      new(Kind::Quit, byte: byte, offset: offset)
    end

    # Create a new "gave up" error
    def self.gave_up(offset : Int32) : MatchError
      new(Kind::GaveUp, offset: offset)
    end

    # Create a new "haystack too long" error
    def self.haystack_too_long(len : Int32) : MatchError
      new(Kind::HaystackTooLong, len: len)
    end

    # Create a new "unsupported anchored" error
    def self.unsupported_anchored(mode : Anchored, pattern : PatternID? = nil) : MatchError
      new(Kind::UnsupportedAnchored, mode: mode, pattern: pattern)
    end

    # Check if this is a quit error
    def quit? : Bool
      @kind == Kind::Quit
    end

    # Check if this is a gave up error
    def gave_up? : Bool
      @kind == Kind::GaveUp
    end

    # Check if this is a haystack too long error
    def haystack_too_long? : Bool
      @kind == Kind::HaystackTooLong
    end

    # Check if this is an unsupported anchored error
    def unsupported_anchored? : Bool
      @kind == Kind::UnsupportedAnchored
    end

    def ==(other : MatchError) : Bool
      @kind == other.kind &&
        @byte == other.byte &&
        @offset == other.offset &&
        @len == other.len &&
        @mode == other.mode &&
        @pattern == other.pattern
    end
  end
end
