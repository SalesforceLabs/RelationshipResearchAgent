/* global d3 */

export class RraGraph {
  static BADGE_BACKGROUND_MIN_RADIUS = 6;
  static LINK_BADGE_SIZE = 12;
  static PLUS_BADGE_SIZE = 8;
  static EDGE_ICON_SIZE = 12;
  static EDGE_ICON_BG_RADIUS = 8;

  static defaultOptions = {
    // CSS selector or SVG element
    svg: "svg",
    width: 800,
    height: 800,

    // Geometry
    radius: 20, // base node radius (for layout calculations)
    shellHeight: 40, // height of node shells (rounded rectangles)
    shellPadding: 12, // horizontal padding inside shells
    shellIconTextGap: 8, // gap between icon and text
    shellBorderRadius: 20, // border radius for shell corners
    canvasMargin: 60, // margin from canvas edge
    startAngle: -Math.PI / 2, // start at 12 o'clock

    // Force simulation settings
    orbitRadius: 250, // target radius for first-degree nodes
    minEdgeLength: 100, // minimum edge length to ensure icons are visible
    shellGap: 30, // gap between adjacent node shells

    // Icon sprite (Salesforce symbols.svg)
    // Refer to README for instructions on how to obtain this asset.
    iconsUrl: "",

    iconSize: 22, // width/height of the <use> glyph

    // Label sizing
    maxLabelChars: 20,

    // Zoom settings
    minZoom: 0.3,
    maxZoom: 3,

    onNodeClick: null // callback for node click events
  };

  // Mapping between entity type and SLDS icon id.
  static entityTypeToIconId = Object.freeze({
    organization: "account",
    person: "contact"
  });

  // Mapping between record type and SLDS icon id.
  static recordTypeToIconId = Object.freeze({
    account: "account",
    opportunity: "account",
    contact: "contact",
    lead: "contact"
  });

  static DEFAULT_ENTITY_ICON = "entity";

  options = {};
  simulation = null;
  zoomBehavior = null;
  currentTransform = null;

  constructor(options) {
    this.options = { ...RraGraph.defaultOptions, ...options };
    this.currentTransform = d3.zoomIdentity;
  }

  clear() {
    const { svg } = this.options;
    // Stop any running simulation
    if (this.simulation) {
      this.simulation.stop();
      this.simulation = null;
    }
    while (svg.firstChild) svg.removeChild(svg.firstChild);
  }

  getIconIdForNode(d) {
    let icon = null;
    if (d.recordType) {
      icon = RraGraph.recordTypeToIconId[d.recordType.toLowerCase()];
    } else if (d.entityType) {
      icon = RraGraph.entityTypeToIconId[d.entityType.toLowerCase()];
    }
    return icon || RraGraph.DEFAULT_ENTITY_ICON;
  }

  getCrmBadgeIconId() {
    return "link";
  }

  getIconUrl(icon) {
    return `${this.options.iconsUrl}#${icon}`;
  }

  getIconUtilUrl(icon) {
    return `${this.options.iconsUtilUrl}#${icon}`;
  }

  // Calculate node dimensions based on label text
  _calculateNodeDimensions(svg, nodes, getLabelText) {
    const { iconSize, shellPadding, shellIconTextGap, shellHeight } = this.options;

    nodes.forEach((node) => {
      const labelWidth = measureLabelMetrics(svg, [getLabelText(node)], {
        labelClass: "node-label"
      }).maxLabelWidth;
      // Include badge button space for non-focus nodes (40px for button + spacing)
      const badgeSpace = node.isFocus ? 0 : 40;
      node.shellWidth =
        shellPadding + iconSize + shellIconTextGap + labelWidth + shellPadding + badgeSpace;
      node.shellHalfWidth = node.shellWidth / 2;
      node.shellHalfHeight = shellHeight / 2;
      // Collision radius for force simulation (use the larger dimension)
      node.collisionRadius = Math.max(node.shellHalfWidth, node.shellHalfHeight) + 5;
    });
  }

