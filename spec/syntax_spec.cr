require "./spec_helper"

describe Regex::Automata::Syntax::Config do
  it "exposes the vendored default syntax settings" do
    config = Regex::Automata::Syntax::Config.new

    config.get_case_insensitive.should be_false
    config.get_multi_line.should be_false
    config.get_dot_matches_new_line.should be_false
    config.get_crlf.should be_false
    config.get_line_terminator.should eq('\n'.ord.to_u8)
    config.get_swap_greed.should be_false
    config.get_ignore_whitespace.should be_false
    config.get_unicode.should be_true
    config.get_utf8.should be_true
    config.get_nest_limit.should eq(250)
    config.get_octal.should be_false
  end

  it "returns updated configs without mutating the original" do
    base = Regex::Automata::Syntax::Config.new
    updated = base
      .case_insensitive(true)
      .multi_line(true)
      .dot_matches_new_line(true)
      .crlf(true)
      .line_terminator('x'.ord.to_u8)
      .swap_greed(true)
      .ignore_whitespace(true)
      .unicode(false)
      .utf8(false)
      .nest_limit(7)
      .octal(true)

    base.get_case_insensitive.should be_false
    base.get_multi_line.should be_false
    base.get_dot_matches_new_line.should be_false
    base.get_crlf.should be_false
    base.get_line_terminator.should eq('\n'.ord.to_u8)
    base.get_swap_greed.should be_false
    base.get_ignore_whitespace.should be_false
    base.get_unicode.should be_true
    base.get_utf8.should be_true
    base.get_nest_limit.should eq(250)
    base.get_octal.should be_false

    updated.get_case_insensitive.should be_true
    updated.get_multi_line.should be_true
    updated.get_dot_matches_new_line.should be_true
    updated.get_crlf.should be_true
    updated.get_line_terminator.should eq('x'.ord.to_u8)
    updated.get_swap_greed.should be_true
    updated.get_ignore_whitespace.should be_true
    updated.get_unicode.should be_false
    updated.get_utf8.should be_false
    updated.get_nest_limit.should eq(7)
    updated.get_octal.should be_true
  end
end

describe Regex::Automata::Syntax do
  it "parses with default syntax settings" do
    hir = Regex::Automata::Syntax.parse("([a-z]+)|([0-9]+)")

    hir.static_explicit_captures_len.should eq(1)
    hir.minimum_len.should eq(1)
  end

  it "parses with explicit CRLF and multiline settings" do
    hir = Regex::Automata::Syntax.parse_with(
      "^[a-z]+$",
      Regex::Automata::Syntax::Config.new.multi_line(true).crlf(true)
    )

    hir.look_set.contains_anchor_crlf.should be_true
    hir.node.should be_a(Regex::Syntax::Hir::Concat)
  end

  it "parses byte-oriented syntax when unicode and utf8 are disabled" do
    hir = Regex::Automata::Syntax.parse_with(
      "(?-u:[\\xFF])",
      Regex::Automata::Syntax::Config.new.unicode(false).utf8(false)
    )

    hir.node.should be_a(Regex::Syntax::Hir::CharClass)
    hir.node.as(Regex::Syntax::Hir::CharClass).intervals.should eq([0xFF_u8..0xFF_u8])
    hir.properties.utf8?.should be_false
  end

  it "respects swap greed through the syntax wrapper" do
    hir = Regex::Automata::Syntax.parse_with(
      "a*",
      Regex::Automata::Syntax::Config.new.swap_greed(true)
    )

    hir.node.should be_a(Regex::Syntax::Hir::Repetition)
    hir.node.as(Regex::Syntax::Hir::Repetition).greedy?.should be_false
  end
end
