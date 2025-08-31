import 'package:flutter/material.dart';
import 'package:frontend/__generated__/schema.schema.gql.dart';
import 'package:frontend/graphql_client.dart';
import 'package:frontend/src/circuit_editor/circuit.dart';
import 'package:frontend/src/circuit_editor/component_painter.dart';
import 'package:frontend/src/graphql/__generated__/circuits.req.gql.dart';
import 'package:frontend/src/graphql/__generated__/mutations.req.gql.dart';

import '../graphql/__generated__/circuits.data.gql.dart';
import 'draggable_item.dart';
import 'edge_painter.dart';

class CircuitEditor extends StatefulWidget {
  const CircuitEditor({super.key, this.circuit});

  final GGetCircuitsData_circuits? circuit;

  @override
  State<CircuitEditor> createState() => _CircuitEditorState();
}

class _CircuitEditorState extends State<CircuitEditor> {
  bool loading = false;
  late final circuitNotifier = ValueNotifier(widget.circuit?.toAppCircuit());

  @override
  void initState() {
    super.initState();

    WidgetsFlutterBinding.ensureInitialized().addPostFrameCallback((_) async {
      if (widget.circuit == null) {
        // create circuit
        _showNameCircuitDialog(context, (name) async {
          setState(() {
            loading = true;
          });
          final createReq = await client.request(GCreateCircuitReq((b) => b..vars.title = name)).first;

          circuitNotifier.value = Circuit(
            id: createReq.data?.createCircuit.id ?? '',
            title: createReq.data?.createCircuit.title ?? '',
            nodes: [],
            edges: [],
          );

          setState(() {
            loading = false;
          });
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: ValueListenableBuilder(
          valueListenable: circuitNotifier,
          builder: (context, value, child) {
            if (value != null) {
              return Text(value.title);
            }
            return Text('Circuit Editor');
          },
        ),
        actions: [
          Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  if (circuitNotifier.value == null) return;
                  try {
                    await _triggerEvaluate(context);
                  } catch (e) {
                    setState(() {
                      loading = false;
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                    }
                  }
                },
                child: Text('Evaluate Circuit'),
              );
            },
          ),
        ],
      ),

      body: ValueListenableBuilder(
        valueListenable: circuitNotifier,
        builder: (context, value, child) {
          if (value == null) {
            return SizedBox();
          }
          return _Editor(
            circuit: value,
            onChanged: (circuit) {
              circuitNotifier.value = circuit;
            },
          );
        },
      ),
    );
  }

  Future<void> _triggerEvaluate(BuildContext context) async {
    if (circuitNotifier.value?.id.isEmpty ?? false) return;

    final cct = circuitNotifier.value!;

    final requestInputs = <String, bool>{};
    final inputNodes = cct.nodes.where((n) => n.type == NodeType.inputNode);

    for (final input in inputNodes) {
      final iInput = await _showCollectBoolInput(context, '${input.label}#${input.id}');
      if (iInput != null) requestInputs[input.id] = iInput;
    }

    setState(() {
      loading = true;
    });
    final request = await client
        .request(
          GEvaluateCircuitReq(
            (b) => b
              ..vars.circuitID = cct.id
              ..vars.inputs.addAll([
                ...requestInputs.entries.map((e) {
                  return GInputNodeValue(
                    (b) => b
                      ..value = e.value
                      ..nodeID = e.key,
                  );
                }),
              ]),
          ),
        )
        .first;

    setState(() {
      loading = false;
    });
    if (!context.mounted) return;

    if (request.data?.evaluateCircuit.success == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Circuit failed to evaluate with error: ${request.data?.evaluateCircuit.error}'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Evaluation Result'),
          content: Text('Evaluation result to ${request.data?.evaluateCircuit.outputs.first.value}'),
        );
      },
    );
  }

  Future<bool?> _showCollectBoolInput(BuildContext context, String inputName) async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Enter input for $inputName'),
          content: Text('Select true or false for input'),
          actions: <Widget>[
            TextButton(child: const Text('True'), onPressed: () => Navigator.of(dialogContext).pop(true)),
            TextButton(child: const Text('False'), onPressed: () => Navigator.of(dialogContext).pop(false)),
          ],
        );
      },
    );
  }

  Future<void> _showNameCircuitDialog(BuildContext context, Function(String) onSaveWithName) async {
    final TextEditingController nameController = TextEditingController();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Name Your Circuit'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(hintText: "Enter circuit name"),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(child: const Text('Cancel'), onPressed: () => Navigator.of(dialogContext).pop()),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                final circuitName = nameController.text.trim();
                if (circuitName.isNotEmpty) {
                  Navigator.of(dialogContext).pop();
                  onSaveWithName(circuitName);
                } else {
                  ScaffoldMessenger.of(
                    dialogContext,
                  ).showSnackBar(const SnackBar(content: Text("Name cannot be empty"), backgroundColor: Colors.red));
                }
              },
            ),
          ],
        );
      },
    );
  }
}

