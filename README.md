# Relationship Research Agent (RRA)

> An AI-powered Salesforce application that automatically discovers and visualizes business relationships by analyzing CRM data and web sources.

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE.txt)
[![Salesforce API](https://img.shields.io/badge/Salesforce%20API-v62.0-blue.svg)](https://developer.salesforce.com/)

## Overview

Relationship Research Agent (RRA) enhances your Salesforce CRM by automatically discovering and mapping business relationships between people and organizations. Using AI-powered analysis, RRA:

- **Discovers hidden connections** between accounts, contacts, leads, and opportunities
- **Visualizes relationship networks** with interactive D3.js-based graphs
- **Enriches CRM data** by combining internal records with web research
- **Provides context** with citations and sources for every relationship discovered

## Features

- 🔍 **Automated Relationship Discovery** - Analyzes CRM data and web sources to find connections
- 📊 **Interactive Graph Visualization** - D3.js-powered relationship network display
- 🤖 **AI-Powered Entity Matching** - Uses Einstein Prompt Builder for intelligent entity resolution
- ⚡ **Async Processing** - Background job processing for large data sets
- 📱 **Lightning Experience Ready** - Custom components for Account, Contact, Lead, and Opportunity pages

## Prerequisites

Before installing RRA, ensure your Salesforce org has:

- **Salesforce Edition:** Enterprise, Unlimited, or Developer Edition
- **API Version:** 62.0 or higher
- **Agentforce:** Enabled
- **Einstein Prompt Builder:** GenAI Prompt Template support
- **Agentforce Data Library:** Web Retriever configured
- **Platform Cache:** Org cache allocated
- **Lightning Experience:** Enabled
- **My Domain:** Deployed

## Installation

1. **Clone the Repository**

   ```bash
   git clone https://github.com/SalesforceLabs/RelationshipResearchAgent.git
   cd RelationshipResearchAgent
   ```

1. **(Optional) Install Dev Dependencies**

   Only needed if you plan to run tests, linters, or formatters.

   ```bash
   nvm use  # optional: if using nvm
   npm install
   ```

1. **Authenticate to Salesforce**

   ```bash
   sf org login web --set-default
   ```

   Or authenticate to a specific instance:

   ```bash
   sf org login web --instance-url https://your-domain.my.salesforce.com --alias rra-org
   ```

1. **Configure Salesforce Org Prerequisites**

   a. **Enable Agentforce**
   - Navigate to **Setup > Agentforce**
   - Enable Agentforce for your org

   b. **Create Web Retriever (Agentforce Data Library)**
   - Navigate to **Setup > Agentforce Data Library**
   - Click **New**
   - Configure:
     - **Data Type:** Web
     - **Turn on Web Search:** Enabled
     - **Web Source:** Search the Web
   - Save

   c. **Configure Platform Cache**
   - Navigate to **Setup > Platform Cache**
   - Create a partition named `rrapicache` (or use your default partition)
   - Allocate memory to both **Org Cache** and **Session Cache**

   d. **Disable Data Masking**
   - Navigate to **Setup > Einstein Trust Layer**
   - Select **Large Language Model Data Masking**
   - Turn **Off**

   **Note:** Data masking will hinder entity name recognition and relationship extraction.

1. **Deploy All Metadata to Salesforce**

   ```bash
   sf project deploy start --test-level NoTestRun
   ```

   Or deploy using the manifest:

   ```bash
   sf project deploy start --manifest manifest/package.xml
   ```

1. **Activate Custom Record Pages**
   - Navigate to **Setup > Lightning App Builder**
   - Open each custom record page:
     - `Account_Record_Page`
     - `Contact_Record_Page`
     - `Lead_Record_Page1`
     - `Opportunity_Record_Page`
   - Click **Activation**
   - Set as org default or assign to specific apps/profiles
   - Save

   _Alternatively, you can add the RRA component to your own custom record pages._

1. **Verify Prompt Templates**

   Navigate to **Setup > Prompt Builder** and verify all templates are active:
   - `RRA_CommonNameVariants`
   - `RRA_EntityMatcher`
   - `RRA_EntitiesFromCRM`
   - `RRA_ConsolidateInsights`
   - `RRA_AppendRelationships`
   - `RRA_DeepWebResearch_Discovery`
   - `RRA_DeepWebResearch_Refinement`

   **Known Issue:** Templates may deploy as inactive. Manually activate if needed, and ensure output mode is set to **JSON**.

## Usage

### Discovering Relationships

1. Navigate to an Account, Contact, Lead, or Opportunity record
2. The RRA component appears on the Lightning page
3. Click **Start Research**
4. Processing occurs in the background (async)
5. View the interactive relationship graph when complete

### Understanding the Visualization

- **Nodes:** Represent people and organizations
- **Edges:** Show relationships with predicates (e.g., "founded", "CEO of")
- **Colors:** Indicate entity types

### Interacting with the Graph

Click on entities to:

- **Create Record:** Create a new CRM record (Account, Contact, or Lead) from an unmatched entity
- **Link Record:** Associate an entity with an existing CRM record
- **View Record:** Navigate to the linked CRM record
- **View Citations:** See source URLs and references for discovered relationships

### Monitoring Job Status

RRA processes relationships asynchronously in the background. To monitor job progress:

1. Navigate to **Setup > Environments > Jobs > Apex Jobs**
2. Look for jobs with class name **RRAClientAsync**
3. Check the **Status** column (Queued, Processing, Completed, Failed)
4. Refresh the record page to see updated results when the job completes

## Architecture

### Core Components

**Apex Classes:**

- `RRAClient` / `RRAClientAsync` - Main API entry points
- `CrmRelationshipInsightsProcessor` - Orchestrates relationship discovery
- `DeepWebResearchEngine` - Web research via Agentforce
- `EntityMatcher` - AI-powered entity resolution
- `EntityMatcherDataCloud` - Data Cloud subroutines for entity resolution
- `CrmDatabaseSelectors` - Database queries for CRM data
- `RelationshipInsightsPersister` - Persists discovered relationships

**Lightning Web Components:**

- `rraComponent` - Main component for Lightning pages
- `rraGraph` - D3.js-based graph visualization
- `rraConfirmMatchModal` - Entity matching UI
- `rraCreateRecordModal` - Record creation dialog

**Custom Objects:**

- `RRARelationships__c` - Stores relationship data as JSON

**GenAI Prompt Templates:**

- 7 specialized prompts for entity extraction, matching, consolidation, and web research

### Data Cloud components

- [See DataCloud Readme](./README_DC.md)

## Development

### Running Tests

Run all Apex tests:

```bash
sf apex run test --synchronous --code-coverage --result-format human
```

Run specific test class:

```bash
sf apex run test --synchronous --tests EntityMatcherTest
```

### View Debug Logs

Get the most recent log:

```bash
sf apex log get --number 1
```

Filter to USER_DEBUG only:

```bash
sf apex log get --number 1 | grep 'USER_DEBUG'
```

Remove ANSI color codes with [`ansi2txt`](https://github.com/kilobyte/colorized-logs):

```bash
sf apex log get --number 1 | ansi2txt > test.log
```

### Code Quality

Format code with Prettier:

```bash
npm run prettier
```

Verify formatting:

```bash
npm run prettier:verify
```

Run linter:

```bash
npm run lint
```

### Deploying Specific Components

Deploy a single Apex class:

```bash
sf project deploy start --metadata ApexClass:EntityMatcher
```

Deploy multiple components:

```bash
sf project deploy start --metadata ApexClass:EntityMatcher --metadata ApexClass:EntityMatcherTest
```

### Updating SLDS Icons

The graph component uses Salesforce Lightning Design System icons via SVG sprite files.

To update icons:

```bash
# Install SLDS
npm install @salesforce-ux/design-system --save-dev

# Copy sprite files to static resources
cp node_modules/@salesforce-ux/design-system/assets/icons/standard-sprite/svg/symbols.svg force-app/main/default/staticresources/symbols.svg
cp node_modules/@salesforce-ux/design-system/assets/icons/utility-sprite/svg/symbols.svg force-app/main/default/staticresources/symbolsutil.svg
```

## Known Issues

### Prompt Builder Templates

- Templates may deploy as inactive even when exported as active
- Output mode may reset from JSON
- **Workaround:** Manually activate templates and set output mode to JSON in Prompt Builder

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Security

To report security vulnerabilities, see [SECURITY.md](SECURITY.md).

## License

Copyright (c) 2025 Salesforce, Inc.

Licensed under the Apache License, Version 2.0. See [LICENSE.txt](LICENSE.txt) for details.

## Support

- **GitHub Issues:** [Report bugs and request features](https://github.com/SalesforceLabs/RelationshipResearchAgent/issues)
- **GitHub Discussions:** [Ask questions and share ideas](https://github.com/SalesforceLabs/RelationshipResearchAgent/discussions)

---

Built with ❤️ by Salesforce
