import { LightningElement, api, track } from "lwc";
import * as Constants from "c/rraConstants";

export default class RraConfirmMatchModal extends LightningElement {
  @api isOpen = false;
  @api recordId = null;
  @api nodeData = {};

  @track isConfirming = false;

  get titlecaseRecordType() {
    return Constants.RECORD_TYPE_TITLECASE_MAP[this.nodeData?.recordType] || "";
  }

  get isContact() {
    return this.titlecaseRecordType === Constants.RECORD_TYPES.CONTACT;
  }

  get isAccount() {
    return this.titlecaseRecordType === Constants.RECORD_TYPES.ACCOUNT;
  }

  get isLead() {
    return this.titlecaseRecordType === Constants.RECORD_TYPES.LEAD;
  }

  get isOpportunity() {
    return this.titlecaseRecordType === Constants.RECORD_TYPES.OPPORTUNITY;
  }

  get confirmButtonLabel() {
    return this.isConfirming ? "Confirming..." : "Confirm";
  }

  handleConfirm() {
    this.isConfirming = true;

    const confirmEvent = new CustomEvent("confirm", {
      detail: {
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
