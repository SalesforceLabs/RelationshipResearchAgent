# Customizing RRA Research

## Introduction

RRA extracts many types of business relationships from CRM data and web sources. The system uses **priority rules** to focus research in selective areas and rank discovered relationships for presentation to the user.

**Default Priority Order:**
1. Leadership roles (CEO, Founder, Chair)
2. Ownership/Investment
3. Formal governance (Board roles)
4. Employment
5. Mentorship/Influence
6. Strategic partnerships
7. Competitive relationships

**Why Customize Research?**

Different use cases benefit from different relationship focus. You can customize RRA to prioritize the relationships most relevant to your business needs by:
- **Reprioritizing** existing relationship categories to change which relationships are shown
- **Removing** relationship categories that aren't relevant to your use case
- **Adding** new relationship categories specific to your industry or research goals

---

## Understanding the Relevant Prompts

RRA uses interconnected prompts that work together in a pipeline. To maintain consistency, you must update all relevant prompts when changing relationship priorities:

| Prompt Template | Role in Pipeline | What to Edit |
|------|---------|----------------|
| **RRA_DeepWebResearch_Discovery** | Extracts relationships from web search results | Priority list with category names and example predicates |
| **RRA_DeepWebResearch_Refinement** | Scores and filters web relationships by importance | Importance score bands (High, Medium-High, Medium, Lower) |
| **RRA_EntitiesFromCRM** | Extracts relationships from CRM data | Priority list with category names and example predicates |
| **RRA_ConsolidateInsights** | Consolidates and deduplicates CRM relationships | Specific predicate list with exact relationship phrases |

---

## How to Edit RRA Prompts

1. Log in to Salesforce after installation of RRA
2. Navigate to **Setup**
3. In the Quick Find box, search for **"Prompt Builder"**
4. Click on **Prompt Builder**
5. Find the prompt template you want to edit from the list above
6. Click **Edit** to open the prompt editor
7. Search for the section you need to modify (see scenarios below)
8. Edit the relevant prompt instructions
9. Verify that **Response Format** is set to **JSON** in the template settings
10. Click **Save** and then **Activate** to publish your changes

---

## Scenario 1: Reprioritizing or Removing Relationship Categories

This scenario shows how to:
- Move "Employment" from position #4 to position #2 (higher priority)
- Remove "Competitive relationships" entirely

### Step 1: Update RRA_DeepWebResearch_Discovery

**Search for:** "Targeting Constraints"

**Find this section:**
```
* If multiple valid relationships exist between the same pair of entities, select the most business-significant using the following prioritization (from highest to lowest):
 1. Leadership roles (e.g., is CEO of, is founder of, is chair of)
 2. Ownership or investment relationships (e.g., invested in, owns, acquired)
 3. Formal governance or board roles (e.g., served on board of)
 4. Employment relationships (e.g., was employed by)
 5. Mentorship or influence dynamics (e.g., was mentor to)
 6. Strategic or business partner (e.g., was business partner of)
 7. Competitive relationships (e.g., is competitor of)
```

**Change to:**
```
* If multiple valid relationships exist between the same pair of entities, select the most business-significant using the following prioritization (from highest to lowest):
 1. Leadership roles (e.g., is CEO of, is founder of, is chair of)
 2. Employment relationships (e.g., was employed by)
 3. Ownership or investment relationships (e.g., invested in, owns, acquired)
 4. Formal governance or board roles (e.g., served on board of)
 5. Mentorship or influence dynamics (e.g., was mentor to)
 6. Strategic or business partner (e.g., was business partner of)
```

