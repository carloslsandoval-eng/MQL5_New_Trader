# DistributedNeatManager - Multi-Agent NEAT Optimization

## Overview

`DistributedNeatManager.mqh` implements a distributed NEAT (NeuroEvolution of Augmenting Topologies) system for MetaTrader 5 (MT5). It enables multiple MT5 Agents (sandboxed instances) to collaboratively train a shared population of neural networks via the FILE_COMMON file system.

## Architecture

### State Machine Design

The system uses a distributed state machine with three main phases:

1. **TESTING Phase**: Agents checkout genomes, evaluate them, and report fitness
2. **EVOLVING Phase**: When all jobs complete, evolution runs automatically
3. **New Generation**: Fresh population with status reset to TESTING

### Components

#### 1. CFileMutex - File-Based Mutex

**Purpose**: Prevents race conditions between concurrent agents accessing shared state.

**Features**:
- RAII-style lock management (automatic release on scope exit)
- Spin-wait with configurable timeout (default: 30 seconds)
- Stale lock detection and automatic recovery
- Uses `neat.lock` file in FILE_COMMON directory

**Usage**:
```cpp
CFileMutex mutex;
if(mutex.TryLock())
{
   // Critical section - exclusive access to shared state
   // ...
   mutex.Release();  // Or automatic via destructor
}
```

#### 2. SNeatState - Global State Structure

**Fields**:
- `generation_id`: Current generation number
- `epoch_status`: STATUS_TESTING or STATUS_EVOLVING
- `innovation_db[]`: Historical mutation records (prevents duplicate innovations)
- `population[]`: Array of SGenome structures
- `innovation_counter`: Global innovation ID counter

**Persistence**: Serialized to `neat_state.bin` using FILE_COMMON | FILE_BIN.

#### 3. SGenome - Individual Structure

**Fields**:
- `id`: Unique genome identifier
- `nodes[]`: Neural network nodes (from CNetwork)
- `links[]`: Neural network connections (from CNetwork)
- `fitness`: Evaluated performance score
- `species_id`: Speciation cluster ID
- `job_status`: JOB_PENDING, JOB_BUSY, or JOB_DONE
- `job_start_time`: For timeout detection

#### 4. CDistributedNeatManager - Main Coordinator

**Key Methods**:

##### `InitializePopulation(int population_size, int input_count)`
- Creates initial population from scratch
- Uses CNetwork::Init_Genesis() for baseline topology
- Sets all jobs to JOB_PENDING
- Saves state to file

##### `GetNextJob(SGenome &genome)`
- **Atomic operation**: Lock → Load → Scan → Mark Busy → Save → Unlock
- Returns first JOB_PENDING genome
- Marks it JOB_BUSY with timestamp
- Returns `false` if no jobs available (evolution may be in progress)

##### `ReportFitness(int genome_id, double fitness)`
- **Atomic operation**: Lock → Load → Update → Check Complete → Evolve (if complete) → Save → Unlock
- Updates genome fitness and marks JOB_DONE
- If generation complete, triggers automatic evolution
- Returns `false` if genome not found

##### `GetGenerationInfo(int &gen_id, int &jobs_pending, int &jobs_done)`
- Non-blocking status query
- Returns current generation state

#### 5. CNeatCore - Evolution Logic Engine

**Methods**:

##### `Speciate(SGenome &population[])`
- Simplified distance-based clustering
- Groups by network complexity (node count)

##### `Crossover(SGenome &parent1, SGenome &parent2, SGenome &offspring)`
- Structure from fitter parent
- Weights mixed from both parents

##### `Mutate(SGenome &genome, SInnovation &innovations[], int &innovation_counter)`
- **Add Node** (5% chance): Splits link with new hidden node
- **Add Link** (5% chance): Connects unconnected nodes
- **Perturb Weights** (70% chance): Gaussian noise perturbation
- Innovation tracking prevents duplicate structural mutations

##### `EvolvePopulation(SNeatState &state)`
- Elitism: Preserves top 10% genomes
- Fitness-proportional parent selection
- 70% crossover, 30% asexual reproduction
- Mutation applied to all offspring
- Increments generation_id
- Resets all jobs to JOB_PENDING

## Configuration Constants

