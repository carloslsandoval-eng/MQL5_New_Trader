# CNetwork Class Documentation

## Overview
CNetwork is a NEAT-style (NeuroEvolution of Augmenting Topologies) recurrent constructive neural network implementation for MQL5. It features sparse heuristic initialization and evolutionary mutation operators.

## Architecture Specifications

### Type
- **Architecture**: Recurrent Constructive (NEAT-style)
- **Dependencies**: Standalone (no external dependencies)
- **Style**: Telegraphic, Fast Math

### Network Topology

#### Fixed Output Nodes (Indices 0-5)
| Index | Name | Activation | Purpose | Range |
|-------|------|------------|---------|-------|
| 0 | IDX_BUY | Sigmoid | Buy signal strength | [0.0, 1.0] |
| 1 | IDX_SELL | Sigmoid | Sell signal strength | [0.0, 1.0] |
| 2 | IDX_FILT | Sigmoid | Filter/Gatekeeper (>0.5 to trade) | [0.0, 1.0] |
| 3 | IDX_SL | Sigmoid | Stop Loss ratio | [0.0, 1.0] |
| 4 | IDX_TP | Sigmoid | Take Profit ratio | [0.0, 1.0] |
| 5 | IDX_SIZE | Sigmoid | Position size multiplier | [0.0, 1.0] |

#### Constants
- `CNT_OUT = 6` - Number of output nodes
- `MAX_NODES = 50` - Maximum nodes to prevent CPU blowout

### Data Structures

#### SNode - Neural Network Node
```cpp
struct SNode
{
   int               id;           // Unique node identifier
   ENUM_NODE_TYPE    type;         // INPUT, HIDDEN, or OUTPUT
   double            bias;         // Node bias value
   double            response;     // Response multiplier
   ENUM_ACTIVATION   activation;   // Activation function
   double            value;        // Current activation value
   double            sum;          // Accumulated input sum
};
```

#### SLink - Network Connection
```cpp
struct SLink
{
   int               in_node_id;   // Source node ID
   int               out_node_id;  // Target node ID
   double            weight;       // Connection weight
   bool              enabled;      // Active flag
   bool              recurrent;    // Recurrent connection flag
};
```

## Genesis Initialization (Heuristic Map)

The network starts with a **sparse heuristic initialization** that connects inputs intelligently based on domain knowledge:

### Input Map Reference
- **[0]** PA - Price Action
- **[1]** ATR - Volatility Regime
- **[2]** DistHi - Ceiling Proximity
- **[3]** VolSlope - Volatility Acceleration

### Heuristic Connections ("The Eyes to the Brain")
1. **Direction Heads (BUY/SELL)** see **Price Action [0]**
   - Random weight: [-1.0, 1.0]
   
2. **Filter Head** sees **Ceiling Proximity [2]**
   - Random weight: [-1.0, 1.0]
   
3. **Risk Heads (SL/TP)** see **Volatility Regime [1]**
   - Random weight: [0.5, 1.0] (positive bias)
   
4. **Sizing Head** sees **Volatility Acceleration [3]**
   - Random weight: [-1.0, 1.0]

### Initial Network Topology
- **Nodes**: 6 output nodes
- **Links**: 7 connections (sparse)
- **Hidden**: 0 (starts minimal, grows through evolution)

## API Reference

### Initialization

#### `bool Init_Genesis(int input_count)`
Initialize network with heuristic sparse topology.

**Parameters:**
- `input_count` - Number of input features (minimum 4 for heuristic mapping)

**Returns:**
- `true` if successful
- `false` if input_count < 4

**Example:**
```cpp
CNetwork net;
if(!net.Init_Genesis(4))
{
   Print("Failed to initialize network");
   return;
}
```

### Runtime

#### `bool FeedForward(double &inputs[], double &outputs[])`
Process inputs through the network to produce outputs.

**Parameters:**
- `inputs[]` - Input feature array (must have at least m_input_count elements)
- `outputs[]` - Output array (resized to 6 elements, values in [0.0, 1.0])

**Returns:**
- `true` if successful
- `false` if insufficient inputs

**Processing:**
1. Reset all node states
2. Iterative passes (3 iterations for recurrent support)
3. Activate nodes (Tanh for hidden, Sigmoid for output)
4. Extract 6 output values

