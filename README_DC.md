# DataCloud with Relationship Research Agent (RRA)

## Overview

DataCloud component of RRA uses DataCloud to perform searches over unstructured data
and match entities found on the web to the entities residing in Data Cloud.

### Design goals

The DataCloud component is fully customizable: one can map different DMOs,
use Search Indexes to search against additional fields, retrieve different
attributes to match, and customize a LLM Prompt Template to do the matching.

### Our implementation

To perform that, we have two tables, both indexed with a single Search index.
One table is `RRA_Entity`, which is used to aggregate matchable information
on entities such as Accounts and Contacts coming from CRM. The other is `RRA_Note`
which accumulates long text fields associated with the Entities.
The search indexes over these tables are referenced by `RRA_EntitiesDatacloudSearch`
prompt template via Einstein Studio's Retrievers. By modifying the prompt and
search indexes, you have complete control over what and how to search. The
examples are provided below in the configuration guide.

However, anything can be customized, including the flow `RRA_EntitiesDatacloudSearch`
which currently wraps the LLM prompt.

## Default configuration

The two DMOs are `RRA_Entity`, `RRA_Note`. DMOs are accessed only by retrievers
(not direct queries) and therefore require search indexes, which have a limit
per database. Two searchable DMOs require only two indexes, that's why we're
storing `RRA_Account` and `RRA_Contact` together. You only need `RRA_Note`
if you want to search against Description fields mapped as many-to-one to Account/Contacts, or have
an unstructured data to search against (eg files/messages/...), in which case
you need to populate `RRA_Note` table. The default configuration maps `Description`
fields in Account/Contacts (which is redundant) solely for illustration purposes.

The default configuration is mapping CRM's Accounts and Contacts into
`RRA_Account`, `RRA_Contact` data streams, which in turn are mapped into `RRA_Entity`.
The `Description` fields are mapped into `RRA_Note` table solely for illustration
purposes, it is not required (you can leave `RRA_Note` unused and unmapped, as long as
you do not reference it in the prompt template)

Data is extracted from `RRA_Entity` via a Search index (which you can customize
to search for more fields, or to return more information), and a Retriever.
The Retriever has to be created manually and then referenced in the `RRA_EntitiesDatacloudSearch`
prompt template. The default `RRA_EntitiesDatacloudSearch` has two retrievers,
which are set side-by-side. If you don't map `RRA_Notes`, just use your only
retriever there instead.

## Extensibility points

### Use different data sources

