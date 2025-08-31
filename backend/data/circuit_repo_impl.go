package data

import (
	"backend/internal/entity"
	"database/sql"
	"fmt"
	"log"
	"os"

	"github.com/google/uuid"
	"github.com/joho/godotenv"
	_ "github.com/lib/pq"
)

var DB *sql.DB

func init() {
	if err := godotenv.Load(); err != nil {
		log.Println("Warning: Could not load .env file. Using environment variables.")
	}

	connStr := fmt.Sprintf("user=%s dbname=%s password=%s sslmode=disable",
		os.Getenv("DATABASE_USER"),
		os.Getenv("DATABASE_NAME"),
		os.Getenv("DATABASE_PASSWORD"),
	)

	var err error
	DB, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatalf("Error opening database connection: %v", err)
	}

	// Ping the database to verify the connection is alive.
	if err = DB.Ping(); err != nil {
		log.Fatalf("Error connecting to the database: %v", err)
	}
}

type circuitRepositoryImpl struct {
}

func SqlCircuitRepository() CircuitRepository {
	return &circuitRepositoryImpl{}
}

func (c circuitRepositoryImpl) CreateCircuit(circuit *entity.Circuit) error {
	tx, err := DB.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback() // Rollback on error

	// Assign UUID to circuit if it doesn't have one
	if circuit.ID == "" {
		circuit.ID = uuid.New().String()
	}

	// Insert circuit
	_, err = tx.Exec("INSERT INTO circuits (id, title) VALUES ($1, $2)", circuit.ID, circuit.Title)
	if err != nil {
		return fmt.Errorf("failed to insert circuit: %w", err)
	}

	// Insert nodes and edges
	if err := c.upsertNodesAndEdges(tx, circuit); err != nil {
		return err
	}

	return tx.Commit()
}

func (c circuitRepositoryImpl) AddNode(circuitID string, node entity.Node) error {
	tx, err := DB.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Insert the node
	if err := c.insertNode(tx, circuitID, node); err != nil {
		return err
	}

	return tx.Commit()
}

func (c circuitRepositoryImpl) AddEdge(circuitID string, edge *entity.Edge) error {
	tx, err := DB.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Assign UUID to edge if it doesn't have one
	if edge.ID == "" {
		edge.ID = uuid.New().String()
	}

	// Insert edge
	_, err = tx.Exec(
		"INSERT INTO edges (id, circuit_id, source_node_id, target_node_id) VALUES ($1, $2, $3, $4)",
		edge.ID, circuitID, edge.SourceNodeID, edge.TargetNodeID,
	)
	if err != nil {
		return fmt.Errorf("failed to insert edge %s: %w", edge.ID, err)
	}

	return tx.Commit()
}

func (c circuitRepositoryImpl) GetCircuit(id string) (*entity.Circuit, error) {
	// Use a map to prevent infinite recursion on circular dependencies
	visited := make(map[string]bool)
	return c.getCircuitRecursive(id, visited)
}

