# frozen_string_literal: true

require "bashcov/line"

module Bashcov
  # Simple lexer which analyzes Bash files in order to get information for
  # coverage
  class Lexer
    # Lines starting with one of these tokens are irrelevant for coverage
    IGNORE_START_WITH = %w(# function).freeze

    # Lines ending with one of these tokens are irrelevant for coverage
    IGNORE_END_WITH = %w|(|.freeze

    # Lines containing only one of these keywords are irrelevant for coverage
    IGNORE_IS = %w(esac if then else elif fi while do done { } ;;).freeze

    # @param [String] filename File to analyze
    # @param [Hash] coverage Coverage with executed lines marked
    # @raise [ArgumentError] if the given +filename+ is invalid.
    def initialize(filename, coverage)
      @filename = filename
      @coverage = coverage

      unless File.file?(@filename) # rubocop:disable Style/GuardClause
        raise ArgumentError, "#{@filename} is not a file"
      end
    end

    # Process and complete initial coverage.
    # @return [void]
    def complete_coverage
      lines = File.read(@filename).lines

      lines.each_with_index do |line, lineno|
        mark_multiline(lines, lineno, /\A[^\n]+<<-?'?(\w+)'?\s*$.*\1/m) # heredoc
        mark_multiline(lines, lineno, /\A[^\n]+\\$(\s*['"][^'"]*['"]\s*\\$){1,}\s*['"][^'"]*['"]\s*$/) # multiline string concatenated with backslashes
        mark_multiline(lines, lineno, /\A[^\n]+\s+(['"])[^'"]*\1/m, forward: false) # multiline string concatenated with newlines

        mark_line(line, lineno)
      end
    end

  private

    def mark_multiline(lines, lineno, regexp, forward: true)
      seek_forward = lines[lineno..-1].join
      return unless (multiline_match = seek_forward.match(regexp))

      length = multiline_match.to_s.count($/)
      first, last = lineno + 1, lineno + length
      range = (forward ? first.upto(last) : (last - 1).downto(first - 1))
      reference_lineno = (forward ? first - 1 : last)

      range.each do |sub_lineno|
        # mark related lines with the same coverage as the reference line
        @coverage[sub_lineno] = @coverage[reference_lineno]
      end
    end

    def mark_line(line, lineno)
      return unless @coverage[lineno] == Bashcov::Line::IGNORED

      @coverage[lineno] = Bashcov::Line::UNCOVERED if relevant?(line)
    end

    def relevant?(line)
      line.sub!(/ #.*\Z/, "") # remove comments
      line.strip!

      relevant = true

      relevant &= false if line.empty? ||
                           IGNORE_IS.include?(line) ||
                           line.start_with?(*IGNORE_START_WITH) ||
                           line.end_with?(*IGNORE_END_WITH)

      relevant &= false if line =~ /\A\w+\(\)/ # function declared without the `function` keyword
      relevant &= false if line =~ /\A[^\)]+\)\Z/ # case statement selector, e.g. `--help)`

      relevant
    end
  end
end