  // Compute initial positions for nodes in a radial layout
  _initializePositions(nodes) {
    const { width, height, startAngle, orbitRadius } = this.options;

    const cx = width / 2;
    const cy = height / 2;

    const focus = nodes.find((n) => n.isFocus) ?? nodes[0];
    const related = nodes.filter((n) => n !== focus);
    const N = related.length;

    // Place focus node at center
    if (focus) {
      focus.x = cx;
      focus.y = cy;
      focus.fx = cx; // Fix focus node position
      focus.fy = cy;
      focus.depth = 0;
    }

    // Calculate radius that ensures nodes don't overlap
    const totalArcNeeded = related.reduce(
      (sum, node) => sum + node.shellWidth + this.options.shellGap,
      0
    );
    const radiusFromArc = totalArcNeeded / (2 * Math.PI);
    const targetRadius = Math.max(orbitRadius, radiusFromArc, this.options.minEdgeLength);

    // Initialize positions for related nodes
    if (N > 0) {
      related.forEach((node, i) => {
        const theta = startAngle + (2 * Math.PI * i) / N;
        node.x = cx + targetRadius * Math.cos(theta);
        node.y = cy + targetRadius * Math.sin(theta);
        node.depth = 1; // First-degree nodes
        node.targetRadius = targetRadius;
      });
    }

    return { targetRadius };
  }

  // Create D3 force simulation
  _createSimulation(nodes, links, targetRadius) {
    const { width, height } = this.options;
    const cx = width / 2;
    const cy = height / 2;

    // Create simulation with forces
    this.simulation = d3
      .forceSimulation(nodes)
      // Radial force: pull first-degree nodes to target orbit
      .force(
        "radial",
        d3
          .forceRadial((d) => (d.isFocus ? 0 : targetRadius), cx, cy)
          .strength((d) => (d.isFocus ? 0 : 0.8))
      )
      // Collision force: prevent node overlaps
      .force(
        "collision",
        d3.forceCollide().radius((d) => d.collisionRadius)
      )
      // Link force: maintain edge connections (optional, for stability)
      .force(
        "link",
        d3
          .forceLink(links)
          .id((d) => d.id)
          .distance(targetRadius)
          .strength(0.1)
      )
      // Gentle repulsion between nodes
      .force("charge", d3.forceManyBody().strength(-50))
      .alphaDecay(0.05) // Slower decay for smoother settling
      .velocityDecay(0.4);

    return this.simulation;
  }

  // Set up zoom and pan behavior
  _setupZoom(svg, rootGroup) {
    const { minZoom, maxZoom } = this.options;

    this.zoomBehavior = d3
      .zoom()
      .scaleExtent([minZoom, maxZoom])
      .on("start", () => {
        svg.style("cursor", "grabbing");
      })
      .on("zoom", (event) => {
        this.currentTransform = event.transform;
        rootGroup.attr("transform", event.transform);
      })
      .on("end", () => {
        svg.style("cursor", "grab");
      });

    svg.call(this.zoomBehavior);

    // Set initial grab cursor on canvas
    svg.style("cursor", "grab");

    // Double-click to reset zoom
    svg.on("dblclick.zoom", () => {
      svg.transition().duration(300).call(this.zoomBehavior.transform, d3.zoomIdentity);
    });
  }

