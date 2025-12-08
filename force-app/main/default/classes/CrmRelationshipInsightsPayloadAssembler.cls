public with sharing class CrmRelationshipInsightsPayloadAssembler implements Database.AllowsCallouts {
  private static final Integer ACCOUNT_LIMIT = 300;
  private static final Integer CONTACT_LIMIT = 2000;

  final CrmDataDtos.CrmDataPayload payload = new CrmDataDtos.CrmDataPayload();
  final Set<String> addedIds = new Set<String>();
  public CrmDataDtos.CrmDataPayload getPayload() {
    return payload;
  }

  public Integer size() {
    return payload.size();
  }

  // Builds payload with most recently created records (eg fallback when not enough records found).
  public void buildWithNewestRecords() {
    List<Account> accounts = CrmDatabaseSelectors.getNewestAccounts(ACCOUNT_LIMIT);

    for (Account acc : accounts) {
      if (addedIds.add(acc.Id)) {
        payload.accounts.add(new CrmDataDtos.CompactAccount(acc));
      }
    }

    List<Contact> contacts = CrmDatabaseSelectors.getNewestContactsWithEmail(CONTACT_LIMIT);
    for (Contact con : contacts) {
      if (addedIds.add(con.Id)) {
        payload.contacts.add(new CrmDataDtos.CompactContact(con));
      }
    }
  }

  Set<Id> queryAccounts = new Set<Id>();
  Set<Id> queryContacts = new Set<Id>();

  public void addEntity(ICrmReferentialEntity entity) {
    String accountId = entity.getAccountId();
    if (!String.isBlank(accountId)) {
      queryAccounts.add(accountId);
    }
    String contactId = entity.getContactId();
    if (!String.isBlank(contactId)) {
      queryContacts.add(contactId);
    }
  }

  public void build() {
    if (queryAccounts.size() > 0) {
      List<Account> dbAccounts = CrmDatabaseSelectors.getAccountsByIds(queryAccounts);
      for (Account a : dbAccounts) {
        if (addedIds.add(a.Id)) {
          payload.accounts.add(new CrmDataDtos.CompactAccount(a));
        }
      }
    }
    if (queryAccounts.size() > 0 || queryContacts.size() > 0) {
      List<Contact> dbContacts = CrmDatabaseSelectors.getContactsByIds(
        queryContacts,
        queryAccounts
      );
      for (Contact c : dbContacts) {
        if (addedIds.add(c.Id)) {
          payload.contacts.add(new CrmDataDtos.CompactContact(c));
        }
      }
    }
  }
}
