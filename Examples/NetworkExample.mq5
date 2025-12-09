//+------------------------------------------------------------------+
//|                                              NetworkExample.mq5 |
//|                                   CNetwork Usage Example/Test   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property version   "1.00"
#property script_show_inputs

#include "../Include/Network/CNetwork.mqh"

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   Print("=== CNetwork Test Started ===");
   
   // Test 1: Basic initialization
   Print("\n--- Test 1: Initialization ---");
   CNetwork network;
   if(network.Initialize(3))
   {
      Print("Network initialized with 3 inputs");
      Print("Input count: ", network.GetInputCount());
      Print("Output count: ", network.GetOutputCount());
      Print("Total nodes: ", network.GetNodeCount());
      Print("Total connections: ", network.GetConnectionCount());
   }
   else
   {
      Print("ERROR: Failed to initialize network");
      return;
   }
   
   // Test 2: Feed forward
   Print("\n--- Test 2: Feed Forward ---");
   double inputs[3];
   inputs[0] = 0.5;
   inputs[1] = -0.3;
   inputs[2] = 0.8;
   
   if(network.FeedForward(inputs))
   {
      Print("Feed forward successful");
      Print("Input values: ", inputs[0], ", ", inputs[1], ", ", inputs[2]);
      
      double outputs[];
      network.GetOutputs(outputs);
      Print("Output 0 (Buy): ", outputs[OUT_BUY]);
      Print("Output 1 (Sell): ", outputs[OUT_SELL]);
      Print("Output 2 (Filter): ", outputs[OUT_FILTER]);
      Print("Output 3 (SL): ", outputs[OUT_SL]);
      Print("Output 4 (TP): ", outputs[OUT_TP]);
      
      // Alternative way to get specific output
      double buySignal = network.GetOutput(OUT_BUY);
      Print("Buy signal (alternative): ", buySignal);
   }
   else
   {
      Print("ERROR: Feed forward failed");
   }
   
   // Test 3: Lateral mutation
   Print("\n--- Test 3: Lateral Mutation ---");
   int nodesBefore = network.GetNodeCount();
   int connsBefore = network.GetConnectionCount();
   
   if(network.MutateLateral())
   {
      Print("Lateral mutation successful");
      Print("Nodes: ", nodesBefore, " -> ", network.GetNodeCount());
      Print("Connections: ", connsBefore, " -> ", network.GetConnectionCount());
   }
   
   // Test 4: Memory mutation
   Print("\n--- Test 4: Memory Mutation ---");
   nodesBefore = network.GetNodeCount();
   connsBefore = network.GetConnectionCount();
   
   if(network.MutateMemory())
   {
      Print("Memory mutation successful");
      Print("Nodes: ", nodesBefore, " -> ", network.GetNodeCount());
      Print("Connections: ", connsBefore, " -> ", network.GetConnectionCount());
   }
   
   // Test 5: Depth mutation
   Print("\n--- Test 5: Depth Mutation ---");
   nodesBefore = network.GetNodeCount();
   connsBefore = network.GetConnectionCount();
   
   if(network.MutateDepth())
   {
      Print("Depth mutation successful");
      Print("Nodes: ", nodesBefore, " -> ", network.GetNodeCount());
      Print("Connections: ", connsBefore, " -> ", network.GetConnectionCount());
   }
   
   // Test 6: Feed forward after mutations
   Print("\n--- Test 6: Feed Forward After Mutations ---");
   // Update input array for new input count
   int newInputCount = network.GetInputCount();
   double inputs2[];
   ArrayResize(inputs2, newInputCount);
   for(int i = 0; i < newInputCount; i++)
   {
      inputs2[i] = (i % 2 == 0) ? 0.5 : -0.5;
   }
   
   if(network.FeedForward(inputs2))
   {
      Print("Feed forward after mutations successful");
      double outputs2[];
      network.GetOutputs(outputs2);
      Print("Buy: ", outputs2[OUT_BUY], " Sell: ", outputs2[OUT_SELL], 
            " Filter: ", outputs2[OUT_FILTER], " SL: ", outputs2[OUT_SL], " TP: ", outputs2[OUT_TP]);
   }
   
   // Test 7: Recurrent buffers
   Print("\n--- Test 7: Recurrent Buffers ---");
   Print("First pass with recurrent connections...");
   network.FeedForward(inputs2);
   double outputs3[];
   network.GetOutputs(outputs3);
   Print("Outputs: ", outputs3[0], ", ", outputs3[1], ", ", outputs3[2], ", ", outputs3[3], ", ", outputs3[4]);
   
   Print("Second pass (recurrent buffers active)...");
   network.FeedForward(inputs2);
   network.GetOutputs(outputs3);
   Print("Outputs: ", outputs3[0], ", ", outputs3[1], ", ", outputs3[2], ", ", outputs3[3], ", ", outputs3[4]);
   
   Print("Resetting recurrent buffers...");
   network.ResetRecurrentBuffers();
   network.FeedForward(inputs2);
   network.GetOutputs(outputs3);
   Print("Outputs after reset: ", outputs3[0], ", ", outputs3[1], ", ", outputs3[2], ", ", outputs3[3], ", ", outputs3[4]);
   
   // Test 8: Save and Load (Binary)
   Print("\n--- Test 8: Save and Load (Binary) ---");
   string filename = "network_test.bin";
   
   if(network.SaveToFile(filename))
   {
      Print("Network saved to ", filename);
      
      CNetwork network2;
      if(network2.LoadFromFile(filename))
      {
         Print("Network loaded from ", filename);
         Print("Loaded - Inputs: ", network2.GetInputCount(), 
               " Outputs: ", network2.GetOutputCount(),
               " Nodes: ", network2.GetNodeCount(),
               " Connections: ", network2.GetConnectionCount());
         
         // Test loaded network
         if(network2.FeedForward(inputs2))
         {
            double outputs4[];
            network2.GetOutputs(outputs4);
            Print("Loaded network outputs: ", outputs4[0], ", ", outputs4[1], ", ", 
                  outputs4[2], ", ", outputs4[3], ", ", outputs4[4]);
         }
      }
      else
      {
         Print("ERROR: Failed to load network");
      }
      
      // Clean up test file
      FileDelete(filename);
   }
   else
   {
      Print("ERROR: Failed to save network");
   }
   
   // Test 8b: Save and Load (CSV for inspection)
   Print("\n--- Test 8b: Save and Load (CSV) ---");
   string csvFilename = "network_test.csv";
   
   if(network.SaveToFile(csvFilename, true))
   {
      Print("Network saved to CSV: ", csvFilename);
      Print("CSV file can be opened in Excel for inspection");
      
      CNetwork network3;
      if(network3.LoadFromFile(csvFilename))
      {
         Print("Network loaded from CSV");
         Print("Loaded - Inputs: ", network3.GetInputCount(), 
               " Outputs: ", network3.GetOutputCount(),
               " Nodes: ", network3.GetNodeCount(),
               " Connections: ", network3.GetConnectionCount());
         
         // Test loaded network
         if(network3.FeedForward(inputs2))
         {
            double outputs5[];
            network3.GetOutputs(outputs5);
            Print("CSV network outputs: ", outputs5[0], ", ", outputs5[1], ", ", 
                  outputs5[2], ", ", outputs5[3], ", ", outputs5[4]);
         }
      }
      else
      {
         Print("ERROR: Failed to load CSV network");
      }
      
      // Clean up test file
      FileDelete(csvFilename);
   }
   else
   {
      Print("ERROR: Failed to save CSV network");
   }
   
   // Test 9: Multiple mutations
   Print("\n--- Test 9: Multiple Mutations ---");
   CNetwork network4;
   network4.Initialize(2);
   Print("Initial: Nodes=", network4.GetNodeCount(), " Connections=", network4.GetConnectionCount());
   
   for(int i = 0; i < 3; i++)
   {
      network4.MutateDepth();
      Print("After depth mutation ", i+1, ": Nodes=", network4.GetNodeCount(), 
            " Connections=", network4.GetConnectionCount());
   }
   
   for(int i = 0; i < 2; i++)
   {
      network4.MutateLateral();
      Print("After lateral mutation ", i+1, ": Nodes=", network4.GetNodeCount(), 
            " Connections=", network4.GetConnectionCount());
   }
   
   network4.MutateMemory();
   Print("After memory mutation: Nodes=", network4.GetNodeCount(), 
         " Connections=", network4.GetConnectionCount());
   
   // Final feed forward test
   double inputs3[];
   ArrayResize(inputs3, network4.GetInputCount());
   for(int i = 0; i < network4.GetInputCount(); i++)
   {
      inputs3[i] = 0.1 * i;
   }
   
   if(network4.FeedForward(inputs3))
   {
      Print("Final feed forward successful on complex network");
      double outputs6[];
      network4.GetOutputs(outputs6);
      Print("Final outputs: Buy=", outputs6[OUT_BUY], " Sell=", outputs6[OUT_SELL], 
            " Filter=", outputs6[OUT_FILTER], " SL=", outputs6[OUT_SL], " TP=", outputs6[OUT_TP]);
   }
   
   Print("\n=== CNetwork Test Completed Successfully ===");
}
//+------------------------------------------------------------------+