  render(data) {
    const {
      svg: svgSelector,
      width,
      height,
      iconSize,
      shellHeight,
      shellPadding,
      shellIconTextGap,
      shellBorderRadius,
      maxLabelChars
    } = this.options;

    const svg = d3.select(svgSelector).attr("width", width).attr("height", height);

    const getLabelText = (d) => {
      const t = d.label ?? d.id;
      return t.length > maxLabelChars ? t.slice(0, maxLabelChars) + "…" : t;
    };

    // Calculate node dimensions
    this._calculateNodeDimensions(svg, data.nodes, getLabelText);

    // Initialize positions
    const { targetRadius } = this._initializePositions(data.nodes);

    // Create node map for links
    const nodeById = new Map(data.nodes.map((n) => [n.id, n]));

    // Process links
    const links = (data.links || [])
      .map((link) => {
        const source = nodeById.get(link.source);
        const target = nodeById.get(link.target);
        if (!source || !target) {
          console.warn("Unknown nodes in link", { link, source, target });
          return null;
        }
        return { ...link, source, target };
      })
      .filter(Boolean);

    // Create root group for zoom/pan
    const rootGroup = svg.append("g").attr("class", "graph-root");

    // Set up zoom behavior
    this._setupZoom(svg, rootGroup);

    // Create simulation
    const simulation = this._createSimulation(data.nodes, links, targetRadius);

    // Render links
    const linkGroup = rootGroup.append("g").attr("class", "links");

    const linkLines = linkGroup
      .selectAll("line")
      .data(links)
      .enter()
      .append("line")
      .attr("class", (d) => `link-line ${d.isCrmLink ? "link-crm" : "link-default"}`);

    // Render edge badges (icons on edges)
    const edgeBadgeGroup = rootGroup.append("g").attr("class", "edge-badges");

    const edgeBadges = edgeBadgeGroup
      .selectAll("g")
      .data(links)
      .enter()
      .append("g")
      .attr("class", "edge-badge");

    // White background circle for edge icon
    edgeBadges
      .append("circle")
      .attr("r", RraGraph.EDGE_ICON_BG_RADIUS)
      .attr("class", "edge-badge-bg");

    // Icon for CRM links
    edgeBadges
      .filter((d) => d.isCrmLink)
      .append("use")
      .attr("href", this.getIconUtilUrl("salesforce1"))
      .attr("width", RraGraph.EDGE_ICON_SIZE)
      .attr("height", RraGraph.EDGE_ICON_SIZE)
      .attr("x", -RraGraph.EDGE_ICON_SIZE / 2)
      .attr("y", -RraGraph.EDGE_ICON_SIZE / 2)
      .attr("class", "edge-icon edge-icon-crm");

    // Icon for web links
    edgeBadges
      .filter((d) => !d.isCrmLink)
      .append("use")
      .attr("href", this.getIconUtilUrl("world"))
      .attr("width", RraGraph.EDGE_ICON_SIZE)
      .attr("height", RraGraph.EDGE_ICON_SIZE)
      .attr("x", -RraGraph.EDGE_ICON_SIZE / 2)
      .attr("y", -RraGraph.EDGE_ICON_SIZE / 2)
      .attr("class", "edge-icon edge-icon-web");

    // Render nodes
    const nodeGroup = rootGroup.append("g").attr("class", "nodes");

    const nodeElements = nodeGroup
      .selectAll("g")
      .data(data.nodes)
      .join("g")
      .attr("class", "node")
      .style("cursor", "default")
      .on("click", (event, d) => {
        if (this.options.onNodeClick) {
          this.options.onNodeClick(d);
        }
      });

    // Node shell background (rounded rectangle)
    nodeElements
      .append("rect")
      .attr("x", (d) => -d.shellHalfWidth)
      .attr("y", (d) => -d.shellHalfHeight)
      .attr("width", (d) => d.shellWidth)
      .attr("height", shellHeight)
      .attr("rx", shellBorderRadius)
      .attr("ry", shellBorderRadius)
      .attr("class", (d) => {
        const cl = ["node-shell"];
        if (d.isFocus) cl.push("node-shell--focus");
        if (d.isFocus || d.isCrmLink) {
          cl.push("node-crm");
          if (d.recordType) cl.push(`node-${d.recordType.toLowerCase()}`);
        }
        return cl.join(" ");
      });

    // Colored circle background for icon
    nodeElements
      .append("circle")
      .attr("r", iconSize / 2)
      .attr("cx", (d) => -d.shellHalfWidth + shellPadding + iconSize / 2)
      .attr("cy", 0)
      .attr("class", (d) => {
        const cl = ["node-icon-bg"];
        if (d.isFocus || d.isCrmLink) {
          cl.push("node-icon-bg-crm");
          if (d.recordType) cl.push(`node-icon-bg-${d.recordType.toLowerCase()}`);
        }
        return cl.join(" ");
      });

    // Icon on the left side of the shell
    nodeElements
      .append("use")
      .attr("href", (d) => this.getIconUrl(this.getIconIdForNode(d)))
      .attr("width", iconSize)
      .attr("height", iconSize)
      .attr("x", (d) => -d.shellHalfWidth + shellPadding)
      .attr("y", -iconSize / 2)
      .attr("class", "node-icon");

    // Text label - with help cursor for tooltip hint
    nodeElements
      .append("text")
      .attr("class", "node-label")
      .attr("x", (d) => -d.shellHalfWidth + shellPadding + iconSize + shellIconTextGap)
      .attr("y", 0)
      .attr("text-anchor", "start")
      .attr("dominant-baseline", "central")
      .style("pointer-events", "auto")
      .style("cursor", "help")
      .text((d) => getLabelText(d));

    // Badge overlay for non-focus nodes
    const badgeG = nodeElements
      .filter((d) => !d.isFocus)
      .append("g")
      .attr("class", "node-badge");

    // White circle background for badge button - with pointer cursor
    badgeG
      .append("circle")
      .attr("r", 14)
      .attr("cx", (d) => d.shellHalfWidth - 20)
      .attr("cy", 0)
      .attr("class", "node-badge-bg")
      .style("cursor", "pointer");

    // Link badge icon for CRM records
    badgeG
      .filter((d) => d.recordId)
      .append("use")
      .attr("href", this.getIconUrl("link"))
      .attr("width", 16)
      .attr("height", 16)
      .attr("x", (d) => d.shellHalfWidth - 20 - 8)
      .attr("y", -8)
      .attr("class", "node-badge-icon");

    // Plus sign badge icon for new records
    badgeG
      .filter((d) => !d.recordId)
      .append("use")
      .attr("href", this.getIconUtilUrl("add"))
      .attr("width", 16)
      .attr("height", 16)
      .attr("x", (d) => d.shellHalfWidth - 20 - 8)
      .attr("y", -8)
      .attr("class", "node-badge-icon");

    // Update positions on simulation tick
    simulation.on("tick", () => {
      // Update link positions
      linkLines
        .attr("x1", (d) => d.source.x)
        .attr("y1", (d) => d.source.y)
        .attr("x2", (d) => d.target.x)
        .attr("y2", (d) => d.target.y);

      // Update edge badge positions (midpoint of edge)
      edgeBadges.attr("transform", (d) => {
        const midX = (d.source.x + d.target.x) / 2;
        const midY = (d.source.y + d.target.y) / 2;
        return `translate(${midX},${midY})`;
      });

      // Update node positions
      nodeElements.attr("transform", (d) => `translate(${d.x},${d.y})`);
    });

    // Run simulation for a bit then stop for static display
    simulation.tick(150);
    simulation.stop();

    // Final position update
    linkLines
      .attr("x1", (d) => d.source.x)
      .attr("y1", (d) => d.source.y)
      .attr("x2", (d) => d.target.x)
      .attr("y2", (d) => d.target.y);

    edgeBadges.attr("transform", (d) => {
      const midX = (d.source.x + d.target.x) / 2;
      const midY = (d.source.y + d.target.y) / 2;
      return `translate(${midX},${midY})`;
    });

    nodeElements.attr("transform", (d) => `translate(${d.x},${d.y})`);

    // Set up tooltips on node labels
    this._setupTooltip(nodeElements);
  }

