import { track, LightningElement, api, wire } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { loadScript } from "lightning/platformResourceLoader";
import { CurrentPageReference, NavigationMixin } from "lightning/navigation";
import { subscribe, unsubscribe, onError } from "lightning/empApi";
import { refreshApex } from "@salesforce/apex";
import getRelationships from "@salesforce/apex/RRAClient.getRelationships";
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
    width: 800,
    height: 800
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
  appendToExistingResearch = false;
  useDeepWebSearch = true;
  useRecordContext = true;
  generateSyntheticData = false;
  entityMatcherMode = "SOSL_ONLY";
  entityMatcherModeOptions = [
    { label: "SOSL Only", value: "SOSL_ONLY" },
    { label: "Datacloud Only", value: "DATACLOUD_ONLY" },
    { label: "Datacloud and SOSL, No Fallback", value: "DATACLOUD_AND_SOSL" },
    { label: "Datacloud and SOSL, Fallback Enabled", value: "DATACLOUD_AND_SOSL_FALLBACK" },
    { label: "Datacloud, Fallback on SOSL", value: "DATACLOUD_FALLBACK_SOSL" }
  ];

  // modal form behavior
  showCreateRecordModal = false;
  showConfirmMatchModal = false;
  selectedNodeData = {};

  // graph instance for zoom control
  graph = null;

  // Platform Event subscription
  subscription = {};
  channelName = "/event/RRA_Job_Complete__e";
  isResearchInProgress = false;

  // Store wire result for refresh
  wiredRelationshipsResult;

  @wire(CurrentPageReference)
  currentPageReference;

  wiredDataExists(data) {
    return typeof data === "string" && data.length > 0;
  }

  loadRelationships(data) {
    if (!this.wiredDataExists(data)) {
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
    this.graphRendered = false;
  }

  async updateRelationships() {
    const result = await createRelationshipsAsync({
      recordId: this.recordId,
      optionsJson: this.wireOptionsJson
    });

    const jobInfo = JSON.parse(result);

    if (jobInfo.status === "ALREADY_QUEUED") {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Research In Progress",
          message:
            "Research is already running for this record. Results will refresh automatically when complete.",
          variant: "warning"
        })
      );
    } else {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Research Started",
          message:
            "Your research is in progress. Results will refresh automatically when complete.",
          variant: "info"
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
      this.graph = new RraGraph({
        ...this.options,
        svg: this.template.querySelector("svg.d3"),
        iconsUrl: ICONS_URL,
        iconsUtilUrl: ICONS_UTIL_URL,
        onNodeClick: this.handleNodeClick.bind(this)
      });
      this.graph.clear();
      this.graph.render(this.graphData);
    } catch (error) {
      console.error("Error rendering graph:", error.toString());
    }
  }

  // Zoom control handlers
  handleZoomIn() {
    if (this.graph) {
      this.graph.zoomIn();
    }
  }

  handleZoomOut() {
    if (this.graph) {
      this.graph.zoomOut();
    }
  }

  handleZoomReset() {
    if (this.graph) {
      this.graph.resetZoom();
    }
  }

  // lifecycle callbacks

  // order of execution is (1) constructor (2) connectedCallback (3) renderedCallback
  // instance variables are reactive and will trigger new renders/callbacks
  // wire callbacks will be interleaved with the the above based on completion timing

  get wireOptions() {
    return {
      generateSyntheticData: this.generateSyntheticData,
      useDeepWebSearch: this.useDeepWebSearch,
      useRecordContext: this.useRecordContext,
      entityMatcherMode: this.entityMatcherMode,
      appendToExistingResearch: this.appendToExistingResearch
    };
  }

  // Wire params do not support rich data types so must use string
  get wireOptionsJson() {
    return JSON.stringify(this.wireOptions);
  }

  @wire(getRelationships, { recordId: "$recordId" })
  getWiredRelationships(result) {
    console.log(
      "[RraComponent] getWiredRelationships start",
      JSON.stringify({
        recordId: this.recordId,
        hasData: !!result.data,
        hasError: !!result.error,
        dataLength: result.data?.length,
        errorMessage: result.error?.body?.message,
        graphRendered: this.graphRendered,
        isLoading: this.isLoading
      })
    );

    // Store the result for later refresh
    this.wiredRelationshipsResult = result;

    const { data, error } = result;

    if (error != null) {
      console.error("[RraComponent] Error from getWiredRelationships:", error.toString());
      this.isLoading = false;
      return;
    }

    if (this.wiredDataExists(data)) {
      this.loadRelationships(data);
      this.isLoading = false;
    }

    console.log("[RraComponent] getWiredRelationships end");
  }

  constructor() {
    console.log("[RraComponent] constructor start");
    super();
    console.log(
      "[RraComponent] constructor end",
      JSON.stringify({
        recordId: this.recordId,
        graphRendered: this.graphRendered,
        isLoading: this.isLoading
      })
    );
  }

  connectedCallback() {
    console.log(
      "[RraComponent] connectedCallback start",
      JSON.stringify({
        recordId: this.recordId,
        graphRendered: this.graphRendered,
        isLoading: this.isLoading
      })
    );

    // Load persisted checkbox values from localStorage (localized to this record)
    if (this.recordId) {
      const savedAppendToExistingResearch = localStorage.getItem(
        `rra_${this.recordId}_appendToExistingResearch`
      );
      const savedDeepWeb = localStorage.getItem(`rra_${this.recordId}_useDeepWebSearch`);
      const savedRecordContext = localStorage.getItem(`rra_${this.recordId}_useRecordContext`);
      const savedGenerateSyntheticData = localStorage.getItem(
        `rra_${this.recordId}_generateSyntheticData`
      );
      const entityMatcherMode = localStorage.getItem(`rra_${this.recordId}_entityMatcherMode`);

      if (savedAppendToExistingResearch !== null)
        this.appendToExistingResearch = savedAppendToExistingResearch === "true";
      if (savedDeepWeb !== null) this.useDeepWebSearch = savedDeepWeb === "true";
      if (savedRecordContext !== null) this.useRecordContext = savedRecordContext === "true";
      if (savedGenerateSyntheticData !== null)
        this.generateSyntheticData = savedGenerateSyntheticData === "true";
      if (entityMatcherMode !== null) this.entityMatcherMode = entityMatcherMode;
    }

    // Subscribe to Platform Events
    this.handleSubscribe();
    this.registerErrorListener();

    console.log(
      "[RraComponent] connectedCallback end",
      JSON.stringify({
        recordId: this.recordId,
        graphRendered: this.graphRendered,
        isLoading: this.isLoading
      })
    );
  }

  disconnectedCallback() {
    console.log(
      "[RraComponent] disconnectedCallback start",
      JSON.stringify({
        recordId: this.recordId
      })
    );
    this.handleUnsubscribe();
    console.log(
      "[RraComponent] disconnectedCallback end",
      JSON.stringify({
        recordId: this.recordId
      })
    );
  }

  handlePlatformEvent(response) {
    console.log("Received Platform Event:", JSON.stringify(response));

    const payload = response.data.payload;

    if (payload.RecordId__c === this.recordId) {
      console.log("Job completed for current record");
      this.isResearchInProgress = false;

      if (payload.Status__c === "Success") {
        // Refresh the wired data, which will trigger getWiredRelationships and new graph render
        refreshApex(this.wiredRelationshipsResult).then(() => {
          this.dispatchEvent(
            new ShowToastEvent({
              title: "Research Complete",
              message: "Relationship insights have been updated",
              variant: "success"
            })
          );
        });
      } else {
        this.dispatchEvent(
          new ShowToastEvent({
            title: "Research Failed",
            message: "An error occurred during research. Please try again.",
            variant: "error"
          })
        );
      }
    }
  }

  handleSubscribe() {
    subscribe(this.channelName, -1, this.handlePlatformEvent.bind(this))
      .then((response) => {
        console.log("Successfully subscribed to channel:", response.channel);
        this.subscription = response;
      })
      .catch((error) => {
        console.error("Error subscribing to Platform Event:", error);
      });
  }

  handleUnsubscribe() {
    unsubscribe(this.subscription, (response) => {
      console.log("Unsubscribed from channel:", response);
    });
  }

  registerErrorListener() {
    onError((error) => {
      console.error("Streaming API error:", JSON.stringify(error));
    });
  }

  async renderedCallback() {
    console.log(
      "[RraComponent] renderedCallback start",
      JSON.stringify({
        recordId: this.recordId,
        graphRendered: this.graphRendered,
        hasGraphData: this.graphData != null,
        graphDataNodeCount: this.graphData?.nodes?.length,
        isLoading: this.isLoading
      })
    );
    if (!(await this.loadD3())) return;

    if (!this.graphRendered && this.graphData != null) {
      this.renderGraph();
      this.graphRendered = true;
    }
    console.log(
      "[RraComponent] renderedCallback end",
      JSON.stringify({
        recordId: this.recordId,
        graphRendered: this.graphRendered,
        hasGraphData: this.graphData != null,
        graphDataNodeCount: this.graphData?.nodes?.length,
        isLoading: this.isLoading
      })
    );
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

  handleGenerateSyntheticDataToggle(event) {
    this.generateSyntheticData = event.target.checked;
    if (this.recordId) {
      localStorage.setItem(
        `rra_${this.recordId}_generateSyntheticData`,
        this.generateSyntheticData
      );
    }
  }

  handleAppendToExistingResearchToggle(event) {
    this.appendToExistingResearch = event.target.checked;
    if (this.recordId) {
      localStorage.setItem(
        `rra_${this.recordId}_appendToExistingResearch`,
        this.appendToExistingResearch
      );
    }
  }

  handleEntityMatcherModeChange(event) {
    this.entityMatcherMode = event.target.value;
    if (this.recordId) {
      localStorage.setItem(`rra_${this.recordId}_entityMatcherMode`, this.entityMatcherMode);
    }
  }

  handleCopyRelationshipData() {
    navigator.clipboard.writeText(this.relationshipJson);
  }

  handleCopyDiagnosticsData() {
    navigator.clipboard.writeText(this.diagnosticsJson);
  }

  async handleResearchButtonClick() {
    if (this.isLoading) return;

    try {
      this.isLoading = true;
      await this.updateRelationships();
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
