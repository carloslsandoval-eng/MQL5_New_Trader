//+------------------------------------------------------------------+
//|                                     DistributedNeatManager.mqh |
//|                                  Copyright 2024, Carlos Sandoval |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Carlos Sandoval"
#property link      ""
#property strict

#include "CNetwork.mqh"

//+------------------------------------------------------------------+
//| Enums and Constants                                               |
//+------------------------------------------------------------------+
enum ENUM_EPOCH_STATUS
{
   STATUS_TESTING,    // Agents are evaluating genomes
   STATUS_EVOLVING    // Evolution in progress
};

enum ENUM_JOB_STATUS
{
   JOB_PENDING,       // Ready to be assigned
   JOB_BUSY,          // Agent is working on it
   JOB_DONE           // Fitness reported
};

#define LOCK_TIMEOUT_MS    30000    // 30 seconds max lock wait
#define LOCK_RETRY_MS      100      // Retry every 100ms
#define JOB_TIMEOUT_MS     600000   // 10 minutes job timeout
#define MAX_POPULATION     100      // Population size cap
#define INNOVATION_CAP     10000    // Max innovation records
#define RAND_MAX_MQL5      32767.0  // MQL5 MathRand() max value
#define ARRAY_IDX_EPSILON  0.001    // Small value to avoid array boundary issues
#define GAUSS_SAMPLES      12       // Samples for Gaussian approximation
#define GAUSS_MEAN         6.0      // Mean adjustment for Gaussian
#define GAUSS_STDDEV       0.1      // Standard deviation for weight perturbation
#define MIN_INITIAL_LINKS  4        // Minimum initial links per genome
#define INITIAL_LINK_RANGE 4        // Random range added to minimum links

//+------------------------------------------------------------------+
//| Structures                                                         |
//+------------------------------------------------------------------+

// Innovation record for historical mutations
struct SInnovation
{
   int               id;
   int               in_node;
   int               out_node;
   int               new_node;        // -1 if link mutation
   datetime          timestamp;
};

// Genome represents a single individual
struct SGenome
{
   int               id;
   SNode             nodes[];
   SLink             links[];
   double            fitness;
   int               species_id;
   datetime          job_start_time;  // For timeout detection
   ENUM_JOB_STATUS   job_status;
};

// Global NEAT state
struct SNeatState
{
   int               generation_id;
   ENUM_EPOCH_STATUS epoch_status;
   SInnovation       innovation_db[];
   SGenome           population[];
   int               innovation_counter;
};

//+------------------------------------------------------------------+
//| FileMutex Class - RAII-style file lock                           |
//+------------------------------------------------------------------+
class CFileMutex
{
private:
   string            m_lock_file;
   bool              m_is_locked;
   datetime          m_lock_start;
   
public:
                     CFileMutex();
                    ~CFileMutex();
   
   bool              TryLock();
   void              Release();
   bool              IsLocked() { return m_is_locked; }
};

//+------------------------------------------------------------------+
CFileMutex::CFileMutex()
{
   m_lock_file = "neat.lock";
   m_is_locked = false;
   m_lock_start = 0;
}

//+------------------------------------------------------------------+
CFileMutex::~CFileMutex()
{
   Release();
}

