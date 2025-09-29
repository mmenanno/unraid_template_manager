# UnRAID Template Manager

A Rails application for managing UnRAID Docker template files and comparing
them with Community Applications to keep your templates up to date.

## Features

- **Template Discovery**: Automatically scans your local UnRAID template
  directory
- **Community Sync**: Fetches matching templates from the UnRAID Community
  Applications feed
- **Smart Comparison**: Identifies differences between local and community
  templates
- **Field-by-Field Review**: Choose which values to keep for each changed field
- **Backup System**: Automatically backs up templates before applying changes
- **Background Jobs**: Async processing for template syncing and comparison
- **Modern Dark UI**: Clean, responsive dark mode interface built with
  Tailwind CSS

## Architecture

### Models

- **Template**: Represents both local and community templates
- **TemplateConfig**: Individual configuration elements within templates
- **TemplateComparison**: Tracks differences between local and community
  versions

### Services

- **LocalTemplateScanner**: Scans filesystem for template XML files
- **CommunityApplicationsClient**: Fetches templates from Community
  Applications API
- **TemplateDifferenceCalculator**: Identifies specific differences between
  templates
- **TemplateChangesApplier**: Applies user choices to update local templates

### Background Jobs

- **SyncLocalTemplatesJob**: Discovers and indexes local templates
- **SyncCommunityTemplatesJob**: Fetches matching community templates
- **UpdateTemplateComparisonsJob**: Recalculates template differences

## Workflow

1. **Template Discovery**: App scans
   `/boot/config/plugins/dockerMan/templates-user/` for XML files
2. **Community Matching**: Finds corresponding templates in Community
   Applications by repository URL
3. **Difference Detection**: Compares templates field-by-field including XML
   configurations
4. **User Review**: Present differences in an intuitive interface for user
   decisions
5. **Backup & Apply**: Creates backup then applies user choices to local
   templates

## Template Comparison Features

The app intelligently compares:

- **Basic Fields**: Name, network mode, category, WebUI URL, description
- **Configuration Elements**: Ports, paths, variables with all their
  attributes
- **New Configurations**: Configs that exist in community but not locally
- **Removed Configurations**: Configs that exist locally but not in community

## Development

### Setup

```bash
bundle install
bin/rails db:create db:migrate
bin/rails test
```

### Testing

The app includes comprehensive test coverage for:

- Service layer business logic
- Background job processing
- Template comparison algorithms
- UI controller functionality

### Configuration

Key configuration in `config/application.rb`:

- `config.template_directory`: Template scan path (default: `/templates` Docker volume)
- `config.backup_directory`: Backup location for original templates (default: `/storage/backups` Docker volume)

## Deployment

The app is designed to run as a Docker container on UnRAID:

1. Map the template directory:
   `/boot/config/plugins/dockerMan/templates-user:/templates`
2. Map a storage directory: `/mnt/user/appdata/unraid_template_manager:/rails/storage`
3. The app will automatically discover and manage your templates

## API Integration

Integrates with the official UnRAID Community Applications API:

- Feed URL:
  `https://raw.githubusercontent.com/Squidly271/AppFeed/master/applicationFeed.json`
- Matches templates by Docker repository URL
- Handles repository normalization (e.g., `lscr.io` variations)

## Security

- No modification of templates without explicit user approval
- Automatic backup creation before any changes
- Validation of XML structure before applying changes
- Read-only access to Community Applications API

---

Built with Rails 8, Tailwind CSS dark mode, and designed specifically for UnRAID Docker template management.
