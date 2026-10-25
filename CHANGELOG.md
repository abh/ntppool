# Changelog

All notable changes to the NTP Pool Project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## prod-2026.10.4

### ⚠️ Upgrade notes

- Requires NTP Pool API v0.8.6 or later. Deploy it first; with an older API
  the netspeed dropdown on the server page is empty.

### 🌐 User Interface & Experience

- The netspeed dropdown offers the speeds the API accepts for the server. A
  server with a netspeed target above its current netspeed can choose speeds
  up to the target before it is verified
- The help form on the sign-in page is behind a "Need help signing in?"
  button

## prod-2026.10.3

### 🔒 Security

- Fix: user-supplied text on the public profile, add-server, check results,
  vendor and account pages is escaped before it is shown (thanks Ross Paxton)
- Fix: the login redirect only goes to pages on this site (thanks Ross Paxton)
- Stricter Content Security Policy: no inline scripts or `eval`, and scripts
  load only from a short list of hosts (thanks Ross Paxton)

### 🌐 User Interface & Experience

- The site no longer loads Google Analytics
- The error page asks you to email support with the IDs it shows
- Fix: vendor subscription and zone data is sent as JSON instead of HTML

## prod-2026.10.2

- Fix: vendor zones created before the API migration open again, and the
  admin "show" link no longer bounces back to the zone list

## prod-2026.10.1

- Adding a hostname with several addresses no longer times out; the confirm
  step reuses the checks from the first step instead of running them again
- The add-server button shows "Checking servers…" and ignores repeat clicks
- Fix: "Server already registered" shows as a warning, without a trace ID

## prod-2026.10.0

### ⚠️ Upgrade notes

- The website gets all its data from the NTP Pool API (PostgreSQL) and no
  longer connects to a database. Deploy the matching API version first; the
  site answers with a 503 page when the API is unavailable.

### 🛒 Vendors

- Checkout for tiered plans is priced for the number of devices the account
  needs, and the zone page offers a plan upgrade when the account is over its
  limit
- New and rejected zones always ask for an open-source justification when
  submitted

### 🌐 User Interface & Experience

- Account admins can resend a pending team invitation
- Error messages include a trace ID to send to support
- The comment field on the add-server page is optional and collapsed; use it
  when you need help from the support team with the addition
- Fix: a deleted server's page says it "was deleted" instead of "is scheduled
  for deletion", and its graph stays available until the history is hidden
  six months after deletion
- Fix: loading indicators with reduced motion turned on no longer show two
  messages (e.g. "Updating... Loading...")

## prod-2026.05.1

### 🧙🏼‍♀️ Admin features

- Staff can delete a specific team member's user from the team list, with a
  confirmation page; members scheduled for deletion are marked
- Fix: the staff account deletion link targets the selected user instead of
  the staff member

### 🌐 User Interface & Experience

- "Remove" on the team list is now "Remove from team"
- Fix: charts on the server and zone pages render at full size again
- Fix: "Delete user" and "Download user data" only show on accounts you are a
  member of

## prod-2026.05.0

- Fix: account deletion no longer counts deleted monitors as blockers, and says
  what is preventing the deletion

## prod-2026.04.1

- Fix: the account log page loads quickly for accounts with a long history
- Fix: notices about servers removed from the pool go to the account's users
- Fix: unknown graph URLs return 404, and old `score.png` links show the offset
  graph

## prod-2026.04.0

- Traditional Chinese (zh-tw) translation of the documentation pages
- Server graphs color offsets with the same thresholds the monitor scorer uses
- Fix: missing "was scheduled for deletion" text in Croatian and Traditional
  Chinese

## prod-2026.03.0

- Thai translation
- Updated DNS server requirements (CPU and bandwidth)
- Translation fixes for Chinese, Czech and Portuguese

## prod-2025.11.0

- Updated country names
- Fix: zone charts no longer break when a data point has no monitors
- Fix: zone charts work for zone names containing `@`

## prod-2025.09.1

- The help form on the login page sends through webform.dev
- Fix: show the API's error message when changing a server's net speed fails

## prod-2025.08.1

### 🖥️ Monitor Management

- Monitor registration improvements (better experience when re-adding monitors)
- Fix deleting monitors in Firefox (and improve UI for everyone else)
- Better error handling when deleting monitors
- Improved monitor metrics display with proper value formatting and conditional "ok" display
- HTMX-based confirm-delete modal with loading indicators for better user experience

### 🌐 User Interface & Experience

- Add number of data points to developer menu (control-d) on scores page (experimental)
- Add round trip time to "Candidate" monitors on scores page
- Bootstrap popovers for displaying RTT (Round Trip Time) data
- HTMX loading indicators with reduced motion support for better accessibility

### 🧙🏼‍♀️ Admin features

- Search working in Firefox
- Show monitors in search results
- Search for accounts with monitors (`monitors:`)
- Search for accounts with servers in a zone (`zone:xy`)
- Admin search relevance filtering with "show all results" checkbox to hide secondary results

