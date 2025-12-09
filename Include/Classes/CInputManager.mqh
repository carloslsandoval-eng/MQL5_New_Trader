//+------------------------------------------------------------------+
//|                                               CInputManager.mqh |
//|                                  Copyright 2024, Carlos Sandoval |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Carlos Sandoval"
#property link      ""
#property strict

//+------------------------------------------------------------------+
//| CInputManager Class                                               |
//| Architecture: Standalone (MQL5 Standard Lib)                     |
//| Purpose: Generate 20 normalized input features for ML/trading    |
//| Style: Telegraphic, Dense, No Prose                             |
//| Output: All values normalized to [-1.0, 1.0] or [0.0, 1.0]     |
//+------------------------------------------------------------------+
class CInputManager
{
private:
   // Symbol and timeframe
   string            m_symbol;
   ENUM_TIMEFRAMES   m_period;
   
   // Indicator handles
   int               m_handle_atr14;        // ATR(14)
   int               m_handle_ma50;         // MA(50)
   int               m_handle_ma200;        // MA(200)
   int               m_handle_rsi7;         // RSI(7)
   int               m_handle_adx14;        // ADX(14)
   int               m_handle_bb20;         // Bollinger Bands(20,2)
   int               m_handle_stddev10;     // StdDev(10)
   int               m_handle_stddev50;     // StdDev(50)
   
   // Private calculation method
   double            CalculateInput(int index);
   
   // Helper methods
   double            GetATRValue(int shift);
   double            GetRSIValue(int shift);
   double            GetADXValue(int shift);
   double            GetMAValue(int handle, int shift);
   double            GetStdDevValue(int handle, int shift);
   double            GetBBValue(int buffer, int shift);
   int               FindPivotAge(int bars);
   double            GetATR_MA(int period);
   
public:
   // Constructor
                     CInputManager();
   // Destructor
                    ~CInputManager();
   
   // Initialization
   bool              Init(string symbol, ENUM_TIMEFRAMES period);
   
   // Main interface
   bool              GetInputs(int count, double &buffer[]);
   int               GetTotalInputs(int complexity);
   
   // Cleanup
   void              Deinit();
};

//+------------------------------------------------------------------+
//| Constructor                                                       |
//+------------------------------------------------------------------+
CInputManager::CInputManager()
{
   m_symbol = "";
   m_period = PERIOD_CURRENT;
   
   // Initialize all handles to INVALID
   m_handle_atr14 = INVALID_HANDLE;
   m_handle_ma50 = INVALID_HANDLE;
   m_handle_ma200 = INVALID_HANDLE;
   m_handle_rsi7 = INVALID_HANDLE;
   m_handle_adx14 = INVALID_HANDLE;
   m_handle_bb20 = INVALID_HANDLE;
   m_handle_stddev10 = INVALID_HANDLE;
   m_handle_stddev50 = INVALID_HANDLE;
}

//+------------------------------------------------------------------+
//| Destructor                                                        |
//+------------------------------------------------------------------+
CInputManager::~CInputManager()
{
   Deinit();
}

//+------------------------------------------------------------------+
//| Initialize indicator handles                                      |
//+------------------------------------------------------------------+
bool CInputManager::Init(string symbol, ENUM_TIMEFRAMES period)
{
   m_symbol = symbol;
   m_period = period;
   
   // Create ATR(14)
   m_handle_atr14 = iATR(m_symbol, m_period, 14);
   if(m_handle_atr14 == INVALID_HANDLE)
   {
      Print("Failed to create ATR(14) handle");
      return false;
   }
   
   // Create MA(50)
   m_handle_ma50 = iMA(m_symbol, m_period, 50, 0, MODE_SMA, PRICE_CLOSE);
   if(m_handle_ma50 == INVALID_HANDLE)
   {
      Print("Failed to create MA(50) handle");
      return false;
   }
   
   // Create MA(200)
   m_handle_ma200 = iMA(m_symbol, m_period, 200, 0, MODE_SMA, PRICE_CLOSE);
   if(m_handle_ma200 == INVALID_HANDLE)
   {
      Print("Failed to create MA(200) handle");
      return false;
   }
   
   // Create RSI(7)
   m_handle_rsi7 = iRSI(m_symbol, m_period, 7, PRICE_CLOSE);
   if(m_handle_rsi7 == INVALID_HANDLE)
   {
      Print("Failed to create RSI(7) handle");
      return false;
   }
   
   // Create ADX(14)
   m_handle_adx14 = iADX(m_symbol, m_period, 14);
   if(m_handle_adx14 == INVALID_HANDLE)
   {
      Print("Failed to create ADX(14) handle");
      return false;
   }
   
   // Create Bollinger Bands(20, 2.0)
   m_handle_bb20 = iBands(m_symbol, m_period, 20, 0, 2.0, PRICE_CLOSE);
   if(m_handle_bb20 == INVALID_HANDLE)
   {
      Print("Failed to create Bollinger Bands handle");
      return false;
   }
   
   // Create StdDev(10)
   m_handle_stddev10 = iStdDev(m_symbol, m_period, 10, 0, MODE_SMA, PRICE_CLOSE);
   if(m_handle_stddev10 == INVALID_HANDLE)
   {
      Print("Failed to create StdDev(10) handle");
      return false;
   }
   
   // Create StdDev(50)
   m_handle_stddev50 = iStdDev(m_symbol, m_period, 50, 0, MODE_SMA, PRICE_CLOSE);
   if(m_handle_stddev50 == INVALID_HANDLE)
   {
      Print("Failed to create StdDev(50) handle");
      return false;
   }
   
   // Note: Tick volume MA will be calculated manually from series data
   
   Print("CInputManager initialized successfully");
   return true;
}

