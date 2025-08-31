package entity

import (
	"errors"
	"fmt"
)

type EvaluationResult struct {
	Success bool          `json:"success"`
	Outputs []*NodeOutput `json:"outputs"`
	Error   string        `json:"error"`
}

type NodeOutput struct {
	NodeID string `json:"nodeID"`
	Value  bool   `json:"value"`
}

type InputNodeValue struct {
	NodeID string `json:"nodeID"`
	Value  bool   `json:"value"`
}

// EvaluateCircuit evaluates a boolean circuit with given input values
func (c *Circuit) EvaluateCircuit(inputs []*InputNodeValue) (*EvaluationResult, error) {
	// It's good practice to validate the circuit structure before evaluation.
	if err := c.ValidateCircuit(); err != nil {
		return &EvaluationResult{Success: false, Error: err.Error()}, err
	}

	// --- 1. Setup ---
	nodeMap := make(map[string]Node)
	// This map stores incoming connections for each node.
	// Key: targetNodeID, Value: list of sourceNodeIDs that feed into it.
	incomingEdges := make(map[string][]string)
	for _, node := range c.Nodes {
		nodeMap[node.GetID()] = node
		incomingEdges[node.GetID()] = []string{} // Initialize with empty slice
	}
	for _, edge := range c.Edges {
		incomingEdges[edge.TargetNodeID] = append(incomingEdges[edge.TargetNodeID], edge.SourceNodeID)
	}

	// --- 2. Topological Sort ---
	// Get the correct order to ensure nodes are evaluated only after their inputs are.
	evaluationOrder, err := topologicalSort(incomingEdges)
	if err != nil {
		return &EvaluationResult{Success: false, Error: err.Error()}, err
	}

	// --- 3. Evaluation ---
	computedValues := make(map[string]bool)
	// Pre-populate computedValues with the provided external inputs.
	for _, input := range inputs {
		if _, ok := nodeMap[input.NodeID].(*InputNode); !ok {
			err := fmt.Errorf("provided input '%s' is not an InputNode", input.NodeID)
			return &EvaluationResult{Success: false, Error: err.Error()}, err
		}
		computedValues[input.NodeID] = input.Value
	}

	// Evaluate nodes in their topologically sorted order.
	for _, nodeID := range evaluationOrder {
		node := nodeMap[nodeID]

		// Input nodes are our starting point; their values are already in computedValues.
		if _, ok := node.(*InputNode); ok {
			if _, exists := computedValues[nodeID]; !exists {
				err := fmt.Errorf("missing value for InputNode: %s", nodeID)
				return &EvaluationResult{Success: false, Error: err.Error()}, err
			}
			continue
		}

		// Gather the computed values from all incoming connections.
		sourceNodeIDs := incomingEdges[nodeID]
		inputValues := make([]bool, 0, len(sourceNodeIDs))
		for _, sourceNodeID := range sourceNodeIDs {
			value, exists := computedValues[sourceNodeID]
			if !exists {
				// This should not happen if the topological sort is correct and all inputs are provided.
				err := fmt.Errorf("internal evaluation error: input value for node %s from source %s not computed", nodeID, sourceNodeID)
				return &EvaluationResult{Success: false, Error: err.Error()}, err
			}
			inputValues = append(inputValues, value)
		}

		// Evaluate the current node and store its result.
		result, err := c.evaluateNode(node, inputValues)
		if err != nil {
			err = fmt.Errorf("failed to evaluate node %s: %w", nodeID, err)
			return &EvaluationResult{Success: false, Error: err.Error()}, err
		}
		computedValues[nodeID] = result
	}

	// --- 4. Collect Results ---
	var outputs []*NodeOutput
	for _, node := range c.Nodes {
		if _, ok := node.(*OutputNode); ok {
			if value, exists := computedValues[node.GetID()]; exists {
				outputs = append(outputs, &NodeOutput{NodeID: node.GetID(), Value: value})
			} else {
				// This can happen if an output node is disconnected from all inputs.
				err := fmt.Errorf("output node %s was not evaluated, check circuit connections", node.GetID())
				return &EvaluationResult{Success: false, Error: err.Error()}, err
			}
		}
	}

	return &EvaluationResult{Success: true, Outputs: outputs}, nil
}