  _truncateUrl(url, maxLength = 100) {
    if (url.length <= maxLength) {
      return url;
    }
    return url.substring(0, maxLength - 3) + "...";
  }

  _buildTooltipContent(nodeData) {
    let content = nodeData.context ?? nodeData.label ?? nodeData.id;

    if (nodeData.citationURL) {
      const displayUrl = this._truncateUrl(nodeData.citationURL);
      content += `<br><br><a href="${nodeData.citationURL}" target="_blank" style="color: #87CEEB; text-decoration: underline;">[Source] ${displayUrl}</a>`;
    }

    return content;
  }

  // Calculate tooltip position based on mouse event coordinates
  _calculateTooltipPositionFromEvent(event) {
    // Position tooltip slightly below and to the right of the cursor
    return {
      x: event.pageX + 12,
      y: event.pageY + 12
    };
  }

  _createTooltip() {
    return d3
      .select("body")
      .append("div")
      .attr("class", "rra-tooltip")
      .style("opacity", 0)
      .style("position", "absolute")
      .style("background", "rgba(0, 0, 0, 0.85)")
      .style("color", "white")
      .style("padding", "8px 12px")
      .style("border-radius", "4px")
      .style("font-size", "12px")
      .style("line-height", "1.4")
      .style("max-width", "300px")
      .style("word-wrap", "break-word")
      .style("pointer-events", "none")
      .style("z-index", "9999")
      .style("transition", "opacity 0.1s ease-out");
  }

  _setupTooltip(nodeSelection) {
    const tooltip = this._createTooltip();

    // Show tooltip instantly at cursor position
    const showTooltip = (event, d) => {
      const content = this._buildTooltipContent(d);
      tooltip.html(content);

      const position = this._calculateTooltipPositionFromEvent(event);
      tooltip
        .style("left", position.x + "px")
        .style("top", position.y + "px")
        .style("opacity", 0.95);
    };

    // Hide tooltip instantly
    const hideTooltip = () => {
      tooltip.style("opacity", 0);
    };

    // Attach events to node labels specifically
    nodeSelection.selectAll(".node-label").on("mouseenter", (event, d) => {
      showTooltip(event, d);
    });

    nodeSelection.selectAll(".node-label").on("mousemove", (event) => {
      // Update position as cursor moves
      const position = this._calculateTooltipPositionFromEvent(event);
      tooltip.style("left", position.x + "px").style("top", position.y + "px");
    });

    nodeSelection.selectAll(".node-label").on("mouseleave", () => {
      hideTooltip();
    });
  }
}

export class GraphDataBuilder {
  envelope = null;

  static _isValidAnchor(a) {
    if (!a || typeof a !== "object") return false;
    return !isBlank(a.entityName);
  }

