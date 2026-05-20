# frozen_string_literal: true

require "mechanize"
require "uri"

class ApplicationsLodgedPage
  URL = "https://www.busselton.wa.gov.au/plan-and-build/planning-and-building-resources/applications-issued-determined-lodged"

  # Returns Array of "Applications Lodged" links to fully-qualified URLs of PDFs
  # @return [Array<String>] URLs in page order (current year first then descending)
  def self.applications_lodged_pdfs
    agent = Mechanize.new
    page = agent.get(URL)
    page.links
        .select { |link| link.text.strip.match?(/applications\s+lodged/i) }
        .map    { |link| URI.join(URL, link.href).to_s }
  end
end
