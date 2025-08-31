// Create a new CustomPainter for edges (or integrate into an existing canvas painter)
import 'package:flutter/material.dart';

import 'component_painter.dart';
import 'draggable_item.dart';

class EdgePainter extends CustomPainter {
  final List<DraggableNodeItem> nodes;
  final List<Edge> edges;
  final Port? edgeStartPort; // For drawing the line while user is creating an edge
  final Offset? edgeDragEndPosition; // Current end position of the new edge being dragged

  EdgePainter({required this.nodes, required this.edges, this.edgeStartPort, this.edgeDragEndPosition});

  @override
  void paint(Canvas canvas, Size size) {
    final edgePaint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final portPaint = Paint()
      ..color = Colors.blueGrey
      ..style = PaintingStyle.fill;

    final highlightedPortPaint = Paint()
      ..color = Colors.deepOrangeAccent
      ..style = PaintingStyle.fill;

    // 1. Draw existing edges
    for (final edge in edges) {
      final sourceNode = nodes.firstWhere((n) => n.id == edge.sourceNodeId, orElse: () => _dummyNode());
      final targetNode = nodes.firstWhere((n) => n.id == edge.targetNodeId, orElse: () => _dummyNode());

      if (sourceNode.id == 'dummy' || targetNode.id == 'dummy') continue; // Skip if nodes not found

      final sourcePort = sourceNode.ports.firstWhere((p) => p.id == edge.sourcePortId);
      final targetPort = targetNode.ports.firstWhere((p) => p.id == edge.targetPortId);

      final startPoint = sourceNode.position + sourcePort.relativePosition;
      final endPoint = targetNode.position + targetPort.relativePosition;

      // Draw a simple line (can be enhanced with curves: Path.quadraticBezierTo)
      canvas.drawLine(startPoint, endPoint, edgePaint);
    }

    // 2. Draw the edge being currently created
    if (edgeStartPort != null && edgeDragEndPosition != null) {
      final sourceNode = nodes.firstWhere((n) => n.id == edgeStartPort!.nodeId, orElse: () => _dummyNode());
      if (sourceNode.id != 'dummy') {
        final startPoint = sourceNode.position + edgeStartPort!.relativePosition;
        canvas.drawLine(startPoint, edgeDragEndPosition!, edgePaint..color = Colors.blueAccent.withValues(alpha: 0.7));
      }
    }

    // 3. Draw all ports on nodes (optional, but good for UX)
    for (final node in nodes) {
      for (final port in node.ports) {
        final portAbsPosition = node.position + port.relativePosition;
        bool isHighlighted =
            edgeStartPort != null && edgeStartPort!.nodeId == port.nodeId && edgeStartPort!.id == port.id;
        isHighlighted = isHighlighted || (_isPortHoveredForConnection(port, node.id, edgeDragEndPosition));

        canvas.drawCircle(portAbsPosition, 5.0, isHighlighted ? highlightedPortPaint : portPaint); // Port radius
      }
    }
  }

  // Helper to check if the current drag-to-connect is hovering over a valid input port
  bool _isPortHoveredForConnection(Port portToCheck, String portNodeId, Offset? currentDragPos) {
    if (edgeStartPort == null ||
        currentDragPos == null ||
        portToCheck.type != PortType.input ||
        portNodeId == edgeStartPort!.nodeId) {
      return false;
    }
    // Find the node that portToCheck belongs to
    final DraggableNodeItem? nodeOfPort = nodes.cast<DraggableNodeItem?>().firstWhere(
      (n) => n?.id == portNodeId,
      orElse: () => null,
    );
    if (nodeOfPort == null) return false;

    final portAbsPosition = nodeOfPort.position + portToCheck.relativePosition;
    final portRect = Rect.fromCircle(center: portAbsPosition, radius: 8.0); // Tappable radius
    return portRect.contains(currentDragPos);
  }

  // Dummy node to avoid crashing if a node for an edge is somehow missing
  DraggableNodeItem _dummyNode() =>
      DraggableNodeItem(id: 'dummy', position: Offset.zero, nodeType: NodeType.circuitNode, size: Size.zero, ports: []);

  @override
  bool shouldRepaint(covariant EdgePainter oldDelegate) {
    return oldDelegate.nodes != nodes ||
        oldDelegate.edges != edges ||
        oldDelegate.edgeStartPort != edgeStartPort ||
        oldDelegate.edgeDragEndPosition != edgeDragEndPosition;
  }
}
