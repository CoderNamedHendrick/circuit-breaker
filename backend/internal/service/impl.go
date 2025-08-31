package service

import (
	"backend/data"
	"backend/internal/entity"
	"fmt"

	"github.com/google/uuid"
)

type circuitServiceImpl struct {
	repo data.CircuitRepository
}

func NewCircuitService(repo data.CircuitRepository) CircuitService {
	return &circuitServiceImpl{repo}
}

// Circuit operations
func (s *circuitServiceImpl) CreateCircuit(title string) (*entity.Circuit, error) {
	if title == "" {
		return nil, fmt.Errorf("circuit title cannot be empty")
	}

	circuit := &entity.Circuit{
		ID:    uuid.New().String(),
		Title: title,
		Nodes: []entity.Node{},
		Edges: []*entity.Edge{},
	}

	if err := s.repo.CreateCircuit(circuit); err != nil {
		return nil, fmt.Errorf("failed to create circuit: %w", err)
	}

	return circuit, nil
}

func (s *circuitServiceImpl) GetCircuit(id string) (*entity.Circuit, error) {
	if id == "" {
		return nil, fmt.Errorf("circuit ID cannot be empty")
	}

	circuit, err := s.repo.GetCircuit(id)
	if err != nil {
		return nil, fmt.Errorf("failed to get circuit: %w", err)
	}

	return circuit, nil
}

func (s *circuitServiceImpl) GetAllCircuits() ([]*entity.Circuit, error) {
	circuits, err := s.repo.GetAllCircuits()
	if err != nil {
		return nil, fmt.Errorf("failed to get all circuits: %w", err)
	}

	return circuits, nil
}

// Node operations
func (s *circuitServiceImpl) CreateInputNode(circuitID string, title string) (*entity.InputNode, error) {
	if circuitID == "" {
		return nil, fmt.Errorf("circuit ID cannot be empty")
	}

	// Create the new input node
	inputNode := &entity.InputNode{
		ID:    uuid.New().String(),
		Title: title,
	}

	// Update the circuit in the database
	if err := s.repo.AddNode(circuitID, inputNode); err != nil {
		return nil, fmt.Errorf("failed to update circuit with new input node: %w", err)
	}

	return inputNode, nil
}

func (s *circuitServiceImpl) CreateOutputNode(circuitID string, title string) (*entity.OutputNode, error) {
	if circuitID == "" {
		return nil, fmt.Errorf("circuit ID cannot be empty")
	}

	// Create the new output node
	outputNode := &entity.OutputNode{
		ID:    uuid.New().String(),
		Title: title,
	}

	// Update the circuit in the database
	if err := s.repo.AddNode(circuitID, outputNode); err != nil {
		return nil, fmt.Errorf("failed to update circuit with new output node: %w", err)
	}

	return outputNode, nil
}

func (s *circuitServiceImpl) CreateAndNode(circuitID string) (*entity.AndNode, error) {
	if circuitID == "" {
		return nil, fmt.Errorf("circuit ID cannot be empty")
	}

	// Create the new AND node
	andNode := &entity.AndNode{
		ID: uuid.New().String(),
	}

	// Update the circuit in the database
	if err := s.repo.AddNode(circuitID, andNode); err != nil {
		return nil, fmt.Errorf("failed to update circuit with new AND node: %w", err)
	}

	return andNode, nil
}

func (s *circuitServiceImpl) CreateOrNode(circuitID string) (*entity.OrNode, error) {
	if circuitID == "" {
		return nil, fmt.Errorf("circuit ID cannot be empty")
	}

	// Create the new OR node
	orNode := &entity.OrNode{
		ID: uuid.New().String(),
	}

	// Update the circuit in the database
	if err := s.repo.AddNode(circuitID, orNode); err != nil {
		return nil, fmt.Errorf("failed to update circuit with new OR node: %w", err)
	}

	return orNode, nil
}

func (s *circuitServiceImpl) CreateNotNode(circuitID string) (*entity.NotNode, error) {
	if circuitID == "" {
		return nil, fmt.Errorf("circuit ID cannot be empty")
	}

	// Create the new NOT node
	notNode := &entity.NotNode{
		ID: uuid.New().String(),
	}

	// Update the circuit in the database
	if err := s.repo.AddNode(circuitID, notNode); err != nil {
		return nil, fmt.Errorf("failed to update circuit with new NOT node: %w", err)
	}

	return notNode, nil
}

