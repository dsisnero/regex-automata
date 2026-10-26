require "./spec_helper"

describe "Rust util::unicode_data::perl_word" do
  it "reuses the pinned Unicode 16.0 Perl-word range table from regex-syntax" do
    ranges = Regex::Syntax::UnicodeTables::PerlWord::PERL_WORD
    ranges.size.should eq(796)
    ranges.first.should eq(0x30_u32..0x39_u32)
    ranges.last.should eq(0xE0100_u32..0xE01EF_u32)

    Regex::Syntax.try_is_word_character(0x30.chr).should be_true
    Regex::Syntax.try_is_word_character(0x3A.chr).should be_false
    Regex::Syntax.try_is_word_character(0xE0100.chr).should be_true
    Regex::Syntax.try_is_word_character(0xE01F0.chr).should be_false
  end
end