//+------------------------------------------------------------------+
// Try to acquire lock with spin-wait and timeout
//+------------------------------------------------------------------+
bool CFileMutex::TryLock()
{
   if(m_is_locked)
      return true;  // Already locked by this instance
   
   datetime start_time = TimeLocal();
   
   while(true)
   {
      // Check timeout
      datetime now = TimeLocal();
      if((now - start_time) * 1000 > LOCK_TIMEOUT_MS)
      {
         Print("ERROR: Lock timeout after ", LOCK_TIMEOUT_MS, "ms");
         return false;
      }
      
      // Try to open/create lock file
      int handle = FileOpen(m_lock_file, FILE_COMMON | FILE_BIN | FILE_READ | FILE_WRITE);
      
      if(handle == INVALID_HANDLE)
      {
         // File might be locked, wait and retry
         Sleep(LOCK_RETRY_MS);
         continue;
      }
      
      // Check if file is empty (not locked by another agent)
      if(FileSize(handle) == 0)
      {
         // Acquire lock by writing timestamp
         FileWriteLong(handle, now);
         FileFlush(handle);
         FileClose(handle);
         
         m_is_locked = true;
         m_lock_start = now;
         return true;
      }
      else
      {
         // File has content, check if stale
         datetime lock_time = (datetime)FileReadLong(handle);
         FileClose(handle);
         
         // If lock is older than timeout, consider it stale
         if((now - lock_time) * 1000 > LOCK_TIMEOUT_MS)
         {
            // Force release stale lock
            FileDelete(m_lock_file, FILE_COMMON);
            Sleep(LOCK_RETRY_MS);
            continue;
         }
         
         // Lock is active, wait
         Sleep(LOCK_RETRY_MS);
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
// Release lock
//+------------------------------------------------------------------+
void CFileMutex::Release()
{
   if(m_is_locked)
   {
      FileDelete(m_lock_file, FILE_COMMON);
      m_is_locked = false;
      m_lock_start = 0;
   }
}

//+------------------------------------------------------------------+
//| NeatCore Class - Evolution Logic Engine                          |
//+------------------------------------------------------------------+
class CNeatCore
{
private:
   double            RandomRange(double min, double max);
   int               SelectParent(SGenome &population[], double total_fitness);
   void              CopyGenome(SGenome &src, SGenome &dst);
   
public:
                     CNeatCore();
                    ~CNeatCore();
   
   void              Speciate(SGenome &population[]);
   void              Crossover(SGenome &parent1, SGenome &parent2, SGenome &offspring);
   void              Mutate(SGenome &genome, SInnovation &innovations[], int &innovation_counter);
   void              EvolvePopulation(SNeatState &state);
};

//+------------------------------------------------------------------+
CNeatCore::CNeatCore()
{
}

//+------------------------------------------------------------------+
CNeatCore::~CNeatCore()
{
}

//+------------------------------------------------------------------+
// Simple random range helper
//+------------------------------------------------------------------+
double CNeatCore::RandomRange(double min, double max)
{
   double norm = MathRand() / RAND_MAX_MQL5;
   return min + (max - min) * norm;
}

//+------------------------------------------------------------------+
// Select parent using fitness-proportional selection
//+------------------------------------------------------------------+
int CNeatCore::SelectParent(SGenome &population[], double total_fitness)
{
   if(total_fitness <= 0.0)
   {
      // Random selection if no fitness
      return (int)(RandomRange(0, ArraySize(population) - ARRAY_IDX_EPSILON));
   }
   
   double spin = RandomRange(0.0, total_fitness);
   double cumulative = 0.0;
   
   int pop_size = ArraySize(population);
   for(int i = 0; i < pop_size; i++)
   {
      cumulative += MathMax(0.0, population[i].fitness);
      if(cumulative >= spin)
         return i;
   }
   
   return pop_size - 1;
}

//+------------------------------------------------------------------+
// Copy genome structure
//+------------------------------------------------------------------+
void CNeatCore::CopyGenome(SGenome &src, SGenome &dst)
{
   dst.id = src.id;
   dst.fitness = src.fitness;
   dst.species_id = src.species_id;
   dst.job_status = src.job_status;
   dst.job_start_time = src.job_start_time;
   
   int node_count = ArraySize(src.nodes);
   ArrayResize(dst.nodes, node_count);
   for(int i = 0; i < node_count; i++)
      dst.nodes[i] = src.nodes[i];
   
   int link_count = ArraySize(src.links);
   ArrayResize(dst.links, link_count);
   for(int i = 0; i < link_count; i++)
      dst.links[i] = src.links[i];
}

//+------------------------------------------------------------------+
// Speciate population (simplified - distance-based clustering)
//+------------------------------------------------------------------+
void CNeatCore::Speciate(SGenome &population[])
{
   // Simplified: Assign species based on genome size similarity
   int pop_size = ArraySize(population);
   
   for(int i = 0; i < pop_size; i++)
   {
      int node_count = ArraySize(population[i].nodes);
      // Simple clustering: species 0-3 based on node count
      if(node_count < 10)
         population[i].species_id = 0;
      else if(node_count < 20)
         population[i].species_id = 1;
      else if(node_count < 30)
         population[i].species_id = 2;
      else
         population[i].species_id = 3;
   }
}

//+------------------------------------------------------------------+
// Crossover two parents (simplified)
//+------------------------------------------------------------------+
void CNeatCore::Crossover(SGenome &parent1, SGenome &parent2, SGenome &offspring)
{
   // Simplified: Copy structure from fitter parent, weights from both
   SGenome &better = (parent1.fitness > parent2.fitness) ? parent1 : parent2;
   CopyGenome(better, offspring);
   
   // Randomly mix weights from both parents
   int link_count = ArraySize(offspring.links);
   for(int i = 0; i < link_count; i++)
   {
      if(RandomRange(0.0, 1.0) < 0.5)
      {
         // Try to find matching link in other parent
         for(int j = 0; j < ArraySize(parent2.links); j++)
         {
            if(parent2.links[j].in_node_id == offspring.links[i].in_node_id &&
               parent2.links[j].out_node_id == offspring.links[i].out_node_id)
            {
               offspring.links[i].weight = parent2.links[j].weight;
               break;
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
// Mutate genome with innovation tracking
//+------------------------------------------------------------------+
void CNeatCore::Mutate(SGenome &genome, SInnovation &innovations[], int &innovation_counter)
{
   double rnd = RandomRange(0.0, 1.0);
   
   if(rnd < 0.05)
   {
      // Add node mutation
      int link_count = ArraySize(genome.links);
      if(link_count > 0)
      {
         int link_idx = (int)(RandomRange(0, link_count - ARRAY_IDX_EPSILON));
         if(genome.links[link_idx].enabled)
         {
            int in_id = genome.links[link_idx].in_node_id;
            int out_id = genome.links[link_idx].out_node_id;
            
            // Check innovation history
            int innovation_id = -1;
            for(int i = 0; i < ArraySize(innovations); i++)
            {
               if(innovations[i].in_node == in_id && 
                  innovations[i].out_node == out_id &&
                  innovations[i].new_node >= 0)
               {
                  innovation_id = innovations[i].new_node;
                  break;
               }
            }
            
            if(innovation_id < 0)
            {
               // New innovation
               innovation_id = innovation_counter++;
               
               // Record innovation
               int innov_size = ArraySize(innovations);
               if(innov_size < INNOVATION_CAP)
               {
                  ArrayResize(innovations, innov_size + 1);
                  innovations[innov_size].id = innov_size;
                  innovations[innov_size].in_node = in_id;
                  innovations[innov_size].out_node = out_id;
                  innovations[innov_size].new_node = innovation_id;
                  innovations[innov_size].timestamp = TimeLocal();
               }
            }
            
            // Disable old link
            genome.links[link_idx].enabled = false;
            
            // Add new node
            int node_count = ArraySize(genome.nodes);
            ArrayResize(genome.nodes, node_count + 1);
            genome.nodes[node_count].id = innovation_id;
            genome.nodes[node_count].type = NODE_HIDDEN;
            genome.nodes[node_count].activation = ACT_TANH;
            genome.nodes[node_count].bias = 0.0;
            genome.nodes[node_count].response = 1.0;
            
            // Add two new links
            int new_link_count = ArraySize(genome.links) + 2;
            ArrayResize(genome.links, new_link_count);
            
            genome.links[new_link_count - 2].in_node_id = in_id;
            genome.links[new_link_count - 2].out_node_id = innovation_id;
            genome.links[new_link_count - 2].weight = 1.0;
            genome.links[new_link_count - 2].enabled = true;
            
            genome.links[new_link_count - 1].in_node_id = innovation_id;
            genome.links[new_link_count - 1].out_node_id = out_id;
            genome.links[new_link_count - 1].weight = genome.links[link_idx].weight;
            genome.links[new_link_count - 1].enabled = true;
         }
      }
   }
   else if(rnd < 0.10)
   {
      // Add link mutation (simplified)
      int node_count = ArraySize(genome.nodes);
      if(node_count > 0)
      {
         int link_count = ArraySize(genome.links);
         ArrayResize(genome.links, link_count + 1);
         
         // Random connection
         int in_idx = (int)(RandomRange(0, node_count - ARRAY_IDX_EPSILON));
         int out_idx = (int)(RandomRange(0, node_count - ARRAY_IDX_EPSILON));
         
         genome.links[link_count].in_node_id = genome.nodes[in_idx].id;
         genome.links[link_count].out_node_id = genome.nodes[out_idx].id;
         genome.links[link_count].weight = RandomRange(-1.0, 1.0);
         genome.links[link_count].enabled = true;
      }
   }
   else if(rnd < 0.80)
   {
      // Perturb weights
      int link_count = ArraySize(genome.links);
      for(int i = 0; i < link_count; i++)
      {
         if(genome.links[i].enabled)
         {
            double gauss = 0.0;
            for(int j = 0; j < GAUSS_SAMPLES; j++)
               gauss += RandomRange(0.0, 1.0);
            gauss = (gauss - GAUSS_MEAN) * GAUSS_STDDEV;
            
            genome.links[i].weight += gauss;
            genome.links[i].weight = MathMax(-5.0, MathMin(5.0, genome.links[i].weight));
         }
      }
   }
}

//+------------------------------------------------------------------+
// Evolve entire population
//+------------------------------------------------------------------+
void CNeatCore::EvolvePopulation(SNeatState &state)
{
   int pop_size = ArraySize(state.population);
   if(pop_size == 0)
      return;
   
   // Calculate total fitness
   double total_fitness = 0.0;
   for(int i = 0; i < pop_size; i++)
      total_fitness += MathMax(0.0, state.population[i].fitness);
   
   // Speciate
   Speciate(state.population);
   
   // Create new population
   SGenome new_population[];
   ArrayResize(new_population, pop_size);
   
   // Elitism: Keep best 10%
   int elite_count = (int)(pop_size * 0.1);
   if(elite_count < 1) elite_count = 1;
   
   // Sort by fitness (simple bubble sort for small populations)
   for(int i = 0; i < pop_size - 1; i++)
   {
      for(int j = i + 1; j < pop_size; j++)
      {
         if(state.population[j].fitness > state.population[i].fitness)
         {
            SGenome temp;
            CopyGenome(state.population[i], temp);
            CopyGenome(state.population[j], state.population[i]);
            CopyGenome(temp, state.population[j]);
         }
      }
   }
   
   // Copy elite
   for(int i = 0; i < elite_count; i++)
      CopyGenome(state.population[i], new_population[i]);
   
   // Generate rest through crossover and mutation
   for(int i = elite_count; i < pop_size; i++)
   {
      int parent1_idx = SelectParent(state.population, total_fitness);
      int parent2_idx = SelectParent(state.population, total_fitness);
      
      if(RandomRange(0.0, 1.0) < 0.7)
      {
         // Crossover
         Crossover(state.population[parent1_idx], state.population[parent2_idx], new_population[i]);
      }
      else
      {
         // Asexual reproduction
         CopyGenome(state.population[parent1_idx], new_population[i]);
      }
      
      // Mutate
      Mutate(new_population[i], state.innovation_db, state.innovation_counter);
      
      // Reset for next generation
      new_population[i].fitness = 0.0;
      new_population[i].job_status = JOB_PENDING;
      new_population[i].job_start_time = 0;
      new_population[i].id = i;
   }
   
   // Replace population
   ArrayResize(state.population, pop_size);
   for(int i = 0; i < pop_size; i++)
      CopyGenome(new_population[i], state.population[i]);
   
   // Increment generation
   state.generation_id++;
   state.epoch_status = STATUS_TESTING;
   
   Print("Evolution complete. Generation: ", state.generation_id);
}

//+------------------------------------------------------------------+
//| DistributedNeatManager Class - Main Coordinator                  |
//+------------------------------------------------------------------+
class CDistributedNeatManager
{
private:
   string            m_state_file;
   CFileMutex        m_mutex;
   CNeatCore         m_core;
   
   bool              LoadState(SNeatState &state);
   bool              SaveState(SNeatState &state);
   bool              CheckGenerationComplete(SNeatState &state);
   void              ResetStaleJobs(SNeatState &state);
   
public:
                     CDistributedNeatManager();
                    ~CDistributedNeatManager();
   
   bool              Init(string state_file = "neat_state.bin");
   bool              InitializePopulation(int population_size, int input_count);
   bool              GetNextJob(SGenome &genome);
   bool              ReportFitness(int genome_id, double fitness);
   bool              GetGenerationInfo(int &gen_id, int &jobs_pending, int &jobs_done);
};

//+------------------------------------------------------------------+
CDistributedNeatManager::CDistributedNeatManager()
{
   m_state_file = "neat_state.bin";
}

//+------------------------------------------------------------------+
CDistributedNeatManager::~CDistributedNeatManager()
{
}

//+------------------------------------------------------------------+
// Initialize manager
//+------------------------------------------------------------------+
bool CDistributedNeatManager::Init(string state_file)
{
   m_state_file = state_file;
   return true;
}

//+------------------------------------------------------------------+
// Initialize population from scratch
//+------------------------------------------------------------------+
bool CDistributedNeatManager::InitializePopulation(int population_size, int input_count)
{
   if(population_size > MAX_POPULATION)
   {
      Print("ERROR: Population size exceeds maximum (", MAX_POPULATION, ")");
      return false;
   }
   
   if(!m_mutex.TryLock())
   {
      Print("ERROR: Failed to acquire lock for initialization");
      return false;
   }
   
   SNeatState state;
   state.generation_id = 0;
   state.epoch_status = STATUS_TESTING;
   state.innovation_counter = 1000;  // Start after node IDs
   
   ArrayResize(state.innovation_db, 0);
   ArrayResize(state.population, population_size);
   
   // Create initial population
   for(int i = 0; i < population_size; i++)
   {
      state.population[i].id = i;
      state.population[i].fitness = 0.0;
      state.population[i].species_id = 0;
      state.population[i].job_status = JOB_PENDING;
      state.population[i].job_start_time = 0;
      
      // Create minimal network structure
      CNetwork temp_net;
      if(temp_net.Init_Genesis(input_count))
      {
         // Extract network structure
         ArrayResize(state.population[i].nodes, CNT_OUT);
         for(int j = 0; j < CNT_OUT; j++)
         {
            state.population[i].nodes[j].id = j;
            state.population[i].nodes[j].type = NODE_OUTPUT;
            state.population[i].nodes[j].activation = ACT_SIGMOID;
            state.population[i].nodes[j].bias = 0.0;
            state.population[i].nodes[j].response = 1.0;
         }
         
         // Add some random initial connections
         int init_links = MIN_INITIAL_LINKS + (int)(MathRand() % INITIAL_LINK_RANGE);  // 4-7 links
         ArrayResize(state.population[i].links, init_links);
         
         for(int j = 0; j < init_links; j++)
         {
            int in_id = (int)(MathRand() % input_count);
            int out_id = (int)(MathRand() % CNT_OUT);
            
            state.population[i].links[j].in_node_id = in_id;
            state.population[i].links[j].out_node_id = out_id;
            state.population[i].links[j].weight = (MathRand() / RAND_MAX_MQL5) * 2.0 - 1.0;
            state.population[i].links[j].enabled = true;
            state.population[i].links[j].recurrent = false;
         }
      }
   }
   
   bool success = SaveState(state);
   m_mutex.Release();
   
   if(success)
      Print("Population initialized. Size: ", population_size, " Generation: 0");
   
   return success;
}

//+------------------------------------------------------------------+
// Get next job for this agent
//+------------------------------------------------------------------+
bool CDistributedNeatManager::GetNextJob(SGenome &genome)
{
   if(!m_mutex.TryLock())
      return false;
   
   SNeatState state;
   if(!LoadState(state))
   {
      m_mutex.Release();
      return false;
   }
   
   // Reset stale jobs
   ResetStaleJobs(state);
   
   // Scan for pending job
   int pop_size = ArraySize(state.population);
   for(int i = 0; i < pop_size; i++)
   {
      if(state.population[i].job_status == JOB_PENDING)
      {
         // Mark as busy
         state.population[i].job_status = JOB_BUSY;
         state.population[i].job_start_time = TimeLocal();
         
         // Copy genome to output
         int node_count = ArraySize(state.population[i].nodes);
         ArrayResize(genome.nodes, node_count);
         for(int j = 0; j < node_count; j++)
            genome.nodes[j] = state.population[i].nodes[j];
         
         int link_count = ArraySize(state.population[i].links);
         ArrayResize(genome.links, link_count);
         for(int j = 0; j < link_count; j++)
            genome.links[j] = state.population[i].links[j];
         
         genome.id = state.population[i].id;
         genome.fitness = state.population[i].fitness;
         genome.species_id = state.population[i].species_id;
         genome.job_status = state.population[i].job_status;
         genome.job_start_time = state.population[i].job_start_time;
         
         SaveState(state);
         m_mutex.Release();
         return true;
      }
   }
   
   // No pending jobs - check if generation complete
   if(CheckGenerationComplete(state))
   {
      // Trigger evolution
      if(state.epoch_status == STATUS_TESTING)
      {
         Print("Generation ", state.generation_id, " complete. Starting evolution...");
         state.epoch_status = STATUS_EVOLVING;
         m_core.EvolvePopulation(state);
         SaveState(state);
      }
   }
   
   m_mutex.Release();
   return false;  // No job available, wait
}

//+------------------------------------------------------------------+
// Report fitness for completed job
//+------------------------------------------------------------------+
bool CDistributedNeatManager::ReportFitness(int genome_id, double fitness)
{
   if(!m_mutex.TryLock())
      return false;
   
   SNeatState state;
   if(!LoadState(state))
   {
      m_mutex.Release();
      return false;
   }
   
   // Find genome
   int pop_size = ArraySize(state.population);
   bool found = false;
   
   for(int i = 0; i < pop_size; i++)
   {
      if(state.population[i].id == genome_id)
      {
         state.population[i].fitness = fitness;
         state.population[i].job_status = JOB_DONE;
         found = true;
         break;
      }
   }
   
   if(!found)
   {
      Print("ERROR: Genome ID ", genome_id, " not found");
      m_mutex.Release();
      return false;
   }
   
   // Check if generation complete
   if(CheckGenerationComplete(state))
   {
      if(state.epoch_status == STATUS_TESTING)
      {
         Print("Generation ", state.generation_id, " complete. Starting evolution...");
         state.epoch_status = STATUS_EVOLVING;
         m_core.EvolvePopulation(state);
      }
   }
   
   SaveState(state);
   m_mutex.Release();
   
   Print("Fitness reported for genome ", genome_id, ": ", fitness);
   return true;
}

//+------------------------------------------------------------------+
// Get generation info
//+------------------------------------------------------------------+
bool CDistributedNeatManager::GetGenerationInfo(int &gen_id, int &jobs_pending, int &jobs_done)
{
   if(!m_mutex.TryLock())
      return false;
   
   SNeatState state;
   if(!LoadState(state))
   {
      m_mutex.Release();
      return false;
   }
   
   gen_id = state.generation_id;
   jobs_pending = 0;
   jobs_done = 0;
   
   int pop_size = ArraySize(state.population);
   for(int i = 0; i < pop_size; i++)
   {
      if(state.population[i].job_status == JOB_PENDING || state.population[i].job_status == JOB_BUSY)
         jobs_pending++;
      else if(state.population[i].job_status == JOB_DONE)
         jobs_done++;
   }
   
   m_mutex.Release();
   return true;
}

//+------------------------------------------------------------------+
// Load state from file
//+------------------------------------------------------------------+
bool CDistributedNeatManager::LoadState(SNeatState &state)
{
   int handle = FileOpen(m_state_file, FILE_COMMON | FILE_BIN | FILE_READ);
   if(handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot open state file for reading");
      return false;
   }
   
   // Read header
   state.generation_id = FileReadInteger(handle);
   state.epoch_status = (ENUM_EPOCH_STATUS)FileReadInteger(handle);
   state.innovation_counter = FileReadInteger(handle);
   
   // Read innovation DB
   int innov_size = FileReadInteger(handle);
   ArrayResize(state.innovation_db, innov_size);
   for(int i = 0; i < innov_size; i++)
   {
      state.innovation_db[i].id = FileReadInteger(handle);
      state.innovation_db[i].in_node = FileReadInteger(handle);
      state.innovation_db[i].out_node = FileReadInteger(handle);
      state.innovation_db[i].new_node = FileReadInteger(handle);
      state.innovation_db[i].timestamp = (datetime)FileReadLong(handle);
   }
   
   // Read population
   int pop_size = FileReadInteger(handle);
   ArrayResize(state.population, pop_size);
   
   for(int i = 0; i < pop_size; i++)
   {
      state.population[i].id = FileReadInteger(handle);
      state.population[i].fitness = FileReadDouble(handle);
      state.population[i].species_id = FileReadInteger(handle);
      state.population[i].job_start_time = (datetime)FileReadLong(handle);
      state.population[i].job_status = (ENUM_JOB_STATUS)FileReadInteger(handle);
      
      // Read nodes
      int node_count = FileReadInteger(handle);
      ArrayResize(state.population[i].nodes, node_count);
      for(int j = 0; j < node_count; j++)
      {
         state.population[i].nodes[j].id = FileReadInteger(handle);
         state.population[i].nodes[j].type = (ENUM_NODE_TYPE)FileReadInteger(handle);
         state.population[i].nodes[j].bias = FileReadDouble(handle);
         state.population[i].nodes[j].response = FileReadDouble(handle);
         state.population[i].nodes[j].activation = (ENUM_ACTIVATION)FileReadInteger(handle);
      }
      
      // Read links
      int link_count = FileReadInteger(handle);
      ArrayResize(state.population[i].links, link_count);
      for(int j = 0; j < link_count; j++)
      {
         state.population[i].links[j].in_node_id = FileReadInteger(handle);
         state.population[i].links[j].out_node_id = FileReadInteger(handle);
         state.population[i].links[j].weight = FileReadDouble(handle);
         state.population[i].links[j].enabled = (bool)FileReadInteger(handle);
         state.population[i].links[j].recurrent = (bool)FileReadInteger(handle);
      }
   }
   
   FileClose(handle);
   return true;
}

//+------------------------------------------------------------------+
// Save state to file
//+------------------------------------------------------------------+
bool CDistributedNeatManager::SaveState(SNeatState &state)
{
   int handle = FileOpen(m_state_file, FILE_COMMON | FILE_BIN | FILE_WRITE);
   if(handle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot open state file for writing");
      return false;
   }
   
   // Write header
   FileWriteInteger(handle, state.generation_id);
   FileWriteInteger(handle, (int)state.epoch_status);
   FileWriteInteger(handle, state.innovation_counter);
   
   // Write innovation DB
   int innov_size = ArraySize(state.innovation_db);
   FileWriteInteger(handle, innov_size);
   for(int i = 0; i < innov_size; i++)
   {
      FileWriteInteger(handle, state.innovation_db[i].id);
      FileWriteInteger(handle, state.innovation_db[i].in_node);
      FileWriteInteger(handle, state.innovation_db[i].out_node);
      FileWriteInteger(handle, state.innovation_db[i].new_node);
      FileWriteLong(handle, (long)state.innovation_db[i].timestamp);
   }
   
   // Write population
   int pop_size = ArraySize(state.population);
   FileWriteInteger(handle, pop_size);
   
   for(int i = 0; i < pop_size; i++)
   {
      FileWriteInteger(handle, state.population[i].id);
      FileWriteDouble(handle, state.population[i].fitness);
      FileWriteInteger(handle, state.population[i].species_id);
      FileWriteLong(handle, (long)state.population[i].job_start_time);
      FileWriteInteger(handle, (int)state.population[i].job_status);
      
      // Write nodes
      int node_count = ArraySize(state.population[i].nodes);
      FileWriteInteger(handle, node_count);
      for(int j = 0; j < node_count; j++)
      {
         FileWriteInteger(handle, state.population[i].nodes[j].id);
         FileWriteInteger(handle, (int)state.population[i].nodes[j].type);
         FileWriteDouble(handle, state.population[i].nodes[j].bias);
         FileWriteDouble(handle, state.population[i].nodes[j].response);
         FileWriteInteger(handle, (int)state.population[i].nodes[j].activation);
      }
      
      // Write links
      int link_count = ArraySize(state.population[i].links);
      FileWriteInteger(handle, link_count);
      for(int j = 0; j < link_count; j++)
      {
         FileWriteInteger(handle, state.population[i].links[j].in_node_id);
         FileWriteInteger(handle, state.population[i].links[j].out_node_id);
         FileWriteDouble(handle, state.population[i].links[j].weight);
         FileWriteInteger(handle, (int)state.population[i].links[j].enabled);
         FileWriteInteger(handle, (int)state.population[i].links[j].recurrent);
      }
   }
   
   FileFlush(handle);
   FileClose(handle);
   return true;
}

//+------------------------------------------------------------------+
// Check if generation is complete
//+------------------------------------------------------------------+
bool CDistributedNeatManager::CheckGenerationComplete(SNeatState &state)
{
   int pop_size = ArraySize(state.population);
   
   for(int i = 0; i < pop_size; i++)
   {
      if(state.population[i].job_status != JOB_DONE)
         return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
// Reset stale jobs (timeout detection)
//+------------------------------------------------------------------+
void CDistributedNeatManager::ResetStaleJobs(SNeatState &state)
{
   datetime now = TimeLocal();
   int pop_size = ArraySize(state.population);
   
   for(int i = 0; i < pop_size; i++)
   {
      if(state.population[i].job_status == JOB_BUSY)
      {
         datetime start = state.population[i].job_start_time;
         if((now - start) * 1000 > JOB_TIMEOUT_MS)
         {
            Print("WARNING: Job ", state.population[i].id, " timed out. Resetting to PENDING.");
            state.population[i].job_status = JOB_PENDING;
            state.population[i].job_start_time = 0;
         }
      }
   }
}
//+------------------------------------------------------------------+