func (c circuitRepositoryImpl) GetAllCircuits() ([]*entity.Circuit, error) {
	// Use a single query with JOINs to fetch all data at once
	query := `
		SELECT 
			c.id as circuit_id,
			c.title as circuit_title,
			n.id as node_id,
			n.type as node_type,
			n.title as node_title,
			n.referenced_circuit_id,
			e.id as edge_id,
			e.source_node_id,
			e.target_node_id
		FROM circuits c
		LEFT JOIN nodes n ON c.id = n.circuit_id
		LEFT JOIN edges e ON c.id = e.circuit_id
		ORDER BY c.title, n.id, e.id
	`

	rows, err := DB.Query(query)
	if err != nil {
		return nil, fmt.Errorf("failed to query circuits with joins: %w", err)
	}
	defer rows.Close()

	// Map to store circuits by ID
	circuitMap := make(map[string]*entity.Circuit)

	// Map to store nodes by circuit ID and node ID to avoid duplicates
	nodeMap := make(map[string]map[string]entity.Node)

	// Map to store edges by circuit ID to avoid duplicates
	edgeMap := make(map[string][]*entity.Edge)

	for rows.Next() {
		var circuitID, circuitTitle string
		var nodeID, nodeType, nodeTitle, referencedCircuitID sql.NullString
		var edgeID, sourceNodeID, targetNodeID sql.NullString

		err := rows.Scan(
			&circuitID, &circuitTitle,
			&nodeID, &nodeType, &nodeTitle, &referencedCircuitID,
			&edgeID, &sourceNodeID, &targetNodeID,
		)
		if err != nil {
			return nil, fmt.Errorf("failed to scan joined row: %w", err)
		}

		// Create circuit if it doesn't exist
		if _, exists := circuitMap[circuitID]; !exists {
			circuitMap[circuitID] = &entity.Circuit{
				ID:    circuitID,
				Title: circuitTitle,
				Nodes: []entity.Node{},
				Edges: []*entity.Edge{},
			}
			nodeMap[circuitID] = make(map[string]entity.Node)
			edgeMap[circuitID] = []*entity.Edge{}
		}

		// Add node if it exists and hasn't been added yet
		if nodeID.Valid && nodeType.Valid {
			if _, nodeExists := nodeMap[circuitID][nodeID.String]; !nodeExists {
				node := c.createNodeFromDB(nodeID.String, nodeType.String, nodeTitle, referencedCircuitID)
				if node != nil {
					nodeMap[circuitID][nodeID.String] = node
				}
			}
		}

		// Add edge if it exists and hasn't been added yet
		if edgeID.Valid && sourceNodeID.Valid && targetNodeID.Valid {
			// Check if edge already exists
			edgeExists := false
			for _, existingEdge := range edgeMap[circuitID] {
				if existingEdge.ID == edgeID.String {
					edgeExists = true
					break
				}
			}

			if !edgeExists {
				edge := &entity.Edge{
					ID:           edgeID.String,
					SourceNodeID: sourceNodeID.String,
					TargetNodeID: targetNodeID.String,
				}
				edgeMap[circuitID] = append(edgeMap[circuitID], edge)
			}
		}
	}

	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("error iterating joined rows: %w", err)
	}

	// Convert maps to slice and populate circuit data
	var circuits []*entity.Circuit
	for circuitID, circuit := range circuitMap {
		// Add nodes to circuit
		for _, node := range nodeMap[circuitID] {
			circuit.Nodes = append(circuit.Nodes, node)
		}

		// Add edges to circuit
		circuit.Edges = edgeMap[circuitID]

		circuits = append(circuits, circuit)
	}

	return circuits, nil
}

func (c circuitRepositoryImpl) UpdateCircuit(circuit *entity.Circuit) error {
	tx, err := DB.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// 1. Check if circuit exists and update its title
	res, err := tx.Exec("UPDATE circuits SET title = $1 WHERE id = $2", circuit.Title, circuit.ID)
	if err != nil {
		return fmt.Errorf("failed to update circuit %s: %w", circuit.ID, err)
	}
	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected for circuit update %s: %w", circuit.ID, err)
	}
	if rowsAffected == 0 {
		return fmt.Errorf("circuit with id %s not found for update", circuit.ID)
	}

	// 2. Delete old nodes (ON DELETE CASCADE in the DB will handle deleting associated edges)
	_, err = tx.Exec("DELETE FROM nodes WHERE circuit_id = $1", circuit.ID)
	if err != nil {
		return fmt.Errorf("failed to delete old nodes for circuit %s: %w", circuit.ID, err)
	}

	// 3. Insert new nodes and edges
	if err := c.upsertNodesAndEdges(tx, circuit); err != nil {
		return err
	}

	return tx.Commit()
}

func (c circuitRepositoryImpl) DeleteCircuit(id string) error {
	res, err := DB.Exec("DELETE FROM circuits WHERE id = $1", id)
	if err != nil {
		return fmt.Errorf("failed to delete circuit %s: %w", id, err)
	}
	rowsAffected, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("failed to get rows affected for circuit delete %s: %w", id, err)
	}
	if rowsAffected == 0 {
		return fmt.Errorf("circuit with id %s not found for deletion", id)
	}
	return nil
}

func NewCircuitRepository() CircuitRepository {
	return &circuitRepositoryImpl{}
}

// --- Helper Functions ---

