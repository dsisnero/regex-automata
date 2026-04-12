module Regex::Automata
  # Base error type for regex-automata
  class Error < Exception
  end

  # Error returned when building a DFA/NFA fails
  class BuildError < Error
  end

  # Error returned when deserialization fails
  class DeserializeError < Error
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

    def initialize(@kind : Kind, @byte : UInt8? = nil, @offset : Int32? = nil, @len : Int32? = nil, @mode : Anchored? = nil)
      message = case @kind
                when Kind::Quit
                  "quit byte #{@byte.not_nil!} at offset #{@offset.not_nil!}"
                when Kind::GaveUp
                  "gave up at offset #{@offset.not_nil!}"
                when Kind::HaystackTooLong
                  "haystack too long: #{@len.not_nil!} bytes"
                when Kind::UnsupportedAnchored
                  "unsupported anchored mode"
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
    def self.unsupported_anchored(mode : Anchored) : MatchError
      new(Kind::UnsupportedAnchored, mode: mode)
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
  end
end
