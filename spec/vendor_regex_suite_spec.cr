require "./spec_helper"
require "./support/vendor_regex_suite"

# Pinned Rust contract: vendor/regex/regex-test/lib.rs::{RegexTests::load_slice,
# RegexTest, Captures}. The fixture paths and names are from tests/lib.rs.
describe VendorRegexSuite do
  it "loads exactly the 25 TOML groups selected by regex-automata/tests/lib.rs" do
    suite = VendorRegexSuite.load
    suite.groups.size.should eq(25)
    suite.cases.size.should eq(1194)
    suite.groups.should contain("fowler/basic")
    suite.groups.should contain("word-boundary-special")
    suite.cases.map(&.full_name).uniq.size.should eq(suite.cases.size)
  end

  it "preserves Rust capture groups, absent spans, and pattern IDs" do
    suite = VendorRegexSuite.load
    with_captures = suite.cases.find { |item| item.matches.any? { |mat| mat.spans.size > 1 && mat.spans.any?(&.nil?) } }.not_nil!
    with_captures.matches.any? { |mat| mat.spans.size > 1 && mat.spans.any?(&.nil?) }.should be_true
    with_ids = suite.cases.find { |item| item.matches.any? { |mat| mat.id > 0 } }.not_nil!
    with_ids.expected_pattern_ids.should contain(with_ids.matches.find(&.id.>(0)).not_nil!.id)
  end

  it "keeps byte haystacks, byte bounds, and named multiline literals" do
    suite = VendorRegexSuite.load
    byte_case = suite.cases.find { |item| item.unescape && item.haystack.any? { |byte| byte >= 0x80_u8 } }.not_nil!
    byte_case.haystack.is_a?(Bytes).should be_true
    bounded = suite.cases.find { |item| item.bounds[0] > 0 }.not_nil!
    bounded.bounds[1].should be <= bounded.haystack.size
    suite.cases.find { |item| item.full_name == "fowler/basic/basic3" }.not_nil!.patterns.should eq(["abracadabra$"])
  end

  it "uses the Rust filename-stem group and default field values" do
    suite = VendorRegexSuite.load
    basic = suite.cases.find { |item| item.full_name == "fowler/basic/basic3" }.not_nil!
    basic.group.should eq("fowler/basic")
    basic.compiles.should be_true
    basic.unicode.should be_true
    basic.utf8.should be_true
    basic.line_terminator.should eq('\n'.ord.to_u8)
  end

  it "preserves explicit false options instead of replacing them with Rust defaults" do
    suite = VendorRegexSuite.load
    suite.cases.any? { |item| !item.unicode }.should be_true
    suite.cases.any? { |item| !item.utf8 }.should be_true
    suite.cases.any? { |item| !item.compiles }.should be_true
    suite.cases.find { |item| item.full_name == "no-unicode/invalid-utf8-literal1" }.not_nil!.unicode.should be_false
  end

  it "applies Rust hybrid's exact compilation and cache-capacity exclusions" do
    suite = VendorRegexSuite.load
    ordinary = suite.cases.count { |item| VendorRegexSuite.hybrid_skip_reason(item, "default").nil? }
    shrunk = suite.cases.count { |item| VendorRegexSuite.hybrid_skip_reason(item, "nfa_shrink").nil? }
    ordinary.should eq(1147)
    shrunk.should eq(1148)
    expensive = suite.cases.find { |item| item.full_name == "expensive/regression-many-repeat-no-stack-overflow" }.not_nil!
    VendorRegexSuite.hybrid_skip_reason(expensive, "default").should eq("cache-capacity blacklist")
    VendorRegexSuite.hybrid_skip_reason(expensive, "nfa_shrink").should be_nil
  end

  it "tracks every pinned Rust source file, including files with no API-item row" do
    root = File.join(__DIR__, "..")
    paths = Dir.glob(File.join(root, "vendor/regex/regex-automata/src/**/*.rs"))
      .map { |path| path.sub(File.join(root, "vendor/regex/regex-automata/"), "") }.sort
    rows = File.read(File.join(root, "plans/inventory/rust_file_parity.tsv"))
      .lines.skip(1).map(&.split('\t'))
    rows.map(&.[0]).sort.should eq(paths)
    rows.size.should eq(72)
    rows.count { |row| row[1] == "0" }.should eq(18)
    api_counts = Hash(String, Int32).new(0)
    File.each_line(File.join(root, "plans/inventory/rust_port_inventory.tsv")) do |line|
      next if line.starts_with?("#")
      api_counts[line.split('\t')[0].split("::")[0]] += 1
    end
    rows.each { |row| row[1].to_i.should eq(api_counts[row[0]]) }
    empty = rows.find { |row| row[0] == "src/util/empty.rs" }.not_nil!
    empty[1].should eq("0")
    empty[2].should eq("reviewed")
    empty[3].should contain("spec/utf8_empty_parity_spec.cr")
  end
end
