#!/usr/bin/env ruby

# Read abstract methods from automaton.cr
abstract_methods = []
File.readlines('src/regex/automata/automaton.cr').each do |line|
  if line =~ /abstract def (\w+[?]?)\(/
    method_name = Regexp.last_match(1)
    abstract_methods << method_name
  end
end

puts "Abstract methods (#{abstract_methods.size}):"
abstract_methods.each { |m| puts "  - #{m}" }

# Read DFA methods from dfa.cr
dfa_methods = []
File.readlines('src/regex/automata/dfa.cr').each do |line|
  if line =~ /^\s*def (\w+[?]?)\(/
    method_name = Regexp.last_match(1)
    dfa_methods << method_name unless method_name == 'initialize'
  end
end

puts "\nDFA methods (#{dfa_methods.size}):"
# dfa_methods.each { |m| puts "  - #{m}" }

# Check which abstract methods are implemented
missing = []
abstract_methods.each do |abstract_method|
  missing << abstract_method unless dfa_methods.include?(abstract_method)
end

puts "\nMissing methods (#{missing.size}):"
missing.each { |m| puts "  - #{m}" }

if missing.empty?
  puts "\nAll abstract methods are implemented!"
else
  puts "\nSome abstract methods are not implemented."
end
