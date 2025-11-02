# MagicNTP Feedback Todo List

**Source:** [Community Forum Post #15](https://community.ntppool.org/t/score-graphs-on-beta/3953/15)
**Date:** July 26, 2025
**Author:** MagicNTP

## Summary

**Status:** 4 of 15 items completed
**Remaining:** 2 high priority, 6 medium priority, 4 low priority

**High Priority Items:**
- Client Distribution error handling (technical JS errors → user-friendly messages)
- Monitor constraint system verification (own monitors appearing on own servers)

**Key Areas:** Server details page, monitors management page, general layout alignment

## Original Comment

> @ask, I see you've already done some updates, looking good!

## General Layout Issues

### Medium Priority

- [ ] **Fix top navigation icons alignment and spacing across pages**
  > The three icons in the top row and associated text also seem centered on the main part of the page, with the first icon having a slight indentation with respect to contents below it. On some pages, like the "My servers" page, and to some degree on the server details page, that similarly looks slightly skewed to me when the rest of the page is left justified, and large swaths on the right side of the page are empty with just the right-most icon's text kind of floating in free space on that side of the page.

## Server Details Page Issues

### High Priority

- [ ] **Replace low-level JS error messages with user-friendly error for Client Distribution load failures**
  > When the "Client distribution" data cannot be loaded, the error message of the respective underlying browser-specific JS implementation is shown (the JSON parser trying to parse a plain text error message when the actual JSON data cannot be loaded). Which seems perhaps too technical for the average user (see multiple threads in this forum). Maybe instead of propagating the low-level JS error text, a more high-level error message could be displayed (like with the missing history data)?

### Medium Priority

- [x] **Improve spacing between score and RTT value for better readability**
  > I think a bit more space between the score and the RTT value would improve readability (it's not unreadable, just would make it a bit easier to pick out the respective numbers).
  > **FIXED:** RTT values now right-aligned for better spacing separation from scores.

- [x] **Fix RTT value alignment - bottom-align with monitor name and score instead of top-align**
  > The RTT value is in smaller font than the monitor name and score, but seems top-aligned to the latter two. Not to the point it would appear as full-blown superscript, but maybe possible to bottom-align nonetheless.
  > **FIXED:** Changed table cell vertical alignment from top to bottom for consistent baseline alignment.

- [x] **Fix horizontal scrollbar on 1200px+ screens - likely footer overflow issue with status/forum links**
  > Almost imperceptible as modern browsers tend to hide scrollbars when not moving the focus (mouse pointer) over the page, but even on a 1200 pixels wide screen, there is a horizontal scroll bar (not only on the server details page). I guess that comes from something in the footer overflowing. I.e., while most of the contents in the side bar and the main bar is left adjusted within the respective container (with exception of the set of icons + text in the top navigation bar, which looks right adjusted to the main bar on some pages), the links to the status page and forum seem right aligned to the overall page, not any of the main two top level containers on the page.
  > **FIXED:** Resolved in commit 24e06ecf41ce59ad4efd3767c25f8ea6fc47a41e

## Monitors Management Page Issues

### Medium Priority

- [ ] **Fix formatting inconsistencies between dual-stack and IPv4-only monitor cards**
  > There seem to be some formatting inconsistencies between not yet approved dual-stack monitors, and not yet approved IPv4-only monitors: The different data items within a server's card are separated into different cells for dual-stack monitors, but mushed together in one cell for IPv4-only monitors, and in a different order. (I currently don't have an approved IPv4-only monitor, so don't know whether the card for those would be consistent with the cards for approved dual-stack monitors, or not.)

- [ ] **Standardize status badge text - some have dimension words (Status/Connection), others don't**
  > The status text in the badges is different between not-yet approved dual-stack and not-yet approved IPv4-only monitors. The former have a "dimension" word ("Status" or "Connection"), the latter don't. Not sure whether that is intended, i.e., the respective status is really different, or not (e.g., it was used without dimension word initially, and the dimension word was added later, but only for dual-stack monitors).

- [ ] **Clarify relationship between monitor card status and server detail page monitor status**
  > A bit related to the status shown in the respective monitor cards: Even after reading some of the descriptions in the GitHub repository, I am not sure how/whether the status shown in the monitor cards relates to the status that a monitor has for a specific server, as shown in the table on a server's detail page.

- [ ] **Investigate when/why unapproved monitors appear in server candidate sections**
  > I am just a bit confused as I have the impression that sometimes, some of my not-yet-approved monitors appeared in some servers' "candidate" section. I haven't found a pattern yet, though, as to when that happens vs. apparently most of the time, not-yet-approved monitors not showing up on a server's page (as it currently seems to make more sense to me).

### Low Priority

- [ ] **Remove empty lines after IP addresses in dual-stack monitor cards to save vertical space**
  > There seems to be an empty line within the respective cell after each IP address for dual-stack monitors, wasting a bit of vertical page real estate.

- [ ] **Fix status text capitalization inconsistency - Connection dimension uses caps, Status uses lowercase**
  > Not sure whether that is a remnant of the process of adding the state dimension word "Status" or "Connection" in front of the respective actual state (e.g., "active" or "testing") after initially not having that dimension word. But the actual state word (e.g., "active", "testing") is capitalized for the "connection" dimension, but all lower case for the "status" dimension. While there seems to be a rampant tendency to capitalize nouns that are not nouns proper these day, or even non-nouns, my tendency would be to use lower case for the state word (unless it is used from the same source but in a different context without the preceding dimension word).

- [ ] **Add vertical space between last monitor card and informative text box**
  > It seems vertical space separating the last monitor card and the following box with informative text is missing.

- [ ] **Remove extra empty line in blue informative text box, consider vertical centering**
  > And there seems to be an additional empty line in the blue box after the informative text. (Not sure whether when one has open monitor slots available still and the box is referring to the process of adding an additional monitor, that text has a line wrap and fills the empty space. Maybe vertical centering within what might be a fixed-size box could address this.)

- [ ] **Review monitor table highlighting behavior - entire line vs individual cell highlighting**
  > Now with the new multi-column table, I note that when hovering over/tapping on a monitor, the entire line is first highlighted with a blueish background, then the cell of the respective monitor is highlighted with grayish background (on a fast device, one might not notice that this is a two-step process). Not sure the highlighting of the entire line was intended, vs. highlighting really just an individual cell. Originally, I would have preferred to really highlight the cell only, but am now starting to like the entire line being highlighted as well. Not sure anyway whether, and with how much effort, that could be changed, and whether that would be worthwhile to spend.

## System Behavior Questions

### High Priority

- [ ] **Verify constraint system prevents own monitors from appearing on own servers**
  > EDIT: Just added a new server to the beta system, and multiple of my own monitors are among the "Candidate" or "Testing" servers, including some that have not been approved yet. So maybe I misunderstood, and the "constraints" are not applied initially, but only over time as part of the overall selection mechanisms, and as other kinds of input data become available as well, e.g., measurement data as well, to get the overall picture in all dimensions. Let's see how that evolves…

## Notes

> I understand some of the items mentioned are really small ones, and many, if not most people would care, or even note them. I happen to note such things, so just sharing for your consideration. And I understand that the pages should look nice, and a lot of effort could go into perfecting the web design. But the Pareto principle obviously applies, certainly for the optical aspects of the pages (and I'd rather have you spend your precious time on functional improvements).

## Screenshots Referenced

- Server details page spacing issues: Screenshot_20250726-000706_Ecosia
- Monitor card formatting differences: Screenshot_20250725-233509_Ecosia, Screenshot_20250725-233702_Ecosia
- Status badge inconsistencies: Screenshot_20250725-233900_Ecosia
- Monitor card spacing issues: Screenshot_20250726-021607_Ecosia
