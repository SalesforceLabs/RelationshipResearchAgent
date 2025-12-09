import { LightningElement, api } from "lwc";
import * as Constants from "c/rraConstants";

export default class RraSidePanel extends LightningElement {
  @api isOpen = false;
  @api nodeData = null;

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
    if (!this.nodeData) return Constants.DEFAULT_ICON;

    if (this.nodeData.recordType) {
      return Constants.RECORD_TYPE_ICON_MAP[this.nodeData.recordType] || Constants.DEFAULT_ICON;
    }

    if (this.nodeData.entityType) {
      return Constants.ENTITY_TYPE_ICON_MAP[this.nodeData.entityType] || Constants.DEFAULT_ICON;
    }

    return Constants.DEFAULT_ICON;
  }

  get entitySubtitle() {
    if (!this.nodeData) return "";

    const parts = [];

    if (this.nodeData.recordType) {
      parts.push(
        Constants.RECORD_TYPE_TITLECASE_MAP[this.nodeData.recordType] || this.nodeData.recordType
      );
    } else if (this.nodeData.entityType) {
      parts.push(this.nodeData.entityType);
    }

    if (this.nodeData.source) {
      parts.push(this.sourceLabel);
    }

    return parts.join(", ");
  }

  get sourceLabel() {
    if (!this.nodeData?.source) return "";
    return Constants.SOURCE_LABEL_MAP[this.nodeData.source] || this.nodeData.source;
  }

  get hasRecordId() {
    return !!this.nodeData?.recordId;
  }

  get needsConfirmation() {
    return this.nodeData?.source === Constants.SOURCE_TYPES.WEB && !this.nodeData?.isCrmConfirmed;
  }

  get hasCitation() {
    return !!this.nodeData?.citation;
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

    const isPerson = this.nodeData.entityType === Constants.ENTITY_TYPES.PERSON;
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
