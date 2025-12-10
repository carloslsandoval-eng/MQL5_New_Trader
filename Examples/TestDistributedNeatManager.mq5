//+------------------------------------------------------------------+
//|                                 TestDistributedNeatManager.mq5  |
//|                                  Copyright 2024, Carlos Sandoval |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Carlos Sandoval"
#property link      ""
#property version   "1.00"
#property script_show_inputs

#include "../Include/Classes/DistributedNeatManager.mqh"
#include "../Include/Classes/CInputManager.mqh"

//--- Input parameters
input int InpPopulationSize = 10;     // Population size
input int InpInputCount = 4;          // Number of inputs
input int InpRandomSeed = 42;         // Random seed for reproducibility
input bool InpCleanStart = true;      // Clean start (delete old state)

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== DistributedNeatManager Test ===");
   
   // Set random seed for reproducibility
   MathSrand(InpRandomSeed);
   
   // Clean start if requested
   if(InpCleanStart)
   {
      Print("\n--- Cleaning old state ---");
      FileDelete("neat_state.bin", FILE_COMMON);
      FileDelete("neat.lock", FILE_COMMON);
      Print("Old state files deleted");
   }
   
   //--- Test 1: Initialize Manager
   Print("\n--- Test 1: Initialize Manager ---");
   CDistributedNeatManager manager;
   
   if(!manager.Init("neat_state.bin"))
   {
      Print("ERROR: Failed to initialize manager");
      return;
   }
   Print("Manager initialized successfully");
   
   //--- Test 2: Initialize Population
   Print("\n--- Test 2: Initialize Population ---");
   
   if(!manager.InitializePopulation(InpPopulationSize, InpInputCount))
   {
      Print("ERROR: Failed to initialize population");
      return;
   }
   Print("Population initialized successfully");
   
   //--- Test 3: Check Initial State
   Print("\n--- Test 3: Check Initial State ---");
   
   int gen_id, jobs_pending, jobs_done;
   if(manager.GetGenerationInfo(gen_id, jobs_pending, jobs_done))
   {
      Print("Generation: ", gen_id);
      Print("Jobs Pending: ", jobs_pending);
      Print("Jobs Done: ", jobs_done);
   }
   
   //--- Test 4: Get Jobs (Simulate Multiple Agents)
   Print("\n--- Test 4: Get Jobs (Simulate 3 Agents) ---");
   
   SGenome jobs[];
   ArrayResize(jobs, 3);
   int jobs_acquired = 0;
   
   for(int i = 0; i < 3; i++)
   {
      if(manager.GetNextJob(jobs[i]))
      {
         jobs_acquired++;
         Print("Agent ", i + 1, " acquired job: Genome ID = ", jobs[i].id,
               ", Nodes = ", ArraySize(jobs[i].nodes),
               ", Links = ", ArraySize(jobs[i].links));
      }
      else
      {
         Print("Agent ", i + 1, " could not acquire job");
      }
   }
   
   Print("Total jobs acquired: ", jobs_acquired);
   
   //--- Test 5: Evaluate Genomes (Simulate Network Execution)
   Print("\n--- Test 5: Evaluate Acquired Genomes ---");
   
   CInputManager inputMgr;
   bool input_mgr_ready = false;
   
   if(inputMgr.Init(_Symbol, _Period))
   {
      input_mgr_ready = true;
      Print("CInputManager initialized for real market data");
   }
   else
   {
      Print("WARNING: CInputManager not available. Using random fitness.");
   }
   
   for(int i = 0; i < jobs_acquired; i++)
   {
      double fitness = 0.0;
      
      if(input_mgr_ready)
      {
         // Use real network evaluation
         CNetwork net;
         
         // Load genome structure into network (simplified)
         // In real implementation, would reconstruct full network from genome
         if(net.Init_Genesis(InpInputCount))
         {
            double inputs[];
            double outputs[];
            
            inputMgr.GetInputs(InpInputCount, inputs);
            net.FeedForward(inputs, outputs);
            
            // Simple fitness: sum of outputs (demonstration)
            for(int j = 0; j < ArraySize(outputs); j++)
               fitness += outputs[j];
            
            fitness /= ArraySize(outputs);  // Normalize
         }
      }
      else
      {
         // Random fitness for testing
         fitness = MathRand() / 32767.0;
      }
      
      Print("Agent ", i + 1, " evaluated Genome ", jobs[i].id, ": Fitness = ", fitness);
   }
   
   if(input_mgr_ready)
      inputMgr.Deinit();
   
   //--- Test 6: Report Fitness
   Print("\n--- Test 6: Report Fitness ---");
   
   for(int i = 0; i < jobs_acquired; i++)
   {
      double fitness = (i + 1) * 0.1;  // Simple test fitness
      
      if(manager.ReportFitness(jobs[i].id, fitness))
      {
         Print("Agent ", i + 1, " reported fitness for Genome ", jobs[i].id);
      }
      else
      {
         Print("ERROR: Agent ", i + 1, " failed to report fitness");
      }
   }
   
   //--- Test 7: Check State After Reports
   Print("\n--- Test 7: Check State After Reports ---");
   
   if(manager.GetGenerationInfo(gen_id, jobs_pending, jobs_done))
   {
      Print("Generation: ", gen_id);
      Print("Jobs Pending: ", jobs_pending);
      Print("Jobs Done: ", jobs_done);
   }
   
   //--- Test 8: Complete Generation (Process All Jobs)
   Print("\n--- Test 8: Complete Generation ---");
   
   int max_jobs = InpPopulationSize;
   int processed = jobs_acquired;
   
   while(processed < max_jobs)
   {
      SGenome job;
      if(manager.GetNextJob(job))
      {
         // Simulate evaluation
         double fitness = MathRand() / 32767.0;
         
         // Report immediately
         if(manager.ReportFitness(job.id, fitness))
         {
            processed++;
            Print("Processed job ", processed, "/", max_jobs, ": Genome ", job.id, " Fitness = ", fitness);
         }
      }
      else
      {
         // No more jobs or waiting for evolution
         Sleep(100);
         break;
      }
   }
   
   //--- Test 9: Check Final State
   Print("\n--- Test 9: Check Final State ---");
   
   if(manager.GetGenerationInfo(gen_id, jobs_pending, jobs_done))
   {
      Print("Generation: ", gen_id);
      Print("Jobs Pending: ", jobs_pending);
      Print("Jobs Done: ", jobs_done);
      
      if(jobs_done == InpPopulationSize)
      {
         Print("✓ All jobs completed!");
      }
      else if(gen_id > 0)
      {
         Print("✓ Evolution triggered! Now in Generation ", gen_id);
      }
   }
   
   //--- Test 10: FileMutex Stress Test
   Print("\n--- Test 10: FileMutex Stress Test ---");
   
   int lock_attempts = 5;
   int success_count = 0;
   
   for(int i = 0; i < lock_attempts; i++)
   {
      CFileMutex mutex;
      if(mutex.TryLock())
      {
         success_count++;
         Sleep(50);  // Hold lock briefly
         mutex.Release();
      }
   }
   
   Print("FileMutex stress test: ", success_count, "/", lock_attempts, " successful");
   
   //--- Test 11: State Persistence Check
   Print("\n--- Test 11: State Persistence Check ---");
   
   // Create new manager instance to test state loading
   CDistributedNeatManager manager2;
   if(manager2.Init("neat_state.bin"))
   {
      int gen_id2, jobs_pending2, jobs_done2;
      if(manager2.GetGenerationInfo(gen_id2, jobs_pending2, jobs_done2))
      {
         Print("Loaded state from file:");
         Print("  Generation: ", gen_id2);
         Print("  Jobs Pending: ", jobs_pending2);
         Print("  Jobs Done: ", jobs_done2);
         
         if(gen_id2 == gen_id)
            Print("✓ State persistence verified!");
         else
            Print("✗ State mismatch detected!");
      }
   }
   
   //--- Test 12: Multi-Generation Test
   Print("\n--- Test 12: Multi-Generation Test ---");
   
   Print("Attempting to run multiple generations...");
   int target_generations = 3;
   
   for(int gen = 0; gen < target_generations; gen++)
   {
      Print("\n--- Processing Generation ", gen, " ---");
      
      // Process all jobs in this generation
      int gen_processed = 0;
      
      while(gen_processed < InpPopulationSize)
      {
         SGenome job;
         if(manager.GetNextJob(job))
         {
            // Random fitness
            double fitness = 0.5 + (MathRand() / 32767.0) * 0.5;  // [0.5, 1.0]
            
            if(manager.ReportFitness(job.id, fitness))
            {
               gen_processed++;
            }
         }
         else
         {
            // Check if evolution happened
            int current_gen, pending, done;
            if(manager.GetGenerationInfo(current_gen, pending, done))
            {
               if(current_gen > gen)
               {
                  Print("Generation ", gen, " complete. Evolved to Generation ", current_gen);
                  break;
               }
            }
            Sleep(100);
         }
         
         // Safety break
         if(gen_processed >= InpPopulationSize)
            break;
      }
   }
   
   // Final generation check
   if(manager.GetGenerationInfo(gen_id, jobs_pending, jobs_done))
   {
      Print("\n✓ Multi-generation test complete!");
      Print("Final Generation: ", gen_id);
      Print("Expected at least: ", target_generations);
   }
   
   Print("\n=== All Tests Complete ===");
   
   // Cleanup
   if(InpCleanStart)
   {
      Print("\nCleaning up test files...");
      // Don't delete here - let user inspect the state file
      // FileDelete("neat_state.bin", FILE_COMMON);
      // FileDelete("neat.lock", FILE_COMMON);
   }
}
//+------------------------------------------------------------------+
