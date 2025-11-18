public with sharing class CrmRelationshipInsightsPayloadAssembler implements Database.AllowsCallouts {
  private static final Integer ACCOUNT_LIMIT = 300;
  private static final Integer CONTACT_LIMIT = 2000;

  public CrmRelationshipInsightsPayloadAssembler() {
  }

  public CrmDataDtos.CrmDataPayload build() {
    CrmDataDtos.CrmDataPayload payload = new CrmDataDtos.CrmDataPayload();

    List<Account> accounts = CrmDatabaseSelectors.getNewestAccounts(ACCOUNT_LIMIT);
    for (Account acc : accounts) {
      payload.accounts.add(new CrmDataDtos.CompactAccount(acc));
    }

    List<Contact> contacts = CrmDatabaseSelectors.getNewestContactsWithEmail(CONTACT_LIMIT);
    for (Contact con : contacts) {
      payload.contacts.add(new CrmDataDtos.CompactContact(con));
    }

    return payload;
  }
}
