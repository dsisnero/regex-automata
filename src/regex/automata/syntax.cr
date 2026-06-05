require "regex-syntax"

module Regex::Automata
  module Syntax
    class Config
      getter case_insensitive : Bool
      getter multi_line : Bool
      getter dot_matches_new_line : Bool
      getter crlf : Bool
      getter line_terminator : UInt8
      getter swap_greed : Bool
      getter ignore_whitespace : Bool
      getter unicode : Bool
      getter utf8 : Bool
      getter nest_limit : Int32
      getter octal : Bool

      def initialize(
        @case_insensitive : Bool = false,
        @multi_line : Bool = false,
        @dot_matches_new_line : Bool = false,
        @crlf : Bool = false,
        @line_terminator : UInt8 = '\n'.ord.to_u8,
        @swap_greed : Bool = false,
        @ignore_whitespace : Bool = false,
        @unicode : Bool = true,
        @utf8 : Bool = true,
        @nest_limit : Int32 = 250,
        @octal : Bool = false,
      )
      end

      def case_insensitive(yes : Bool) : Config
        Config.new(
          case_insensitive: yes,
          multi_line: @multi_line,
          dot_matches_new_line: @dot_matches_new_line,
          crlf: @crlf,
          line_terminator: @line_terminator,
          swap_greed: @swap_greed,
          ignore_whitespace: @ignore_whitespace,
          unicode: @unicode,
          utf8: @utf8,
          nest_limit: @nest_limit,
          octal: @octal
        )
      end

      def multi_line(yes : Bool) : Config
        Config.new(
          case_insensitive: @case_insensitive,
          multi_line: yes,
          dot_matches_new_line: @dot_matches_new_line,
          crlf: @crlf,
          line_terminator: @line_terminator,
          swap_greed: @swap_greed,
          ignore_whitespace: @ignore_whitespace,
          unicode: @unicode,
          utf8: @utf8,
          nest_limit: @nest_limit,
          octal: @octal
        )
      end

      def dot_matches_new_line(yes : Bool) : Config
        Config.new(
          case_insensitive: @case_insensitive,
          multi_line: @multi_line,
          dot_matches_new_line: yes,
          crlf: @crlf,
          line_terminator: @line_terminator,
          swap_greed: @swap_greed,
          ignore_whitespace: @ignore_whitespace,
          unicode: @unicode,
          utf8: @utf8,
          nest_limit: @nest_limit,
          octal: @octal
        )
      end

      def crlf(yes : Bool) : Config
        Config.new(
          case_insensitive: @case_insensitive,
          multi_line: @multi_line,
          dot_matches_new_line: @dot_matches_new_line,
          crlf: yes,
          line_terminator: @line_terminator,
          swap_greed: @swap_greed,
          ignore_whitespace: @ignore_whitespace,
          unicode: @unicode,
          utf8: @utf8,
          nest_limit: @nest_limit,
          octal: @octal
        )
      end

      def line_terminator(byte : UInt8) : Config
        Config.new(
          case_insensitive: @case_insensitive,
          multi_line: @multi_line,
          dot_matches_new_line: @dot_matches_new_line,
          crlf: @crlf,
          line_terminator: byte,
          swap_greed: @swap_greed,
          ignore_whitespace: @ignore_whitespace,
          unicode: @unicode,
          utf8: @utf8,
          nest_limit: @nest_limit,
          octal: @octal
        )
      end

      def swap_greed(yes : Bool) : Config
        Config.new(
          case_insensitive: @case_insensitive,
          multi_line: @multi_line,
          dot_matches_new_line: @dot_matches_new_line,
          crlf: @crlf,
          line_terminator: @line_terminator,
          swap_greed: yes,
          ignore_whitespace: @ignore_whitespace,
          unicode: @unicode,
          utf8: @utf8,
          nest_limit: @nest_limit,
          octal: @octal
        )
      end

      def ignore_whitespace(yes : Bool) : Config
        Config.new(
          case_insensitive: @case_insensitive,
          multi_line: @multi_line,
          dot_matches_new_line: @dot_matches_new_line,
          crlf: @crlf,
          line_terminator: @line_terminator,
          swap_greed: @swap_greed,
          ignore_whitespace: yes,
          unicode: @unicode,
          utf8: @utf8,
          nest_limit: @nest_limit,
          octal: @octal
        )
      end

      def unicode(yes : Bool) : Config
        Config.new(
          case_insensitive: @case_insensitive,
          multi_line: @multi_line,
          dot_matches_new_line: @dot_matches_new_line,
          crlf: @crlf,
          line_terminator: @line_terminator,
          swap_greed: @swap_greed,
          ignore_whitespace: @ignore_whitespace,
          unicode: yes,
          utf8: @utf8,
          nest_limit: @nest_limit,
          octal: @octal
        )
      end

      def utf8(yes : Bool) : Config
        Config.new(
          case_insensitive: @case_insensitive,
          multi_line: @multi_line,
          dot_matches_new_line: @dot_matches_new_line,
          crlf: @crlf,
          line_terminator: @line_terminator,
          swap_greed: @swap_greed,
          ignore_whitespace: @ignore_whitespace,
          unicode: @unicode,
          utf8: yes,
          nest_limit: @nest_limit,
          octal: @octal
        )
      end

      def nest_limit(limit : Int32) : Config
        Config.new(
          case_insensitive: @case_insensitive,
          multi_line: @multi_line,
          dot_matches_new_line: @dot_matches_new_line,
          crlf: @crlf,
          line_terminator: @line_terminator,
          swap_greed: @swap_greed,
          ignore_whitespace: @ignore_whitespace,
          unicode: @unicode,
          utf8: @utf8,
          nest_limit: limit,
          octal: @octal
        )
      end

      def octal(yes : Bool) : Config
        Config.new(
          case_insensitive: @case_insensitive,
          multi_line: @multi_line,
          dot_matches_new_line: @dot_matches_new_line,
          crlf: @crlf,
          line_terminator: @line_terminator,
          swap_greed: @swap_greed,
          ignore_whitespace: @ignore_whitespace,
          unicode: @unicode,
          utf8: @utf8,
          nest_limit: @nest_limit,
          octal: yes
        )
      end

      def get_case_insensitive : Bool
        @case_insensitive
      end

      def get_multi_line : Bool
        @multi_line
      end

      def get_dot_matches_new_line : Bool
        @dot_matches_new_line
      end

      def get_crlf : Bool
        @crlf
      end

      def get_line_terminator : UInt8
        @line_terminator
      end

      def get_swap_greed : Bool
        @swap_greed
      end

      def get_ignore_whitespace : Bool
        @ignore_whitespace
      end

      def get_unicode : Bool
        @unicode
      end

      def get_utf8 : Bool
        @utf8
      end

      def get_nest_limit : Int32
        @nest_limit
      end

      def get_octal : Bool
        @octal
      end

      def apply(builder : ::Regex::Syntax::ParserBuilder) : ::Regex::Syntax::ParserBuilder
        builder
          .case_insensitive(@case_insensitive)
          .multi_line(@multi_line)
          .dot_matches_new_line(@dot_matches_new_line)
          .crlf(@crlf)
          .line_terminator(@line_terminator)
          .swap_greed(@swap_greed)
          .ignore_whitespace(@ignore_whitespace)
          .unicode(@unicode)
          .utf8(@utf8)
          .nest_limit(@nest_limit)
          .octal(@octal)
      end
    end

    def self.parse(pattern : String) : ::Regex::Syntax::Hir::Hir
      parse_with(pattern, Config.new)
    end

    def self.parse_with(pattern : String, config : Config) : ::Regex::Syntax::Hir::Hir
      builder = ::Regex::Syntax::ParserBuilder.new
      config.apply(builder)
      builder.build.parse(pattern)
    end
  end
end