**Example:**
```cpp
double inputs[4] = {0.5, 0.8, 0.3, -0.2};
double outputs[];

if(net.FeedForward(inputs, outputs))
{
   Print("BUY: ", outputs[IDX_BUY]);
   Print("SELL: ", outputs[IDX_SELL]);
   Print("FILTER: ", outputs[IDX_FILT]);
}
```

### Evolution (Mutation Operators)

#### `void Mutate()`
Probabilistic mutation dispatcher.

**Probabilities:**
- 5% chance: Add node (split link)
- 5% chance: Add link (new connection)
- 80% chance: Perturb weights (Gaussian jitter)

#### `void Mutate_AddNode()`
Split an existing link with a new hidden node.

**Operation:**
- Select random enabled link A→C
- Disable original link
- Create new hidden node B
- Create links: A→B (weight=1.0), B→C (weight=original)
- **Constraint**: Preserves signal flow

**Activation:** New hidden nodes use Tanh

#### `void Mutate_AddLink()`
Add a new connection between unconnected nodes.

**Operation:**
- Randomly select source (input or node)
- Randomly select target (hidden or output node)
- Check for duplicate (no duplicates allowed)
- Create link with random weight [-1.0, 1.0]

**Max Attempts:** 30 (to avoid infinite loops)

#### `void Mutate_PerturbWeights()`
Jitter all enabled link weights with Gaussian noise.

**Operation:**
- Iterate through all enabled links
- Add Gaussian noise: mean=0, stddev≈0.1
- Clamp weights to range [-5.0, 5.0]

**Gaussian Approximation:**
- Sum of 12 uniform random variables
- Center and scale: `(sum - 6.0) * 0.1`

### Getters

#### `int GetNodeCount()`
Returns current number of nodes in the network.

#### `int GetLinkCount()`
Returns current number of connections in the network.

## Activation Functions

### Sigmoid (Output Nodes)
```cpp
f(x) = 1.0 / (1.0 + exp(-x))
```
- **Range**: [0.0, 1.0]
- **Clamping**: x > 20 → 1.0, x < -20 → 0.0
- **Purpose**: Bounded output for control signals

### Tanh (Hidden Nodes)
```cpp
f(x) = (exp(x) - exp(-x)) / (exp(x) + exp(-x))
```
- **Range**: [-1.0, 1.0]
- **Clamping**: x > 20 → 1.0, x < -20 → -1.0
- **Purpose**: Hidden layer feature extraction

## Usage Example

### Basic Network Training Cycle
```cpp
#include "Include/Classes/CNetwork.mqh"
#include "Include/Classes/CInputManager.mqh"

void OnStart()
{
   // Initialize network
   CNetwork net;
   net.Init_Genesis(4);
   
   // Initialize input manager
   CInputManager inputMgr;
   inputMgr.Init(_Symbol, _Period);
   
   // Get market inputs
   double inputs[];
   inputMgr.GetInputs(4, inputs);
   
   // Process through network
   double outputs[];
   net.FeedForward(inputs, outputs);
   
   // Interpret signals
   if(outputs[IDX_FILT] > 0.5)  // Filter passes
   {
      if(outputs[IDX_BUY] > outputs[IDX_SELL])
      {
         double sl_ratio = outputs[IDX_SL];
         double tp_ratio = outputs[IDX_TP];
         double size_mult = outputs[IDX_SIZE];
         
         Print("BUY Signal - SL:", sl_ratio, " TP:", tp_ratio, " Size:", size_mult);
      }
   }
   
   // Evolve network
   for(int i = 0; i < 10; i++)
      net.Mutate();
   
   Print("Network evolved: ", net.GetNodeCount(), " nodes, ", 
         net.GetLinkCount(), " links");
}
```

### Integration with Training Loop
```cpp
void TrainingLoop()
{
   CNetwork population[50];
   
   // Initialize population
   for(int i = 0; i < 50; i++)
      population[i].Init_Genesis(4);
   
   // Training epochs
   for(int epoch = 0; epoch < 100; epoch++)
   {
      // Evaluate fitness for each network
      double fitness[50];
      
      for(int i = 0; i < 50; i++)
      {
         fitness[i] = EvaluateFitness(population[i]);
      }
      
      // Select best performers
      int best_indices[];
      SelectBest(fitness, best_indices, 10);
      
      // Mutate best to create next generation
      for(int i = 0; i < 50; i++)
      {
         int parent = best_indices[i % 10];
         population[i] = population[parent];  // Clone
         population[i].Mutate();              // Mutate
      }
      
      Print("Epoch ", epoch, " - Best fitness: ", fitness[best_indices[0]]);
   }
}
```

