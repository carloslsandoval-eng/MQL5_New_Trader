# CNetwork - MQL5 Neural Network Class

## Overview

`CNetwork` is a standalone MQL5 neural network class implementing a NEAT-like (NeuroEvolution of Augmenting Topologies) architecture with fixed output nodes and dynamic input/hidden topology.

## Features

- **Standalone**: No external dependencies
- **Dynamic Inputs**: Supports variable number of input nodes
- **Fixed Outputs**: 5 predefined output nodes (Buy, Sell, Filter, Stop Loss, Take Profit)
- **Topological Execution**: Nodes executed in topologically sorted order for efficient feedforward
- **Innovation-Based Genes**: Connections sorted by innovation number for genetic algorithms
- **Three Mutation Types**:
  - **Lateral**: Adds new input and hidden nodes
  - **Memory**: Adds recurrent connections for temporal processing
  - **Depth**: Splits connections to increase network depth
- **State Management**: Recurrent buffers for memory, initialized to 0
- **Persistence**: Save/Load topology and weights (buffers not persisted)

## Architecture

### Node Types
- `NODE_INPUT`: Input nodes (dynamic count)
- `NODE_HIDDEN`: Hidden nodes (added through mutations)
- `NODE_OUTPUT`: Output nodes (fixed at 5)
- `NODE_RECURRENT`: Recurrent nodes for memory

### Output Nodes (Fixed)
```mql5
enum ENUM_OUTPUT_NODE
{
   OUT_BUY = 0,     // Buy signal output
   OUT_SELL = 1,    // Sell signal output
   OUT_FILTER = 2,  // Filter signal output
   OUT_SL = 3,      // Stop Loss output
   OUT_TP = 4       // Take Profit output
};
```

### Data Structures

#### SNode
- `id`: Unique node identifier
- `type`: Node type (input/hidden/output/recurrent)
- `value`: Current activation value
- `recurrentBuffer`: Buffer for recurrent connections (init to 0)
- `topoLevel`: Topological level for sorting

#### SConnection (Gene)
- `fromNode`: Source node ID
- `toNode`: Target node ID
- `weight`: Connection weight
- `enabled`: Connection enabled flag
- `frozen`: Frozen flag (set during mutations)
- `recurrent`: Recurrent connection flag
- `innovation`: Innovation number (for sorting)

## Usage

### Initialization

```mql5
#include "Include/Network/CNetwork.mqh"

CNetwork network;
network.Initialize(3);  // Initialize with 3 input nodes
```

### Feed Forward

```mql5
double inputs[3] = {0.5, -0.3, 0.8};
network.FeedForward(inputs);

// Get all outputs
double outputs[];
network.GetOutputs(outputs);

// Or get specific output
double buySignal = network.GetOutput(OUT_BUY);
```

### Mutations

#### Lateral Mutation
Adds new input node and hidden node, connects to output with weight=0, freezes old connections.

```mql5
network.MutateLateral();
```

#### Memory Mutation
Adds recurrent node with self-connection, connects to output with weight=0, freezes old connections.

```mql5
network.MutateMemory();
```

#### Depth Mutation
Splits existing connection A→B into A→New→B where A→New has weight=1.0 and New→B has original weight. Does not freeze connections.

```mql5
network.MutateDepth();
```

### State Management

```mql5
// Reset all recurrent buffers to 0
network.ResetRecurrentBuffers();
```

### Persistence

```mql5
// Save network in binary format (default)
// Files are saved to the common folder (shared across terminals)
network.SaveToFile("my_network.bin");

// Save network in CSV format for inspection
network.SaveToFile("my_network.csv", true);

// Load network from common folder
// Automatically detects format based on file extension
CNetwork loadedNetwork;
loadedNetwork.LoadFromFile("my_network.bin");  // Binary
loadedNetwork.LoadFromFile("my_network.csv");  // CSV
```

#### CSV Format
The CSV format is human-readable and designed for inspection during testing:
- Includes metadata (input/output counts, node/connection counts)
- Node table with ID, Type, and Topological Level
- Connection table with Innovation, From/To nodes, Weight, and flags
- Can be opened in Excel or any text editor for examination

## Implementation Details

### Topological Sort
- Nodes are executed in topological order based on their connections
- Input nodes are at level 0
- Each node's level is one more than its maximum predecessor's level
- Recurrent connections are skipped during topological sorting
- Ensures efficient single-pass feedforward execution

### Activation Functions
Different activation functions for different node types:
- **Output nodes**: Sigmoid activation (range [0, 1])
  ```mql5
  output = 1.0 / (1.0 + exp(-weighted_sum))
  ```
- **Hidden/Recurrent nodes**: Hyperbolic tangent (range [-1, 1])
  ```mql5
  output = tanh(weighted_sum_of_inputs)
  ```

This ensures output values (Buy, Sell, Filter, SL, TP) are strictly non-negative [0, 1].

### Innovation Numbers
- Each connection has a unique innovation number
- Connections are sorted by innovation number
- Facilitates genetic algorithms and crossover operations

### Recurrent Connections
- Recurrent buffers store previous activation values
- Buffers are initialized to 0
- Not persisted during save/load operations
- Updated after each feedforward pass

## Mutation Behavior

### Lateral Mutation
1. Freezes all existing connections
2. Creates new input node
3. Creates new hidden node
4. Adds connection: NewInput → NewHidden (weight = 0)
5. Adds connection: NewHidden → RandomOutput (weight = 0)
6. Resorts connections and recalculates topology

### Memory Mutation
1. Freezes all existing connections
2. Creates new recurrent node
3. Adds self-recurrent connection (weight = 0)
4. Adds connection: RecurrentNode → RandomOutput (weight = 0)
5. Resorts connections and recalculates topology

### Depth Mutation
1. Selects random enabled non-recurrent connection
2. Disables original connection
3. Creates new hidden node
4. Adds connection: From → New (weight = 1.0)
5. Adds connection: New → To (original weight)
6. Does NOT freeze connections
7. Resorts connections and recalculates topology

## File Format

Binary format for persistence (saved to common folder):
- **Location**: Common folder (shared across all MT5 terminals)
- **Format**: Binary file with FILE_COMMON flag
- Header: input count, output count, node count, connection count, next node ID, next innovation
- Nodes: ID, type, topological level (skip value and recurrentBuffer)
- Connections: from, to, weight, enabled, frozen, recurrent, innovation

## Example

See `Examples/NetworkExample.mq5` for comprehensive usage examples including:
- Initialization
- Feed forward operations
- All mutation types
- Recurrent buffer management
- Save/Load operations
- Multiple sequential mutations

## MQL5 Syntax Compliance

- Uses `.` for member access (no `->`)
- All structures defined inside class
- Optimized for fast feedforward execution
- Compatible with MQL5 compilation requirements

## Performance Characteristics

- **Feedforward**: O(N + E) where N = nodes, E = edges
- **Topological Sort**: O(N * E) worst case, typically much faster
- **Mutations**: O(E log E) due to sorting
- **Memory**: Dynamic arrays, scales with network complexity

## Limitations

- Maximum network size limited by available memory
- No automatic weight training (designed for evolutionary algorithms)
- Recurrent connections are single-step delays
- Output count fixed at 5 (architecture requirement)

## Thread Safety

Not thread-safe. Create separate instances for concurrent use.
