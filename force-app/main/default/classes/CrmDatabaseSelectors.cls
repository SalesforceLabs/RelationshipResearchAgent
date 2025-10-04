// This class provides strongly-typed, reusable field lists and SOQL accessors
// for standard CRM objects (Account, Contact).
//
// Apex limitation note:
//
// Apex does not allow static methods or variables in inner classes.  This
// restriction prevents encapsulating static logic (like field lists and
// selectors) within logical inner groupings of this class (e.g., CrmFields,
// Accounts, Contacts).
//
// To avoid polluting the global namespace with multiple top-level classes, a
// decision was made to flatten the structure into a single top-level class.

public with sharing class CrmDatabaseSelectors {
  // When changing this list, make sure it's same list as in getAccountsByIds
  public static final List<SObjectField> ACCOUNT_FIELDS = new List<SObjectField>{
    Account.Id,
    Account.Name,
    Account.Website,
    Account.BillingCity,
    Account.BillingState,
    Account.BillingCountry,
    Account.Industry,
    Account.Description
  };
  // When changing this list, make sure to add to getContactsByIds
  public static final List<String> ACCOUNT_ASSOCIATED_FIELDS = new List<String>{
    'Account.Name',
    'Account.Industry'
  };
  // When changing this list, make sure it's same as in getContactsByIds
  public static final List<SObjectField> CONTACT_FIELDS = new List<SObjectField>{
    Contact.Id,
    Contact.Name,
    Contact.Email,
    Contact.AccountId,
    Contact.Title,
    Contact.Department,
    Contact.Description
  };

  public static final List<SObjectField> OPTY_FIELDS = new List<SObjectField>{
    Opportunity.Id,
    Opportunity.AccountId,
    Opportunity.ContactId,
    Opportunity.OwnerId,
    Opportunity.Description,
    Opportunity.Name
  };

  public static final List<SObjectField> LEAD_FIELDS = new List<SObjectField>{
    Lead.Id,
    Lead.Name,
    Lead.Company,
    Lead.Title,
    Lead.Industry,
    Lead.City,
    Lead.State,
    Lead.Country,
    Lead.Email,
    Lead.Phone,
    Lead.OwnerId
  };

  public static String join(List<SObjectField> fields) {
    List<String> api = new List<String>();
    for (SObjectField f : fields) {
      api.add(f.getDescribe().getName());
    }
    return String.join(api, ',');
  }

  private static final String ACCOUNT_FIELD_LIST = join(ACCOUNT_FIELDS);

  public static Account getAccountById(Id recordId) {
    String soql = 'SELECT ' + ACCOUNT_FIELD_LIST + ' FROM Account WHERE Id = :recordId LIMIT 1';
    List<Account> rows = Database.query(soql);
    return rows.isEmpty() ? null : rows[0];
  }

  // This function is here to ensure that the field names are consistent between
  // queries and to provide a single class to update field lists.
  public static List<Account> getAccountsByIds(Set<Id> recordIds) {
    List<Account> dbAccounts = [
      SELECT Id, Name, Website, BillingCity, BillingState, BillingCountry, Industry, Description
      FROM Account
      WHERE Id IN :recordIds
    ];
    return dbAccounts;
  }

  public static List<Contact> getContactsByIds(Set<Id> recordIds, Set<Id> accountIds) {
    List<Contact> dbContacts = [
      SELECT
        Id,
        Name,
        Email,
        AccountId,
        Title,
        Department,
        Description,
        Account.Name,
        Account.Industry
      FROM Contact
      WHERE Id IN :recordIds OR AccountId IN :accountIds
    ];
    return dbContacts;
  }
  
  public static List<Account> getNewestAccounts(Integer limitSize) {
    // NOTE: The WHERE clause below was removed.  Including it could result in
    // no accounts being returned if none were created in the past 30 days.
    //
    //    WHERE CreatedDate = LAST_N_DAYS:30
    String soql =
      'SELECT ' +
      ACCOUNT_FIELD_LIST +
      ' FROM Account ORDER BY CreatedDate DESC LIMIT :limitSize';
    return Database.query(soql);
  }

  private static final String CONTACT_FIELD_LIST = join(CONTACT_FIELDS);

  public static Contact getContactById(Id recordId) {
    String soql =
      'SELECT ' +
      CONTACT_FIELD_LIST +
      ', ' +
      String.join(ACCOUNT_ASSOCIATED_FIELDS, ', ') +
      ' FROM Contact WHERE Id = :recordId LIMIT 1';
    List<Contact> rows = Database.query(soql);
    return rows.isEmpty() ? null : rows[0];
  }

  public static Opportunity getOptyById(Id recordId) {
    String soql =
      'SELECT ' +
      join(OPTY_FIELDS) +
      ', ' +
      String.join(ACCOUNT_ASSOCIATED_FIELDS, ', ') +
      ' FROM Opportunity WHERE Id = :recordId LIMIT 1';
    List<Opportunity> rows = Database.query(soql);
    return rows.isEmpty() ? null : rows[0];
  }

  public static Lead getLeadById(Id recordId) {
    String soql = 'SELECT ' + join(LEAD_FIELDS) + ' FROM Lead WHERE Id = :recordId LIMIT 1';
    List<Lead> rows = Database.query(soql);
    return rows.isEmpty() ? null : rows[0];
  }

  public static List<Contact> getNewestContactsWithEmail(Integer limitSize) {
    // The WHERE clause below was adjusted.  Restricting to recently modified
    // contacts with an email address could lead to an restricted result set.
    //
    //    WHERE LastModifiedDate = LAST_N_DAYS:90 AND Email != NULL
    String soql =
      'SELECT ' +
      CONTACT_FIELD_LIST +
      ', ' +
      String.join(ACCOUNT_ASSOCIATED_FIELDS, ', ') +
      ' FROM Contact ORDER BY LastModifiedDate DESC LIMIT :limitSize';
    return Database.query(soql);
  }

  public static RRARelationships__c getRraRecord(Id recordId, String recordType) {
    List<RRARelationships__c> results = [
      SELECT RelationshipJson__c, Diagnostics__c
      FROM RRARelationships__c
      WHERE RecordId__c = :recordId AND RecordType__c = :recordType
      LIMIT 1
    ];
    return results.isEmpty() ? null : results[0];
  }

  public static AsyncApexJob getActiveAsyncJob(String jobId) {
    List<AsyncApexJob> jobs = [
      SELECT Status
      FROM AsyncApexJob
      WHERE Id = :jobId AND Status IN ('Queued', 'Processing', 'Preparing')
      LIMIT 1
    ];
    return jobs.isEmpty() ? null : jobs[0];
  }
}