| Constant | Default | Description |
|----------|---------|-------------|
| `LOCK_TIMEOUT_MS` | 30000 | Max time to wait for lock (30 sec) |
| `LOCK_RETRY_MS` | 100 | Lock retry interval |
| `JOB_TIMEOUT_MS` | 600000 | Job timeout before reset (10 min) |
| `MAX_POPULATION` | 100 | Maximum population size |
| `INNOVATION_CAP` | 10000 | Max innovation records |
| `MIN_INITIAL_LINKS` | 4 | Minimum initial connections |
| `INITIAL_LINK_RANGE` | 4 | Random link count range (4-7) |

## Workflow Example

### Single Agent Workflow

```cpp
// 1. Initialize manager
CDistributedNeatManager manager;
manager.Init("neat_state.bin");

// 2. Initialize population (first agent only)
manager.InitializePopulation(50, 4);

// 3. Agent loop
while(true)
{
   SGenome job;
   if(manager.GetNextJob(job))
   {
      // 4. Evaluate genome
      CNetwork net;
      // ... reconstruct network from job.nodes and job.links
      // ... run simulation
      double fitness = CalculateFitness(net);
      
      // 5. Report results
      manager.ReportFitness(job.id, fitness);
   }
   else
   {
      // No jobs available or evolution in progress
      Sleep(1000);
   }
}
```

### Multi-Agent Workflow

**Agent 1** (Master):
```cpp
manager.InitializePopulation(50, 4);
// Evaluates genomes 0-16 (1/3 of population)
```

**Agent 2**:
```cpp
manager.Init();  // Loads existing state
// Evaluates genomes 17-33 (1/3 of population)
```

**Agent 3**:
```cpp
manager.Init();  // Loads existing state
// Evaluates genomes 34-49 (1/3 of population)
```

**Result**: All agents contribute. When the last job completes, evolution runs automatically, and all agents move to the next generation.

## Error Handling

### Stale Job Detection
- Jobs marked JOB_BUSY for >10 minutes are reset to JOB_PENDING
- Handles agent crashes gracefully

### Stale Lock Recovery
- Locks older than LOCK_TIMEOUT_MS are automatically deleted
- Prevents permanent deadlock from agent crashes

### File Corruption
- Binary format with sequential reads/writes
- If corruption detected, manual reset required (delete state file)

## Performance Considerations

### Lock Contention
- Minimize critical section time
- Only lock during state transitions
- Avoid holding lock during evaluation

### File I/O Overhead
- Binary format for speed
- Sequential writes minimize fragmentation
- Consider SSD for FILE_COMMON directory

### Population Size
- Larger populations = more parallelism
- Recommended: Population size ≥ 2x number of agents
- Max: 100 (configurable via MAX_POPULATION)

## Testing

See `Examples/TestDistributedNeatManager.mq5` for comprehensive test suite:

1. **Initialization Test**: Population creation
2. **Job Checkout Test**: Simulates multiple agents
3. **Fitness Reporting Test**: Job completion tracking
4. **Generation Completion Test**: Evolution triggering
5. **FileMutex Stress Test**: Concurrent lock attempts
6. **State Persistence Test**: File I/O validation
7. **Multi-Generation Test**: Full lifecycle

Run with:
```
MetaEditor → Tools → Run Script → TestDistributedNeatManager
```

## Integration with CNetwork

The DistributedNeatManager uses CNetwork structures directly:
- `SNode`: Neural network nodes
- `SLink`: Neural network connections
- `ENUM_NODE_TYPE`: Input/Hidden/Output types
- `ENUM_ACTIVATION`: Sigmoid/Tanh activation functions

Agents reconstruct CNetwork instances from SGenome data for evaluation.

## Limitations

1. **No Centralized Coordinator**: First agent to report last fitness triggers evolution
2. **Simplified Speciation**: Distance metric based only on node count
3. **Binary Serialization**: Not human-readable (use debugging tools)
4. **Single Machine**: FILE_COMMON is local to one MT5 installation
5. **No Checkpointing**: Crash during evolution loses progress (rare)

## Future Enhancements

- [ ] TCP/IP coordination for multi-machine scaling
- [ ] Advanced speciation (genetic distance calculation)
- [ ] Checkpoint/resume during evolution
- [ ] Adaptive mutation rates
- [ ] Novelty search option
- [ ] Parallel evolution (island model)

## License

Copyright 2024, Carlos Sandoval

## See Also

- `CNetwork.mqh`: Neural network implementation
- `CInputManager.mqh`: Feature engineering
- `TestDistributedNeatManager.mq5`: Test suite
