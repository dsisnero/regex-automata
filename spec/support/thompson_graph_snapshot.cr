module ThompsonGraphSnapshot
  def self.look_bits(kind : Regex::Automata::NFA::Look::Kind) : UInt32
    index = case kind
            when .start_text?                then 0
            when .end_text?                  then 1
            when .start_lf?                  then 2
            when .end_lf?                    then 3
            when .start_crlf?                then 4
            when .end_crlf?                  then 5
            when .word_boundary_ascii?       then 6
            when .non_word_boundary_ascii?   then 7
            when .word_boundary_unicode?     then 8
            when .non_word_boundary_unicode? then 9
            when .word_start_ascii?          then 10
            when .word_end_ascii?            then 11
            when .word_start_unicode?        then 12
            when .word_end_unicode?          then 13
            when .word_start_half_ascii?     then 14
            when .word_end_half_ascii?       then 15
            when .word_start_half_unicode?   then 16
            when .word_end_half_unicode?     then 17
            else                                  raise "Unsupported look kind: #{kind}"
            end
    1_u32 << index
  end

  def self.snapshot(nfa : Regex::Automata::NFA::NFA) : String
    starts = nfa.start_pattern.map(&.to_i).join(',')
    states = nfa.states.map do |state|
      case state
      when Regex::Automata::NFA::ByteRange
        trans = state.trans
        "B,#{trans.start},#{trans.end},#{trans.next.to_i}"
      when Regex::Automata::NFA::Sparse
        "S,#{state.transitions.map { |trans| "#{trans.start}:#{trans.end}:#{trans.next.to_i}" }.join(',')}"
      when Regex::Automata::NFA::Look
        "L,#{look_bits(state.kind)},#{state.next.to_i}"
      when Regex::Automata::NFA::Union
        "U,#{state.alternates.map(&.to_i).join(',')}"
      when Regex::Automata::NFA::BinaryUnion
        "Q,#{state.alt1.to_i},#{state.alt2.to_i}"
      when Regex::Automata::NFA::Capture
        "C,#{state.next.to_i},#{state.pattern_id.to_i},#{state.group_index},#{state.slot}"
      when Regex::Automata::NFA::Match
        "M,#{state.pattern_id.to_i}"
      when Regex::Automata::NFA::Fail
        "F"
      else
        raise "Unexpected final Thompson state: #{state}"
      end
    end.join('|')
    "#{nfa.start_anchored.to_i};#{nfa.start_unanchored.to_i};#{starts};#{nfa.group_info.all_group_len};#{nfa.is_utf8};#{nfa.is_reverse};#{nfa.has_empty}|#{states}"
  end

  def self.build(name : String, configuration : String, patterns_hex : String) : Regex::Automata::NFA::NFA
    opts = configuration.split(',')
    captures = case opts[0]
               when "none"     then Regex::Automata::NFA::WhichCaptures::None
               when "implicit" then Regex::Automata::NFA::WhichCaptures::Implicit
               when "all"      then Regex::Automata::NFA::WhichCaptures::All
               else                 raise "Unknown captures policy"
               end
    compiler = Regex::Automata::NFA::NFA.compiler
      .configure(Regex::Automata::NFA::NFA.config.which_captures(captures)
        .unanchored_prefix(opts[1] == "1").reverse(opts[2] == "1")
        .shrink(opts[3] == "1").utf8(opts[5] == "1"))
      .syntax(Regex::Automata::Syntax::Config.new.utf8(opts[4] == "1"))
    if name.starts_with?("empty_class_")
      node = name == "empty_class_bytes" ? Regex::Syntax::Hir::CharClass.empty : Regex::Syntax::Hir::UnicodeClass.empty
      compiler.build_from_hir(Regex::Syntax::Hir::Hir.new(node))
    else
      compiler.build_many(patterns_hex.split(',').map { |hex| String.new(hex.hexbytes) })
    end
  end
end