### 🏭 Internals

- More OpenTelemetry tracing
- Increase some internal timeouts
- Added "paused" state to server_scores status enum in database schema
- CORS headers added for cross-origin HTMX requests
- Firefox-specific HTMX form submission compatibility fixes
- OpenTelemetry error spans added to internal API calls
- Monitor constraint fields added to API timeout configurations

## prod-2025.08.0

### 🖥️ Monitor Management

#### Enhanced Monitor Registration

- Streamlined monitor acceptance workflow with improved confirmation process
- User monitor deletion feature for better self-service management
- Updated monitor setup with auto-redirect and performance metrics display
- IPv4/IPv6 setup options added to monitor instructions

#### Monitor Interface Improvements

- Monitor "name" field renamed to "hostname" for clarity
- Enhanced monitor management UI with hostname display
- Performance metrics now visible in the management interface
- Improved monitor status sorting in server graphs

### 🌐 User Interface & Experience

#### Modern Web Framework

- Upgraded to Bootstrap v5 for improved mobile and desktop experience
- Modernized JavaScript loading with HTMX integration
- Added responsive navigation system with collapsible menus
- Improved mobile layout and tablet view optimizations

#### Chart & Visualization Improvements

- Enhanced server charts with better time formatting and legend sorting
- Improved chart performance with reduced transitions and debounced interactions
- Better accessibility with improved color schemes
- Cleaner x-axis date formatting and reduced tick density
- Eliminated hover state issues on charts and tables

#### Navigation & Layout

- Fixed navigation layout issues and improved responsive breakpoints
- Reduced table row padding for server graphs
- Fixed footer overflow issues and horizontal scrollbars
- Improved admin search functionality with deleted items option

### 🔒 Security & Performance

#### Content Security Policy

- Enabled Content Security Policy for enhanced security
- Optimized asset loading and removed inline styles
- Updated build system to ensure CSP compliance

#### Session Management

- Added Argon2 session key support for enhanced security
- Implemented server-side user sessions
- Made cookies httpOnly for better security

### 🌍 Internationalization

#### New Language Support

- Added Czech language support
- Added Croatian language support
- Added Sinhala language support
- Promoted Polish from testing to production

#### Translation Updates

- Updated translations for 12+ languages including Italian, Spanish, Danish, Vietnamese, Chinese, Ukrainian, Turkish, Swedish, Serbian, Russian, Portuguese, Norwegian, Dutch, Korean, Japanese, Hindi, French, Finnish, Persian, Hungarian, Hebrew, Bulgarian, Greek, and German
- Fixed translation management tools and processes

### 🛠️ Administrative Features

#### Admin Interface Improvements

- Enhanced staff search with hostname display in results
- Added account token support for better context preservation
- Improved zone edit form with duplicate button fixes
- Better admin permissions and monitor interface

#### API & Integration

- Added X-Forwarded-For header support to internal API
- Improved error handling with trace ID extraction
- Enhanced monitor admin API with better configuration options
- Added support for canonical links on all pages

### 🏗️ Infrastructure & Build

#### Build System Modernization

- Added Node.js support and modern JavaScript build integration
- Migrated charts to TypeScript with Vite build system
- Integrated SCSS and modern asset management
- Added Vite manifest integration for optimized file loading

#### Database & Performance

- Added monitors_data view for analytics
- Improved server score cleanup and optimization
- Added candidate state to server scores
- Enhanced initial server setup timing

## [beta-2025.06.0]

### 🖥️ Monitor Management Improvements

- Enhanced Monitor Registration: Streamlined monitor acceptance workflow with improved confirmation process
- Hostname Field: Monitor "name" field renamed to "hostname" for better clarity throughout the system
- API Integration: Better API integration for monitor management operations
- Admin Interface: New monitor administration pages with improved permissions and interface

### 🌍 Translation Updates

- Italian: Completed and updated Italian translation
- Spanish: Review and updates to Spanish translation
- Danish: Updated Danish translation to sync with English source
- Vietnamese: Fixed Vietnamese translation issues
- Chinese: Minor translation improvements

### 🔧 Technical Improvements

- Error Handling: Improved error templates and API error handling
- Security: Made plain cookies httpOnly for better security
- UI Framework: Added htmx for enhanced user interactions
- Navigation: Fixed management interface navigation colors after Bootstrap 5 upgrade
- Performance: Fixed caching bug on 404 pages

### 🔑 API & Database

- API Keys: Prepared new API key feature for monitors
- Database: Added missing foreign keys and improved cascade deletion
- Data Reporting: New data-api integration for DNS query count reporting
- Search: Staff can now search accounts by tokenized account ID

### 🎨 Visual Updates

- Code Blocks: Changed website code blocks from red to blue styling
- Monitor Cards: Enhanced monitor information display cards
- Installation Guide: Updated monitor installation instructions

## [prod-2024.12.1]

### Fixed

- Minor bugfixes
- Updated Norwegian Nynorsk translation
- Added keep-alive connection cache to NP::UA
