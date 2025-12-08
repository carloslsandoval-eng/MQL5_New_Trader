# MQL5_New_Trader

## CNetwork - Neural Network for Trading

This repository contains a standalone MQL5 neural network class (`CNetwork`) designed for evolutionary trading algorithms.

### Features

- **Standalone Implementation**: No external dependencies
- **Dynamic Architecture**: Variable input nodes, 5 fixed output nodes (Buy, Sell, Filter, SL, TP)
- **NEAT-Inspired**: Innovation-based genes, topological sorting for execution
- **Three Mutation Types**:
  - **Lateral**: Add new input → hidden → output paths
  - **Memory**: Add recurrent connections for temporal processing
  - **Depth**: Split connections to increase network depth
- **Efficient Execution**: Topologically sorted feedforward propagation
- **Persistence**: Save/Load network topology and weights

### Quick Start

```mql5
#include "Include/Network/CNetwork.mqh"

// Initialize network with 3 inputs
CNetwork network;
network.Initialize(3);

// Feed forward
double inputs[3] = {0.5, -0.3, 0.8};
network.FeedForward(inputs);

// Get outputs
double buySignal = network.GetOutput(OUT_BUY);
double sellSignal = network.GetOutput(OUT_SELL);

// Mutate network
network.MutateLateral();  // Add complexity
network.MutateMemory();   // Add recurrence
network.MutateDepth();    // Add depth
```

### Documentation

- See `Include/Network/README.md` for detailed documentation
- See `Examples/NetworkExample.mq5` for comprehensive usage examples

### Architecture

- **Dynamic Inputs**: Adapt to different numbers of market indicators
- **5 Fixed Outputs**: Buy, Sell, Filter, Stop Loss, Take Profit
- **Genes Sorted by Innovation**: Compatible with genetic algorithms
- **Topological Execution**: Fast, single-pass feedforward
- **Recurrent Buffers**: Support for memory (initialized to 0, not persisted)

### File Structure

```
MQL5_New_Trader/
├── Include/
│   └── Network/
│       ├── CNetwork.mqh      # Main network class
│       └── README.md          # Detailed documentation
├── Examples/
│   └── NetworkExample.mq5    # Usage examples
└── README.md                  # This file
```

### Usage in Trading

The CNetwork class is designed for evolutionary trading systems:

1. Initialize population of networks
2. Evaluate fitness on historical data
3. Apply mutations to top performers
4. Repeat evolution process

Output nodes provide:
- **Buy/Sell**: Trading signals
- **Filter**: Signal filtering/confidence
- **SL/TP**: Dynamic stop loss and take profit levels

### License

Copyright 2024