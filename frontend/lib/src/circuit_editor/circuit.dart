// lib/src/circuit_editor/graph_to_class_extension.dart
import 'package:flutter/foundation.dart'; // For @immutable if you use it
import 'package:frontend/src/circuit_editor/component_painter.dart'; // For NodeType
import 'package:frontend/src/graphql/__generated__/circuits.data.gql.dart';

// Potentially import your DraggableNodeItem and Edge models if they align and you want to reuse them
// For this example, I'll define distinct Node and Edge classes for the Circuit model
// to keep it decoupled from UI-specific DraggableNodeItem state.

// --- App's Internal Circuit Model ---

@immutable // Good practice for model classes if they are not meant to be mutated directly
class Circuit {
  final String id;
  final String title;
  final List<CircuitNode> nodes;
  final List<CircuitEdge> edges;

  const Circuit({required this.id, required this.title, required this.nodes, required this.edges});

  Circuit copyWith({String? id, String? title, List<CircuitNode>? nodes, List<CircuitEdge>? edges}) {
    return Circuit(
      id: id ?? this.id,
      title: title ?? this.title,
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Circuit &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          listEquals(nodes, other.nodes) &&
          listEquals(edges, other.edges);

  @override
  int get hashCode => id.hashCode ^ title.hashCode ^ nodes.hashCode ^ edges.hashCode;
}

@immutable
class CircuitNode {
  final String id;
  final NodeType type; // Use your existing NodeType enum
  final String label;

  // Add other properties like position if they come from the backend
  // final Offset position; // Example

  const CircuitNode({
    required this.id,
    required this.type,
    required this.label,
    // required this.position,
  });

  CircuitNode copyWith({
    String? id,
    NodeType? type,
    String? label,
    // Offset? position,
  }) {
    return CircuitNode(
      id: id ?? this.id,
      type: type ?? this.type,
      label: label ?? this.label,
      // position: position ?? this.position,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CircuitNode &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          label == other.label;

  // position == other.position;

  @override
  int get hashCode => id.hashCode ^ type.hashCode ^ label.hashCode;
  // position.hashCode;
}

@immutable
class CircuitEdge {
  final String id;
  final String sourceNodeId;

  // final String sourcePortId; // If your GQL model has port IDs for edges
  final String targetNodeId;

  // final String targetPortId; // If your GQL model has port IDs for edges

  const CircuitEdge({
    required this.id,
    required this.sourceNodeId,
    // required this.sourcePortId,
    required this.targetNodeId,
    // required this.targetPortId,
  });

  CircuitEdge copyWith({
    String? id,
    String? sourceNodeId,
    // String? sourcePortId,
    String? targetNodeId,
    // String? targetPortId,
  }) {
    return CircuitEdge(
      id: id ?? this.id,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      // sourcePortId: sourcePortId ?? this.sourcePortId,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      // targetPortId: targetPortId ?? this.targetPortId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CircuitEdge &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sourceNodeId == other.sourceNodeId &&
          // sourcePortId == other.sourcePortId &&
          targetNodeId == other.targetNodeId;

  // targetPortId == other.targetPortId;

  @override
  int get hashCode =>
      id.hashCode ^
      sourceNodeId.hashCode ^
      // sourcePortId.hashCode ^
      targetNodeId.hashCode;
  // targetPortId.hashCode;
}

// --- Extension for Conversion ---

// Import the generated GraphQL data class
// Make sure this path is correct for your project structure

extension GraphQLCircuitConversion on GGetCircuitsData_circuits {
  Circuit toAppCircuit() {
    // Convert GQL Nodes to App Nodes
    final appNodes = nodes.map((gqlNode) {
      NodeType nodeType = NodeType.fromString(gqlNode.G__typename);
      String label = ''; // Default label

      // Determine NodeType and Label based on GQL node type (__typename)
      // This part is crucial and depends on your GQL schema's union/interface types for nodes
      if (gqlNode is GGetCircuitsData_circuits_nodes__asInputNode) {
        label = gqlNode.inputTitle ?? 'Input'; // Use a default if title is null
      } else if (gqlNode is GGetCircuitsData_circuits_nodes__asOutputNode) {
        label = gqlNode.outputTitle ?? 'Output';
      } else if (gqlNode is GGetCircuitsData_circuits_nodes__asCircuitNode) {
        // This is a nested circuit. Your app's Node model might need to handle this.
        // For simplicity, I'm treating it as a generic 'CircuitNode' for now.
        // You might want to represent its title or even recursively convert the nested circuit.
        label = gqlNode.circuit.title; // Label it with the nested circuit's title
      }
      // Add more 'else if' cases here for AndNode, OrNode, NotNode
      // if they are distinct types in your GraphQL schema (e.g., GGetCircuitsData_circuits_nodes__asAndNode)
      // For now, I'll assume they might be generic or you'll determine type by another field.
      // If they don't have a specific GQL type, you might need another field on the GQL node
      // to determine its type (e.g., gqlNode.componentType == 'AND_NODE')
      else {
        // Fallback or error based on your GQL schema.
        // You might need a way to determine AND, OR, NOT from a generic GQL node.
        // For this example, let's assume a 'type' field or infer from __typename if possible
        // This is a placeholder - adjust based on your actual GQL node structure for logic gates
        debugPrint("Unknown GQL node type: ${gqlNode.G__typename} with ID: ${gqlNode.id}");
        // Default to a generic node type if unmappable, or throw error
        // For demonstration, let's try to infer from a potential label or fallback.
        // This part NEEDS to be adapted to your actual GQL schema for logic gates.
        // Example: if (gqlNode.someFieldIndicatingType == 'AND') nodeType = NodeType.andNode;
        // For now, defaulting to CircuitNode for unhandled cases and hoping label helps.
        label = "";
      }

      return CircuitNode(
        id: gqlNode.id,
        type: nodeType,
        label: label,
        // position: Offset.zero, // You'd need to get position from GQL if available
        // Or initialize positions when loading into the editor UI
      );
    }).toList();

    // Convert GQL Edges to App Edges
    final appEdges = edges.map((gqlEdge) {
      return CircuitEdge(
        id: gqlEdge.id,
        sourceNodeId: gqlEdge.sourceNodeID, // Check exact field name from .gql.dart
        targetNodeId: gqlEdge.targetNodeID, // Check exact field name
      );
    }).toList();

    return Circuit(
      id: id, // 'this' refers to the GGetCircuitsData_circuits instance
      title: title,
      nodes: appNodes,
      edges: appEdges,
    );
  }
}