func (c circuitRepositoryImpl) getCircuitRecursive(id string, visited map[string]bool) (*entity.Circuit, error) {
	if visited[id] {
		// If we've already visited this circuit in this call stack,
		// return a shallow circuit to break the recursion.
		return &entity.Circuit{ID: id, Title: "Recursive Reference"}, nil
	}
	visited[id] = true
	defer delete(visited, id) // Clean up for other branches of the call tree

	circuit := &entity.Circuit{ID: id}

	// Fetch circuit details
	err := DB.QueryRow("SELECT title FROM circuits WHERE id = $1", id).Scan(&circuit.Title)
	if err != nil {
		if err == sql.ErrNoRows {
			return nil, fmt.Errorf("circuit with id %s not found", id)
		}
		return nil, fmt.Errorf("failed to query circuit %s: %w", id, err)
	}

	// Fetch nodes
	nodes, err := c.fetchNodesForCircuit(id, visited)
	if err != nil {
		return nil, err
	}
	circuit.Nodes = nodes

	// Fetch edges
	edges, err := c.fetchEdgesForCircuit(id)
	if err != nil {
		return nil, err
	}
	circuit.Edges = edges

	return circuit, nil
}

func (c circuitRepositoryImpl) fetchNodesForCircuit(circuitID string, visited map[string]bool) ([]entity.Node, error) {
	rows, err := DB.Query("SELECT id, type, title, referenced_circuit_id FROM nodes WHERE circuit_id = $1", circuitID)
	if err != nil {
		return nil, fmt.Errorf("failed to query nodes for circuit %s: %w", circuitID, err)
	}
	defer rows.Close()

	var nodes []entity.Node
	for rows.Next() {
		var id, nodeType string
		var title, referencedCircuitID sql.NullString
		if err := rows.Scan(&id, &nodeType, &title, &referencedCircuitID); err != nil {
			return nil, fmt.Errorf("failed to scan node row: %w", err)
		}

		var node entity.Node
		switch nodeType {
		case "INPUT":
			node = &entity.InputNode{ID: id, Title: title.String}
		case "OUTPUT":
			node = &entity.OutputNode{ID: id, Title: title.String}
		case "AND":
			node = &entity.AndNode{ID: id}
		case "OR":
			node = &entity.OrNode{ID: id}
		case "NOT":
			node = &entity.NotNode{ID: id}
		case "CIRCUIT":
			cn := &entity.CircuitNode{ID: id}
			if referencedCircuitID.Valid && referencedCircuitID.String != "" {
				// Recursively fetch the nested circuit
				nestedCircuit, err := c.getCircuitRecursive(referencedCircuitID.String, visited)
				if err != nil {
					log.Printf("warning: failed to fetch nested circuit %s for node %s: %v", referencedCircuitID.String, id, err)
					cn.Circuit = &entity.Circuit{ID: referencedCircuitID.String, Title: "Not Found"}
				} else {
					cn.Circuit = nestedCircuit
				}
			}
			node = cn
		default:
			log.Printf("warning: unknown node type '%s' found in database for circuit %s", nodeType, circuitID)
			continue // Skip unknown node types
		}
		nodes = append(nodes, node)
	}
	return nodes, rows.Err()
}

func (c circuitRepositoryImpl) fetchEdgesForCircuit(circuitID string) ([]*entity.Edge, error) {
	rows, err := DB.Query("SELECT id, source_node_id, target_node_id FROM edges WHERE circuit_id = $1", circuitID)
	if err != nil {
		return nil, fmt.Errorf("failed to query edges for circuit %s: %w", circuitID, err)
	}
	defer rows.Close()

	var edges []*entity.Edge
	for rows.Next() {
		edge := &entity.Edge{}
		if err := rows.Scan(&edge.ID, &edge.SourceNodeID, &edge.TargetNodeID); err != nil {
			return nil, fmt.Errorf("failed to scan edge row: %w", err)
		}
		edges = append(edges, edge)
	}
	return edges, rows.Err()
}

