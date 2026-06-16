#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "date"
require "open-uri"
require "yaml"

require "nokogiri"
require "scraperwiki"

require_relative "lib/constants"
require_relative "lib/applications_lodged_page"
require_relative "lib/pdf_document"
require_relative "lib/pdf_page"

class Scraper
  INFO_URL = "https://www.busselton.wa.gov.au/plan-and-build/planning-and-building-resources/applications-issued-determined-lodged"

  def run
    count = process_site
    puts "Finished! Processed #{count} records."
  end

  def process_site
    date_scraped = Date.today.iso8601
    count = 0
    urls = ApplicationsLodgedPage.applications_lodged_pdfs
    earliest_date_of_interest = Date.today - 30

    urls.each do |url|
      previous_table_headings = nil
      puts "Retrieving #{url} ..."
      pdf_content = URI.open(url).read
      puts "Parsing as a PdfDocument ..." if ENV["DEBUG"]
      pdf_doc = PdfDocument.new(pdf_content)
      page_no = 0
      previous_record = nil
      pdf_doc.pages.each do |page_entry|
        page_no += 1
        puts "Processing page# #{page_no}"
        pdf_page = PdfPage.new(page_entry, previous_table_headings)
        if pdf_page.lodged_upto_date < earliest_date_of_interest
          if ENV["DEBUG"]
            puts "NOTE: Ignoring rest of document since #{pdf_page.lodged_upto_date} in page heading is <= 30 days ago (#{earliest_date_of_interest})"
          end
          return count
        end
        pdf_page.table_data do |data|
          puts "ROW: #{data.to_yaml}" if ENV["DEBUG"]

          council_reference = data["Application Number"]&.fetch(:text)
          description = data["Description"]&.fetch(:text)
          address = data["Primary Property Address"]&.fetch(:text)
          raw_date = data["Date Application Received"].to_s.strip
          if council_reference&.match(/\A(\S+)\s+(\S.*)\z/)
            council_reference = ::Regexp.last_match(1)
            description = "#{::Regexp.last_match(2)&.strip} #{description}".strip
          end
          if address&.match(/\A(.*) (#{Constants::DATE_PATTERN}.*)\z/)
            address = ::Regexp.last_match(1)
            raw_date = "#{::Regexp.last_match(2)} #{raw_date}".strip
          end
          date_received =
            if raw_date != ""
              begin
                first_date = raw_date.scan(Constants::DATE_PATTERN).first.to_s
                Date.strptime(first_date, "%d/%m/%Y").iso8601
              rescue StandardError => e
                puts "Warning: unparseable date_received: #{raw_date.inspect} — #{e}"
              end
            end

          record = {
            "council_reference" => council_reference,
            "description" => description,
            "address" => address,
            "date_scraped" => date_scraped,
            "date_received" => date_received,
            "info_url" => INFO_URL,
          }
          if record["council_reference"].to_s == ""
            raise "No previous record to append to!" unless previous_record

            puts "Appending continuation to previous_record..."
            record.each do |key, value|
              if key.start_with?("date_") || key == "info_url" || previous_record[key] == value
                previous_record[key] = value if value.to_s != ""
              else
                previous_record[key] = "#{previous_record[key]} #{value}".strip
              end
            end
          else
            save(previous_record) if previous_record && !record.empty?
            count += 1
            previous_record = record
          end
        end
        previous_table_headings = pdf_page.table_headings
        puts "Finished processing page #{page_no}" if ENV["DEBUG"]
      end
      save(previous_record) if previous_record
    end
    count
  end

  # Fixes record, appending WA and moving Lot numbers to description to make address correctly geocoded in Google Maps
  def fix_record(record)
    address = record["address"].to_s
    description = record["description"].to_s
    address = "#{address} WA" if address != "" && !address.match?(/\bWA(\s+\d{4})?\z/)
    # This makes the location much more accurate on long roads
    if address =~ /\A(Lot \d+) No (\d+\s.*)\z/
      address = ::Regexp.last_match(2)
      description = "#{::Regexp.last_match(1)}: #{description}".strip
    end
    record["address"] = address
    record["description"] = description
  end

  def save(record)
    fix_record(record)
    puts "Saving #{record['council_reference']} - #{record['address']}"
    ScraperWiki.save_sqlite(["council_reference"], record)
    puts "SAVED RECORD: #{record.to_yaml}" if ENV["DEBUG"]
  end
end

# Run the scraper whilst allowing this file to be required in tests without auto-execution
Scraper.new.run if __FILE__ == $PROGRAM_NAME