## Performance Characteristics

### Memory Footprint
- **Per Node**: ~50 bytes (struct size)
- **Per Link**: ~30 bytes (struct size)
- **Maximum**: 50 nodes × 50 bytes + links ≈ 2.5KB - 10KB

### Computational Complexity

#### FeedForward
- **Time**: O(L × I) where L=links, I=iterations
- **Typical**: 7 links × 3 iterations = 21 operations
- **Evolved**: 50 links × 3 iterations = 150 operations
- **Speed**: < 1ms on modern CPUs

#### Mutation
- **AddNode**: O(L) - linear in links
- **AddLink**: O(L × A) - attempts × link check
- **PerturbWeights**: O(L) - linear in links
- **Speed**: < 0.1ms

### Scaling Limits
- **MAX_NODES**: 50 (configurable, prevents CPU blowout)
- **Recommended**: 10-30 nodes for trading applications
- **Links**: Typically O(N²) worst case, sparse in practice

## Design Patterns

### Sparse Initialization
- Start minimal (7 connections)
- Grow through evolution
- Avoids premature complexity
- Faster initial training

### Link Preservation
- `Mutate_AddNode()` preserves signal flow
- Disabled links maintain history
- Enables undo/rollback in future versions

### Duplicate Prevention
- `LinkExists()` prevents redundant connections
- Maintains network efficiency
- Critical for mutation stability

## Known Constraints

### 1. Minimum Inputs
- Requires at least 4 inputs for heuristic mapping
- Can be initialized with more (just uses first 4 for heuristics)

### 2. Fixed Output Count
- Always 6 outputs (BUY, SELL, FILT, SL, TP, SIZE)
- Cannot be changed without code modification

### 3. Topological Processing
- Uses iterative passes (3 iterations)
- Not true topological sort
- Sufficient for shallow networks

### 4. No Backpropagation
- NEAT-style evolution only
- No gradient descent
- Requires fitness-based selection

## Future Enhancements (Optional)

1. **Innovation Numbers** - Track historical gene innovations (classic NEAT)
2. **Speciation** - Protect innovation through niche preservation
3. **Crossover** - Genetic recombination between networks
4. **Serialization** - Save/load network weights
5. **Visualization** - Export network topology as graph
6. **Topological Sort** - True DAG processing for non-recurrent
7. **Dynamic Activation** - Per-node activation function selection
8. **Adaptive Mutation Rates** - Self-adjusting probabilities

## Testing

### Unit Tests (TestNetwork.mq5)
1. Genesis initialization
2. FeedForward processing
3. Mutation operators
4. Boundary conditions
5. Integration with CInputManager
6. Consistency checks

### Validation Criteria
- ✅ All outputs in [0.0, 1.0] range
- ✅ FeedForward is deterministic
- ✅ Mutations respect constraints
- ✅ No duplicate links
- ✅ Node capacity limit enforced
- ✅ Signal flow preserved in AddNode

## Troubleshooting

### Issue: Outputs always near 0.5
**Cause**: Network not evolved or poor initialization
**Solution**: Run multiple mutations, ensure diverse weight initialization

### Issue: Mutations not working
**Cause**: Probabilities sum < 1.0 or wrong random seed
**Solution**: Check `Mutate()` probabilities, seed RNG with `MathSrand()`

### Issue: FeedForward inconsistent
**Cause**: Recurrent connections with insufficient iterations
**Solution**: Increase max_iterations in FeedForward (currently 3)

### Issue: Network grows too large
**Cause**: Too many AddNode mutations
**Solution**: Reduce AddNode probability or increase MAX_NODES limit

## References

- **NEAT Paper**: Stanley & Miikkulainen (2002) - "Evolving Neural Networks through Augmenting Topologies"
- **NEAT-Python**: https://neat-python.readthedocs.io/
- **MQL5 Documentation**: https://www.mql5.com/en/docs

---

**Implementation Status**: ✅ Complete  
**Version**: 1.0  
**Date**: 2024-12-09  
**Lines of Code**: ~520
