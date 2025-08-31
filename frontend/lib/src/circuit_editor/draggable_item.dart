// In your draggable_item.dart or directly in circuit_editor.dart if not separate
import 'package:flutter/material.dart';
import 'package:frontend/src/circuit_editor/component_painter.dart'; // For NodeType

class Port {
  final String id;
  final String nodeId; // ID of the node this port belongs to
  final PortType type; // Input or Output
  final Offset relativePosition; // Position relative to the node's top-left corner
  // You might add capacity (e.g., an input port can only accept one connection)

  Port({required this.id, required this.nodeId, required this.type, required this.relativePosition});
}

enum PortType { input, output }

class DraggableNodeItem {
  String id;
  Offset position;
  NodeType nodeType;
  String label;
  Size size; // Each node can have its own size
  List<Port> ports; // Each node will have ports

  DraggableNodeItem({
    required this.id,
    required this.position,
    required this.nodeType,
    this.label = '',
    this.size = const Size(80, 50), // Default size, can be overridden
    List<Port>? ports,
  }) : ports = ports ?? _generateDefaultPorts(id, nodeType, size);

  // Helper to check if a point is within this item's bounds
  // This is important for the GestureDetector to know which item is tapped
  Rect get rect => Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

  bool contains(Offset point) => rect.contains(point);

  // Helper to get the absolute position of a port
  Offset getPortAbsolutePosition(String portId) {
    final port = ports.firstWhere((p) => p.id == portId);
    return position + port.relativePosition;
  }

  static List<Port> _generateDefaultPorts(String nodeId, NodeType type, Size size) {
    List<Port> generatedPorts = [];
    // Example: Add one output port on the right middle for most gates
    if (type != NodeType.outputNode) {
      // Inputs typically don't have outputs in this basic model
      generatedPorts.add(
        Port(
          id: '${nodeId}_out1',
          nodeId: nodeId,
          type: PortType.output,
          relativePosition: Offset(size.width, size.height / 2),
        ),
      );
    }

    // Example: Add input ports on the left middle
    if (type != NodeType.inputNode) {
      // Outputs typically don't source inputs
      if (type == NodeType.notNode || type == NodeType.outputNode /* input itself as source */ ) {
        generatedPorts.add(
          Port(id: '${nodeId}_in1', nodeId: nodeId, type: PortType.input, relativePosition: Offset(0, size.height / 2)),
        );
      } else if (type == NodeType.andNode || type == NodeType.orNode) {
        generatedPorts.add(
          Port(
            id: '${nodeId}_in1',
            nodeId: nodeId,
            type: PortType.input,
            relativePosition: Offset(0, size.height * 0.25),
          ),
        );
        generatedPorts.add(
          Port(
            id: '${nodeId}_in2',
            nodeId: nodeId,
            type: PortType.input,
            relativePosition: Offset(0, size.height * 0.75),
          ),
        );
      }
    }
    return generatedPorts;
  }
}

class Edge {
  final String id;
  final String sourceNodeId;
  final String sourcePortId;
  final String targetNodeId;
  final String targetPortId;

  Edge({
    required this.id,
    required this.sourceNodeId,
    required this.sourcePortId,
    required this.targetNodeId,
    required this.targetPortId,
  });

  // Optional: Add equality and hashCode if you store edges in Sets or use them as Map keys
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Edge && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
