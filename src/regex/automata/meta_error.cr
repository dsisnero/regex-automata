module Regex::Automata::Meta
  class BuildError < ::Regex::Automata::BuildError
    getter pattern : ::Regex::Automata::PatternID?
    getter size_limit : Int64?
    getter syntax_error : String?

    def initialize(
      *,
      message : String? = nil,
      @pattern : ::Regex::Automata::PatternID? = nil,
      @size_limit : Int64? = nil,
      @syntax_error : String? = nil,
      size_limit_exceeded : Bool = false,
    )
      super(message, size_limit_exceeded)
    end

    def self.syntax_error(pid : ::Regex::Automata::PatternID, error) : BuildError
      BuildError.new(
        message: "error parsing pattern #{pid.to_i}",
        pattern: pid,
        syntax_error: error.message
      )
    end

    def self.pattern(pid : ::Regex::Automata::PatternID, error) : BuildError
      syntax_error(pid, error)
    end

    def self.size_limit(limit : Int64, error = nil) : BuildError
      BuildError.new(
        message: "error building NFA",
        size_limit: limit,
        syntax_error: error.try(&.message),
        size_limit_exceeded: true
      )
    end
  end

  abstract class RetryError < ::Regex::Automata::Error
  end

  class RetryQuadraticError < RetryError
    def initialize
      super("regex engine gave up to avoid quadratic behavior")
    end
  end

  class RetryFailError < RetryError
    getter offset : Int32

    def initialize(@offset : Int32)
      super("regex engine failed at offset #{@offset}")
    end

    def self.from_match_error(error : ::Regex::Automata::MatchError) : self
      case error.kind
      when ::Regex::Automata::MatchError::Kind::Quit,
           ::Regex::Automata::MatchError::Kind::GaveUp
        new(error.offset || 0)
      else
        raise "impossible meta retry failure: #{error.message}"
      end
    end
  end
end
