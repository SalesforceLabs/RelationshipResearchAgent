import { LightningElement, api, track } from "lwc";

export default class RraCreateRecordModal extends LightningElement {
  @api isOpen = false;
  @api nodeData = {};

  @track isCreating = false;

  get objectApiName() {
    const entityType = this.nodeData?.entityType?.toLowerCase();

    if (entityType === "person") {
      return "Contact";
    } else {
      return "Account";
    }
  }

  get recordTypeLabel() {
    return this.objectApiName === "Contact" ? "Contact" : "Account";
  }

  get isContactForm() {
    return this.objectApiName === "Contact";
  }

  get isAccountForm() {
    return this.objectApiName === "Account";
  }

  get saveButtonLabel() {
    return this.isCreating ? "Creating..." : "Save";
  }

  get defaultFieldValues() {
    const entityName = this.nodeData?.label || this.nodeData?.id || "";

    if (this.objectApiName === "Contact") {
      const nameParts = entityName.trim().split(" ");
      const firstName = nameParts[0] || "";
      const lastName = nameParts.slice(1).join(" ") || entityName;

      return {
        FirstName: firstName,
        LastName: lastName
      };
    } else if (this.objectApiName === "Account") {
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
