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

  get isEdge() {
    return this.nodeData?.isEdge === true;
  }

  get anchorNode() {
    return this.nodeData?.anchorNode;
  }

  get targetNode() {
    return this.nodeData?.targetNode;
  }

  get panelTitle() {
    if (this.isEdge) {
      return "Relationship";
    }
    return this.targetNode?.isStrongInfluencer ? "Strong Influencer" : "Relationship";
  }

  get showStrongInfluencerIcon() {
    return !this.isEdge && this.targetNode?.isStrongInfluencer;
  }

  get anchorIcon() {
    return this.nodeIcon(this.anchorNode);
  }

  get entityIcon() {
    return this.nodeIcon(this.targetNode);
  }

  nodeIcon(node) {
    if (!node) return Constants.DEFAULT_ICON;

    if (node.recordType) {
      // lowercase needed because anchor node has titlecase record type while target entity does not
      return (
        Constants.RECORD_TYPE_ICON_MAP[node.recordType.toLowerCase()] || Constants.DEFAULT_ICON
      );
    }

    if (node.entityType) {
      return Constants.ENTITY_TYPE_ICON_MAP[node.entityType] || Constants.DEFAULT_ICON;
    }

    return Constants.DEFAULT_ICON;
  }

  get anchorSubtitle() {
    return this.buildSubtitle(this.anchorNode);
  }

  get entitySubtitle() {
    return this.buildSubtitle(this.targetNode);
  }

  buildSubtitle(node) {
    if (!node) return "";

    const parts = [];

    if (node.recordType) {
      parts.push(
        Constants.RECORD_TYPE_TITLECASE_MAP[node.recordType.toLowerCase()] || node.recordType
      );
    } else if (node.entityType) {
      parts.push(node.entityType);
    }

    if (node.source) {
      parts.push(this.sourceLabel);
    }

    return parts.join(", ");
  }

  get sourceLabel() {
    if (!this.targetNode?.source) return "";
    return Constants.SOURCE_LABEL_MAP[this.targetNode.source] || this.targetNode.source;
  }

  nodeSourceLabel(node) {
    if (!node.source) return "";
    return Constants.SOURCE_LABEL_MAP[node] || source;
  }

  get hasRecordId() {
    return !!this.targetNode?.recordId;
  }

  get needsConfirmation() {
    return (
      this.targetNode?.source === Constants.SOURCE_TYPES.WEB && !this.targetNode?.isCrmConfirmed
    );
  }

  get hasCitation() {
    return !!this.targetNode?.citation;
  }

  get truncatedCitationURL() {
    if (!this.targetNode?.citationURL) return "";
    const url = this.targetNode.citationURL;
    const maxLength = 100;
    if (url.length <= maxLength) {
      return url;
    }
    return url.substring(0, maxLength - 3) + "...";
  }

  get contextHeading() {
    if (!this.targetNode) return "About";

    const isPerson = this.targetNode.entityType === Constants.ENTITY_TYPES.PERSON;
    const prefix = isPerson ? "Who is" : "About";
    return `${prefix} ${this.targetNode.label}`;
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
          nodeData: this.targetNode
        }
      })
    );
  }

  handleViewRecord() {
    this.dispatchEvent(
      new CustomEvent("viewrecord", {
        detail: {
          nodeData: this.targetNode
        }
      })
    );
  }

  handleCreateRecord() {
    this.dispatchEvent(
      new CustomEvent("createrecord", {
        detail: {
          nodeData: this.targetNode
        }
      })
    );
  }
}
