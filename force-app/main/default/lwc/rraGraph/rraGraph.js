export class RraGraph {
  static BADGE_BACKGROUND_MIN_RADIUS = 6;
  static LINK_BADGE_SIZE = 12;
  static PLUS_BADGE_SIZE = 8;
  static EDGE_ICON_SIZE = 12;
  static EDGE_ICON_BG_RADIUS = 8;

  static defaultOptions = {
    // CSS selector or SVG element
    svg: "svg",
    width: 600, // increased for better spacing
    height: 600,

    // Geometry
    radius: 20, // base node radius (for layout calculations)
    pillHeight: 40, // height of pill-shaped nodes
    pillPadding: 12, // horizontal padding inside pills
    pillIconTextGap: 8, // gap between icon and text
    pillBorderRadius: 20, // border radius for pill corners
    canvasMargin: 20, // increased margin for better spacing
    startAngle: -Math.PI / 2, // start at 12 o'clock
    textOffsetY: 10, // vertical offset for label under node from perimeter

    // Icon sprite (Salesforce symbols.svg)
    //
    // Refer to README for instructions on how to obtain this asset.
    iconsUrl: "",

    iconSize: 22, // width/height of the <use> glyph

    // Label sizing; used for layout calculations
    maxLabelChars: 20, // higher hard cap than ERI1's; beyond this we add "…"

    onNodeClick: null // callback for node click events
  };

  // Mapping beteen entity type and SLDS icon id.
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

  constructor(options) {
    this.options = { ...RraGraph.defaultOptions, ...options };
  }

  clear() {
    const { svg } = this.options;
    while (svg.firstChild) svg.removeChild(svg.firstChild);
  }

  // Compute a deterministic radial layout with the focus node at the center and all other nodes
  // evenly spaced around a circle.  Mutates nodes to add x/y, returning a Map id->node for
  // convenience.
  _layout(nodes, { labelHalfWidth = 0, labelHeight = 0 } = {}) {
    if (!nodes || nodes.length < 1) return new Map();

    const { width, height, radius, canvasMargin, startAngle } = this.options;

    const cx = width / 2;
    const cy = height / 2;

    const focus = nodes.find((n) => n.isFocus) ?? nodes[0];
    const related = nodes.filter((n) => n !== focus);
    const N = related.length;

    // Per-side padding that accounts for pill node size
    // Add extra padding to ensure pills don't get cut off and edges are visible
    const padX = canvasMargin + labelHalfWidth + 20;
    const padY = canvasMargin + labelHeight / 2 + 20;
    const padLeft = padX;
    const padRight = padX;
    const padTop = padY;
    const padBottom = padY;

    // Max allowed orbit radius so nothing crosses any side
    const rXLeft = cx - padLeft;
    const rXRight = width - cx - padRight;
    const rYTop = cy - padTop;
    const rYBottom = height - cy - padBottom;

    // Increase multiplier to 8 for much better spacing and edge visibility
    const circleR = Math.max(radius * 8, Math.min(rXLeft, rXRight, rYTop, rYBottom));

    if (focus) {
      focus.x = cx;
      focus.y = cy;
    }

    for (let i = 0; i < N; i++) {
      const theta = startAngle + (2 * Math.PI * i) / Math.max(1, N);
      const n = related[i];
      n.x = cx + circleR * Math.cos(theta);
      n.y = cy + circleR * Math.sin(theta);
    }

    return new Map(nodes.map((n) => [n.id, n]));
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

  // CRM badge (e.g., link icon) to show in the corner if node has a CRM record and isn't the anchor
  // node.
  getCrmBadgeIconId() {
    return "link";
  }

  getIconUrl(icon) {
    return `${this.options.iconsUrl}#${icon}`;
  }

  getIconUtilUrl(icon) {
    return `${this.options.iconsUtilUrl}#${icon}`;
  }

  render(data) {
    const {
      svg: svgSelector,
      width,
      height,
      radius,
      iconSize,
      pillHeight,
      pillPadding,
      pillIconTextGap,
      pillBorderRadius,
      maxLabelChars
    } = this.options;
    const svg = d3.select(svgSelector).attr("width", width).attr("height", height);

    const getLabelText = (d) => {
      const t = d.label ?? d.id;
      return t.length > maxLabelChars ? t.slice(0, maxLabelChars) + "…" : t;
    };

    const labels = (data.nodes ?? []).map(getLabelText);
    const { maxLabelWidth, labelHeight } = measureLabelMetrics(svg, labels, {
      labelClass: "node-label"
    });

    // Calculate pill width for each node
    data.nodes.forEach((node) => {
      const labelWidth = measureLabelMetrics(svg, [getLabelText(node)], {
        labelClass: "node-label"
      }).maxLabelWidth;
      // Include badge button space for non-focus nodes (40px for button + spacing)
      const badgeSpace = node.isFocus ? 0 : 40;
      node.pillWidth =
        pillPadding + iconSize + pillIconTextGap + labelWidth + pillPadding + badgeSpace;
      node.pillHalfWidth = node.pillWidth / 2;
      node.pillHalfHeight = pillHeight / 2;
    });

    const nodeById = this._layout(data.nodes, {
      labelHalfWidth: maxLabelWidth / 2 + pillPadding + iconSize,
      labelHeight: pillHeight
    });

    const links = (data.links || [])
      .map((link) => {
        const source = nodeById.get(link.source);
        const target = nodeById.get(link.target);
        if (!source || !target) {
          console.warn("One or more unknown nodes in link", {
            link,
            source,
            target
          });
          return null;
        }
        return { ...link, source, target };
      })
      .filter(Boolean);

    svg
      .append("g")
      .attr("class", "links")
      .selectAll("line")
      .data(links)
      .enter()
      .append("line")
      .attr("class", (d) => `link-line ${d.isCrmLink ? "link-crm" : "link-default"}`)
      .attr("x1", (d) => d.source.x)
      .attr("y1", (d) => d.source.y)
      .attr("x2", (d) => d.target.x)
      .attr("y2", (d) => d.target.y);

    // Add edge icons to indicate source (CRM vs Web)
    const edgeBadgeG = svg
      .append("g")
      .attr("class", "edge-badges")
      .selectAll("g")
      .data(links)
      .enter()
      .append("g")
      .attr("class", "edge-badge")
      .attr("transform", (d) => {
        // Calculate midpoint of the edge
        const midX = (d.source.x + d.target.x) / 2;
        const midY = (d.source.y + d.target.y) / 2;
        return `translate(${midX},${midY})`;
      });

    // White background circle for edge icon
    edgeBadgeG
      .append("circle")
      .attr("r", RraGraph.EDGE_ICON_BG_RADIUS)
      .attr("class", "edge-badge-bg");

    // Icon for CRM links (salesforce1 utility icon)
    edgeBadgeG
      .filter((d) => d.isCrmLink)
      .append("use")
      .attr("href", this.getIconUtilUrl("salesforce1"))
      .attr("width", RraGraph.EDGE_ICON_SIZE)
      .attr("height", RraGraph.EDGE_ICON_SIZE)
      .attr("x", -RraGraph.EDGE_ICON_SIZE / 2)
      .attr("y", -RraGraph.EDGE_ICON_SIZE / 2)
      .attr("class", "edge-icon edge-icon-crm");

    // Icon for web links (world utility icon)
    edgeBadgeG
      .filter((d) => !d.isCrmLink)
      .append("use")
      .attr("href", this.getIconUtilUrl("world"))
      .attr("width", RraGraph.EDGE_ICON_SIZE)
      .attr("height", RraGraph.EDGE_ICON_SIZE)
      .attr("x", -RraGraph.EDGE_ICON_SIZE / 2)
      .attr("y", -RraGraph.EDGE_ICON_SIZE / 2)
      .attr("class", "edge-icon edge-icon-web");

    const g = svg
      .append("g")
      .attr("class", "nodes")
      .selectAll("g")
      .data(data.nodes)
      .join("g")
      .attr("transform", (d) => `translate(${d.x},${d.y})`)
      .style("cursor", "pointer")
      .on("click", (event, d) => {
        if (this.options.onNodeClick) {
          this.options.onNodeClick(d);
        }
      });

    // Pill-shaped background (rounded rectangle)
    g.append("rect")
      .attr("x", (d) => -d.pillHalfWidth)
      .attr("y", (d) => -d.pillHalfHeight)
      .attr("width", (d) => d.pillWidth)
      .attr("height", pillHeight)
      .attr("rx", pillBorderRadius)
      .attr("ry", pillBorderRadius)
      .attr("class", (d) => {
        const cl = ["node-pill"];
        if (d.isFocus) cl.push("node-pill--focus");
        if (d.isFocus || d.isCrmLink) {
          cl.push("node-crm");
          if (d.recordType) cl.push(`node-${d.recordType.toLowerCase()}`);
        }
        return cl.join(" ");
      });

    // Colored circle background for icon
    g.append("circle")
      .attr("r", iconSize / 2)
      .attr("cx", (d) => -d.pillHalfWidth + pillPadding + iconSize / 2)
      .attr("cy", 0)
      .attr("class", (d) => {
        const cl = ["node-icon-bg"];
        if (d.isFocus || d.isCrmLink) {
          cl.push("node-icon-bg-crm");
          if (d.recordType) cl.push(`node-icon-bg-${d.recordType.toLowerCase()}`);
        }
        return cl.join(" ");
      });

    // Icon on the left side of the pill
    g.append("use")
      .attr("href", (d) => this.getIconUrl(this.getIconIdForNode(d)))
      .attr("width", iconSize)
      .attr("height", iconSize)
      .attr("x", (d) => -d.pillHalfWidth + pillPadding)
      .attr("y", -iconSize / 2)
      .attr("class", "node-icon");

    // Text label on the right side of the icon
    g.append("text")
      .attr("class", "node-label")
      .attr("x", (d) => -d.pillHalfWidth + pillPadding + iconSize + pillIconTextGap)
      .attr("y", 0)
      .attr("text-anchor", "start")
      .attr("dominant-baseline", "central")
      .text((d) => getLabelText(d));

    // Badge overlay (right edge, vertically centered), shown for nodes that aren't the focus
    const badgeG = g
      .filter((d) => !d.isFocus)
      .append("g")
      .attr("class", "node-badge");

    // White circle background for badge button
    badgeG
      .append("circle")
      .attr("r", 14)
      .attr("cx", (d) => d.pillHalfWidth - 20)
      .attr("cy", 0)
      .attr("class", "node-badge-bg");

    // Link badge icon for CRM records
    badgeG
      .filter((d) => d.recordId)
      .append("use")
      .attr("href", this.getIconUrl("link"))
      .attr("width", 16)
      .attr("height", 16)
      .attr("x", (d) => d.pillHalfWidth - 20 - 8)
      .attr("y", -8)
      .attr("class", "node-badge-icon");

    // Plus sign badge icon for new records
    badgeG
      .filter((d) => !d.recordId)
      .append("use")
      .attr("href", this.getIconUtilUrl("add"))
      .attr("width", 16)
      .attr("height", 16)
      .attr("x", (d) => d.pillHalfWidth - 20 - 8)
      .attr("y", -8)
      .attr("class", "node-badge-icon");

    this._setupTooltip(svg, g, pillHeight / 2);
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

  _calculateTooltipPosition(svg, nodeData, nodeRadius) {
    const svgElement = svg.node();
    const svgRect = svgElement.getBoundingClientRect();

    return {
      x: svgRect.left + window.pageXOffset + nodeData.x + nodeRadius + 15,
      y: svgRect.top + window.pageYOffset + nodeData.y - 10
    };
  }

  _createTooltip() {
    return d3
      .select("body")
      .append("div")
      .attr("class", "rra-tooltip")
      .style("opacity", 0)
      .style("position", "absolute")
      .style("background", "rgba(0, 0, 0, 0.8)")
      .style("color", "white")
      .style("padding", "8px 12px")
      .style("border-radius", "4px")
      .style("font-size", "12px")
      .style("line-height", "1.4")
      .style("max-width", "300px")
      .style("word-wrap", "break-word")
      .style("pointer-events", "auto")
      .style("z-index", "9999");
  }

  _setupTooltip(svg, nodeSelection, nodeRadius) {
    const tooltip = this._createTooltip();
    let hideTimeout = null;
    let currentNodeId = null;

    const SHOW_DURATION = 200;
    const HIDE_DURATION = 250;
    const MOUSEOUT_DELAY = 300;
    const TOOLTIP_LEAVE_DELAY = 300;

    const clearHideTimeout = () => {
      if (hideTimeout) {
        clearTimeout(hideTimeout);
        hideTimeout = null;
      }
    };

    const hideTooltip = () => {
      tooltip
        .transition()
        .duration(HIDE_DURATION)
        .style("opacity", 0)
        .style("pointer-events", "none")
        .on("end", () => {
          currentNodeId = null;
        });
    };

    nodeSelection.on("mouseover", (event, d) => {
      clearHideTimeout();

      const content = this._buildTooltipContent(d);
      tooltip.html(content);

      // Position tooltip only if it's a different node
      if (currentNodeId !== d.id) {
        const position = this._calculateTooltipPosition(svg, d, nodeRadius);
        tooltip.style("left", position.x + "px").style("top", position.y + "px");
        currentNodeId = d.id;
      }

      tooltip
        .transition()
        .duration(SHOW_DURATION)
        .style("opacity", 0.9)
        .style("pointer-events", "auto");
    });

    nodeSelection.on("mouseout", (event, d) => {
      hideTimeout = setTimeout(() => {
        const tooltipNode = tooltip.node();
        const currentTarget = event.currentTarget;

        const tooltipHovered = tooltipNode && tooltipNode.matches(":hover");
        const nodeHovered = currentTarget && currentTarget.matches(":hover");

        if (!tooltipHovered && !nodeHovered) {
          hideTooltip();
        }
      }, MOUSEOUT_DELAY);
    });

    tooltip
      .on("mouseover", () => {
        // Only keep tooltip visible if it's currently visible (opacity > 0)
        const currentOpacity = parseFloat(tooltip.style("opacity"));
        if (currentOpacity > 0) {
          clearHideTimeout();
          tooltip.style("opacity", 0.9).style("pointer-events", "auto");
        }
      })
      .on("mouseout", () => {
        // Only set hide timeout if tooltip is currently visible
        const currentOpacity = parseFloat(tooltip.style("opacity"));
        if (currentOpacity > 0) {
          hideTimeout = setTimeout(hideTooltip, TOOLTIP_LEAVE_DELAY);
        }
      });
  }
}

export class GraphDataBuilder {
  envelope = null;

  static _isValidAnchor(a) {
    if (!a || typeof a !== "object") return false;
    // entityName is the minimal requirement; everything else is optional
    return !isBlank(a.entityName);
  }

  static _isValidRelated(r) {
    if (!r || typeof r !== "object") return false;

    if (isBlank(r.entityName)) return false;
    if (isBlank(r.predicate)) return false;
    // Not requiring citation for now, though at some point we may want to show rel evidence.
    // if (isBlank(r.citation)) return false;

    return true;
  }

  static isValidEnvelope(env) {
    if (!env || typeof env !== "object") return false;
    if (env.schemaVersion !== "2") return false;
    if (!GraphDataBuilder._isValidAnchor(env.anchorEntity)) return false;
    if (!Array.isArray(env.relatedEntities)) return false;

    // Must contain at least one valid related entity to render anything meaningful
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

    // Resolve anchor identity
    const anchorName = anchorEntity.entityName.trim();
    const anchorLabel = coalesce(anchorEntity.canonicalName, anchorName);
    const anchorRecordId = coalesce(recordId, anchorEntity.recordId);
    const anchorRecordType = coalesce(recordType, anchorEntity.recordType, "account");
    const anchorEntityType = coalesce(
      anchorEntity.entityType,
      "organization" // the entity type equivalent of record type 'Account'
    )?.toLowerCase();

    const nodes = {};
    const links = {};

    // Add special focus (anchor) node
    nodes[anchorName] = {
      id: anchorName,
      label: anchorLabel,
      isFocus: true,
      isCrmLink: true,
      entityType: anchorEntityType,
      recordId: anchorRecordId,
      recordType: anchorRecordType
    };

    // Add related entities and one link per unique pair (limit to top 8 valid entities)
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
      }

      // TODO: do better than simply checking for name equality here; at the very least, also
      // consider record ids/types.  Skipping for now.
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
        citationURL: rel.citationURL || undefined
      };

      const pairKey = GraphDataBuilder.keyForPair(anchorName, otherName);
      if (links[pairKey]) {
        // Shouldn't happen due to the earlier check on node
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

// Measure text dimensions by rendering offscreen in an SVG element.
// Assumes that web fonts have loaded and CSS is applied.
// Returns { maxLabelWidth, labelHeight } based on actual text rendering.
function measureLabelMetrics(svg, labels, { labelClass = "node-label" } = {}) {
  // Create a temporary <text> that inherits the same CSS as your labels
  const meas = svg
    .append("text")
    .attr("class", labelClass)
    .attr("x", -9999)
    .attr("y", -9999)
    .attr("visibility", "hidden");

  let maxLabelWidth = 0;

  // Height can be measured with any representative string
  meas.text("Ag");
  const labelHeight = meas.node().getBBox().height;

  // Compute max width across the actual labels that will be displayed
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
  } else {
    return true;
  }
}

function coalesce(...v) {
  for (const x of v) {
    if (!isBlank(x)) return x.trim();
  }
  return undefined;
}
