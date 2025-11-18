import { track, LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { loadScript } from "lightning/platformResourceLoader";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import getRelationships from "@salesforce/apex/RRAClient.getRelationships";
import createRelationships from "@salesforce/apex/RRAClient.createRelationships";
import createRelationshipsAsync from "@salesforce/apex/RRAClientAsync.createRelationshipsAsync";
import confirmCrmMatch from "@salesforce/apex/RRAClient.confirmCrmMatch";

import D3 from "@salesforce/resourceUrl/d3";
import ICONS_URL from "@salesforce/resourceUrl/symbols";
import ICONS_UTIL_URL from "@salesforce/resourceUrl/symbolsutil";

import { RraGraph, GraphDataBuilder } from "c/rraGraph";

export default class RraComponent extends NavigationMixin(LightningElement) {
  static d3Loaded = false;

  // TODO: Update the prompt to return titlecase record types instead of handling conversion here
  static RECORD_TYPE_TITLECASE = {
    lead: "Lead",
    contact: "Contact",
    account: "Account",
    opportunity: "Opportunity"
  };

  @api recordId;
  @api objectApiName;

  options = {
    width: 400,
    height: 400
  };

  diagnosticsData = null;

  // source data for d3 graph
  graphData = null;
  graphRendered = false;

  // raw relationship data from api
  relationshipData = null;

  // default to showing spinner until api calls complete
  isLoading = true;

  // UI checkbox options - defaults
  useAsyncExecution = true;
  useDeepWebSearch = true;
  useRecordContext = true;

  // modal form behavior
  showCreateRecordModal = false;
  showConfirmMatchModal = false;
  selectedNodeData = {};

  @wire(CurrentPageReference)
  currentPageReference;

  loadRelationships(data) {
    if (data === undefined || data === null || typeof data !== "string" || data.length < 1) {
      console.log("loadRelationships() called with empty data");
      return;
    }

    this.relationshipData = null;
    this.graphData = null;
    this.diagnosticsData = null;

    let record;
    try {
      record = JSON.parse(data);
    } catch (e) {
      console.error("Error parsing RRARelationships__c record", e.toString());
      return;
    }

    if (record.RelationshipJson__c === undefined) {
      // before a custom object has been created, this field will be undefined
      return;
    }

    let envelope;
    try {
      envelope = JSON.parse(record.RelationshipJson__c);
    } catch (e) {
      console.error("Error parsing RelationshipJson__c field:", e.toString());
      return;
    }

    // sort by importance for consistency/stability (top n items are selected for graph)
    if (envelope.relatedEntities) {
      envelope.relatedEntities.sort((a, b) => (b.importanceScore || 0) - (a.importanceScore || 0));
    }

    this.relationshipData = envelope;
    this.diagnosticsData = record.Diagnostics__c;
    this.graphData = new GraphDataBuilder(this.relationshipData).build({
      recordId: this.recordId,
      recordType: this.objectApiName
    });
  }

  async updateRelationships({ isNewResearch = true }) {
    if (this.useAsyncExecution) {
      const result = await createRelationshipsAsync({
        recordId: this.recordId,
        useDeepWebSearch: this.useDeepWebSearch,
        useRecordContext: this.useRecordContext,
        isNewResearch: isNewResearch
      });

      const jobInfo = JSON.parse(result);

      if (jobInfo.status === "ALREADY_QUEUED") {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Job Already Running",
            message: `A job is already processing for this record (ID: ${jobInfo.jobId})`,
            variant: "warning"
          })
        );
      } else {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Job Queued",
            message: `Relationships job queued (ID: ${jobInfo.jobId}). Check back later for results.`,
            variant: "info"
          })
        );
      }
    } else {
      const data = await createRelationships({
        recordId: this.recordId,
        useDeepWebSearch: this.useDeepWebSearch,
        useRecordContext: this.useRecordContext,
        isNewResearch: isNewResearch
      });
      this.loadRelationships(data);
      this.graphRendered = false;

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: "Relationships successfully generated",
          variant: "success"
        })
      );
    }
  }

  async loadD3() {
    if (RraComponent.d3Loaded) return true;

    try {
      await loadScript(this, D3);
      RraComponent.d3Loaded = true;
      return true;
    } catch (e) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: `Error loading D3 library: ${e.message}`,
          variant: "error"
        })
      );
    }

    return false;
  }

  renderGraph() {
    try {
      const graph = new RraGraph({
        ...this.options,
        svg: this.template.querySelector("svg.d3"),
        iconsUrl: ICONS_URL,
        iconsUtilUrl: ICONS_UTIL_URL,
        onNodeClick: this.handleNodeClick.bind(this)
      });
      graph.clear();
      graph.render(this.graphData);
    } catch (error) {
      console.error("Error rendering graph:", error.toString());
    }
  }

  // lifecycle callbacks

  // order of execution is (1) constructor (2) connectedCallback (3) renderedCallback
  // instance variables are reactive and will trigger new renders/callbacks
  // wire callbacks will be interleaved with the the above based on completion timing

  @wire(getRelationships, { recordId: "$recordId" })
  getWiredRelationships(result) {
    console.log("[RraComponent] getWiredRelationships start");

    const { data, error } = result;

    if (error != null) {
      console.error("[RraComponent] Error from getWiredRelationships:", error.toString());
      this.isLoading = false;
      return;
    }

    // LWC runtime will send empty data on initial wired call, then api data once it completes
    this.loadRelationships(data);

    if (data != null && typeof data === "string" && data.length > 0) {
      this.isLoading = false;
    }

    console.log("[RraComponent] getWiredRelationships end");
  }

  constructor() {
    console.log("[RraComponent] constructor start");
    super();
    console.log("[RraComponent] constructor end");
  }

  connectedCallback() {
    console.log("[RraComponent] connectedCallback start");

    // Load persisted checkbox values from localStorage (localized to this record)
    if (this.recordId) {
      const savedAsync = localStorage.getItem(`rra_${this.recordId}_useAsyncExecution`);
      const savedDeepWeb = localStorage.getItem(`rra_${this.recordId}_useDeepWebSearch`);
      const savedRecordContext = localStorage.getItem(`rra_${this.recordId}_useRecordContext`);

      if (savedAsync !== null) this.useAsyncExecution = savedAsync === "true";
      if (savedDeepWeb !== null) this.useDeepWebSearch = savedDeepWeb === "true";
      if (savedRecordContext !== null) this.useRecordContext = savedRecordContext === "true";
    }

    console.log("[RraComponent] connectedCallback end");
  }

  async renderedCallback() {
    console.log("[RraComponent] renderedCallback start");
    if (!(await this.loadD3())) return;

    if (!this.graphRendered && this.graphData != null) {
      this.renderGraph();
      this.graphRendered = true;
    }
    console.log("[RraComponent] renderedCallback end");
  }

  // getters

  get relationshipJson() {
    return JSON.stringify(this.relationshipData, null, 2);
  }

  get graphJson() {
    return JSON.stringify(this.graphData, null, 2);
  }

  sortObjectKeys(obj) {
    if (Array.isArray(obj)) {
      return obj.map((item) => this.sortObjectKeys(item));
    } else if (obj !== null && typeof obj === "object") {
      return Object.keys(obj)
        .sort()
        .reduce((sorted, key) => {
          sorted[key] = this.sortObjectKeys(obj[key]);
          return sorted;
        }, {});
    }
    return obj;
  }

  get diagnosticsJson() {
    if (this.diagnosticsData) {
      const diagnostics = JSON.parse(this.diagnosticsData);
      const sortedDiagnostics = this.sortObjectKeys(diagnostics);
      return JSON.stringify(sortedDiagnostics, null, 2);
    }
    return "";
  }

  get showDebug() {
    if (this.currentPageReference && this.currentPageReference.state) {
      return this.currentPageReference.state.c__rraDebug === "1";
    }
    return false;
  }

  // handlers

  async handleNodeClick(nodeData) {
    if (nodeData.recordId) {
      if (nodeData.source === "web" && !nodeData.isCrmConfirmed) {
        this.selectedNodeData = {
          ...nodeData,
          titlecaseRecordType: RraComponent.RECORD_TYPE_TITLECASE[nodeData.recordType] || ""
        };
        this.showConfirmMatchModal = true;
      } else {
        const recordUrl = await this[NavigationMixin.GenerateUrl]({
          type: "standard__recordPage",
          attributes: {
            recordId: nodeData.recordId,
            objectApiName: nodeData.recordType,
            actionName: "view"
          }
        });
        window.open(recordUrl, "_blank");
      }
    } else {
      this.selectedNodeData = {
        ...nodeData,
        titlecaseRecordType: RraComponent.RECORD_TYPE_TITLECASE[nodeData.recordType] || ""
      };
      this.showCreateRecordModal = true;
    }
  }

  handleCloseCreateRecordModal() {
    this.showCreateRecordModal = false;
    const modal = this.template.querySelector("c-rra-create-record-modal");
    if (modal) {
      modal.reset();
    }
  }

  handleCloseConfirmModal() {
    this.showConfirmMatchModal = false;
    const modal = this.template.querySelector("c-rra-confirm-match-modal");
    if (modal) {
      modal.reset();
    }
  }

  async handleConfirmMatch(event) {
    const { recordId, objectApiName, nodeId, nodeData } = event.detail;

    try {
      await confirmCrmMatch({
        recordId: this.recordId,
        entityUuid: nodeData.uuid
      });
    } catch (error) {
      console.error("Error confirming match:", error);

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: `Failed to confirm match: ${error.body.message}`,
          variant: "error"
        })
      );

      const modal = this.template.querySelector("c-rra-confirm-match-modal");
      if (modal) {
        modal.setConfirming(false);
      }
      return;
    }

    if (this.relationshipData && this.relationshipData.relatedEntities) {
      const entityToUpdate = this.relationshipData.relatedEntities.find(
        (entity) => entity.uuid === nodeData.uuid
      );
      if (entityToUpdate) {
        entityToUpdate.isCrmConfirmed = true;

        this.graphData = new GraphDataBuilder(this.relationshipData).build({
          recordId: this.recordId,
          recordType: this.objectApiName
        });

        this.renderGraph();
      }
    }

    this.dispatchEvent(
      new ShowToastEvent({
        title: "Match Confirmed",
        message: `CRM match confirmed for ${nodeData.label || nodeId}`,
        variant: "success"
      })
    );

    this.handleCloseConfirmModal();
  }

  async handleCreateRecord(event) {
    const { nodeId, objectType, formData, sourceData } = event.detail;
    const recordType = objectType;

    try {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Success",
          message: `${recordType} created successfully`,
          variant: "success"
        })
      );

      this.handleCloseCreateRecordModal();
    } catch (error) {
      console.error("Error creating record:", error);

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: `Failed to create ${recordType}: ${error.message}`,
          variant: "error"
        })
      );

      const modal = this.template.querySelector("c-rra-create-record-modal");
      if (modal) {
        modal.setCreating(false);
      }
    }
  }

  handleAsyncToggle(event) {
    this.useAsyncExecution = event.target.checked;
    if (this.recordId) {
      localStorage.setItem(`rra_${this.recordId}_useAsyncExecution`, this.useAsyncExecution);
    }
  }

  handleDeepWebSearchToggle(event) {
    this.useDeepWebSearch = event.target.checked;
    if (this.recordId) {
      localStorage.setItem(`rra_${this.recordId}_useDeepWebSearch`, this.useDeepWebSearch);
    }
  }

  handleRecordContextToggle(event) {
    this.useRecordContext = event.target.checked;
    if (this.recordId) {
      localStorage.setItem(`rra_${this.recordId}_useRecordContext`, this.useRecordContext);
    }
  }

  handleCopyRelationshipData() {
    navigator.clipboard.writeText(this.relationshipJson);
  }

  handleCopyDiagnosticsData() {
    navigator.clipboard.writeText(this.diagnosticsJson);
  }

  async handleResearchButtonClick(event) {
    if (this.isLoading) return;

    try {
      this.isLoading = true;
      const isNewResearch = event.target.dataset.isnewresearch === "1";
      await this.updateRelationships({ isNewResearch });
    } catch (error) {
      const message = error?.body?.message || error?.message || "Unknown error";
      console.error("Error reloading data:", message, error);

      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: `Error generating relationships: ${message}`,
          variant: "error"
        })
      );
    } finally {
      this.isLoading = false;
    }
  }
}
