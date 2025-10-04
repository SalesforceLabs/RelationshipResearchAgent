// This class holds the Data Transfer Objects (DTOs) for compact serialization
// and for parsing the structured response from the LLM.
public with sharing class CrmDataDtos {
  // Structure for the data we send TO the LLM
  public class CrmDataPayload {
    public List<CompactAccount> accounts;
    public List<CompactContact> contacts;

    public CrmDataPayload() {
      this.accounts = new List<CompactAccount>();
      this.contacts = new List<CompactContact>();
    }
    public Integer size() {
      return accounts.size() + contacts.size();
    }
    public List<Object> toObjectList() {
      List<Object> elements = new List<Object>();

      elements.addAll((List<Object>) JSON.deserializeUntyped(JSON.serialize(accounts)));
      elements.addAll((List<Object>) JSON.deserializeUntyped(JSON.serialize(contacts)));

      return elements;
    }
  }

  // Compact Account representation
  public class CompactAccount implements ICrmReferentialEntity {
    public String id;
    public String type;
    public String name;
    public String website;
    public String country;
    public String city;
    public String industry;
    public String description;

    public CompactAccount(Account acc) {
      this.id = acc.Id;
      this.type = 'account';
      this.name = acc.Name;
      this.website = acc.Website;
      this.country = acc.BillingCountry;
      this.city = acc.BillingCity;
      this.industry = acc.Industry;
      this.description = acc.Description;
    }

    public String getSobjectType() {
      return 'Account';
    }

    public String getId() {
      return id;
    }

    public String getName() {
      return name;
    }

    public String serialize() {
      return JSON.serialize(this);
    }
    public string getAccountId() {
      return id;
    }
    public string getContactId() {
      return '';
    }
  }

  public static String getFullContactName(Contact con) {
    if (!String.isBlank(con.Name)) {
      return con.Name;
    }
    String fullName = '';
    if (!String.isBlank(con.FirstName)) {
      fullName += con.FirstName;
    }
    if (!String.isBlank(con.LastName)) {
      if (fullName != '')
        fullName += ' ';
      fullName += con.LastName;
    }
    return fullName;
  }

  public static String getFullContactName(Contact con) {
    String fullName = '';
    if (!String.isBlank(con.FirstName)) {
      fullName += con.FirstName;
    }
    if (!String.isBlank(con.LastName)) {
      if (fullName != '')
        fullName += ' ';
      fullName += con.LastName;
    }
    return fullName;
  }

  public class CompactContact implements ICrmReferentialEntity {
    public String id;
    public String type;
    public String name;
    public String email;
    public String accountId;
    public String accountName;
    public String accountIndustry;
    public String title;
    public String department;
    public String description;

    public CompactContact(Contact con) {
      this.id = con.Id;
      this.type = 'contact';
      this.name = getFullContactName(con);
      this.email = con.Email;
      this.accountId = con.AccountId;
      this.accountName = con.Account?.Name;
      this.accountIndustry = con.Account?.Industry;
      this.title = con.Title;
      this.department = con.Department;
      this.description = con.Description;
    }

    public String getSobjectType() {
      return 'Contact';
    }

    public String getId() {
      return id;
    }

    public String getName() {
      return name;
    }

    public String serialize() {
      return JSON.serialize(this);
    }
    public string getAccountId() {
      return accountId;
    }
    public string getContactId() {
      return id;
    }
  }

  public class CompactOpty implements ICrmReferentialEntity {
    public String id;
    public String type;
    public String name;
    public String accountId;
    public String accountName;
    public String accountIndustry;
    public String contactId;
    public String ownerId;
    public String description;

    public CompactOpty(Opportunity opty) {
      this.id = opty.Id;
      this.type = 'opportunity';
      this.accountId = opty.AccountId;
      this.accountName = opty.Account?.Name;
      this.accountIndustry = opty.Account?.Industry;
      this.contactId = opty.ContactId;
      this.ownerId = opty.OwnerId; // owner is User object
      this.name = opty.Name;
      this.description = opty.Description;
    }

    public String getSobjectType() {
      return 'Opportunity';
    }

    public String getId() {
      return id;
    }

    public String getName() {
      return name;
    }

    public String getDescription() {
      return description;
    }

    public String serialize() {
      return JSON.serialize(this);
    }
    public string getAccountId() {
      return accountId;
    }
    public string getContactId() {
      return contactId;
    }
  }

  public class CompactLead implements ICrmReferentialEntity {
    public String id;
    public String type;
    public String name;
    public String company;
    public String title;
    public String industry;
    public String city;
    public String state;
    public String country;
    public String email;
    public String phone;

    public String ownerId;

    public CompactLead(Lead lead) {
      this.id = lead.Id;
      this.type = 'lead';
      this.name = lead.Name;
      this.company = lead.company;
      this.title = lead.title;
      this.industry = lead.Industry;
      this.city = lead.City;
      this.state = lead.State;
      this.country = lead.Country;
      this.email = lead.email;
      this.phone = lead.phone;

      this.ownerId = lead.ownerId;
    }

    public String getSobjectType() {
      return 'Lead';
    }

    public String getId() {
      return id;
    }

    public String getName() {
      return name;
    }

    public String getCompany() {
      return company;
    }

    public String getTitle() {
      return title;
    }

    public String getEmail() {
      return email;
    }

    public String getPhone() {
      return phone;
    }

    public String getOwnerId() {
      return ownerId;
    }

    public String serialize() {
      return JSON.serialize(this);
    }
    public string getAccountId() {
      return '';
    }
    public string getContactId() {
      return '';
    }
  }
}
