//+------------------------------------------------------------------+
//|                                          TestInputManager.mq5    |
//|                                  Copyright 2024, Carlos Sandoval |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Carlos Sandoval"
#property link      ""
#property version   "1.00"
#property script_show_inputs

#include "../Include/Classes/CInputManager.mqh"

//--- Input parameters
input int InpComplexity = 2; // Complexity (0=Min, 1=Std, 2=Rich)

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
   //--- Create instance
   CInputManager inputMgr;
   
   //--- Initialize with current symbol and timeframe
   if(!inputMgr.Init(_Symbol, _Period))
   {
      Print("ERROR: Failed to initialize CInputManager");
      return;
   }
   
   Print("=== CInputManager Test ===");
   Print("Symbol: ", _Symbol);
   Print("Period: ", EnumToString(_Period));
   Print("Complexity: ", InpComplexity);
   
   //--- Get number of inputs for complexity level
   int total = inputMgr.GetTotalInputs(InpComplexity);
   Print("Total Inputs: ", total);
   
   //--- Get inputs
   double inputs[];
   if(!inputMgr.GetInputs(total, inputs))
   {
      Print("ERROR: Failed to get inputs");
      return;
   }
   
   //--- Display all inputs with names
   string names[20] = 
   {
      "PA_Body", "ATR_Norm", "Dist_Hi20", "Vol_Slope", "RSI_Fast", "Dist_Lo20",
      "ADX_Norm", "Mom_Conf", "Wick_Up", "BB_Width", "Time_Sess", "Round_Num",
      "Wick_Low", "StdDev_R", "MA_Dist", "Pivot_Age", "BB_Break", "Lag_Ret",
      "MA_Long", "Tick_Vol"
   };
   
   Print("\n--- Input Values ---");
   for(int i = 0; i < total; i++)
   {
      Print(StringFormat("[%2d] %-12s = %8.4f", i, names[i], inputs[i]));
   }
   
   //--- Test all three complexity levels
   Print("\n--- Complexity Level Testing ---");
   for(int complexity = 0; complexity <= 2; complexity++)
   {
      int count = inputMgr.GetTotalInputs(complexity);
      Print(StringFormat("Complexity %d -> %d inputs", complexity, count));
   }
   
   //--- Cleanup
   inputMgr.Deinit();
   
   Print("\n=== Test Complete ===");
}
//+------------------------------------------------------------------+