**What changed:**
- Moved "Employment relationships" from #4 to #2
- Removed "Competitive relationships" (was #7)
- Renumbered remaining categories

### Step 2: Update RRA_DeepWebResearch_Refinement

**Search for:** "High Importance"

**Find this section:**
```
**High Importance (0.8-1.0):**
- C-Suite roles (CEO, CFO, CTO, etc.)
- President, Managing Director, Founder/Co-founder
- Board Chair, Board Member
- Direct ownership (>5% stake)

**Medium-High Importance (0.6-0.79):**
- Investment relationships (VC, PE, angel funding)
- Merger and acquisition relationships
- Senior management (VP+, Director+)

**Medium Importance (0.4-0.59):**
- Advisory board, consultant relationships
- Key partnerships and alliances
- Employment relationships (senior level)

**Lower Importance (0.2-0.39):**
- General employment relationships
- Vendor/customer relationships
- Competitive relationships
```

**Change to:**
```
**High Importance (0.8-1.0):**
- C-Suite roles (CEO, CFO, CTO, etc.)
- President, Managing Director, Founder/Co-founder
- Board Chair, Board Member
- Direct ownership (>5% stake)
- Employment relationships (senior level)
- General employment relationships

**Medium-High Importance (0.6-0.79):**
- Investment relationships (VC, PE, angel funding)
- Merger and acquisition relationships
- Senior management (VP+, Director+)

**Medium Importance (0.4-0.59):**
- Advisory board, consultant relationships
- Key partnerships and alliances

**Lower Importance (0.2-0.39):**
- Vendor/customer relationships
```

**What changed:**
- Moved both employment categories to "High Importance" (elevating employment priority)
- Removed "Competitive relationships" from Lower Importance

### Step 3: Update RRA_EntitiesFromCRM

**Search for:** "Targeting Constraints"

**Find this section:**
```
* For any unique relationship to `canonicalName` output **one** relationship, chosen by the following priority (highest → lowest):
 1 Leadership roles (`is CEO of`, `is founder of`, `is chair of`)
 2 Ownership / investment (`invested in`, `owns`, `acquired`)
 3 Formal governance roles (`served on board of`)
 4 Employment (`was employed by`)
 5 Mentorship / influence (`was mentor to`)
 6 Strategic or business partner (`was business partner of`)
 7 Competitive relationship (`is competitor of`)
```

**Change to:**
```
* For any unique relationship to `canonicalName` output **one** relationship, chosen by the following priority (highest → lowest):
 1 Leadership roles (`is CEO of`, `is founder of`, `is chair of`)
 2 Employment (`was employed by`)
 3 Ownership / investment (`invested in`, `owns`, `acquired`)
 4 Formal governance roles (`served on board of`)
 5 Mentorship / influence (`was mentor to`)
 6 Strategic or business partner (`was business partner of`)
```

**What changed:**
- Moved "Employment" from #4 to #2
- Removed "Competitive relationship" (was #7)
- Renumbered remaining categories

### Step 4: Update RRA_ConsolidateInsights

**Search for:** "Deduplication"

**Find this section:**
```
2. Deduplication:
 For any (subjectName, objectName) pair, retain only the strongest relationship. If multiple predicates exist, retain the one with highest business significance per this ranking:
 1. is CEO of
 2. is founder of
 3. is chair of
 4. invested in
 5. owns
 6. acquired
 7. served on board of
 8. was employed by
 9. was mentor to
 10. was business partner of
 11. is competitor of
```

**Change to:**
```
2. Deduplication:
 For any (subjectName, objectName) pair, retain only the strongest relationship. If multiple predicates exist, retain the one with highest business significance per this ranking:
 1. is CEO of
 2. is founder of
 3. is chair of
 4. was employed by
 5. invested in
 6. owns
 7. acquired
 8. served on board of
 9. was mentor to
 10. was business partner of
```

**What changed:**
- Moved "was employed by" from #8 to #4 (after leadership roles)
- Removed "is competitor of" (was #11)
- Renumbered remaining predicates

---

## Scenario 2: Adding New Relationship Categories

This scenario shows how to add "Advisory relationships" as a new high-priority category.

### Step 1: Update RRA_DeepWebResearch_Discovery

**Search for:** "Targeting Constraints"

**Find the priority list (see Scenario 1 for full text)**

**Change to:**
```
* If multiple valid relationships exist between the same pair of entities, select the most business-significant using the following prioritization (from highest to lowest):
 1. Leadership roles (e.g., is CEO of, is founder of, is chair of)
 2. Ownership or investment relationships (e.g., invested in, owns, acquired)
 3. Advisory relationships (e.g., advises, is advisor to, is consultant for)
 4. Formal governance or board roles (e.g., served on board of)
 5. Employment relationships (e.g., was employed by)
 6. Mentorship or influence dynamics (e.g., was mentor to)
 7. Strategic or business partner (e.g., was business partner of)
 8. Competitive relationships (e.g., is competitor of)
```

**What changed:**
- Added new category #3: "Advisory relationships" with example predicates
- Renumbered all following categories

### Step 2: Update RRA_DeepWebResearch_Refinement

**Search for:** "High Importance"

**Find the importance bands (see Scenario 1 for full text)**

**Change to:**
```
**High Importance (0.8-1.0):**
- C-Suite roles (CEO, CFO, CTO, etc.)
- President, Managing Director, Founder/Co-founder
- Board Chair, Board Member
- Direct ownership (>5% stake)
- Advisory board members, Strategic advisors

**Medium-High Importance (0.6-0.79):**
- Investment relationships (VC, PE, angel funding)
- Merger and acquisition relationships
- Senior management (VP+, Director+)
- Consultant relationships

**Medium Importance (0.4-0.59):**
- Key partnerships and alliances
- Employment relationships (senior level)

**Lower Importance (0.2-0.39):**
- General employment relationships
- Vendor/customer relationships
- Competitive relationships
```

**What changed:**
- Added "Advisory board members, Strategic advisors" to High Importance (0.8-1.0)
- Added "Consultant relationships" to Medium-High Importance (0.6-0.79)
- This ensures advisory relationships are scored highly and more likely to appear in results

**Also in this prompt, search for:** "Relationship Type Classification"

**Find this section:**
```
1. **Exclusive Relationships** (person can only have ONE active relationship of this type):
   - Employment: "is employed by", "works at", "is [job title] at"
   - C-Suite/Executive: "is CEO of", "is CFO of", "is President of"
   - Primary Ownership: "owns", "is owner of" (majority stake)

2. **Concurrent Relationships** (person can have MULTIPLE active relationships):
   - Board/Governance: "serves on board of", "is director of", "is board member at"
   - Investment: "invested in", "is investor in"
   - Volunteer: "volunteers with", "volunteers at"
   - Speaking/Teaching: "speaks at", "teaches at"
   - Partnership: "partners with", "collaborates with"
```

**Change to:**
```
1. **Exclusive Relationships** (person can only have ONE active relationship of this type):
   - Employment: "is employed by", "works at", "is [job title] at"
   - C-Suite/Executive: "is CEO of", "is CFO of", "is President of"
   - Primary Ownership: "owns", "is owner of" (majority stake)

2. **Concurrent Relationships** (person can have MULTIPLE active relationships):
   - Board/Governance: "serves on board of", "is director of", "is board member at"
   - Advisory: "advises", "is advisor to", "is consultant for"
   - Investment: "invested in", "is investor in"
   - Volunteer: "volunteers with", "volunteers at"
   - Speaking/Teaching: "speaks at", "teaches at"
   - Partnership: "partners with", "collaborates with"
```

**What changed:**
- Added "Advisory" to Concurrent Relationships (person can hold multiple advisory roles simultaneously)

### Step 3: Update RRA_EntitiesFromCRM

**Search for:** "Targeting Constraints"

**Find the priority list (see Scenario 1 for full text)**

**Change to:**
```
* For any unique relationship to `canonicalName` output **one** relationship, chosen by the following priority (highest → lowest):
 1 Leadership roles (`is CEO of`, `is founder of`, `is chair of`)
 2 Ownership / investment (`invested in`, `owns`, `acquired`)
 3 Advisory roles (`advises`, `is advisor to`, `is consultant for`)
 4 Formal governance roles (`served on board of`)
 5 Employment (`was employed by`)
 6 Mentorship / influence (`was mentor to`)
 7 Strategic or business partner (`was business partner of`)
 8 Competitive relationship (`is competitor of`)
```

**What changed:**
- Added new category #3: "Advisory roles" with example predicates
- Renumbered all following categories

### Step 4: Update RRA_ConsolidateInsights

**Search for:** "Deduplication"

**Find the predicate list (see Scenario 1 for full text)**

**Change to:**
```
2. Deduplication:
 For any (subjectName, objectName) pair, retain only the strongest relationship. If multiple predicates exist, retain the one with highest business significance per this ranking:
 1. is CEO of
 2. is founder of
 3. is chair of
 4. invested in
 5. owns
 6. acquired
 7. advises
 8. is advisor to
 9. is consultant for
 10. served on board of
 11. was employed by
 12. was mentor to
 13. was business partner of
 14. is competitor of
```

**What changed:**
- Added three specific advisory predicates: "advises" (#7), "is advisor to" (#8), "is consultant for" (#9)
- These are placed after ownership but before board/employment to match priority in other prompts
- Renumbered all following predicates

**Important:** In this prompt, you must add **specific predicates** (exact phrases), not categories. Add all variations of your new relationship type.

---

## Caveats

### 1. Maintain Consistency Across All Prompts

If priorities differ between prompts, you'll get inconsistent results. Always make changes in the same order across all prompts with consistent numbering and phrasing.

**Best practice:** Save each prompt one-by-one, then activate all of them at once to ensure changes go live simultaneously.

### 2. Don't Break the Output Schema

**What NOT to change:**
- Field names like `entityName`, `predicate`, `canonicalName`
- JSON structure or syntax
- Breaking the output schema will likely lead to blank research results and/or application errors

**What you CAN change:**
- Priority order (numbering 1, 2, 3, etc.)
- Relationship categories and examples
- Importance score assignments
- Adding/removing relationship types in priority lists

### 3. Don't Alter Input Variable Handling

Do not modify, remove, or add input variables in the prompt templates. Input variables appear as links in PromptBuilder and are critical for passing data into the prompts. Altering input variable handling will break the integration between RRA and the prompt templates.

### 4. Use Consistent Predicate Names

Choose one canonical form per relationship type and use it consistently across all prompts.

**Good:** Always use "was employed by"
**Bad:** Using "was employed by" in one prompt and "works at" in another

### 5. Only Edit the Active Version

Each prompt template may have multiple versions. Only edit the **Active** or **Published** version. Avoid editing "Draft" versions unless you intend to activate them.

### 6. Test After Each Set of Changes

After modifying prompts:
1. Click **Activate** to publish your changes
2. Run RRA on a known entity that has multiple relationship types
3. Review the output to confirm the expected relationship was selected
4. Check logs for any errors or unexpected behavior
5. Check Apex job status in Setup > Apex Jobs for any failures

### 7. Understand Exclusive vs Concurrent Relationships

In `RRA_DeepWebResearch_Refinement`, relationships are classified as:

**Exclusive** (person can only have ONE):
- Employment, C-Suite positions, Primary ownership

**Concurrent** (person can have MULTIPLE):
- Board positions, Advisory roles, Investments, Volunteering

**Why it matters:** This classification affects confidence scoring. When adding new relationship types, classify them in the `RRA_DeepWebResearch_Refinement` prompt around the "Exclusive Relationships" section.

### 8. Change Model Types with Caution

Each prompt template is configured to use a specific AI model (e.g., Claude, GPT, Gemini). Changing the model type can have significant consequences including altered behavior, different output quality, varying response times, and changed costs.

---

## Validation Checklist

Before activating your changes, verify:

- [ ] All relevant prompt templates have been updated
- [ ] Priority order is consistent across discovery and CRM prompts
- [ ] Importance scores in consolidation prompt align with priority order
- [ ] New relationship types are added to all relevant sections
- [ ] Predicate names are consistent (same phrasing/tense)
- [ ] No field names were changed (entityName, predicate, canonicalName, etc.)
- [ ] New relationship types classified as exclusive or concurrent (refinement prompt)
- [ ] Response Format is set to JSON in all templates
