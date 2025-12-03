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
    shellHeight: 40, // height of node shells (rounded rectangles)
    shellPadding: 12, // horizontal padding inside shells
    shellIconTextGap: 8, // gap between icon and text
    shellBorderRadius: 20, // border radius for shell corners
    canvasMargin: 20, // increased margin for better spacing
    startAngle: -Math.PI / 2, // start at 12 o'clock
    textOffsetY: 10, // vertical offset for label under node from perimeter

    // Icon sprite (Salesforce symbols.svg)
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

  // Distance we can travel from the node shell center along (dx, dy) before leaving its bounding rectangle.
  _distanceToRectEdge(halfWidth = this.options.radius, halfHeight = this.options.radius, dx, dy) {
    const EPS = 1e-6;
    const absDx = Math.abs(dx);
    const absDy = Math.abs(dy);

    let tx = Infinity;
    let ty = Infinity;

    if (absDx > EPS) {
      tx = halfWidth / absDx;
    }
    if (absDy > EPS) {
      ty = halfHeight / absDy;
    }

    if (!isFinite(tx) && !isFinite(ty)) {
      return 0;
    }

    return Math.min(tx, ty);
  }

  _maxCenterDistanceForNode(cx, cy, { x: dx, y: dy }, node) {
    const { width, height, canvasMargin } = this.options;
    const halfWidth = node.shellHalfWidth ?? this.options.radius;
    const halfHeight = node.shellHalfHeight ?? this.options.radius;
    const EPS = 1e-6;

    let maxR = Infinity;

    if (Math.abs(dx) > EPS) {
      if (dx > 0) {
        const limit = width - canvasMargin - halfWidth;
        const r = (limit - cx) / dx;
        maxR = Math.min(maxR, r);
      } else {
        const limit = canvasMargin + halfWidth;
        const r = (limit - cx) / dx;
        maxR = Math.min(maxR, r);
      }
    }

    if (Math.abs(dy) > EPS) {
      if (dy > 0) {
        const limit = height - canvasMargin - halfHeight;
        const r = (limit - cy) / dy;
        maxR = Math.min(maxR, r);
      } else {
        const limit = canvasMargin + halfHeight;
        const r = (limit - cy) / dy;
        maxR = Math.min(maxR, r);
      }
    }

    if (!isFinite(maxR)) {
      maxR = Math.min(width, height) / 2;
    }

    return Math.max(0, maxR);
  }

  // Compute a deterministic radial layout with the focus node at the center and all other nodes
  // evenly spaced around a circle.  Mutates nodes to add x/y, returning a Map id->node for
  // convenience.
  _layout(nodes) {
    if (!nodes || nodes.length < 1) return new Map();

    const { width, height, radius, startAngle } = this.options;

    const cx = width / 2;
    const cy = height / 2;

    const focus = nodes.find((n) => n.isFocus) ?? nodes[0];
    const related = nodes.filter((n) => n !== focus);
    const N = related.length;

    if (focus) {
      focus.x = cx;
      focus.y = cy;
    }

    // If no related nodes, return early
    if (N === 0) {
      return new Map(nodes.map((n) => [n.id, n]));
    }

    // Calculate the layout direction and constraints for each related node
    const focusHalfWidth = focus?.shellHalfWidth ?? radius;
    const focusHalfHeight = focus?.shellHalfHeight ?? radius;

    const nodeLayoutInfo = related.map((node, index) => {
      const theta = startAngle + (2 * Math.PI * index) / N;
      const dx = Math.cos(theta);
      const dy = Math.sin(theta);
      const dir = { x: dx, y: dy };

      const sourceOffset = this._distanceToRectEdge(focusHalfWidth, focusHalfHeight, dx, dy);
      const targetOffset = this._distanceToRectEdge(
        node.shellHalfWidth ?? radius,
        node.shellHalfHeight ?? radius,
        -dx,
        -dy
      );

      const maxCenterDistance = this._maxCenterDistanceForNode(cx, cy, dir, node);
      const maxEdgeLength = maxCenterDistance - sourceOffset - targetOffset;

      return {
        node,
        dir,
        theta,
        sourceOffset,
        targetOffset,
        maxCenterDistance,
        maxEdgeLength: Math.max(0, maxEdgeLength)
      };
    });

    // Determine the target visible edge length that keeps every node within bounds
    const preferredEdgeLength = radius * 6;
    const edgeLengthLimit = nodeLayoutInfo.reduce(
      (minLimit, info) => Math.min(minLimit, info.maxEdgeLength),
      Infinity
    );
    const targetEdgeLength = Math.max(
      0,
      Math.min(
        edgeLengthLimit,
        isFinite(preferredEdgeLength) ? preferredEdgeLength : edgeLengthLimit
      )
    );

    // Position each node using the computed target edge length
    for (const info of nodeLayoutInfo) {
      const { node, dir, sourceOffset, targetOffset, maxCenterDistance } = info;
      const desiredCenterDistance = targetEdgeLength + sourceOffset + targetOffset;
      const centerDistance = Math.min(maxCenterDistance, desiredCenterDistance);

      node.x = cx + centerDistance * dir.x;
      node.y = cy + centerDistance * dir.y;
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

    // Calculate shell width for each node
    data.nodes.forEach((node) => {
      const labelWidth = measureLabelMetrics(svg, [getLabelText(node)], {
        labelClass: "node-label"
      }).maxLabelWidth;
      // Include badge button space for non-focus nodes (40px for button + spacing)
      const badgeSpace = node.isFocus ? 0 : 40;
      node.shellWidth =
        shellPadding + iconSize + shellIconTextGap + labelWidth + shellPadding + badgeSpace;
      node.shellHalfWidth = node.shellWidth / 2;
      node.shellHalfHeight = shellHeight / 2;
    });

    const nodeById = this._layout(data.nodes);

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

    // Node shell background (rounded rectangle)
    g.append("rect")
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
    g.append("circle")
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
    g.append("use")
      .attr("href", (d) => this.getIconUrl(this.getIconIdForNode(d)))
      .attr("width", iconSize)
      .attr("height", iconSize)
      .attr("x", (d) => -d.shellHalfWidth + shellPadding)
      .attr("y", -iconSize / 2)
      .attr("class", "node-icon");

    // Text label on the right side of the icon
    g.append("text")
      .attr("class", "node-label")
      .attr("x", (d) => -d.shellHalfWidth + shellPadding + iconSize + shellIconTextGap)
      .attr("y", 0)
      .attr("text-anchor", "start")
      .attr("dominant-baseline", "central")
      .style("pointer-events", "auto")
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
      .attr("cx", (d) => d.shellHalfWidth - 20)
      .attr("cy", 0)
      .attr("class", "node-badge-bg");

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

    this._setupTooltip(svg, g, shellHeight / 2, {
      shouldShow: (event) => Boolean(event.target.closest(".node-label"))
    });
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

  _setupTooltip(svg, nodeSelection, nodeRadius, { shouldShow = () => true } = {}) {
    const tooltip = this._createTooltip();
    let currentNodeId = null;

    const SHOW_DURATION = 200;
    const HIDE_DURATION = 250;
    const MOUSEOUT_DELAY = 300;
    const TOOLTIP_LEAVE_DELAY = 300;

    const cancelPendingHide = () => {
      tooltip.interrupt();
      tooltip.style("pointer-events", "auto");
    };

    const hideTooltip = (delay = 0) => {
      tooltip
        .interrupt()
        .transition()
        .delay(delay)
        .duration(HIDE_DURATION)
        .style("opacity", 0)
        .on("end", () => {
          currentNodeId = null;
          tooltip.style("pointer-events", "none");
        });
    };

    nodeSelection.on("mouseover", (event, d) => {
      if (!shouldShow(event, d)) {
        return;
      }
      cancelPendingHide();

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

    nodeSelection.on("mouseout", () => {
      hideTooltip(MOUSEOUT_DELAY);
    });

    tooltip
      .on("mouseover", () => {
        cancelPendingHide();
        tooltip.style("opacity", 0.9).style("pointer-events", "auto");
      })
      .on("mouseout", () => {
        hideTooltip(TOOLTIP_LEAVE_DELAY);
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
  }
  return true;
}

function coalesce(...v) {
  for (const x of v) {
    if (!isBlank(x)) return x.trim();
  }
  return undefined;
}
