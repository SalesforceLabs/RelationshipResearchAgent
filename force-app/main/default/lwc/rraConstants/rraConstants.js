// Record Types
export const ENTITY_TYPES = {
  PERSON: "Person",
  ORGANIZATION: "Organization"
};

export const RECORD_TYPES = {
  LEAD: "Lead",
  CONTACT: "Contact",
  ACCOUNT: "Account",
  OPPORTUNITY: "Opportunity"
};

// TODO: Update the prompt to return titlecase record types instead of requiring this map
export const RECORD_TYPE_TITLECASE_MAP = {
  lead: RECORD_TYPES.LEAD,
  contact: RECORD_TYPES.CONTACT,
  account: RECORD_TYPES.ACCOUNT,
  opportunity: RECORD_TYPES.OPPORTUNITY
};

// Source Types
export const SOURCE_TYPES = {
  WEB: "web",
  CRM: "crm",
  DATACLOUD: "datacloud"
};

export const SOURCE_LABEL_MAP = {
  [SOURCE_TYPES.WEB]: "Web Source",
  [SOURCE_TYPES.CRM]: "CRM",
  [SOURCE_TYPES.DATACLOUD]: "Data Cloud"
};

// Icons
export const ICONS = {
  ACCOUNT: "standard:account",
  CONTACT: "standard:contact",
  LEAD: "standard:lead",
  OPPORTUNITY: "standard:opportunity"
};

export const DEFAULT_ICON = ICONS.ACCOUNT;

export const ENTITY_TYPE_ICON_MAP = {
  [ENTITY_TYPES.PERSON]: ICONS.CONTACT,
  [ENTITY_TYPES.ORGANIZATION]: ICONS.ACCOUNT
};

export const RECORD_TYPE_ICON_MAP = {
  lead: ICONS.LEAD,
  contact: ICONS.CONTACT,
  account: ICONS.ACCOUNT,
  opportunity: ICONS.OPPORTUNITY
};
