# AGENTS.md - Agentic Coding Guidelines

This document provides guidelines for agents working on this codebase.

## Project Overview

- **Language**: Perl
- **Server side MVC Framework**: Mojolicious
- **Frontend styling**: Bootstrap v5
- **ORM Framework**: Durance (available through the PERL5LIB path)
- **Supported Database**: SQLite3
- **Testing**: Test::Mojo
- **Pending and Completed Project Tasks**: PROJECT_PLAN.md

## Project Purpose

This project is to create a single page webapp (SPA) that
  - supports multiple users
  - have one or more todo lists
  - easily add tasks to one or more todo lists
  - share todo tasks with other users
  - set deadlines for completion on tasks
  - visually show users when tasks are nearly late or completely late

The app should be build so that an iOS client could easily use a
cloud-based instance of the backend.

* The app should be as light-weight as possible
* It should require as few external non-core Perl modules as possible
* The app should favor Convention of Configuration (https://en.wikipedia.org/wiki/Convention_over_configuration)

## Planning Workflow

### Before Starting Any New Work
1. **Always read PROJECT_PLAN.md first** - This is the source of truth for what needs to be done
2. Check the "Pending Tasks" section to identify the next task to work on
3. Look for incomplete steps marked with `[ ]` or "IN PROGRESS" status

### Creating New Plans
- **Add new plans directly to PROJECT_PLAN.md** - Do NOT create separate files in plans/ directory
- Use the format: `## Feature: <Feature Name> ✓ PLANNED`
- Include discrete implementation steps with checkboxes `[ ]`
- Mark completed sections with `✓ COMPLETED`

### Updating Plans During Work
- As you complete steps, mark them with `✓ COMPLETED`
- Add implementation notes and code snippets
- Update the status at the top of each plan section

## Directory Structure

```
lib/
├── mojotodo/
t/
└── basic.t               # Test file
```

## Build/Lint/Test Commands

### Install Dependencies
```bash
cpanm --installdeps .
```

### Run All Tests
```bash
prove -l t/
```

### Run Single Test File
```bash
perl t/basic.t
```

### Run Tests Verbose
```bash
perl -Ilib -MTest2::Bundle::Verbose t/basic.t
```

### Code Formatting (Perl::Tidy)
```bash
perltidy -b lib/Some/Module.pm   # Formats in place, creates .bak
perltidy -st -se lib/Some/Module.pm  # stdout output
```

### Syntax Check
```bash
perl -wc lib/Mod.pm
perl -Ilib -wc Namespace/Model.pm
```

### Development Server
```bash
./start_debug_server.sh
```

This starts the app on http://0.0.0.0:8080 with fake auth enabled.

## Code Style Guidelines

### General Principles
- When writing perl scripts (not .pm perl modules), use this shebang line `#!/usr/bin/env perl`
- Always use `use strict;` and `use warnings;` at the top of every file
- If a module needs a helper function or method that does not need to be exposed to the user, those functions will start with an underscore like `_parse_dsn`.
- Do not `use Carp`.  Prefer the standard perl built-ins like `warn` and `die`
- Use the Single Responsibility principle (https://en.wikipedia.org/wiki/Single-responsibility_principle)
- Make the Perl modules easily testible
- Classes should prefer `has-a` relationships to `is-a`

### Naming Conventions
- **Packages/Modules**: UpperCamelCase (e.g., `Durance::Base`, `MyApp::Model::User`)
- **Methods/Subroutines**: lowerCamelCase (e.g., `createTable`, `tableExists`)
- **Attributes**: snake_case (e.g., `dbname`, `primary_key`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `COLUMN_META`)

### Import Style
- Use explicit import lists for modules: `use File::Temp qw(tempfile);` not `use File::Temp;`
- Group imports: core, third-party, local modules.  
- Sort each group alphabetically

### Formatting
- Use 4-space indentation (no tabs)
- Maximum line length: 100 characters
- Use perltidy for automatic formatting
- Use whitespace around operators: `$a + $b` not `$a+$b`

### Function Signatures
```perl
sub my_function ($self, $arg1, $arg2 = 'default') {
    # body
}
```

### Error Handling
- Use `die` for user-facing errors
- Use `warn` for warnings
- Use `//` (defined-or) not `||` for defaults

```perl
my $dbh = $self->dbh // die 'No database handle';
```

### Testing
- Use Test2::Suite (Test2::V0)
- Structure tests with `subtest`
- Use `dies_ok` for expected exceptions
- Use descriptive test names

```perl
use Test2::V0;

subtest 'Durance::Base - CRUD' => sub {
    my $user = MyApp::Model::User->create({ name => 'Test' });
    ok($user->id, 'id generated');
    is($user->name, 'Test', 'name set');
};
```

### Key Patterns
- **Global state**: Package variables with `our` (e.g., `$gDBH`)
- **Class data**: Package hashes (e.g., `%gCOLUMN_META`)
- **Method chaining**: Return `$self` from setters: `$self->name('value');`
- **Attribute accessors**: Use Moo `has`

### Testing Guidelines
- Create temporary SQLite3 databases with File::Temp
- Test success and failure cases
- Clean up resources (disconnect dbh)

### Feature Testing Preference
- **Prefer robust test coverage before adding new features**
- Complete all test coverage for a feature before starting the next feature
- This ensures changes don't break existing functionality
- Run full test suite after each change: `perl -Ilib t/orm.t`

## Documentation Guidelines

### Markdown Files
- Wrap all lines at 100 characters maximum
- This applies to intention, plan, and README files
