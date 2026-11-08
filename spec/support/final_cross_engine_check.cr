require "../../src/regex-automata"

alias RA = Regex::Automata

def error_result(error : RA::MatchError) : String
  case error.kind
  when .quit?              then "error:quit:#{error.byte.not_nil!.to_s(16).rjust(2, '0')}:#{error.offset}"
  when .gave_up?           then "error:gave-up:#{error.offset}"
  when .haystack_too_long? then "error:long:#{error.len}"
  when .unsupported_anchored?
    mode = case error.mode
           when RA::Anchored::No      then "no"
           when RA::Anchored::Yes     then "yes"
           when RA::Anchored::Pattern then "p#{error.pattern.not_nil!.to_i}"
           else                            raise "missing anchored mode"
           end
    "error:anchor:#{mode}"
  else raise "unhandled match error"
  end
end

def half_result(result : RA::HalfMatch? | RA::MatchError) : String
  case result
  when RA::MatchError then error_result(result)
  when RA::HalfMatch  then "half:#{result.pattern.to_i}:#{result.offset}"
  else                     "none"
  end
end

def capture_result(error : Nil | RA::MatchError, caps : RA::Captures) : String
  return error_result(error) if error
  return "none" unless pid = caps.pattern
  groups = caps.iter.map { |span| span ? "#{span.start}-#{span.end}" : "_" }.to_a.join(',')
  "caps:#{pid.to_i}:#{groups}"
end

STDIN.each_line do |line|
  f = line.chomp.split('\t')
  patterns = f[1].split(',').map { |hex| String.new(hex.hexbytes) }
  hay = f[2].hexbytes
  input = RA::Input.new(hay).span(f[3].to_i...f[4].to_i).earliest(f[6] == "1")
  case f[5]
  when "no"  then input.anchored(RA::Anchored::No)
  when "yes" then input.anchored(RA::Anchored::Yes)
  else            input.anchored_pattern(RA::PatternID.new(f[5][1..].to_i))
  end
  utf8 = f[7] == "1"
  term = f[8].to_u8
  kind = f[9] == "all" ? RA::MatchKind::All : RA::MatchKind::LeftmostFirst
  syntax = RA::Syntax::Config.new.utf8(utf8).line_terminator(term)
  look = RA::LookMatcher.new.set_line_terminator(term)
  thompson = RA::HirCompilerConfig.new.utf8(utf8).look_matcher(look)
  {"dense", "dense-min", "sparse", "sparse-min", "hybrid", "pike", "backtrack", "onepass", "meta"}.each do |engine|
    output = begin
      case engine
      when "dense", "dense-min", "sparse", "sparse-min"
        config = RA::DFA::Config.new.match_kind(kind).unicode_word_boundary(true).starts_for_each_pattern(true).minimize(engine.ends_with?("min"))
        dfa = RA::DFA::Builder.new.configure(config).syntax { |parser| syntax.apply(parser) }.thompson { thompson }.build_many(patterns)
        engine.starts_with?("sparse") ? half_result(dfa.to_sparse.try_search_fwd(input)) : half_result(dfa.try_search_fwd(input))
      when "hybrid"
        config = RA::Hybrid::Config.new.match_kind(kind).unicode_word_boundary(true).starts_for_each_pattern(true)
        dfa = RA::Hybrid::Builder.new.configure(config).syntax(syntax).thompson(thompson).build_many(patterns)
        half_result(dfa.try_search_fwd(dfa.create_cache, input))
      when "pike"
        vm = RA::NFA::PikeVM::Builder.new.configure(RA::NFA::PikeVM::Config.new.match_kind(kind)).syntax(syntax).thompson(thompson).build_many(patterns)
        caps = vm.create_captures
        vm.search(vm.create_cache, input, caps)
        capture_result(nil, caps)
      when "backtrack"
        vm = RA::NFA::Backtrack::Builder.new.syntax(syntax).thompson(thompson).build_many(patterns)
        caps = vm.create_captures
        capture_result(vm.try_search(vm.create_cache, input, caps), caps)
      when "onepass"
        config = RA::DFA::OnePass::Config.new.match_kind(kind).starts_for_each_pattern(true)
        dfa = RA::DFA::OnePass::Builder.new.configure(config).syntax(syntax).thompson(thompson).build_many(patterns)
        caps = dfa.create_captures
        capture_result(dfa.try_search(dfa.create_cache, input, caps), caps)
      when "meta"
        config = RA::Meta::Config.new.match_kind(kind).utf8_empty(utf8).line_terminator(term)
        re = RA::Meta::Builder.new.configure(config).syntax(syntax).build_many(patterns)
        caps = re.create_captures
        re.search_captures(input, caps)
        capture_result(nil, caps)
      else raise "unknown engine"
      end
    rescue error : RA::BuildError
      "build-error"
    end
    puts "#{f[0]}\t#{engine}\t#{output}"
  end
end
