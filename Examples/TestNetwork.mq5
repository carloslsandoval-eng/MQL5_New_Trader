//+------------------------------------------------------------------+
//|                                              TestNetwork.mq5     |
//|                                  Copyright 2024, Carlos Sandoval |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Carlos Sandoval"
#property link      ""
#property version   "1.00"
#property script_show_inputs

#include "../Include/Classes/CNetwork.mqh"
#include "../Include/Classes/CInputManager.mqh"

//--- Input parameters
input int InpInputCount = 4;     // Number of inputs (min 4 for heuristic)
input int InpMutations = 5;      // Number of mutations to test
input int InpRandomSeed = 42;    // Random seed for reproducibility

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== CNetwork Test ===");
   
   // Set random seed for reproducibility
   MathSrand(InpRandomSeed);
   
   //--- Test 1: Genesis Initialization
   Print("\n--- Test 1: Genesis Initialization ---");
   CNetwork net;
   
   if(!net.Init_Genesis(InpInputCount))
   {
      Print("ERROR: Failed to initialize network");
      return;
   }
   
   Print("Network initialized successfully");
   Print("Initial Nodes: ", net.GetNodeCount());
   Print("Initial Links: ", net.GetLinkCount());
   
   //--- Test 2: FeedForward with sample inputs
   Print("\n--- Test 2: FeedForward Test ---");
   
   // Create sample inputs (4 minimum for heuristic map)
   double inputs[];
   ArrayResize(inputs, InpInputCount);
   
   // Populate with normalized test values
   inputs[0] = 0.5;   // PA (Price Action)
   inputs[1] = 0.8;   // ATR (Volatility)
   inputs[2] = 0.3;   // DistHi (Ceiling proximity)
   inputs[3] = -0.2;  // VolSlope (Volatility acceleration)
   
   for(int i = 4; i < InpInputCount; i++)
      inputs[i] = (MathRand() / 32767.0) * 2.0 - 1.0;  // Random [-1, 1]
   
   Print("Input values:");
   for(int i = 0; i < InpInputCount; i++)
      Print(StringFormat("  Input[%d] = %.4f", i, inputs[i]));
   
   // Run FeedForward
   double outputs[];
   if(!net.FeedForward(inputs, outputs))
   {
      Print("ERROR: FeedForward failed");
      return;
   }
   
   Print("\nOutput values (all should be in [0.0, 1.0]):");
   string output_names[6] = {"BUY", "SELL", "FILT", "SL", "TP", "SIZE"};
   for(int i = 0; i < 6; i++)
   {
      Print(StringFormat("  %-5s [%d] = %.6f", output_names[i], i, outputs[i]));
   }
   
   //--- Test 3: Mutation Operations
   Print("\n--- Test 3: Mutation Tests ---");
   
   int nodes_before = net.GetNodeCount();
   int links_before = net.GetLinkCount();
   
   Print("Before mutations - Nodes: ", nodes_before, " Links: ", links_before);
   
   // Apply mutations
   for(int i = 0; i < InpMutations; i++)
   {
      net.Mutate();
   }
   
   int nodes_after = net.GetNodeCount();
   int links_after = net.GetLinkCount();
   
   Print("After ", InpMutations, " mutations - Nodes: ", nodes_after, " Links: ", links_after);
   Print("  Nodes added: ", nodes_after - nodes_before);
   Print("  Links added: ", links_after - links_before);
   
   //--- Test 4: FeedForward after mutations
   Print("\n--- Test 4: FeedForward After Mutations ---");
   
   if(!net.FeedForward(inputs, outputs))
   {
      Print("ERROR: FeedForward failed after mutations");
      return;
   }
   
   Print("Output values after mutations:");
   for(int i = 0; i < 6; i++)
   {
      Print(StringFormat("  %-5s [%d] = %.6f", output_names[i], i, outputs[i]));
   }
   
   //--- Test 5: Multiple FeedForward calls (consistency check)
   Print("\n--- Test 5: Consistency Check ---");
   
   double outputs2[];
   if(!net.FeedForward(inputs, outputs2))
   {
      Print("ERROR: Second FeedForward failed");
      return;
   }
   
   bool consistent = true;
   for(int i = 0; i < 6; i++)
   {
      if(MathAbs(outputs[i] - outputs2[i]) > 0.0001)
      {
         consistent = false;
         Print(StringFormat("  WARNING: Output[%d] not consistent: %.6f vs %.6f", 
                           i, outputs[i], outputs2[i]));
      }
   }
   
   if(consistent)
      Print("✓ FeedForward is consistent (deterministic)");
   else
      Print("✗ FeedForward has consistency issues");
   
   //--- Test 6: Integration with CInputManager
   Print("\n--- Test 6: Integration with CInputManager ---");
   
   CInputManager inputMgr;
   if(!inputMgr.Init(_Symbol, _Period))
   {
      Print("WARNING: Could not initialize CInputManager (may need chart)");
   }
   else
   {
      double real_inputs[];
      if(inputMgr.GetInputs(InpInputCount, real_inputs))
      {
         double real_outputs[];
         if(net.FeedForward(real_inputs, real_outputs))
         {
            Print("Successfully processed real market inputs:");
            for(int i = 0; i < 6; i++)
            {
               Print(StringFormat("  %-5s [%d] = %.6f", output_names[i], i, real_outputs[i]));
            }
         }
      }
      inputMgr.Deinit();
   }
   
   //--- Test 7: Specific mutation type tests
   Print("\n--- Test 7: Specific Mutation Type Tests ---");
   
   CNetwork net2;
   net2.Init_Genesis(4);
   
   int n_before = net2.GetNodeCount();
   int l_before = net2.GetLinkCount();
   
   Print("Testing Mutate_AddNode:");
   net2.Mutate_AddNode();
   Print("  Nodes: ", n_before, " -> ", net2.GetNodeCount());
   Print("  Links: ", l_before, " -> ", net2.GetLinkCount());
   
   n_before = net2.GetNodeCount();
   l_before = net2.GetLinkCount();
   
   Print("Testing Mutate_AddLink:");
   net2.Mutate_AddLink();
   Print("  Nodes: ", n_before, " -> ", net2.GetNodeCount());
   Print("  Links: ", l_before, " -> ", net2.GetLinkCount());
   
   n_before = net2.GetNodeCount();
   l_before = net2.GetLinkCount();
   
   Print("Testing Mutate_PerturbWeights:");
   net2.Mutate_PerturbWeights();
   Print("  Nodes: ", n_before, " -> ", net2.GetNodeCount(), " (should be same)");
   Print("  Links: ", l_before, " -> ", net2.GetLinkCount(), " (should be same)");
   
   //--- Test 8: Boundary conditions
   Print("\n--- Test 8: Boundary Conditions ---");
   
   // Test with extreme input values
   double extreme_inputs[];
   ArrayResize(extreme_inputs, 4);
   extreme_inputs[0] = -1.0;
   extreme_inputs[1] = 1.0;
   extreme_inputs[2] = 0.0;
   extreme_inputs[3] = 0.5;
   
   double extreme_outputs[];
   if(net.FeedForward(extreme_inputs, extreme_outputs))
   {
      Print("Extreme inputs test passed. Outputs:");
      bool all_valid = true;
      for(int i = 0; i < 6; i++)
      {
         Print(StringFormat("  Output[%d] = %.6f", i, extreme_outputs[i]));
         if(extreme_outputs[i] < 0.0 || extreme_outputs[i] > 1.0)
         {
            Print("  ERROR: Output out of [0.0, 1.0] range!");
            all_valid = false;
         }
      }
      if(all_valid)
         Print("✓ All outputs within valid range [0.0, 1.0]");
   }
   
   Print("\n=== All Tests Complete ===");
}
//+------------------------------------------------------------------+