//+------------------------------------------------------------------+
//| Get normalized inputs                                             |
//+------------------------------------------------------------------+
bool CInputManager::GetInputs(int count, double &buffer[])
{
   // Clamp count to valid range [1, 20]
   if(count < 1) count = 1;
   if(count > 20) count = 20;
   
   // Resize buffer
   ArrayResize(buffer, count);
   ArrayInitialize(buffer, 0.0);
   
   // Calculate each input
   for(int i = 0; i < count; i++)
   {
      buffer[i] = CalculateInput(i);
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Get total inputs based on complexity                             |
//+------------------------------------------------------------------+
int CInputManager::GetTotalInputs(int complexity)
{
   switch(complexity)
   {
      case 0: return 6;   // Min Viable (BATCH 1)
      case 1: return 12;  // Standard (BATCH 1+2)
      case 2: return 20;  // Rich (All batches)
      default: return 6;
   }
}

//+------------------------------------------------------------------+
//| Calculate individual input by index                              |
//+------------------------------------------------------------------+
double CInputManager::CalculateInput(int index)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   
   // Get recent price data
   if(CopyRates(m_symbol, m_period, 0, 100, rates) < 50)
   {
      Print("Failed to copy rates data");
      return 0.0;
   }
   
   double atr = GetATRValue(0);
   if(atr <= 0.0) atr = 0.0001; // Prevent division by zero
   
   double close = rates[0].close;
   double open = rates[0].open;
   double high = rates[0].high;
   double low = rates[0].low;
   
   switch(index)
   {
      // ===== BATCH 1: Min Viable (0-5) =====
      case 0: // PA_Body = (Close-Open)/ATR
         return (close - open) / atr;
      
      case 1: // ATR_Norm = ATR(14)/MA_ATR(100)
      {
         double atr_ma = GetATR_MA(100);
         if(atr_ma <= 0.0) return 1.0;
         return atr / atr_ma;
      }
      
      case 2: // Dist_Hi20 = (High20-Close)/ATR
      {
         int highest_idx = iHighest(m_symbol, m_period, MODE_HIGH, 20, 0);
         if(highest_idx < 0) return 0.0;
         
         MqlRates high_rates[];
         ArraySetAsSeries(high_rates, true);
         if(CopyRates(m_symbol, m_period, highest_idx, 1, high_rates) < 1)
            return 0.0;
         
         return (high_rates[0].high - close) / atr;
      }
      
      case 3: // Vol_Slope = (ATR(0)-ATR(5))/ATR
      {
         double atr0 = GetATRValue(0);
         double atr5 = GetATRValue(5);
         if(atr0 <= 0.0) return 0.0;
         return (atr0 - atr5) / atr0;
      }
      
      case 4: // RSI_Fast = (RSI(7)-50)/50.0
      {
         double rsi = GetRSIValue(0);
         return (rsi - 50.0) / 50.0;
      }
      
      case 5: // Dist_Lo20 = (Close-Low20)/ATR
      {
         int lowest_idx = iLowest(m_symbol, m_period, MODE_LOW, 20, 0);
         if(lowest_idx < 0) return 0.0;
         
         MqlRates low_rates[];
         ArraySetAsSeries(low_rates, true);
         if(CopyRates(m_symbol, m_period, lowest_idx, 1, low_rates) < 1)
            return 0.0;
         
         return (close - low_rates[0].low) / atr;
      }
      
      // ===== BATCH 2: Standard (6-11) =====
      case 6: // ADX_Norm = ADX(14)/100.0
      {
         double adx = GetADXValue(0);
         return adx / 100.0;
      }
      
      case 7: // Mom_Conf = MathAbs(RSI(7)-50)/50.0
      {
         double rsi = GetRSIValue(0);
         return MathAbs(rsi - 50.0) / 50.0;
      }
      
      case 8: // Wick_Up = (High-Max(O,C))/ATR
      {
         double max_oc = MathMax(open, close);
         return (high - max_oc) / atr;
      }
      
      case 9: // BB_Width = (Upper-Lower)/Middle
      {
         double bb_upper = GetBBValue(1, 0);  // Upper band (buffer 1)
         double bb_lower = GetBBValue(2, 0);  // Lower band (buffer 2)
         double bb_mid = GetBBValue(0, 0);    // Middle band (buffer 0)
         
         if(bb_mid <= 0.0) return 0.0;
         return (bb_upper - bb_lower) / bb_mid;
      }
      
      case 10: // Time_Sess = (Hour*60+Min)/1440.0
      {
         MqlDateTime dt;
         TimeToStruct(rates[0].time, dt);
         return (dt.hour * 60 + dt.min) / 1440.0;
      }
      
      case 11: // Round_Num = (Close - Round(Close*100)/100)/ATR
      {
         // Distance to nearest round number (0.01)
         double rounded = MathRound(close * 100.0) / 100.0;
         return (close - rounded) / atr;
      }
      
      // ===== BATCH 3: Rich (12-19) =====
      case 12: // Wick_Low = (Min(O,C)-Low)/ATR
      {
         double min_oc = MathMin(open, close);
         return (min_oc - low) / atr;
      }
      
      case 13: // StdDev_R = StdDev(10)/StdDev(50)
      {
         double stddev10 = GetStdDevValue(m_handle_stddev10, 0);
         double stddev50 = GetStdDevValue(m_handle_stddev50, 0);
         
         if(stddev50 <= 0.0) return 1.0;
         return stddev10 / stddev50;
      }
      
      case 14: // MA_Dist = (Close-MA(50))/ATR
      {
         double ma50 = GetMAValue(m_handle_ma50, 0);
         return (close - ma50) / atr;
      }
      
      case 15: // Pivot_Age = (CurrentBar - BarHiLo_50)/50.0
      {
         int pivot_age = FindPivotAge(50);
         return pivot_age / 50.0;
      }
      
      case 16: // BB_Break = (Close-Upper)/ATR
      {
         double bb_upper = GetBBValue(1, 0);  // Upper band (buffer 1)
         return (close - bb_upper) / atr;
      }
      
      case 17: // Lag_Ret = (Close-Close[5])/ATR
      {
         if(ArraySize(rates) < 6) return 0.0;
         return (close - rates[5].close) / atr;
      }
      
      case 18: // MA_Long = (Close-MA(200))/ATR
      {
         double ma200 = GetMAValue(m_handle_ma200, 0);
         return (close - ma200) / atr;
      }
      
      case 19: // Tick_Vol = TickVol/MA_TickVol(20)
      {
         // Calculate tick volume MA manually
         long tick_vols[];
         if(CopyTickVolume(m_symbol, m_period, 0, 20, tick_vols) < 20)
            return 1.0;
         
         double sum = 0.0;
         for(int i = 0; i < 20; i++)
            sum += (double)tick_vols[i];
         
         double ma_tick = sum / 20.0;
         if(ma_tick <= 0.0) return 1.0;
         
         return (double)tick_vols[0] / ma_tick;
      }
      
      default:
         return 0.0;
   }
   
   return 0.0;
}

//+------------------------------------------------------------------+
//| Helper: Get ATR value                                            |
//+------------------------------------------------------------------+
double CInputManager::GetATRValue(int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   
   if(CopyBuffer(m_handle_atr14, 0, shift, 1, buffer) <= 0)
      return 0.0;
   
   return buffer[0];
}

//+------------------------------------------------------------------+
//| Helper: Get RSI value                                            |
//+------------------------------------------------------------------+
double CInputManager::GetRSIValue(int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   
   if(CopyBuffer(m_handle_rsi7, 0, shift, 1, buffer) <= 0)
      return 50.0;
   
   return buffer[0];
}

//+------------------------------------------------------------------+
//| Helper: Get ADX value                                            |
//+------------------------------------------------------------------+
double CInputManager::GetADXValue(int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   
   if(CopyBuffer(m_handle_adx14, 0, shift, 1, buffer) <= 0)
      return 0.0;
   
   return buffer[0];
}

//+------------------------------------------------------------------+
//| Helper: Get MA value                                             |
//+------------------------------------------------------------------+
double CInputManager::GetMAValue(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   
   if(CopyBuffer(handle, 0, shift, 1, buffer) <= 0)
      return 0.0;
   
   return buffer[0];
}

//+------------------------------------------------------------------+
//| Helper: Get StdDev value                                         |
//+------------------------------------------------------------------+
double CInputManager::GetStdDevValue(int handle, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   
   if(CopyBuffer(handle, 0, shift, 1, buffer) <= 0)
      return 0.0;
   
   return buffer[0];
}

//+------------------------------------------------------------------+
//| Helper: Get Bollinger Band value                                 |
//+------------------------------------------------------------------+
double CInputManager::GetBBValue(int buffer_index, int shift)
{
   double buffer[];
   ArraySetAsSeries(buffer, true);
   
   if(CopyBuffer(m_handle_bb20, buffer_index, shift, 1, buffer) <= 0)
      return 0.0;
   
   return buffer[0];
}

//+------------------------------------------------------------------+
//| Helper: Find pivot age (bars since highest/lowest)               |
//+------------------------------------------------------------------+
int CInputManager::FindPivotAge(int bars)
{
   int highest_idx = iHighest(m_symbol, m_period, MODE_HIGH, bars, 0);
   int lowest_idx = iLowest(m_symbol, m_period, MODE_LOW, bars, 0);
   
   if(highest_idx < 0 && lowest_idx < 0)
      return 0;
   
   // Return the more recent pivot (smaller index = more recent)
   if(highest_idx < 0)
      return lowest_idx;
   if(lowest_idx < 0)
      return highest_idx;
   
   return MathMin(highest_idx, lowest_idx);
}

//+------------------------------------------------------------------+
//| Helper: Calculate MA of ATR values                               |
//+------------------------------------------------------------------+
double CInputManager::GetATR_MA(int period)
{
   double atr_buffer[];
   ArraySetAsSeries(atr_buffer, true);
   
   if(CopyBuffer(m_handle_atr14, 0, 0, period, atr_buffer) < period)
      return 0.0;
   
   double sum = 0.0;
   for(int i = 0; i < period; i++)
      sum += atr_buffer[i];
   
   return sum / period;
}

//+------------------------------------------------------------------+
//| Cleanup indicator handles                                         |
//+------------------------------------------------------------------+
void CInputManager::Deinit()
{
   if(m_handle_atr14 != INVALID_HANDLE)
      IndicatorRelease(m_handle_atr14);
   if(m_handle_ma50 != INVALID_HANDLE)
      IndicatorRelease(m_handle_ma50);
   if(m_handle_ma200 != INVALID_HANDLE)
      IndicatorRelease(m_handle_ma200);
   if(m_handle_rsi7 != INVALID_HANDLE)
      IndicatorRelease(m_handle_rsi7);
   if(m_handle_adx14 != INVALID_HANDLE)
      IndicatorRelease(m_handle_adx14);
   if(m_handle_bb20 != INVALID_HANDLE)
      IndicatorRelease(m_handle_bb20);
   if(m_handle_stddev10 != INVALID_HANDLE)
      IndicatorRelease(m_handle_stddev10);
   if(m_handle_stddev50 != INVALID_HANDLE)
      IndicatorRelease(m_handle_stddev50);
   
   m_handle_atr14 = INVALID_HANDLE;
   m_handle_ma50 = INVALID_HANDLE;
   m_handle_ma200 = INVALID_HANDLE;
   m_handle_rsi7 = INVALID_HANDLE;
   m_handle_adx14 = INVALID_HANDLE;
   m_handle_bb20 = INVALID_HANDLE;
   m_handle_stddev10 = INVALID_HANDLE;
   m_handle_stddev50 = INVALID_HANDLE;
}
//+------------------------------------------------------------------+