With [SSOT `Individuals` DataCloud DMO](https://developer.salesforce.com/docs/data/data-cloud-dmo-mapping/guide/c360dm-individual-dmo.html)
configured, you can use data transformation
or map the sources into `RRA_Entity` DMO. Alternatively, you can implement
a search index and a retriever on `Individuals` directly, and reference
the retriever in the `RRA_EntitiesDatacloudSearch` prompt template. As long
as you return ContactID, AccountID for an entity already mapped into CRM,
you will be fine.

### Use additional fields for searching

Add more fields to `RRA_Entity` DMO, map them, and include into the Search Index.

### Use additional fields for output and matching

The `RRA_EntitiesDatacloudSearch` prompt template instructs the LLM to grab
the data from the output and reorganize it into a JSON structure with specific
fields. The fields are those produced by the retriever (but you can also customize
the field list with the templates). Any additional business logic on matching the
fields and organizing the result can be specified in the search template.

## Prerequisites

You need to have DataCloud licensed and configured.

## Deployment

### Prepare Data (in absence of DataKit)

#### DMO: RRA_Entity

- DataCloud UI -> Data Model -> New -> New (from Scratch)
- Object Label: **RRA Entity**. Object API Name: **RRA_Entity**. Category: **Profile**
- Fields:

  | Label       | API Name      | Type |
  | ----------- | :------------ | :--: |
  | Account     | Account**Id** | Text |
  | City        | City          | Text |
  | Contact     | Contact**Id** | Text |
  | Country     | Country       | Text |
  | Description | Description   | Text |
  | Email       | Email         | Text |
  | Id          | Id            | Text |
  | Title       | Title         | Text |
  | Type        | Type          | Text |
  | Website     | Website       | Text |

- Primary Key: **Id**

Relationships to be defined after the object has been mapped.

#### DMO: RRA_Note

- DataCloud UI -> Data Model -> New -> New (from Scratch)
- Object Label: **RRA Note**. Object API Name: **RRA_Note**. Category: **Other**
- Fields:

  | Label       | API Name         | Type |
  | ----------- | :--------------- | :--: |
  | Account     | Account**Id**    | Text |
  | Contact     | Contact**Id**    | Text |
  | Id          | Id               | Text |
  | Note        | Note             | Text |
  | Note Source | NoteSource**Id** | Text |
  | RRA Entity  | RRAEntity**Id**  | Text |

- Primary Key: **Id**
  Relationships to be defined after the object has been mapped.

#### Data Stream: RRA_Account

- DataCloud UI -> Data Streams -> New -> Connected Sources / Salesforce CRM -> Next -> View Objects -> Account -> Next
- Set Data Lake Object Label, Data Lake Object API Name, Data Stream Name to **RRA_Account**.
- Object Category: Profile. Primary Key: **Account ID**
- Fields:

  | Field name     | Field Label         | Data Type |
  | -------------- | :------------------ | :-------: |
  | BillingCity    | Billing City        |   Text    |
  | BillingCountry | Billing Country     |   Text    |
  | Description    | Account Description |   Text    |
  | Id             | Account Id          |   Text    |
  | Name           | Account Name        |   Text    |
  | Type           | Account Type        |   Text    |
  | Website        | Website             |    URL    |

- Data mapping: Click _Select Objects_
- On Custom Data Model tab: Select **RRA_Entity**, **RRA_Note**
- Map fields as follows

  | Field               | RRA Entity  | RRA Note                |
  | ------------------- | :---------- | :---------------------- |
  | Account Description | Description | Note                    |
  | Account ID          | Account, Id | Account, Id, RRA Entity |
  | Account Name        | Name        |                         |
  | Account Type        | Type        |                         |
  | Billing City        | City        |                         |
  | Billing Country     | Country     |                         |
  | Website             | Website     |                         |

NOTES:

- This mapping assumes that AccountID maps into Single Source of Truth's ID unchanged.
  If you want to change that, add a calculated field on DataStream, and map it into
  ID field on RRA_Entity, and RRAEntityID field on RRA_Note.
- The Note's ID is unique ID of the note and can also be mapped to a different calculated
  field if so required. The Note's ID does not have to be the same as RRAEntityId or AccountId;
  it is simply a unique ID of the specific note record.
- Mapping Description into both Entities and Notes is redundant, but it is required
  for setting up the RRANotes datasource in absence of other sources.

#### Data Stream: RRA_Contact

- DataCloud UI -> Data Streams -> New -> Connected Sources / Salesforce CRM -> Next -> View Objects -> Contact -> Next
- Set Data Lake Object Label, Data Lake Object API Name, Data Stream Name to **RRA_Contact**.
- Object Category: Profile. Primary Key: **Id**
- Fields:

  | Field name     | Field Label         | Data Type |
  | -------------- | :------------------ | :-------: |
  | AccountId      | Account ID          |   Text    |
  | Description    | Contact Description |   Text    |
  | Email          | Email               |   Text    |
  | Id             | Contact ID          |   Text    |
  | IndividualId   | Individual ID       |   Text    |
  | MailingCity    | Mailing City        |   Text    |
  | MailingCountry | Mailing Country     |   Text    |
  | Name           | Full Name           |   Text    |
  | Title          | Title               |   Text    |

- optional: Add new formula field to calculate **ResolvedIndividualId**
  - you can also map ContactId directly into RRAEntityID fields.
  - Field label, field API Name: **ResolvedIndividualId**.
  - Formula return type: Text.
  - Suggested transformation formula:

  ```
  COALESCE([sourceField['IndividualId'],CONCAT('SFDC_', sourceField['Id'])])
  ```

  Note that adding such formula will consume Data Transformation credits.

- Data Mapping: Click _Select Objects_
- On Custom Data Model tab: Select **RRA_Entity**, **RRA_Note**
- Map fields as follows

  | Field               | RRA Entity  | RRA Note |
  | ------------------- | :---------- | :------- |
  | Account ID          | Account     | Account  |
  | Contact Description | Description | Note     |
  | Contact ID          | Contact     | Contact  |
  | Email               | Email       |          |
  | Full Name           | Name        |          |
  | Mailing City        | City        |          |
  | Mailing Country     | Country     |          |
  | Title               | Title       |          |

- If you have defined **ResolvedIndividualId**:

  | Field                | RRA Entity | RRA Note       |
  | -------------------- | :--------- | :------------- |
  | ResolvedIndividualId | Id         | Id, RRA Entity |

- If you have **NOT** defined **ResolvedIndividualId**:

  | Field      | RRA Entity | RRA Note       |
  | ---------- | :--------- | :------------- |
  | Contact ID | Id         | Id, RRA Entity |

  NOTES:

- **ResolvedIndividualID** is your Single Source of Truth ID. Modify as necessary.
- The Note's ID is unique ID of the note and can also be mapped to a different calculated
  field if so required. The Note's ID does not have to be the same as RRAEntityId or AccountId;
  it is simply a unique ID of the specific note record.
- Mapping Description into both Entities and Notes is redundant, but it is required
  for setting up the RRANotes datasource in absence of other sources.

#### Relationships on DMOs

- Navigate to Data Model, click **RRA Entity**. Switch to Relationships. Click Edit.

- Add Relationships:

  | Field   | Cardinality | Related Object | Related Field |
  | ------- | :---------- | :------------- | :------------ |
  | Account | N:1         | CRM->Account   | Account ID    |
  | Contact | N:1         | CRM->Contact   | Contact ID    |

- Navigate to Data Model, click **RRA Note**. Switch to Relationships. Click Edit.

- Add Relationships:

  | Field      | Cardinality | Related Object         | Related Field |
  | ---------- | :---------- | :--------------------- | :------------ |
  | Account    | N:1         | CRM->Account           | Account ID    |
  | Contact    | N:1         | CRM->Contact           | Contact ID    |
  | RRA Entity | N:1         | Data Cloud->RRA Entity | Id            |

#### Search indexes

- Use Search or Navigation box to open Data Indexes page in DataCloud. New -> Advanced setup
- Search type: **Hybrid search**. Data Model Object Label: **RRA Entity**. Next.
- Chunking: Description, Name, Type. (Indexing on these fields).
- Name: RRA_Entity. Save and build Search index.
- Repeat for **RRA Note**. You only need to chunk on **Note** field.

### Extend searchable data

You can add additional data to be used with RRA (or to be searched), as long as you map it
into the DMOs, or use in the Search index.

#### Enable searching in a custom field name for Accounts

- Add the additional field to **RRA_Entities** DMO.
- Add the additional field to **RRA_Accounts** stream and map it to the DMO field.
- Edit the **RRA_Entities** search index and add the new field to the list of Chunked fields.
  Result: The new field will be searchable by the search index (and by RRA).

#### Enable searching for any unstructured data (eg files, or Slack messages)

This assumes that the files are already mapped to some entity (eg Contacts or Accounts).
The current implementation only supports 1 entity associated with a file (or a message).

- Import slack messages, or files, into a data stream.
- Map entities referenced in the data stream into **RRA_Entity** DMO.
- Map the messages themselves into **RRA_Note** DMO.

Now the **RRA_Note** search index will be working against unstructured data,
and RRA will be able to retrieve entities associated with that data.

### Create retrievers

- In DataCloud UI, navigate to Einstein Studio. Click "Retrievers".
- New Retriever -> Individual Retriever -> Data Cloud.
- Choose **RRA Entity** DMO, it should only contain a single search index.
- No filters (All documents to return).
- Results: add Name, Id, City, Country, Website, AccountId, ContactId.
- Save (Name: **RRA Entity Retriever**). Activate.
- Open the created retriever and note the API name - e.g. `RRA_Entity_Retriever_1Cx_uLK882e3f26`.
- Repeat for `RRA Note`. Add **the same fields** from **RRA Entity** only,
  do not add fields from **RRA Note** table itself (redundant).
- Save (Name: **RRA Note Retriever**). Activate.
- Open the created retriever and note the API name - e.g. `RRA_Note_Retriever_1Cx_uLKe002ffdf`.

### Deploy Prompt and Flow

#### Un-ignore DataCloud search objects in the project

- Open `.forceignore` file in this project. Comment out two lines below. Save.

```
# GenAI Prompt Templates with Data Cloud dependencies
**/RRA_EntitiesDatacloudSearch.genAiPromptTemplate-meta.xml
**/RRA_EntitiesDatacloudSearch.flow-meta.xml
```

#### Deploy DataCloud search objects

- [Open RRA_EntitiesDatacloudSearch Prompt Template](./force-app/main/default/genAiPromptTemplates/RRA_EntitiesDatacloudSearch.genAiPromptTemplate-meta.xml)
- Edit it to reference the retrievers set up previously (eg `1RRA_Note_Retriever_1Cx_AAA`, `RRA_Entity_Retriever_BB` )
- Deploy the prompt; test and activate it.
- Deploy the [RRA_EntitiesDatacloudSearch flow](./force-app/main/default/flows/RRA_EntitiesDatacloudSearch.flow-meta.xml)

#### Configure access to the flow

By default, no one can use the flow you've just published. For debug purposes, you can immediately
enable access by profiles. Or you can add permission to run the flow to a PermissionSet and then assign it to RRA users.

#### Debug/testing approach: set assignment on the flow

- Setup -> Flows -> Locate `RRA_EntitiesDatacloudSearch` -> context on the right -> Edit access.
- Check "Override default behavior and restrict access to enabled profiles or permission sets".
- Select appropriate profiles and permisison sets (eg Standard User, System Administrator for test). Save.

#### Debug the flow

Setup -> Flows -> Select flow `RRA_EntitiesDatacloudSearch` -> Open -> Debug.
If the flow returns without error, it's set up.
