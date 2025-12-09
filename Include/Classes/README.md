# CInputManager Class Documentation

## Overview

`CInputManager` is a standalone MQL5 class designed to generate 20 normalized input features for machine learning and algorithmic trading applications. All outputs are normalized to approximately [-1.0, 1.0] or [0.0, 1.0] ranges, with zero raw price/volume exposure.

## Architecture

- **Dependencies**: None (MQL5 Standard Library only)
- **Style**: Telegraphic, dense, no prose
- **Output**: All values normalized
- **Design**: Zero raw price/volume in outputs

## The Elite 20 Input Map

The class provides 20 distinct input features organized into three batches by complexity:

### BATCH 1: Min Viable (Indices 0-5)
| Index | Name | Formula | Category | Description |
|-------|------|---------|----------|-------------|
| 0 | PA_Body | (Close-Open)/ATR | DIR | Raw candle power |
| 1 | ATR_Norm | ATR(14)/MA_ATR(100) | RISK | Volatility regime |
| 2 | Dist_Hi20 | (High20-Close)/ATR | FILT | Ceiling proximity |
| 3 | Vol_Slope | (ATR(0)-ATR(5))/ATR | SIZE | Volatility acceleration |
| 4 | RSI_Fast | (RSI(7)-50)/50.0 | DIR | Fast momentum |
| 5 | Dist_Lo20 | (Close-Low20)/ATR | FILT | Floor proximity |

### BATCH 2: Standard (Indices 6-11)
| Index | Name | Formula | Category | Description |
|-------|------|---------|----------|-------------|
| 6 | ADX_Norm | ADX(14)/100.0 | FILT | Trend strength |
| 7 | Mom_Conf | abs(RSI(7)-50)/50.0 | SIZE | Momentum conviction |
| 8 | Wick_Up | (High-Max(O,C))/ATR | DIR | Selling pressure |
| 9 | BB_Width | (Upper-Lower)/Middle | RISK | Squeeze/expansion |
| 10 | Time_Sess | (Hour*60+Min)/1440.0 | FILT | Session time (0.0-1.0) |
| 11 | Round_Num | (Close-Round)/ATR | FILT | Distance to round number |

### BATCH 3: Rich (Indices 12-19)
| Index | Name | Formula | Category | Description |
|-------|------|---------|----------|-------------|
| 12 | Wick_Low | (Min(O,C)-Low)/ATR | DIR | Buying pressure |
| 13 | StdDev_R | StdDev(10)/StdDev(50) | RISK | Volatility shock |
| 14 | MA_Dist | (Close-MA(50))/ATR | FILT | Mean reversion |
| 15 | Pivot_Age | (CurrentBar-BarHiLo_50)/50.0 | FILT | Trend age/exhaustion |
| 16 | BB_Break | (Close-Upper)/ATR | SIZE | Breakout magnitude |
| 17 | Lag_Ret | (Close-Close[5])/ATR | DIR | Persistence |
| 18 | MA_Long | (Close-MA(200))/ATR | FILT | Macro bias |
| 19 | Tick_Vol | TickVol/MA_TickVol(20) | SIZE | Hidden effort |

### Categories
- **DIR** (Direction): Directional indicators
- **RISK** (Volatility): Risk and volatility measures
- **FILT** (Regime): Market regime filters
- **SIZE** (Aggression): Position sizing and confidence

## API Reference

### Constructor
```cpp
CInputManager()
```
Initializes the class with invalid handles.

### Destructor
```cpp
~CInputManager()
```
Automatically calls `Deinit()` to release resources.

### Public Methods

#### Init
```cpp
bool Init(string symbol, ENUM_TIMEFRAMES period)
```
Initializes all indicator handles for the specified symbol and timeframe.

**Parameters:**
- `symbol`: Symbol name (e.g., "EURUSD")
- `period`: Timeframe (e.g., PERIOD_H1)

**Returns:** `true` on success, `false` on failure

**Example:**
```cpp
CInputManager inputMgr;
if(!inputMgr.Init("EURUSD", PERIOD_H1))
{
   Print("Initialization failed");
}
```

#### GetInputs
```cpp
bool GetInputs(int count, double &buffer[])
```
Retrieves normalized input features.

**Parameters:**
- `count`: Number of inputs to retrieve (1-20, automatically clamped)
- `buffer`: Output array (automatically resized)

**Returns:** `true` on success

**Example:**
```cpp
double inputs[];
if(inputMgr.GetInputs(12, inputs))
{
   Print("Input[0] (PA_Body): ", inputs[0]);
}
```

#### GetTotalInputs
```cpp
int GetTotalInputs(int complexity)
```
Returns the number of inputs for a given complexity level.

**Parameters:**
- `complexity`: 0 = Min (6 inputs), 1 = Standard (12 inputs), 2 = Rich (20 inputs)

**Returns:** Number of inputs

**Example:**
```cpp
int count = inputMgr.GetTotalInputs(1); // Returns 12
```

#### Deinit
```cpp
void Deinit()
```
Releases all indicator handles. Called automatically by destructor.

## Usage Example

```cpp
#include "../Include/Classes/CInputManager.mqh"

void OnStart()
{
   // Create and initialize
   CInputManager inputMgr;
   if(!inputMgr.Init(_Symbol, _Period))
   {
      Print("Failed to initialize");
      return;
   }
   
   // Get inputs based on complexity
   int complexity = 2; // Rich mode
   int total = inputMgr.GetTotalInputs(complexity);
   
   double inputs[];
   inputMgr.GetInputs(total, inputs);
   
   // Use inputs for ML model, trading decision, etc.
   for(int i = 0; i < total; i++)
   {
      Print("Input[", i, "] = ", inputs[i]);
   }
   
   // Cleanup (optional, done automatically)
   inputMgr.Deinit();
}
```

## Technical Details

### Indicator Handles
The class manages the following MQL5 indicator handles:
- ATR(14)
- MA(50), MA(100), MA(200)
- RSI(7)
- ADX(14)
- Bollinger Bands(20, 2.0)
- StdDev(10), StdDev(50)

### Normalization Strategy
- **ATR-based**: Most features use ATR for scale normalization
- **Percentage-based**: RSI and ADX use their natural ranges
- **Ratio-based**: Volatility ratios (StdDev, ATR) use division
- **Time-based**: Session time normalized to [0.0, 1.0]

### Error Handling
- Returns 0.0 for invalid calculations
- Clamps count to [1, 20] range
- Prevents division by zero with minimum thresholds
- Validates all indicator handle creation

## Performance Considerations

1. **One-time initialization**: Call `Init()` once per symbol/timeframe
2. **Handle reuse**: All indicator handles are reused across calls
3. **Batch processing**: Calculate multiple inputs with a single `GetInputs()` call
4. **Automatic cleanup**: Destructor handles resource management

## Requirements

- MQL5 build 3000 or higher
- Access to symbol's historical data (minimum 200 bars recommended)
- Valid market data for all required indicators

## License

Copyright 2024, Carlos Sandoval