// evaluateNode evaluates a single node based on its type and input values
func (c *Circuit) evaluateNode(node Node, inputValues []bool) (bool, error) {
	switch node.(type) {
	case *InputNode:
		// This case should not be reached in the new evaluation flow, as input values are pre-populated.
		// Its existence is a safeguard against logic errors.
		return false, errors.New("internal evaluation error: evaluateNode called on InputNode")

	case *OutputNode:
		// Output nodes pass through their input value
		if len(inputValues) != 1 {
			return false, errors.New("output node must have exactly one input")
		}
		return inputValues[0], nil

	case *AndNode:
		return evaluateAnd(inputValues), nil

	case *OrNode:
		return evaluateOr(inputValues), nil

	case *NotNode:
		return evaluateNot(inputValues), nil

	case *CircuitNode:
		// For circuit nodes, we would need to recursively evaluate the sub-circuit
		// This is a simplified implementation
		if len(inputValues) != 1 {
			return false, errors.New("circuit node must have exactly one input")
		}
		return inputValues[0], nil

	default:
		return false, fmt.Errorf("unknown node type: %T", node)
	}
}

// evaluateAnd performs AND operation on input values
func evaluateAnd(inputs []bool) bool {
	if len(inputs) == 0 {
		return false
	}

	for _, input := range inputs {
		if !input {
			return false
		}
	}
	return true
}

// evaluateOr performs OR operation on input values
func evaluateOr(inputs []bool) bool {
	if len(inputs) == 0 {
		return false
	}

	for _, input := range inputs {
		if input {
			return true
		}
	}
	return false
}

// evaluateNot performs NOT operation on input values
func evaluateNot(inputs []bool) bool {
	if len(inputs) != 1 {
		return false // Default to false if not exactly one input
	}
	return !inputs[0]
}

// topologicalSort performs topological sorting to determine evaluation order
func topologicalSort(dependencies map[string][]string) ([]string, error) {
	// Calculate in-degrees
	inDegree := make(map[string]int)
	for node := range dependencies {
		inDegree[node] = 0
	}

	// For each node, count how many dependencies it has
	for node, deps := range dependencies {
		inDegree[node] = len(deps)
	}

	// Find nodes with no dependencies (can be evaluated first)
	var queue []string
	for node, degree := range inDegree {
		if degree == 0 {
			queue = append(queue, node)
		}
	}

	var result []string

	// Process nodes
	for len(queue) > 0 {
		// Remove a node from queue
		current := queue[0]
		queue = queue[1:]
		result = append(result, current)

		// Find all nodes that depend on the current node and reduce their in-degree
		for node, deps := range dependencies {
			for _, dep := range deps {
				if dep == current {
					inDegree[node]--
					if inDegree[node] == 0 {
						queue = append(queue, node)
					}
					break
				}
			}
		}
	}

	// Check for cycles
	if len(result) != len(dependencies) {
		return nil, errors.New("circuit contains cycles")
	}

	return result, nil
}

// ValidateCircuit validates that the circuit is properly constructed
func (c *Circuit) ValidateCircuit() error {
	if c == nil {
		return errors.New("circuit is nil")
	}

	if len(c.Nodes) == 0 {
		return errors.New("circuit has no nodes")
	}

	// Check for duplicate node IDs
	nodeIDs := make(map[string]bool)
	for _, node := range c.Nodes {
		if nodeIDs[node.GetID()] {
			return fmt.Errorf("duplicate node ID: %s", node.GetID())
		}
		nodeIDs[node.GetID()] = true
	}

	// Check that all edge references are valid
	for _, edge := range c.Edges {
		if !nodeIDs[edge.SourceNodeID] {
			return fmt.Errorf("edge references non-existent source node: %s", edge.SourceNodeID)
		}
		if !nodeIDs[edge.TargetNodeID] {
			return fmt.Errorf("edge references non-existent target node: %s", edge.TargetNodeID)
		}
	}

	// Check for cycles
	dependencies := make(map[string][]string)
	for _, node := range c.Nodes {
		dependencies[node.GetID()] = []string{}
	}

	for _, edge := range c.Edges {
		dependencies[edge.TargetNodeID] = append(dependencies[edge.TargetNodeID], edge.SourceNodeID)
	}

	_, err := topologicalSort(dependencies)
	if err != nil {
		return fmt.Errorf("circuit validation failed: %w", err)
	}

	return nil
}
