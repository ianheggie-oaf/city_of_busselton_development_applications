require "scraperwiki"
require "tempfile"
require "tmpdir"

# PDF Document
# Based on https://github.com/planningalerts-scrapers/ruby_pdf_helper
class PdfDocument
  # Nokogiri document
  attr_reader :doc

  # Accepts binary contents of a pdf
  def initialize(data)
    # Write data to a temporary file (with a pdf extension)
    src = Tempfile.new(%w[pdftohtml_src. .pdf])
    dst = Tempfile.new(%w[pdftohtml_dst. .xml])

    src.binmode
    dst.binmode

    src.write(data.b)
    src.close

    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        # Run in a temp dir so the extracted images are discarded
        # Usage: pdftohtml [options] <PDF-file> [<html-file> <xml-file>]
        #   -s                    : generate single document that includes all pages
        #   -i                    : ignore images
        #   -noframes             : generate no frames
        #   -xml                  : output for XML post-processing
        #   -noroundcoord         : do not round coordinates (with XML output only) ??
        #   -nomerge              : do not merge paragraphs ??
        #   -enc <string>         : output text encoding name
        command = "/usr/bin/pdftohtml -s -i -noframes -xml -nomerge -enc UTF-8 #{src.path} #{dst.path}"
        puts "Running pdftohtml to convert pdf to xml pages..."
        # Outputs page numbers read ...
        system(command)
      end
    end

    xml_content = dst.read
    # Cleanup
    src.unlink
    dst.unlink

    raise "pdftohtml produced no output" if xml_content.empty?

    puts "Parsing XML document ..."
    @doc = Nokogiri::XML(xml_content)
  end

  # Returns pages
  def pages
    @doc.search("page")
  end
end
