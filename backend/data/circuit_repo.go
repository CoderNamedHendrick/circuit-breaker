package data

import "backend/internal/entity"

type CircuitRepository interface {
	CreateCircuit(circuit *entity.Circuit) error
	AddNode(circuitID string, node entity.Node) error
	AddEdge(circuitID string, edge *entity.Edge) error
	GetCircuit(id string) (*entity.Circuit, error)
	GetAllCircuits() ([]*entity.Circuit, error)
	UpdateCircuit(circuit *entity.Circuit) error
	DeleteCircuit(id string) error
}
