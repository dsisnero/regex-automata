require "json"

# Test-only port of the fixture data contract in the pinned regex-test/lib.rs.
# The selected files and their order come from regex-automata/tests/lib.rs.
module VendorRegexSuite
  GROUPS = %w(
    anchored bytes crazy crlf earliest empty expensive flags iter leftmost-all
    line-terminator misc multiline no-unicode overlapping regression set
    substring unicode utf8 word-boundary word-boundary-special fowler/basic
    fowler/nullsubexpr fowler/repetition
  )

  record ExpectedMatch, id : Int32, spans : Array(Tuple(Int32, Int32)?) do
    def span : Tuple(Int32, Int32)
      spans[0].not_nil!
    end
  end

  record Case,
    group : String,
    name : String,
    patterns : Array(String),
    haystack : Bytes,
    bounds : Tuple(Int32, Int32),
    matches : Array(ExpectedMatch),
    match_limit : Int32?,
    compiles : Bool,
    anchored : Bool,
    case_insensitive : Bool,
    unescape : Bool,
    unicode : Bool,
    utf8 : Bool,
    line_terminator : UInt8,
    match_kind : String,
    search_kind : String do
    def full_name : String
      "#{group}/#{name}"
    end

    def expected_pattern_ids : Array(Int32)
      matches.map(&.id).uniq.sort
    end
  end

  class Suite
    getter groups : Array(String)
    getter cases : Array(Case)

    def initialize(@groups : Array(String), @cases : Array(Case))
    end

    def cases(group : String) : Array(Case)
      @cases.select { |item| item.group == group }
    end
  end

  @@loaded_suite : Suite? = nil

  def self.load : Suite
    @@loaded_suite ||= load_uncached
  end

  private def self.load_uncached : Suite
    cases = [] of Case
    seen = Set(String).new
    GROUPS.each do |group|
      path = File.join(__DIR__, "..", "..", "vendor", "regex", "testdata", "#{group}.toml")
      TomlReader.new(File.read(path)).tables.each_with_index do |fields, index|
        test = decode(group, fields, index + 1)
        raise "duplicate vendor case #{test.full_name}" unless seen.add?(test.full_name)
        cases << test
      end
    end
    Suite.new(GROUPS.to_a, cases)
  end

  # Mirrors regex-automata/tests/hybrid/suite.rs::compiler and each mode's
  # explicit expensive-case blacklist. Compile-error fixtures stay selected.
  def self.hybrid_skip_reason(test : Case, mode : String) : String?
    if test.full_name == "expensive/regression-many-repeat-no-stack-overflow" &&
       mode != "nfa_shrink" && mode != "min_cache_capacity"
      return "cache-capacity blacklist"
    end
    return nil unless test.compiles
    return nil unless test.haystack.any? { |byte| byte >= 0x80_u8 }

    syntax = Regex::Automata::Syntax::Config.new
      .case_insensitive(test.case_insensitive)
      .unicode(test.unicode)
      .utf8(test.utf8)
      .line_terminator(test.line_terminator)
    test.patterns.each do |pattern|
      hir = Regex::Automata::Syntax.parse_with(pattern, syntax)
      return "Unicode word look on non-ASCII haystack" if hir.properties.look_set.contains_word_unicode
    end
    nil
  end

  private def self.decode(group : String, fields : Hash(String, JSON::Any), index : Int32) : Case
    name = fields["name"]?.try(&.as_s) || index.to_s
    pattern = fields["regex"]
    patterns = pattern.as_s? ? [pattern.as_s] : pattern.as_a.map(&.as_s)
    raw_haystack = fields["haystack"].as_s
    unescape = bool(fields, "unescape", false)
    haystack = unescape ? unescape_bytes(raw_haystack) : raw_haystack.to_slice.dup
    bounds = if value = fields["bounds"]?
               if pair = value.as_a?
                 {pair[0].as_i, pair[1].as_i}
               else
                 table = value.as_h
                 {table["start"].as_i, table["end"].as_i}
               end
             else
               {0, haystack.size}
             end
    raise "invalid bounds for #{group}/#{name}" unless 0 <= bounds[0] <= bounds[1] <= haystack.size
    matches = fields["matches"].as_a.map { |value| decode_match(value) }
    term = fields["line-terminator"]?.try(&.as_s) || "\n"
    term_bytes = unescape_bytes(term)
    raise "invalid line terminator for #{group}/#{name}" unless term_bytes.size == 1
    Case.new(group, name, patterns, haystack, bounds, matches,
      fields["match-limit"]?.try(&.as_i), bool(fields, "compiles", true),
      bool(fields, "anchored", false), bool(fields, "case-insensitive", false),
      unescape, bool(fields, "unicode", true), bool(fields, "utf8", true),
      term_bytes[0], fields["match-kind"]?.try(&.as_s) || "leftmost-first",
      fields["search-kind"]?.try(&.as_s) || "leftmost")
  end

  private def self.bool(fields : Hash(String, JSON::Any), key : String, default : Bool) : Bool
    value = fields[key]?
    value ? value.as_bool : default
  end

  private def self.decode_match(value : JSON::Any) : ExpectedMatch
    if table = value.as_h?
      id = table["id"].as_i
      spans = if span = table["span"]?
                [decode_span(span)] of Tuple(Int32, Int32)?
              else
                table["spans"].as_a.map { |item| decode_span(item) }
              end
      return make_match(id, spans)
    end
    items = value.as_a
    spans = if items.size == 2 && items.all? { |item| item.as_i64? }
              [decode_span(value)] of Tuple(Int32, Int32)?
            else
              items.map { |item| decode_span(item) }
            end
    make_match(0, spans)
  end

  private def self.decode_span(value : JSON::Any) : Tuple(Int32, Int32)?
    pair = value.as_a
    return nil if pair.empty?
    raise "invalid vendor span" unless pair.size == 2
    {pair[0].as_i, pair[1].as_i}
  end

  private def self.make_match(id : Int32, spans : Array(Tuple(Int32, Int32)?)) : ExpectedMatch
    raise "invalid vendor captures" if spans.empty? || spans[0].nil?
    ExpectedMatch.new(id, spans)
  end

  # Mirrors bstr's unescape_bytes use in regex-test: the fixture's UTF-8
  # source is converted to raw bytes only when `unescape = true` (and always
  # for the one-byte line terminator).
  private def self.unescape_bytes(value : String) : Bytes
    source = value.to_slice
    output = [] of UInt8
    at = 0
    while at < source.size
      if source[at] == '\\'.ord && at + 1 < source.size
        next_byte = source[at + 1]
        if next_byte == 'x'.ord && at + 3 < source.size
          output << String.new(source[at + 2, 2]).to_u8(16)
          at += 4
          next
        end
        escaped = case next_byte
                  when 'n'.ord  then '\n'.ord.to_u8
                  when 'r'.ord  then '\r'.ord.to_u8
                  when 't'.ord  then '\t'.ord.to_u8
                  when '\\'.ord then '\\'.ord.to_u8
                  else               nil
                  end
        if escaped
          output << escaped
          at += 2
          next
        end
      end
      output << source[at]
      at += 1
    end
    Bytes.new(output.size) { |i| output[i] }
  end

  # Only the TOML forms used by the pinned regex-test schema are accepted.
  # Unlike a line splitter, the cursor retains nested arrays, inline tables,
  # quoted delimiters, comments, and multi-line string values.
  private class TomlReader
    @at = 0

    def initialize(@source : String)
    end

    def tables : Array(Hash(String, JSON::Any))
      result = [] of Hash(String, JSON::Any)
      current = nil.as(Hash(String, JSON::Any)?)
      until done?
        skip_space_and_comments
        break if done?
        if prefix?("[[test]]")
          @at += 8
          current = Hash(String, JSON::Any).new
          result << current
          next
        end
        raise "TOML field before [[test]]" unless current
        key = read_key
        skip_space_and_comments
        expect('=')
        skip_space_and_comments
        raise "duplicate TOML field #{key}" if current.has_key?(key)
        current[key] = read_value
      end
      result
    end

    private def read_key : String
      start = @at
      while !done? && (alphanumeric?(peek) || peek == '-'.ord)
        @at += 1
      end
      raise "invalid TOML key" if start == @at
      @source.byte_slice(start, @at - start)
    end

    private def read_value : JSON::Any
      case peek
      when '"'.ord, '\''.ord
        JSON::Any.new(read_string)
      when '['.ord
        expect('[')
        values = [] of JSON::Any
        loop do
          skip_space_and_comments
          break if consume(']')
          values << read_value
          skip_space_and_comments
          break if consume(']')
          expect(',')
        end
        JSON::Any.new(values)
      when '{'.ord
        expect('{')
        values = Hash(String, JSON::Any).new
        loop do
          skip_space_and_comments
          break if consume('}')
          key = read_key
          skip_space_and_comments
          expect('=')
          skip_space_and_comments
          values[key] = read_value
          skip_space_and_comments
          break if consume('}')
          expect(',')
        end
        JSON::Any.new(values)
      else
        start = @at
        while !done? && !space?(peek) && peek != ','.ord && peek != ']'.ord && peek != '}'.ord && peek != '#'.ord
          @at += 1
        end
        token = @source.byte_slice(start, @at - start)
        case token
        when "true"  then JSON::Any.new(true)
        when "false" then JSON::Any.new(false)
        else              JSON::Any.new(token.to_i64)
        end
      end
    end

    private def read_string : String
      quote = peek
      multiline = @source.byte_slice(@at, 3) == String.build { |io| 3.times { io.write_byte(quote) } }
      @at += multiline ? 3 : 1
      @at += 1 if multiline && peek == '\n'.ord
      output = IO::Memory.new
      until done?
        if multiline && peek == quote && @source.byte_slice(@at, 3) == String.build { |io| 3.times { io.write_byte(quote) } }
          @at += 3
          return output.to_s
        elsif !multiline && peek == quote
          @at += 1
          return output.to_s
        end
        byte = peek
        @at += 1
        if quote == '"'.ord && byte == '\\'.ord
          write_escape(output, multiline)
        else
          output.write_byte(byte)
        end
      end
      raise "unterminated TOML string"
    end

    private def write_escape(output : IO::Memory, multiline : Bool) : Nil
      raise "unterminated TOML escape" if done?
      escaped = peek
      @at += 1
      case escaped
      when '"'.ord  then output.write_byte('"'.ord.to_u8)
      when '\\'.ord then output.write_byte('\\'.ord.to_u8)
      when 'n'.ord  then output.write_byte('\n'.ord.to_u8)
      when 'r'.ord  then output.write_byte('\r'.ord.to_u8)
      when 't'.ord  then output.write_byte('\t'.ord.to_u8)
      when 'b'.ord  then output.write_byte(8_u8)
      when 'f'.ord  then output.write_byte(12_u8)
      when 'u'.ord, 'U'.ord
        digits = escaped == 'u'.ord ? 4 : 8
        codepoint = @source.byte_slice(@at, digits).to_u32(16)
        output << codepoint.chr
        @at += digits
      when '\n'.ord
        raise "newline escape outside multiline string" unless multiline
        skip_space_and_comments
      else
        raise "unsupported TOML escape #{escaped.chr}"
      end
    end

    private def skip_space_and_comments : Nil
      until done?
        if space?(peek)
          @at += 1
        elsif peek == '#'.ord
          until done? || peek == '\n'.ord
            @at += 1
          end
        else
          break
        end
      end
    end

    private def expect(char : Char) : Nil
      raise "expected #{char} at byte #{@at}" unless consume(char)
    end

    private def consume(char : Char) : Bool
      return false if done? || peek != char.ord
      @at += 1
      true
    end

    private def prefix?(value : String) : Bool
      @source.byte_slice(@at, value.bytesize) == value
    end

    private def peek : UInt8
      @source.byte_at(@at)
    end

    private def done? : Bool
      @at >= @source.bytesize
    end

    private def space?(byte : UInt8) : Bool
      byte == ' '.ord || byte == '\t'.ord || byte == '\n'.ord || byte == '\r'.ord
    end

    private def alphanumeric?(byte : UInt8) : Bool
      ('a'.ord <= byte <= 'z'.ord) || ('A'.ord <= byte <= 'Z'.ord) || ('0'.ord <= byte <= '9'.ord)
    end
  end
end
