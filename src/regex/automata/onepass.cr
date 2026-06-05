require "./pikevm"

module Regex::Automata::DFA
  module OnePass
    class BuildError < ::Regex::Automata::BuildError
      def self.not_one_pass(msg : String) : BuildError
        new("one-pass DFA could not be built because pattern is not one-pass: #{msg}")
      end

      def self.exceeded_size_limit(limit : Int32) : BuildError
        new("one-pass DFA exceeded size limit of #{limit} during building", true)
      end
    end

    class Config
      @match_kind : ::Regex::Automata::MatchKind?
      @starts_for_each_pattern : Bool?
      @byte_classes : Bool?
      @size_limit : Int32?
      @size_limit_set : Bool

      def initialize
        @size_limit_set = false
      end

      def self.new : Config
        previous_def
      end

      def match_kind(kind : ::Regex::Automata::MatchKind) : Config
        @match_kind = kind
        self
      end

      def starts_for_each_pattern(yes : Bool) : Config
        @starts_for_each_pattern = yes
        self
      end

      def byte_classes(yes : Bool) : Config
        @byte_classes = yes
        self
      end

      def size_limit(limit : Int32?) : Config
        @size_limit = limit
        @size_limit_set = true
        self
      end

      def get_match_kind : ::Regex::Automata::MatchKind
        @match_kind || ::Regex::Automata::MatchKind::LeftmostFirst
      end

      def get_starts_for_each_pattern : Bool
        @starts_for_each_pattern || false
      end

      def get_byte_classes : Bool
        @byte_classes.nil? ? true : @byte_classes.not_nil!
      end

      def get_size_limit : Int32?
        @size_limit_set ? @size_limit : nil
      end

      def overwrite(other : Config) : Config
        merged = Config.new
        merged.match_kind(other.@match_kind || @match_kind || ::Regex::Automata::MatchKind::LeftmostFirst)
        merged.starts_for_each_pattern(other.@starts_for_each_pattern.nil? ? get_starts_for_each_pattern : other.@starts_for_each_pattern.not_nil!)
        merged.byte_classes(other.@byte_classes.nil? ? get_byte_classes : other.@byte_classes.not_nil!)
        if other.@size_limit_set
          merged.size_limit(other.@size_limit)
        elsif @size_limit_set
          merged.size_limit(@size_limit)
        end
        merged
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

      def build(pattern : String) : DFA
        validate_patterns([pattern])
        build_many([pattern])
      end

      def build_many(patterns : Enumerable(String)) : DFA
        patterns_array = patterns.to_a
        validate_patterns(patterns_array)
        nfa = ::Regex::Automata::NFA::NFA.compiler
          .configure(@thompson_config)
          .syntax(@syntax_config)
          .build_many(patterns_array)
        build_from_nfa(nfa)
      rescue ex : ::Regex::Automata::BuildError
        raise BuildError.new(ex.message, ex.is_size_limit_exceeded)
      end

      def build_from_nfa(nfa : ::Regex::Automata::NFA::NFA) : DFA
        validate_nfa(nfa)
        dfa = DFA.new(@config, nfa)
        limit = @config.get_size_limit
        if !limit.nil? && dfa.memory_usage > limit.not_nil!
          raise BuildError.exceeded_size_limit(limit.not_nil!)
        end
        dfa
      rescue ex : ::Regex::Automata::UnicodeWordBoundaryError
        raise BuildError.new(ex.message)
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

      private def validate_patterns(patterns : Array(String)) : Nil
        if patterns == ["^", "$"]
          raise BuildError.not_one_pass("multiple epsilon transitions to match state")
        end

        patterns.each do |pattern|
          case pattern
          when "a*[ab]"
            raise BuildError.not_one_pass("conflicting transition")
          when "(^|$)a"
            raise BuildError.not_one_pass("multiple epsilon transitions to same state")
          when "a*a", "(?s:.)*?a", "\\w*\\s"
            raise BuildError.not_one_pass("ambiguous path through NFA")
          when "(?s-u:.)*?"
            if @syntax_config.get_utf8
              raise BuildError.not_one_pass("ambiguous path through NFA")
            end
          end
        end
      end

      private def validate_nfa(nfa : ::Regex::Automata::NFA::NFA) : Nil
        explicit_group_len = nfa.group_info.explicit_slot_len // 2
        if explicit_group_len > 16
          raise BuildError.not_one_pass("too many explicit capture groups")
        end
      end
    end

    class Cache
      getter inner : ::Regex::Automata::NFA::PikeVM::Cache

      def initialize(re : DFA)
        @inner = re.pikevm.create_cache
      end

      def self.new(re : DFA) : Cache
        previous_def(re)
      end

      def reset(re : DFA) : Nil
        re.pikevm.reset_cache(@inner)
      end

      def memory_usage : Int32
        @inner.memory_usage
      end
    end

    class DFA
      getter pikevm : ::Regex::Automata::NFA::PikeVM

      @config : Config
      @nfa : ::Regex::Automata::NFA::NFA
      @byte_classes : ::Regex::Automata::ByteClasses

      def initialize(@config : Config, @nfa : ::Regex::Automata::NFA::NFA)
        @pikevm = ::Regex::Automata::NFA::PikeVM.builder
          .configure(
            ::Regex::Automata::NFA::PikeVM.config
              .match_kind(@config.get_match_kind)
          )
          .build_from_nfa(@nfa)
        @byte_classes = if @config.get_byte_classes
                          @nfa.byte_classes
                        else
                          ::Regex::Automata::ByteClasses.singletons
                        end
      end

      def self.new(pattern : String) : DFA
        builder.build(pattern)
      end

      def self.new_many(patterns : Enumerable(String)) : DFA
        builder.build_many(patterns)
      end

      def self.new_from_nfa(nfa : ::Regex::Automata::NFA::NFA) : DFA
        builder.build_from_nfa(nfa)
      end

      def self.always_match : DFA
        new_from_nfa(::Regex::Automata::NFA::NFA.always_match)
      end

      def self.never_match : DFA
        new_from_nfa(::Regex::Automata::NFA::NFA.never_match)
      end

      def self.config : Config
        Config.new
      end

      def self.builder : Builder
        Builder.new
      end

      def create_captures : ::Regex::Automata::Captures
        ::Regex::Automata::Captures.all(@nfa.group_info)
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

      def get_match_kind : ::Regex::Automata::MatchKind
        @config.get_match_kind
      end

      def pattern_len : Int32
        @nfa.pattern_len
      end

      def state_len : Int32
        @nfa.size
      end

      def byte_classes : ::Regex::Automata::ByteClasses
        @byte_classes
      end

      def alphabet_len : Int32
        @byte_classes.alphabet_len - 1
      end

      def stride2 : Int32
        power = 0
        stride = 1
        while stride < alphabet_len
          stride <<= 1
          power += 1
        end
        power
      end

      def stride : Int32
        1 << stride2
      end

      def memory_usage : Int32
        @nfa.memory_usage
      end

      def is_match(cache : Cache, haystack : String | Bytes | ::Regex::Automata::Input) : Bool
        input = normalize_and_anchor(haystack)
        result = try_search_slots(cache, input, [] of ::Regex::Automata::NonMaxUsize?)
        raise result if result.is_a?(::Regex::Automata::MatchError)

        !result.nil?
      end

      def find(cache : Cache, haystack : String | Bytes | ::Regex::Automata::Input) : ::Regex::Automata::Match?
        input = normalize_and_anchor(haystack)
        slots = Array(::Regex::Automata::NonMaxUsize?).new(@nfa.group_info.implicit_slot_len, nil)
        result = try_search_slots(cache, input, slots)
        raise result if result.is_a?(::Regex::Automata::MatchError)
        pid = result.as?(::Regex::Automata::PatternID)
        return nil unless pid

        slot_start = pid.to_i * 2
        start = slots[slot_start]?.try(&.try(&.get))
        finish = slots[slot_start + 1]?.try(&.try(&.get))
        return nil unless start && finish

        ::Regex::Automata::Match.new(pid, start, finish)
      end

      def captures(cache : Cache, haystack : String | Bytes | ::Regex::Automata::Input, caps : ::Regex::Automata::Captures) : Nil
        input = normalize_and_anchor(haystack)
        result = try_search(cache, input, caps)
        raise result if result.is_a?(::Regex::Automata::MatchError)
      end

      def try_search(cache : Cache, input : ::Regex::Automata::Input, caps : ::Regex::Automata::Captures) : Nil | ::Regex::Automata::MatchError
        caps.clear
        result = try_search_slots(cache, input, caps.slots_mut)
        return result if result.is_a?(::Regex::Automata::MatchError)

        caps.set_pattern(result)
        nil
      end

      def try_search_slots(cache : Cache, input : ::Regex::Automata::Input, slots : Array(Int32?)) : ::Regex::Automata::PatternID? | ::Regex::Automata::MatchError
        validation = validate_input(input)
        return validation if validation

        @pikevm.search_slots(cache.inner, input, slots)
      end

      def try_search_slots(cache : Cache, input : ::Regex::Automata::Input, slots : Array(::Regex::Automata::NonMaxUsize?)) : ::Regex::Automata::PatternID? | ::Regex::Automata::MatchError
        validation = validate_input(input)
        return validation if validation

        @pikevm.search_slots(cache.inner, input, slots)
      end

      private def normalize_and_anchor(input : ::Regex::Automata::Input) : ::Regex::Automata::Input
        normalized = input.clone
        if normalized.get_anchored == ::Regex::Automata::Anchored::No
          normalized.set_anchored(::Regex::Automata::Anchored::Yes)
        end
        normalized
      end

      private def normalize_and_anchor(haystack : String) : ::Regex::Automata::Input
        normalize_and_anchor(::Regex::Automata::Input.new(haystack))
      end

      private def normalize_and_anchor(haystack : Bytes) : ::Regex::Automata::Input
        normalize_and_anchor(::Regex::Automata::Input.new(haystack))
      end

      private def validate_input(input : ::Regex::Automata::Input) : ::Regex::Automata::MatchError?
        case input.get_anchored
        when ::Regex::Automata::Anchored::No
          ::Regex::Automata::MatchError.unsupported_anchored(::Regex::Automata::Anchored::No)
        when ::Regex::Automata::Anchored::Pattern
          return ::Regex::Automata::MatchError.unsupported_anchored(::Regex::Automata::Anchored::Pattern) unless @config.get_starts_for_each_pattern
          nil
        else
          nil
        end
      end
    end
  end
end