  static _isValidRelated(r) {
    if (!r || typeof r !== "object") return false;
    if (isBlank(r.entityName)) return false;
    if (isBlank(r.predicate)) return false;
    return true;
  }

  static isValidEnvelope(env) {
    if (!env || typeof env !== "object") return false;
    if (env.schemaVersion !== "2") return false;
    if (!GraphDataBuilder._isValidAnchor(env.anchorEntity)) return false;
    if (!Array.isArray(env.relatedEntities)) return false;

    const hasValidRelated = env.relatedEntities.some(GraphDataBuilder._isValidRelated);
    if (!hasValidRelated) return false;

    return true;
  }

  static keyForPair(a, b) {
    return [a, b].sort().join("::");
  }

  constructor(envelope) {
    this.envelope = GraphDataBuilder.isValidEnvelope(envelope) ? envelope : null;
  }

  build({ recordId, recordType } = {}) {
    if (!this.envelope) {
      return { nodes: [], links: [] };
    }

    const { anchorEntity, relatedEntities } = this.envelope;

    const anchorName = anchorEntity.entityName.trim();
    const anchorLabel = coalesce(anchorEntity.canonicalName, anchorName);
    const anchorRecordId = coalesce(recordId, anchorEntity.recordId);
    const anchorRecordType = coalesce(recordType, anchorEntity.recordType, "account");
    const anchorEntityType = coalesce(anchorEntity.entityType, "organization")?.toLowerCase();

    const nodes = {};
    const links = {};

    // Add focus (anchor) node
    nodes[anchorName] = {
      id: anchorName,
      label: anchorLabel,
      isFocus: true,
      isCrmLink: true,
      entityType: anchorEntityType,
      recordId: anchorRecordId,
      recordType: anchorRecordType
    };

    // Add related entities (limit to top 8)
    const maxNodes = 8;
    let nodeCount = 0;
    for (const rel of relatedEntities) {
      if (!GraphDataBuilder._isValidRelated(rel)) {
        console.warn("Skipping invalid related entity", rel);
        continue;
      }

      if (nodeCount >= maxNodes) {
        break;
      }

      const otherName = rel.entityName.trim();
      if (!otherName) {
        console.warn("Skipping relationship with blank entityName", rel);
        continue;
      }

      if (otherName === anchorName) {
        console.warn(`Skipping self-referential relationship for ${anchorName}`, rel);
        continue;
      }

      if (nodes[otherName]) {
        console.warn(`Duplicate entityName "${otherName}", skipping`, rel);
        continue;
      }

      const label = coalesce(rel.canonicalName, otherName);
      const entityType = coalesce(rel.entityType, "organization");
      const isCrmLink = rel.source === "crm" || rel.isCrmConfirmed;

      nodes[otherName] = {
        id: otherName,
        label,
        isFocus: false,
        entityType,
        isCrmLink,
        recordId: rel.recordId || undefined,
        recordType: rel.recordType || undefined,
        isCrmConfirmed: rel.isCrmConfirmed || false,
        source: rel.source || undefined,
        uuid: rel.uuid || undefined,
        context: rel.context || undefined,
        citation: rel.citation || undefined,
        citationURL: rel.citationURL || undefined,
        // Future support: depth indicates relationship degree (1 = first-degree, 2 = second-degree, etc.)
        depth: 1
      };

      const pairKey = GraphDataBuilder.keyForPair(anchorName, otherName);
      if (links[pairKey]) {
        console.warn(`Duplicate relationship for pair ${pairKey}, skipping`, rel);
        continue;
      }

      links[pairKey] = {
        source: anchorName,
        target: otherName,
        isCrmLink
      };

      nodeCount++;
    }

    return {
      nodes: Object.values(nodes),
      links: Object.values(links)
    };
  }
}

// Measure text dimensions by rendering offscreen in an SVG element
function measureLabelMetrics(svg, labels, { labelClass = "node-label" } = {}) {
  const meas = svg
    .append("text")
    .attr("class", labelClass)
    .attr("x", -9999)
    .attr("y", -9999)
    .attr("visibility", "hidden");

  let maxLabelWidth = 0;

  meas.text("Ag");
  const labelHeight = meas.node().getBBox().height;

  for (const t of labels) {
    meas.text(t);
    const w = meas.node().getComputedTextLength();
    if (w > maxLabelWidth) maxLabelWidth = w;
  }

  meas.remove();
  return { maxLabelWidth, labelHeight };
}

function isBlank(v) {
  if (typeof v === "string") {
    return v.trim().length < 1;
  }
  return true;
}

function coalesce(...v) {
  for (const x of v) {
    if (!isBlank(x)) return x.trim();
  }
  return undefined;
}
