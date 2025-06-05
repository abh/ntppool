This is the website frontend for the NTP Pool Project; the management
system for a global cluster of NTP (time servers) available to internet
users across the world.

The website frontend is written in Perl with Template Toolkit templates.

New features are primarily developed in a separate API service which
the frontend calls over HTTP.

The website is translated to dozens of languages. The HTML translations
are in docs/ntppool/??/ where ?? is the language code. There are PO files
for shorter strings in i18n/??.po.

The system runs in Kubernetes in production and has many dependencies
making it difficult to run partially.

## Development Environment
- Built into Docker containers, executed in Kubernetes
- Uses `Dockerfile.dev` during development
- Uses the most recent released Perl version
- Database is MySQL (accessed via internal API service)

## Project Structure
- `lib/NTPPool/Control.pm` and `lib/NTPPool/Control/*` - Web controllers
- `combust/lib/Combust/` - Internal "Combust" web framework
- `lib/NP/IntAPI.pm` - Interface code for internal API calls
- `lib/NP/Model.pm` and `lib/NP/Model/*` - Database models (Rose::DB)
- `docs/ntppool/` - Main website templates
- `docs/manage/` - Management interface templates
- `docs/shared/` - Shared templates and static files (CSS, JS)
- `i18n/` - PO translation files

## Architecture Guidelines
- **New database functionality**: Implement as API calls to the internal API service, not direct database access
- **API Integration**: Use `lib/NP/IntAPI.pm` for communication with the separate API service
- **Database Models**: Built on Rose::DB, but prefer API calls for new features
- **Web Framework**: Controllers built on the internal "Combust" framework

## Code Standards

### Required Before Each Commit
- Run `perltidy` before committing any changes to ensure proper code formatting
- Trim trailing whitespace on all edited lines. End files with a linebreak.

## Key Guidelines
1. Follow Perl best practices and idiomatic patterns
2. Maintain existing code structure and organization
3. Write unit tests for new functionality. Use table-driven unit tests when possible.
4. For new database operations, implement via API calls rather than direct database access
5. Follow Combust framework patterns when creating new controllers
6. The maintainer's email address is ask@develooper.com; this isn't a typo.