class _Editor extends StatefulWidget {
  const _Editor({required this.circuit, required this.onChanged});

  final Circuit circuit;
  final ValueChanged<Circuit> onChanged;

  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  // Use DraggableNodeItem or your adapted model
  final List<DraggableNodeItem> _draggableNodes = [];

  DraggableNodeItem? _draggingNode;
  Offset _dragOffset = Offset.zero; // Offset of the tap within the dragged item

  // At the top of _CircuitEditorState

  final List<Edge> _edges = []; // Store all connections

  // State for drawing a new edge
  Port? _edgeStartPort; // The port from which the user starts dragging an edge
  Offset? _edgeDragEndPosition; // Current mouse position while dragging a new edge

  void _onPanStart(DragStartDetails details) {
    final tapPosition = details.localPosition;
    _edgeStartPort = null;

    for (final node in _draggableNodes.reversed) {
      for (final port in node.ports) {
        final portAbsPosition = node.position + port.relativePosition;
        final portRect = Rect.fromCircle(center: portAbsPosition, radius: 8.0);

        if (portRect.contains(tapPosition)) {
          if (port.type == PortType.output) {
            setState(() {
              _edgeStartPort = port;
              _edgeDragEndPosition = tapPosition; // Initially, end is where drag started
            });
            return;
          } else {}
        }
      }
    }

    // Iterate in reverse to pick top-most item (items later in the list are drawn on top in a Stack)
    for (final node in _draggableNodes.reversed) {
      if (node.contains(tapPosition)) {
        setState(() {
          _draggingNode = node;
          _dragOffset = tapPosition - node.position;
          // Optional: Bring the dragged item to the "top" of the stack
          // by removing and re-adding it to the list.
          // This ensures it's rendered above other items while dragging.
          _draggableNodes.remove(node);
          _draggableNodes.add(node);
        });
        return;
      }
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final currentPanPosition = details.localPosition;

    if (_edgeStartPort != null) {
      setState(() {
        _edgeDragEndPosition = currentPanPosition;
      });
    } else if (_draggingNode != null) {
      setState(() {
        _draggingNode!.position = currentPanPosition - _dragOffset;
      });
    }
  }

  void _onPanEnd(DragEndDetails details) async {
    if (_edgeStartPort != null && _edgeDragEndPosition != null) {
      // Attempt to complete edge
      for (final targetNode in _draggableNodes) {
        if (targetNode.id == _edgeStartPort!.nodeId) continue; // don't connect to self

        for (final targetPort in targetNode.ports) {
          if (targetPort.type == PortType.input) {
            final targetPortAbsPosition = targetNode.position + targetPort.relativePosition;
            final targetPortRect = Rect.fromCircle(center: targetPortAbsPosition, radius: 8.0);

            if (targetPortRect.contains(_edgeDragEndPosition!)) {
              // Check if this input port is already connected (optional, if inputs have capacity 1)
              bool isTargetPortOccupied = _edges.any(
                (edge) => edge.targetNodeId == targetNode.id && edge.targetPortId == targetPort.id,
              );
              if (isTargetPortOccupied) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("Target port already connected"), backgroundColor: Colors.red));
                break; // or show user feedback
              }

              final edgeReq = await client
                  .request(
                    GCreateEdgeReq(
                      (b) => b
                        ..vars.circuitID = widget.circuit.id
                        ..vars.sourceNodeID = _edgeStartPort!.nodeId
                        ..vars.targetNodeID = targetNode.id,
                    ),
                  )
                  .first;
              final newEdge = Edge(
                id: edgeReq.data?.createEdge.id ?? '',
                sourceNodeId: edgeReq.data?.createEdge.sourceNodeID ?? '',
                sourcePortId: _edgeStartPort!.id,
                targetNodeId: edgeReq.data?.createEdge.targetNodeID ?? '',
                targetPortId: targetPort.id,
              );
              setState(() {
                _edges.add(newEdge);
              });
              break; // Edge created
            }
          }
        }
      }
    }

    setState(() {
      _edgeStartPort = null;
      _edgeDragEndPosition = null;
      _draggingNode = null;
    });

    List<CircuitNode> appNodes = _draggableNodes.map((dn) {
      return CircuitNode(
        // This is your app's Node model from graph_to_class_extension.dart
        id: dn.id,
        type: dn.nodeType,
        label: dn.label,
      );
    }).toList();

    List<CircuitEdge> appEdges = _edges.map((ee) {
      return CircuitEdge(id: ee.id, sourceNodeId: ee.sourceNodeId, targetNodeId: ee.targetNodeId);
    }).toList();

    final cct = Circuit(id: widget.circuit.id, title: widget.circuit.title, nodes: appNodes, edges: appEdges);
    widget.onChanged(cct);
  }

  void _addNode(NodeType type, Offset position, {String label = ''}) async {
    String id;
    switch (type) {
      case NodeType.inputNode:
        final inputNodesCount = _draggableNodes.where((i) => i.nodeType == NodeType.inputNode).length;
        final result = await client
            .request(
              GCreateInputNodeReq(
                (b) => b
                  ..vars.title = 'Input ${inputNodesCount + 1}'
                  ..vars.circuitID = widget.circuit.id,
              ),
            )
            .first;
        id = result.data?.createInputNode.id ?? '';
      case NodeType.outputNode:
        final result = await client
            .request(
              GCreateOutputNodeReq(
                (b) => b
                  ..vars.title = 'Output'
                  ..vars.circuitID = widget.circuit.id,
              ),
            )
            .first;
        id = result.data?.createOutputNode.id ?? '';

      case NodeType.andNode:
        final result = await client.request(GCreateAndNodeReq((b) => b..vars.circuitID = widget.circuit.id)).first;
        id = result.data?.createAndNode.id ?? '';

      case NodeType.orNode:
        final result = await client.request(GCreateOrNodeReq((b) => b..vars.circuitID = widget.circuit.id)).first;
        id = result.data?.createOrNode.id ?? '';

      case NodeType.notNode:
        final result = await client.request(GCreateNotNodeReq((b) => b..vars.circuitID = widget.circuit.id)).first;
        id = result.data?.createNotNode.id ?? '';

      case NodeType.circuitNode:
        final result = await client
            .request(
              GCreateCircuitNodeReq(
                (b) => b
                  ..vars.referencedCircuitID = '${widget.circuit.id}_rcircuit_${DateTime.now().millisecondsSinceEpoch}'
                  ..vars.circuitID = widget.circuit.id,
              ),
            )
            .first;

        id = result.data?.createCircuitNode.id ?? '';
    }

    final newNode = DraggableNodeItem(
      id: id,
      position: position,
      nodeType: type,
      label: label.isEmpty ? type.displayName : label,
      size: (type == NodeType.andNode || type == NodeType.orNode || type == NodeType.circuitNode)
          ? const Size(100, 60)
          : const Size(50, 50), // Example: smaller for input/output/not
    );
    setState(() {
      _draggableNodes.add(newNode);
    });
  }

  @override
  void initState() {
    super.initState();

    _loadCircuit(widget.circuit);
  }

  void _loadCircuit(Circuit circuit) {
    _draggableNodes.clear(); // Clear existing nodes before loading
    _edges.clear(); // Clear existing edges

    double currentX = 50.0;
    double currentY = 50.0;
    const double nodeSpacingX = 150.0;
    const double nodeSpacingY = 100.0; // Increased spacing for clarity
    int nodesInRow = 0;
    const int maxNodesPerRow = 4; // Adjust as needed

    for (final node in circuit.nodes) {
      // Iterate over appCircuit.nodes
      final nodeSize = _getDefaultNodeSize(node.type);
      Offset position;

      // TODO: Implement proper layout algorithm or load positions if available
      // For now, simple staggered layout:
      if (node.id.contains("input")) {
        // Example: position inputs on the left
        position = Offset(currentX, currentY);
        currentY += nodeSpacingY;
        if (currentY > 600) {
          // Reset Y and move X for next column of inputs
          currentY = 50.0;
          currentX += nodeSpacingX;
        }
      } else if (node.id.contains("output")) {
        // Example: position outputs on the right
        position = Offset(
          currentX + nodeSpacingX * (maxNodesPerRow - 1),
          currentY - nodeSpacingY,
        ); // Align with previous row of inputs
        // This output positioning is very basic, adjust currentY, currentX based on actual needs
      } else {
        // Position other nodes
        position = Offset(currentX, currentY);
        currentX += nodeSpacingX;
        nodesInRow++;
        if (nodesInRow >= maxNodesPerRow) {
          currentX = 50.0; // Reset X for next row
          currentY += nodeSpacingY;
          nodesInRow = 0;
        }
      }
      // If your 'Node' model in 'appCircuit' has position information, use it directly:
      // position = node.position; (assuming node.position is an Offset)

      _draggableNodes.add(
        DraggableNodeItem(
          id: node.id,
          position: position,
          nodeType: node.type,
          label: node.label,
          size: nodeSize,
          // Ports are auto-generated by DraggableNodeItem constructor
        ),
      );
    }

    String? targetPortIdToUse;
    for (final edge in circuit.edges) {
      // Iterate over appCircuit.edges
      final sourceNode = _draggableNodes.firstWhere(
        (dn) => dn.id == edge.sourceNodeId,
        orElse: () => _dummyDraggableNode(),
      );
      final targetNode = _draggableNodes.firstWhere(
        (dn) => dn.id == edge.targetNodeId,
        orElse: () => _dummyDraggableNode(),
      );

      if (sourceNode.id == 'dummy' || targetNode.id == 'dummy') {
        debugPrint("Warning: LoadCircuit - Could not find source or target node for edge ${edge.id}");
        continue;
      }

      // Determine sourcePortId and targetPortId.
      // This is the critical part that depends on your 'Edge' model from graph_to_class_extension.dart
      String sourcePortIdToUse;

      final sourceOutputPort = sourceNode.ports.firstWhere(
        (p) => p.type == PortType.output,
        orElse: () => Port(
          id: '${sourceNode.id}_default_out_err',
          nodeId: sourceNode.id,
          type: PortType.output,
          relativePosition: Offset.zero,
        ), // Error/dummy port
      );
      final targetInputPort = targetNode.ports.firstWhere(
        (p) => p.type == PortType.input && p.id != targetPortIdToUse,
        // Potentially find a specific input if multiple
        orElse: () => Port(
          id: '${targetNode.id}_default_in_err',
          nodeId: targetNode.id,
          type: PortType.input,
          relativePosition: Offset.zero,
        ), // Error/dummy port
      );

      if (sourceOutputPort.id.endsWith("_err") || targetInputPort.id.endsWith("_err")) {
        debugPrint(
          "Warning: LoadCircuit - Could not find suitable default ports for edge ${edge.id} between ${sourceNode.label} and ${targetNode.label}",
        );
        continue;
      }
      sourcePortIdToUse = sourceOutputPort.id;
      targetPortIdToUse = targetInputPort.id;

      _edges.add(
        Edge(
          id: edge.id,
          sourceNodeId: edge.sourceNodeId,
          sourcePortId: sourcePortIdToUse,
          targetNodeId: edge.targetNodeId,
          targetPortId: targetPortIdToUse,
        ),
      );
    }
  }

  DraggableNodeItem _dummyDraggableNode() =>
      DraggableNodeItem(id: 'dummy', position: Offset.zero, nodeType: NodeType.circuitNode, size: Size.zero);

  Size _getDefaultNodeSize(NodeType type) {
    return (type == NodeType.andNode || type == NodeType.orNode || type == NodeType.circuitNode)
        ? const Size(100, 60)
        : const Size(50, 50);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 150,
          height: double.maxFinite,
          child: Material(
            elevation: 4,
            child: Column(
              children: [
                Text('Components'),
                SizedBox(height: 50),
                Column(
                  spacing: 30,
                  children: [
                    ...NodeType.values
                        .where((i) => i != NodeType.circuitNode)
                        .map(
                          (node) => Draggable<NodeType>(
                            data: node,
                            dragAnchorStrategy: pointerDragAnchorStrategy,
                            feedback: Opacity(
                              opacity: 0.6,
                              child: CircuitNodeWidget(type: node, label: node.displayName),
                            ),
                            child: CircuitNodeWidget(type: node, label: node.displayName),
                          ),
                        ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: DragTarget<NodeType>(
            onAcceptWithDetails: (details) {
              _addNode(details.data, details.offset);
            },
            builder: (context, candidateItems, rejectedItems) {
              return GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                child: SizedBox.expand(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CustomPaint(
                        painter: EdgePainter(
                          nodes: _draggableNodes,
                          edges: _edges,
                          edgeStartPort: _edgeStartPort,
                          edgeDragEndPosition: _edgeDragEndPosition,
                        ),
                        size: Size.infinite, // Cover the whole canvas
                      ),
                      ..._draggableNodes.map((node) {
                        return Positioned(
                          key: ValueKey(node.id), // Important for widget identity and updates
                          left: node.position.dx,
                          top: node.position.dy,
                          child: CircuitNodeWidget(type: node.nodeType, label: node.label, size: node.size),
                        );
                      }),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
