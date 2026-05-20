# City of Busselton Development Applications (WA)

This is a scraper that runs on [Morph](https://morph.io). To get
started [see the documentation](https://morph.io/documentation)

Add any issues to https://github.com/planningalerts-scrapers/issues/issues

## Development Requirements

### Install pdftohtml

**MacOS**

* Homebrew: Run `brew install pdftohtml`
* MacPorts: Run `sudo port install pdftohtml`

**Linux** (Ubuntu/Debian)

Install poppler-utils by running:

    sudo apt-get install poppler-utils

## To run the scraper

    bundle exec ruby scraper.rb

### Expected output

    Retrieving https://www.busselton.wa.gov.au/documents/13944/applications-lodged-2026 ...
    Running pdftohtml to convert pdf to xml pages...
    Page-1
    ...
    Page-46
    Parsing XML document ...
    Processing page# 1
    Page header: Applications Lodged – 13/03/2026 – 19/03/2026
    Group: Development Applications
    Saving DA26/0185 - Lot 75 No 20 Old Mill Grove QUINDALUP  WA  6281
    ...
    Saving DA26/0195 - Lot 45 No 21 Carline Loop GEOGRAPHE  WA  6280
    Processing page# 2
    ...
    Processing page# 17
    Page header: Applications Lodged – 13/02/2026 – 19/02/2026
    Finished! Processed 178 records.

Execution time ~ 10 seconds

## To run style and coding checks

    bundle exec rubocop

## To check for security updates

    gem install bundler-audit
    bundle-audit

## Development

Set:

* `DEBUG=1` - to enable debug output from scraper

## Data source

[Home](https://www.busselton.wa.gov.au/) >>
Plan and Build >>
[Applications Issued, Determined and Lodged](https://www.busselton.wa.gov.au/plan-and-build/planning-and-building-resources/applications-issued-determined-lodged)

"Applications Lodged" links for the current year and previous year are links to PDFs covering the whole year.
The scraper fetches the first (current year) PDF and continues to the second (prior year) PDF only if it has
not yet found a date range ending more than 30 days ago — this naturally handles the January overlap without
any special date logic in `ApplicationsLodgedPage`.

Format: Each PDF is a concatenation of weekly "Applications Lodged – DD/MM/YYYY – DD/MM/YYYY" documents,
ordered from the most recent week to the earliest week for the year. The date range heading repeats on every
page of each weekly section.

Each weekly section lists one or more groups (eg "Development Applications" or "Building Applications"),
each preceded by a bold group heading and a table with columns:

* Application Number
* Description
* Primary Property Address
* Date Application Received
* Date Deemed Complete *(later Development Applications only — ignored by scraper)*

Notes:

* There is a fixed header and footer region; the data table/s and group headings is contained between them, and rows
  are split across pages when they do not fit.
* Table headings are not repeated on a continuation of a table onto following pages;
* Group headings do not force a page break (a new table starts below)
* Table headings are sometimes split mid-word, eg "Applicatio" on one line and "n Number" on the next line. A list of
  known headings is maintained to handle this to determine if a space should be inserted between lines or not.
    * This implies that column alignment may vary
* Table headings may change with the addition of "Date Deemed Complete", though this was not seen in the last 30 days
* Cell contents are normally aligned to the bottom of the row.
* When a row is split across pages, the first page holds as much of each cell that fits, with the
  remaining cell content appearing on the following page. The scraper uses `previous_record` to handle this.
* html2xml may merge text from two columns, which may cause classification issues, we handle this by 
  * moving the 2nd word from council reference to address if present, eg: "BAC26/0109 Certified:"
  * moving dates at the end of addresses to date_received and ignoring multiple dates for date_received
  * 

