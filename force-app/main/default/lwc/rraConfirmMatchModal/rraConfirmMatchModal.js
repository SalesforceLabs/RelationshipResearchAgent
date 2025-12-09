import { LightningElement, api, track } from "lwc";
import * as Constants from "c/rraConstants";

export default class RraConfirmMatchModal extends LightningElement {
  @api isOpen = false;
  @api recordId = null;
  @api objectApiName = null;
  @api nodeData = {};

  @track isConfirming = false;

  get isContact() {
    return this.nodeData?.titlecaseRecordType === Constants.RECORD_TYPES.CONTACT;
  }

  get isAccount() {
    return this.nodeData?.titlecaseRecordType === Constants.RECORD_TYPES.ACCOUNT;
  }

  get isLead() {
    return this.nodeData?.titlecaseRecordType === Constants.RECORD_TYPES.LEAD;
  }

  get isOpportunity() {
    return this.nodeData?.titlecaseRecordType === Constants.RECORD_TYPES.OPPORTUNITY;
  }

  get confirmButtonLabel() {
    return this.isConfirming ? "Confirming..." : "Confirm";
  }

  handleConfirm() {
    this.isConfirming = true;

    const confirmEvent = new CustomEvent("confirm", {
      detail: {
        recordId: this.recordId,
        objectApiName: this.objectApiName,
        nodeId: this.nodeData.id,
        nodeData: this.nodeData
      }
    });

    this.dispatchEvent(confirmEvent);
  }

  handleClose() {
    this.dispatchEvent(new CustomEvent("close"));
  }

  @api
  reset() {
    this.isConfirming = false;
  }

  @api
  setConfirming(value) {
    this.isConfirming = value;
  }
}
