import { LightningElement, api, track } from "lwc";
import * as Constants from "c/rraConstants";

export default class RraCreateRecordModal extends LightningElement {
  @api isOpen = false;
  @api nodeData = {};

  @track isCreating = false;

  get objectApiName() {
    return this.nodeData.entityType === Constants.ENTITY_TYPES.PERSON
      ? Constants.RECORD_TYPES.CONTACT
      : Constants.RECORD_TYPES.ACCOUNT;
  }

  get recordTypeLabel() {
    return this.objectApiName;
  }

  get isContactForm() {
    return this.objectApiName === Constants.RECORD_TYPES.CONTACT;
  }

  get isAccountForm() {
    return this.objectApiName === Constants.RECORD_TYPES.ACCOUNT;
  }

  get saveButtonLabel() {
    return this.isCreating ? "Creating..." : "Save";
  }

  get defaultFieldValues() {
    const entityName = this.nodeData?.label || this.nodeData?.id || "";

    if (this.isContactForm) {
      const nameParts = entityName.trim().split(" ");
      const firstName = nameParts[0] || "";
      const lastName = nameParts.slice(1).join(" ") || entityName;

      return {
        FirstName: firstName,
        LastName: lastName
      };
    } else if (this.isAccountForm) {
      return {
        Name: entityName
      };
    }

    return {};
  }

  handleRecordSuccess(event) {
    const recordId = event.detail.id;

    const successEvent = new CustomEvent("create", {
      detail: {
        recordId: recordId,
        objectType: this.objectApiName,
        nodeId: this.nodeData.id,
        sourceData: {
          entityName: this.nodeData.id || this.nodeData.label,
          context: this.nodeData.context,
          citation: this.nodeData.citation,
          citationURL: this.nodeData.citationURL
        }
      }
    });

    this.dispatchEvent(successEvent);
  }

  handleRecordError(event) {
    console.error("Error creating record:", event.detail);
    this.isCreating = false;
  }

  handleSave() {
    this.isCreating = true;
    const recordEditForm = this.template.querySelector("lightning-record-edit-form");
    if (recordEditForm) {
      recordEditForm.submit();
    }
  }

  handleClose() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  @api
  reset() {
    this.isCreating = false;
  }

  @api
  setCreating(value) {
    this.isCreating = value;
  }
}
