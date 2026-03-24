require "scraperwiki"
require "tempfile"
require "tmpdir"

# PDF Page
# Based on https://github.com/planningalerts-scrapers/ruby_pdf_helper
class PdfPage
  DATA_TOP_RANGE = 130..785
  FIRST_CELL_LEFT_RANGE = 32..92
  KNOWN_GROUP_NAMES = ["Development Applications", "Building Applications"].freeze
  KNOWN_TABLE_HEADINGS = [
    "Application Number",
    "Description",
    "Primary Property Address",
    "Date Application Received",
    "Date Deemed Complete",
  ].freeze

  # Nokogiri document
  attr_reader :page, :table_headings, :page_header

  # Accepts binary contents of a pdf and the table headings from the previous page
  # not all pages have table headings, so passing in the previous heading is required
  def initialize(page, previous_table_headings)
    @page = page
    @table_headings = previous_table_headings
    @lodged_upto_date = nil
    rewind
  end

  def rewind
    @enum = @page.search("text").to_enum
  end

  def lodged_upto_date
    skip_page_heading_and_footer
    @lodged_upto_date
  end

  # Parses table rows, yielding each decoded row if a block is given
  # @return [Array<Hash>] Array of decoded rows
  def table_data
    skip_page_heading_and_footer
    result = []
    loop do
      skip_any_group_heading
      skip_any_blank_entries
      row_a = collect_row_a
      break if row_a.nil? || row_a.empty?

      if row_a.first[:bold]
        process_table_headings(row_a)
      else
        this_row = process_data_row(row_a)
        if this_row.empty?
          puts "WARNING: Unprocessable row skipped!"
          next
        end

        result << this_row
        yield this_row if block_given?
      end
    end
    result
  end

  private

  # Skips page heading
  # Sets `@page_header` and `@lodged_upto_date`
  # @return [Boolean] true if table heading found (bold text), otherwise false
  def skip_page_heading_and_footer
    loop do
      entry = @enum.peek
      top = entry["top"].to_i
      return true if DATA_TOP_RANGE.include?(top)

      if entry.text =~ %r{Applications Lodged\s.*\s([0-3]?\d)/([0-1]?\d)/(\d{4})}
        @lodged_upto_date = Date.new(::Regexp.last_match(3).to_i, ::Regexp.last_match(2).to_i,
                                     ::Regexp.last_match(1).to_i)
        @page_header = entry.text.strip
        puts "Page header: #{@page_header}"
      end
      @enum.next
    end
  rescue StopIteration
    false
  end

  # Processes group and/or table headings
  def skip_any_group_heading
    text_node = @enum.peek
    return unless bold?(text_node)

    text = text_node.text.strip
    return unless KNOWN_GROUP_NAMES.any? { |name| text.start_with?(name) }

    # Report but otherwise ignore
    puts "Group: #{text}"
    @enum.next
  end

  def skip_any_blank_entries
    text_node = @enum.peek
    while text_node.text.strip == ""
      @enum.next
      text_node = @enum.peek
    end
  end

  # Processes group and/or table headings
  def process_table_headings(row_a)
    text = row_a.first[:text]
    if KNOWN_GROUP_NAMES.any? { |name| text.start_with?(name) }
      # Report but otherwise ignore
      puts "Group: #{text}"
      row_a.unshift
    end
    return if row_a.empty?

    previous_table_headings = @table_headings
    @table_headings = []
    row_a.each do |entry|
      merge_heading(entry)
    end
    if previous_table_headings != table_headings && ENV["DEBUG"]
      puts "Found table headings at these #{previous_table_headings ? 'changed ' : ''}positions:"
      table_headings.each do |heading|
        puts format("  %4d  %s", heading[:left], heading[:text])
      end
    end
  rescue StopIteration
    false
  end

  # Merges a heading node into `@table_headings`, appending text when the existing last entry has the same left value
  def merge_heading(entry)
    last = @table_headings.last
    if last && last[:left] == entry[:left]
      existing = last[:text]
      text = entry[:text]
      compacted = "#{existing}#{text}".strip
      last[:text] =
        if KNOWN_TABLE_HEADINGS.any? { |heading| heading.start_with?(compacted) }
          compacted
        else
          "#{existing} #{text}".strip
        end
    else
      @table_headings << entry
    end
  end

  # Converts nokogiri node to a hash with left, width, and text keys
  # @param text_node [Nokogiri::XML::Element] - the text node to convert
  # @return [{left: Integer, width: Integer, text: String. bold: Boolean}
  def text_to_h(text_node)
    {
      left: text_node["left"].to_i,
      width: text_node["width"].to_i,
      text: text_node.text.to_s.strip,
      bold: bold?(text_node),
      # ignore: top, height, font
    }
  end

  def bold?(text_node)
    !text_node.at("b").nil?
  end

  # Collects an array of text_h entries for a row till left reduces
  # text split across multiple lines have multiple entries, one per top value
  # @return [Array<Hash>,nil] array of text_h entries for a row, or nil if no entries
  def collect_row_a
    current_left = nil
    result = []
    loop do
      entry = begin
        @enum.peek
      rescue StopIteration
        break
      end
      text_h = text_to_h(entry)
      current_left ||= text_h[:left]
      break if text_h[:left] < current_left ||
               (result.first && result.first[:bold] != text_h[:bold])

      current_left = text_h[:left]
      result << text_h
      @enum.next
    end
    result.empty? ? nil : result
  end

  # Returns a hash of column heading to merged text_h entry
  # @return[Hash<Hash>] hash of column heading to merged text_h entry
  def process_data_row(row_a)
    raise "INTERNAL ERROR: row_a is not an array! #{row_a.inspect}" unless row_a.is_a? Array

    result = {}
    row_a.each do |text_h|
      heading = find_heading(table_headings, text_h)
      if result[heading]
        result[heading][:text] = "#{result[heading][:text]} #{text_h[:text]}"
        result[heading][:width] = [result[heading][:width], text_h[:width]].max
      else
        result[heading] = text_h
      end
    end
    result
  end

  # Returns heading name
  # @param table_headings [Array<Hash>] list of heading text_h entries
  # @param text_h [Hash] text node as a hash
  # @return [String,nil] Heading of nil if before the first heading
  def find_heading(table_headings, text_h)
    raise "INTERNAL ERROR: text_h[:width] is not Numeric! #{text_h.inspect}" unless text_h[:width].is_a? Numeric

    middle = text_h[:left] + [text_h[:width] / 2, 10].min
    heading = table_headings.select { |heading| heading[:left] <= middle }.last
    heading[:text] if heading
  end
end
