DROP TABLE IF EXISTS edges;
DROP TABLE IF EXISTS nodes;
DROP TABLE IF EXISTS circuits;
DROP TYPE IF EXISTS node_type;
CREATE TYPE node_type AS ENUM (
    'INPUT',
    'OUTPUT',
    'AND',
    'OR',
    'NOT',
    'CIRCUIT'
);
CREATE TABLE circuits (
    id UUID PRIMARY KEY,
    title TEXT NOT NULL
);
-- Stores all nodes for all circuits. A 'type' column differentiates them.
CREATE TABLE nodes (
    id UUID PRIMARY KEY,
    circuit_id UUID NOT NULL,
    type node_type NOT NULL,
    title TEXT,
    referenced_circuit_id UUID,
    CONSTRAINT fk_circuit FOREIGN KEY (circuit_id) REFERENCES circuits (id) ON DELETE CASCADE,
    CONSTRAINT fk_referenced_circuit FOREIGN KEY (referenced_circuit_id) REFERENCES circuits (id) ON DELETE
    SET NULL
);
CREATE TABLE edges (
    id UUID PRIMARY KEY,
    circuit_id UUID NOT NULL,
    source_node_id UUID NOT NULL,
    target_node_id UUID NOT NULL,
    CONSTRAINT fk_circuit FOREIGN KEY (circuit_id) REFERENCES circuits (id) ON DELETE CASCADE,
    CONSTRAINT fk_source_node FOREIGN KEY (source_node_id) REFERENCES nodes (id) ON DELETE CASCADE,
    CONSTRAINT fk_target_node FOREIGN KEY (target_node_id) REFERENCES nodes (id) ON DELETE CASCADE
);
-- Add indexes on foreign keys to improve query performance.
CREATE INDEX idx_nodes_circuit_id ON nodes (circuit_id);
CREATE INDEX idx_nodes_referenced_circuit_id ON nodes (referenced_circuit_id);
CREATE INDEX idx_edges_circuit_id ON edges (circuit_id);
CREATE INDEX idx_edges_source_node_id ON edges (source_node_id);
CREATE INDEX idx_edges_target_node_id ON edges (target_node_id);