func (s *circuitServiceImpl) CreateCircuitNode(circuitID string, referencedCircuitID string) (*entity.CircuitNode, error) {
	if circuitID == "" {
		return nil, fmt.Errorf("circuit ID cannot be empty")
	}
	if referencedCircuitID == "" {
		return nil, fmt.Errorf("referenced circuit ID cannot be empty")
	}

	// Verify the referenced circuit exists
	referencedCircuit, err := s.repo.GetCircuit(referencedCircuitID)
	if err != nil {
		return nil, fmt.Errorf("referenced circuit not found: %w", err)
	}

	// Create the new circuit node
	circuitNode := &entity.CircuitNode{
		ID:      uuid.New().String(),
		Circuit: referencedCircuit,
	}

	// Update the circuit in the database
	if err := s.repo.AddNode(circuitID, circuitNode); err != nil {
		return nil, fmt.Errorf("failed to update circuit with new circuit node: %w", err)
	}

	return circuitNode, nil
}

// Edge operations
func (s *circuitServiceImpl) CreateEdge(circuitID string, sourceNodeID string, targetNodeID string) (*entity.Edge, error) {
	if circuitID == "" {
		return nil, fmt.Errorf("circuit ID cannot be empty")
	}
	if sourceNodeID == "" {
		return nil, fmt.Errorf("source node ID cannot be empty")
	}
	if targetNodeID == "" {
		return nil, fmt.Errorf("target node ID cannot be empty")
	}
	if sourceNodeID == targetNodeID {
		return nil, fmt.Errorf("source and target nodes cannot be the same")
	}

	// Get the existing circuit
	circuit, err := s.repo.GetCircuit(circuitID)
	if err != nil {
		return nil, fmt.Errorf("failed to get circuit: %w", err)
	}

	// Verify both nodes exist in the circuit
	var sourceExists, targetExists bool
	for _, node := range circuit.Nodes {
		if node.GetID() == sourceNodeID {
			sourceExists = true
		}
		if node.GetID() == targetNodeID {
			targetExists = true
		}
	}

	if !sourceExists {
		return nil, fmt.Errorf("source node %s not found in circuit", sourceNodeID)
	}
	if !targetExists {
		return nil, fmt.Errorf("target node %s not found in circuit", targetNodeID)
	}

	// Check if edge already exists
	for _, edge := range circuit.Edges {
		if edge.SourceNodeID == sourceNodeID && edge.TargetNodeID == targetNodeID {
			return nil, fmt.Errorf("edge already exists between nodes %s and %s", sourceNodeID, targetNodeID)
		}
	}

	// Create the new edge
	newEdge := &entity.Edge{
		ID:           uuid.New().String(),
		SourceNodeID: sourceNodeID,
		TargetNodeID: targetNodeID,
	}

	// Update the circuit in the database
	if err := s.repo.AddEdge(circuitID, newEdge); err != nil {
		return nil, fmt.Errorf("failed to update circuit with new edge: %w", err)
	}

	return newEdge, nil
}

// Evaluation operations
func (s *circuitServiceImpl) EvaluateCircuit(circuit *entity.Circuit, inputs []*entity.InputNodeValue) (*entity.EvaluationResult, error) {
	if circuit == nil {
		return &entity.EvaluationResult{
			Success: false,
			Error:   "circuit cannot be nil",
		}, fmt.Errorf("circuit cannot be nil")
	}

	if inputs == nil {
		return &entity.EvaluationResult{
			Success: false,
			Error:   "inputs cannot be nil",
		}, fmt.Errorf("inputs cannot be nil")
	}

	// Validate the circuit structure before evaluation
	if err := circuit.ValidateCircuit(); err != nil {
		return &entity.EvaluationResult{
			Success: false,
			Error:   fmt.Sprintf("circuit validation failed: %v", err),
		}, fmt.Errorf("circuit validation failed: %w", err)
	}

	// Use the evaluation engine to evaluate the circuit
	result, err := circuit.EvaluateCircuit(inputs)
	if err != nil {
		return &entity.EvaluationResult{
			Success: false,
			Error:   err.Error(),
		}, err
	}

	return result, nil
}