// upsertNodesAndEdges is a helper to insert nodes and edges for a circuit within a transaction.
func (c circuitRepositoryImpl) upsertNodesAndEdges(tx *sql.Tx, circuit *entity.Circuit) error {
	// Insert nodes
	for _, node := range circuit.Nodes {
		if err := c.insertNode(tx, circuit.ID, node); err != nil {
			return err // error is already descriptive
		}
	}

	// Insert edges
	for _, edge := range circuit.Edges {
		if edge.ID == "" {
			edge.ID = uuid.New().String()
		}
		_, err := tx.Exec(
			"INSERT INTO edges (id, circuit_id, source_node_id, target_node_id) VALUES ($1, $2, $3, $4)",
			edge.ID, circuit.ID, edge.SourceNodeID, edge.TargetNodeID,
		)
		if err != nil {
			return fmt.Errorf("failed to insert edge %s: %w", edge.ID, err)
		}
	}
	return nil
}

// insertNode is a helper to insert a generic entity.Node into the database.
func (c circuitRepositoryImpl) insertNode(tx *sql.Tx, circuitID string, node entity.Node) error {
	var nodeType, title, referencedCircuitID sql.NullString
	var nodeID string

	// This function assigns a new UUID to the node's ID field.
	// This is crucial because edge creation relies on these IDs.
	switch n := node.(type) {
	case *entity.InputNode:
		nodeType.String, nodeType.Valid = "INPUT", true
		title.String, title.Valid = n.Title, true
		if n.ID == "" {
			n.ID = uuid.New().String()
		}
		nodeID = n.ID
	case *entity.OutputNode:
		nodeType.String, nodeType.Valid = "OUTPUT", true
		title.String, title.Valid = n.Title, true
		if n.ID == "" {
			n.ID = uuid.New().String()
		}
		nodeID = n.ID
	case *entity.AndNode:
		nodeType.String, nodeType.Valid = "AND", true
		if n.ID == "" {
			n.ID = uuid.New().String()
		}
		nodeID = n.ID
	case *entity.OrNode:
		nodeType.String, nodeType.Valid = "OR", true
		if n.ID == "" {
			n.ID = uuid.New().String()
		}
		nodeID = n.ID
	case *entity.NotNode:
		nodeType.String, nodeType.Valid = "NOT", true
		if n.ID == "" {
			n.ID = uuid.New().String()
		}
		nodeID = n.ID
	case *entity.CircuitNode:
		nodeType.String, nodeType.Valid = "CIRCUIT", true
		if n.Circuit != nil && n.Circuit.ID != "" {
			referencedCircuitID.String, referencedCircuitID.Valid = n.Circuit.ID, true
		}
		if n.ID == "" {
			n.ID = uuid.New().String()
		}
		nodeID = n.ID
	default:
		return fmt.Errorf("unknown node type: %T", n)
	}

	_, err := tx.Exec(
		"INSERT INTO nodes (id, circuit_id, type, title, referenced_circuit_id) VALUES ($1, $2, $3, $4, $5)",
		nodeID, circuitID, nodeType.String, title, referencedCircuitID,
	)
	if err != nil {
		return fmt.Errorf("failed to insert node %s: %w", nodeID, err)
	}
	return nil
}

// createNodeFromDB creates a node entity from database row data
func (c circuitRepositoryImpl) createNodeFromDB(id, nodeType string, title, referencedCircuitID sql.NullString) entity.Node {
	switch nodeType {
	case "INPUT":
		return &entity.InputNode{
			ID:    id,
			Title: title.String,
		}
	case "OUTPUT":
		return &entity.OutputNode{
			ID:    id,
			Title: title.String,
		}
	case "AND":
		return &entity.AndNode{ID: id}
	case "OR":
		return &entity.OrNode{ID: id}
	case "NOT":
		return &entity.NotNode{ID: id}
	case "CIRCUIT":
		circuitNode := &entity.CircuitNode{ID: id}
		if referencedCircuitID.Valid && referencedCircuitID.String != "" {
			// For circuit nodes, we'll create a placeholder circuit
			// The actual circuit data would need to be loaded separately if needed
			circuitNode.Circuit = &entity.Circuit{
				ID:    referencedCircuitID.String,
				Title: "Referenced Circuit",
			}
		}
		return circuitNode
	default:
		log.Printf("warning: unknown node type '%s' found in database", nodeType)
		return nil
	}
}
