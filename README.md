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

# Design of the solution

`ApplicationsLodgedPage.applications_lodged_pdfs` returns an Array of fully-qualified URL strings for the
"Applications Lodged" PDF links found on the page, converting any relative URLs to absolute.

`PdfDocument` orchestrates parsing: it iterates over `<page>` nodes, instantiates a `PdfPage` for each, and
yields complete row hashes to the caller. It maintains last-known headings across pages (since headings only
appear on the first page of each table section). It also handles cross-page row continuation.

`PdfPage` processes `<text>` nodes, classifying each by position (is or is not the start of a new array of text entries
for a row) and bold status:

* **Page header / footer** — nodes with `top` outside `DATA_TOP_RANGE` — skipped, except the date range
  heading (eg `"Applications Lodged – 06/03/2026 – 12/03/2026"`) which is captured as `header`.
* **Group heading** — bolded node with `left` in `FIRST_CELL_LEFT_RANGE` whose stripped text matches a
  known group name (eg `"Development Applications"`) — output to stdout but not otherwise noted.
* **Table headings** — bolded nodes with `left` in `FIRST_CELL_LEFT_RANGE` that are NOT a known group
  name — collected, merged by left position into `headings`: an Array of `{left: Integer, text: String}`.
* **Data nodes** — non-bolded nodes within `DATA_TOP_RANGE` — returned as an array of
  `{left: Integer, text: String}` hashes.

`PdfPage` yields `[data_nodes, header, headings_or_nil]` for each page.

`PdfDocument` keeps the last-seen headings and uses them as the default when `nil` is yielded (pages after
the first in a section have no headings).

`PdfDocument.data_entries` yields complete row hashes (column name → text string) plus the current header
string. The scraper parses the header to extract the end date and stops processing when it is more than
30 days ago.

### Cross-page row continuation

`PdfDocument` detects a continuation row when the first data node on a page has its `left` **outside**
`FIRST_CELL_LEFT_RANGE` — meaning no application reference starts the row. Those nodes are appended to the
accumulated nodes of the previous row before column mapping is applied.

### Column mapping

After collecting all nodes for a row, each node is assigned to the column heading whose `left` is the
largest value that is still ≤ the node's `left + [width/2, 10].min`.

Columns not needed by the scraper (eg `"Date Deemed Complete"`) are silently ignored.

### pdftohtml merge anomalies

Two known cases where pdftohtml merges content that visually spans column boundaries:

1. **Application Number bleeds into Description**: the node at the first-cell left position may contain
   eg `"BAU26/0106 Uncertified: "`. Split on the first space — the part before is the application number,
   the remainder is prepended to the Description value accumulated from subsequent nodes.

2. **Address bleeds into Date Received**: a wide node assigned to the address column may contain a trailing
   date, eg `"Busselton 11/03/2026"`. Detect using `DATE_PATTERN` at end of the address value. Strip the
   date from the address and move it to `"Date Application Received"` if that field is currently empty.
   After moving any date from the end of address, Where two dates appear (eg `"10/01/2025  10/01/2025"`), extract only
   the first match and discard the
   second.

### Address normalisation

Append `", WA"` to the address if it does not already end with `" WA"` or `" WA \d{4}"`.

## Constants

```ruby
# Midpoint between last header text top (122) and first data top (139)
# Midpoint between last data top (748) and footer top (823)
DATA_TOP_RANGE = 130..785

# Observed application number left=62, ±30 to allow year-to-year variation
FIRST_CELL_LEFT_RANGE = 32..92

DATE_PATTERN = /[0-3]?\d\/[01]?\d\/\d{4}/

KNOWN_GROUP_NAMES = ["Development Applications", "Building Applications"].freeze
```

## XML structure reference

The header, footer, and data nodes as returned by pdftohtml (fontspec and image tags have not been shown below):

    # Outside DATA_TOP_RANGE — skipped (footer shown for reference)
    <text top="96"  left="54"   width="448" height="21" font="1">Applications Lodged – 06/03/2026 – 12/03/2026 </text>
    <text top="823" left="1171" width="42"  height="16" font="0">1 of 5 </text>

    # Group heading — bold, left in FIRST_CELL_LEFT_RANGE, text matches KNOWN_GROUP_NAMES
    <text top="157" left="54" width="225" height="22" font="3"><b>Development Applications  </b></text>

    # Table headings — bold, left in FIRST_CELL_LEFT_RANGE, text does NOT match KNOWN_GROUP_NAMES
    # Multi-line headings share the same left value and are merged
    <text top="199" left="62"   width="98"  height="22" font="4"><b>Application </b></text>
    <text top="221" left="62"   width="70"  height="22" font="4"><b>Number </b></text>
    <text top="210" left="179"  width="100" height="22" font="4"><b>Description </b></text>
    <text top="210" left="626"  width="213" height="22" font="4"><b>Primary Property Address </b></text>
    <text top="199" left="1040" width="141" height="22" font="4"><b>Date Application </b></text>
    <text top="221" left="1040" width="79"  height="22" font="4"><b>Received </b></text>

    # Data nodes — not bold, within DATA_TOP_RANGE
    <text top="268" left="62"   width="90"  height="22" font="5">DA26/0159 </text>
    <text top="246" left="179"  width="386" height="22" font="5">Single House (Swimming Pool and Landscaping) - </text>
    <text top="268" left="179"  width="163" height="22" font="5">Special Control Area </text>
    <text top="246" left="626"  width="213" height="22" font="5">Lot 27 No 75 Johnson Road </text>
    <text top="268" left="626"  width="178" height="22" font="5">WILYABRUP  WA  6280 </text>
    <text top="268" left="1115" width="83"  height="22" font="5">6/03/2026 </text>

    # Cross-page split example — last entry on page N:
    <text top="765" left="62"   width="101" height="22" font="5">BAU26/0105 </text>
    <text top="765" left="196"  width="139" height="22" font="5">Uncertified: Shed </text>
    <text top="765" left="646"  width="233" height="22" font="5">Lot 38 No 195 Marine Terrace  </text>
    <text top="765" left="1117" width="96"  height="22" font="5">10/03/2026  </text>

    # First node on page N+1 — left=646 is outside FIRST_CELL_LEFT_RANGE → continuation of above
    <text top="139" left="646"  width="90"  height="22" font="5">Geographe </text>

    # Next entry on page N+1 — application number bleed example:
    <text top="184" left="62"   width="261" height="22" font="5">BAU26/0106 Uncertified: </text>
    <text top="184" left="291"  width="76"  height="22" font="5">Shed </text>
    <text top="162" left="646"  width="208" height="22" font="5">Lot 65 No 6 Seagrott Road  </text>
    # Address/date bleed example — wide node contains suburb + date:
    <text top="184" left="646"  width="952" height="22" font="5">Busselton 11/03/2026 </text>

    # Two-date example (Date Application Received + Date Deemed Complete merged) — use first date only:
    <text top="271" left="1008" width="184" height="22" font="33">10/01/2025  10/01/2025 </text>

    # Xml file starts with:
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE pdf2xml SYSTEM "pdf2xml.dtd">
    
    <pdf2xml producer="poppler" version="24.02.0">
    <page number="1" position="absolute" top="0" left="0" height="892" width="1263">

    # Typical end of one page and start of another:
    </page>
    <page number="218" position="absolute" top="0" left="0" height="892" width="1262">
