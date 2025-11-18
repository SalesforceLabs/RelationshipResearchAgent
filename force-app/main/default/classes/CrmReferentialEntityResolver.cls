public with sharing class CrmReferentialEntityResolver {
  public static final String ObjectType_Account = 'Account';
  public static final String ObjectType_Contact = 'Contact';
  public static final String ObjectType_Opty = 'Opportunity';
  public static final String ObjectType_Lead = 'Lead';

  // Record ID prefix mapping for Account and Contact
  private static final Map<String, String> PREFIX_TO_OBJECT = new Map<String, String>{
    '001' => ObjectType_Account,
    '003' => ObjectType_Contact,
    '006' => ObjectType_Opty,
    '00Q' => ObjectType_Lead
  };

  public class RecordNotFoundException extends Exception {
  }

  public class UnknownRecordTypeException extends Exception {
  }

  public static ICrmReferentialEntity resolveById(String recordId) {
    if (String.isBlank(recordId) || recordId.length() < 3) {
      throw new RecordNotFoundException('Invalid record ID: ' + recordId);
    }

    String prefix = recordId.substring(0, 3);
    String sObjectType = PREFIX_TO_OBJECT.get(prefix);

    if (sObjectType == 'Account') {
      Account acc = CrmDatabaseSelectors.getAccountById(recordId);
      if (acc == null) {
        throw new RecordNotFoundException('No account record found for ID: ' + recordId);
      }
      return new CrmDataDtos.CompactAccount(acc);
    } else if (sObjectType == 'Contact') {
      Contact con = CrmDatabaseSelectors.getContactById(recordId);
      if (con == null) {
        throw new RecordNotFoundException('No contact record found for ID: ' + recordId);
      }
      return new CrmDataDtos.CompactContact(con);
    } else if (sObjectType == 'Opportunity') {
      Opportunity opty = CrmDatabaseSelectors.getOptyById(recordId);
      if (opty == null) {
        throw new RecordNotFoundException('No opty record found for ID: ' + recordId);
      }
      return new CrmDataDtos.CompactOpty(opty);
    } else if (sObjectType == 'Lead') {
      Lead lead = CrmDatabaseSelectors.getLeadById(recordId);
      if (lead == null) {
        throw new RecordNotFoundException('No lead record found for ID: ' + recordId);
      }
      return new CrmDataDtos.CompactLead(lead);
    }

    throw new UnknownRecordTypeException(
      'Unsupported or unknown record type for ID (' + recordId + ')'
    );
  }
}
