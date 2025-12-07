import { LightningElement, api } from "lwc";

export default class RraSidePanel extends LightningElement {
  @api isOpen = false;
  @api nodeData = null;

  static RECORD_TYPE_MAP = {
    lead: "Lead",
    contact: "Contact",
    account: "Account",
    opportunity: "Opportunity"
  };

  static RECORD_TYPE_ICON_MAP = {
    lead: "standard:lead",
    contact: "standard:contact",
    account: "standard:account",
    opportunity: "standard:opportunity"
  };

  static ENTITY_TYPE_ICON_MAP = {
    person: "standard:contact",
    organization: "standard:account"
  };

  get panelClasses() {
    return `slds-panel slds-size_medium slds-panel_docked slds-panel_docked-right ${
      this.isOpen ? "slds-is-open" : ""
    }`;
  }

  get panelTitle() {
    return this.nodeData.strongInfluencer ? "Strong Influencer" : "Relationship";
  }

  get showStrongInfluencerIcon() {
    return this.nodeData.strongInfluencer;
  }

  get entityIcon() {
    if (!this.nodeData) return "standard:account";

    if (this.nodeData.recordType) {
      return (
        RraSidePanel.RECORD_TYPE_ICON_MAP[this.nodeData.recordType.toLowerCase()] ||
        "standard:account"
      );
    }

    if (this.nodeData.entityType) {
      return (
        RraSidePanel.ENTITY_TYPE_ICON_MAP[this.nodeData.entityType.toLowerCase()] ||
        "standard:account"
      );
    }

    return "standard:account";
  }

  get entitySubtitle() {
    if (!this.nodeData) return "";

    const parts = [];

    if (this.nodeData.recordType) {
      parts.push(
        RraSidePanel.RECORD_TYPE_MAP[this.nodeData.recordType] || this.nodeData.recordType
      );
    } else if (this.nodeData.entityType) {
      parts.push(this.formattedEntityType);
    }

    if (this.nodeData.source) {
      parts.push(this.sourceLabel);
    }

    return parts.join(", ");
  }

  get sourceLabel() {
    if (!this.nodeData?.source) return "";
    const sourceMap = {
      web: "Web Source",
      crm: "CRM",
      datacloud: "Data Cloud"
    };
    return sourceMap[this.nodeData.source] || this.nodeData.source;
  }

  get hasRecordId() {
    return !!this.nodeData?.recordId;
  }

  get needsConfirmation() {
    return this.nodeData?.source === "web" && !this.nodeData?.isCrmConfirmed;
  }

  get hasCitation() {
    return !!this.nodeData?.citation;
  }

  get formattedEntityType() {
    if (!this.nodeData?.entityType) return "";
    const type = this.nodeData.entityType;
    return type.charAt(0).toUpperCase() + type.slice(1);
  }

  get truncatedCitationURL() {
    if (!this.nodeData?.citationURL) return "";
    const url = this.nodeData.citationURL;
    const maxLength = 100;
    if (url.length <= maxLength) {
      return url;
    }
    return url.substring(0, maxLength - 3) + "...";
  }

  get contextHeading() {
    if (!this.nodeData) return "About";

    const isPerson = this.nodeData.entityType === "person";
    const prefix = isPerson ? "Who is" : "About";
    return `${prefix} ${this.nodeData.label}`;
  }

  handleClose() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  handleBackdropClick() {
    this.handleClose();
  }

  handleConfirmMatch() {
    this.dispatchEvent(
      new CustomEvent("confirmmatch", {
        detail: {
          nodeData: this.nodeData
        }
      })
    );
  }

  handleViewRecord() {
    this.dispatchEvent(
      new CustomEvent("viewrecord", {
        detail: {
          nodeData: this.nodeData
        }
      })
    );
  }

  handleCreateRecord() {
    this.dispatchEvent(
      new CustomEvent("createrecord", {
        detail: {
          nodeData: this.nodeData
        }
      })
    );
  }
}
