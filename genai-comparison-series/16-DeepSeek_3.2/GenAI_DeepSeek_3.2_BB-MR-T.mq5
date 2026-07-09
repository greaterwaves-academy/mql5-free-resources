//+------------------------------------------------------------------+
//|                                   GenAI_DeepSeek_3.2_BB-MR-T.mq5 |
//|                                  Copyright 2025, MetaQuotes Ltd. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Ltd."
#property link      "https://www.mql5.com"
#property version   "1.00"

//+------------------------------------------------------------------+
//| Input parameters                                                 |
//+------------------------------------------------------------------+
//--- Bollinger Bands
input int      bb_period = 20;                 // Bollinger Bands Period
input double   bb_deviation = 2.0;             // Bollinger Bands Deviation
input ENUM_APPLIED_PRICE bb_applied_price = PRICE_CLOSE; // Bollinger Bands Applied Price

//--- Higher Timeframe Moving Averages
input ENUM_TIMEFRAMES ma_timeframe = PERIOD_H1; // MA Timeframe
input int      ma1_period = 50;                 // MA1 Period
input int      ma2_period = 200;                // MA2 Period
input ENUM_MA_METHOD ma_method = MODE_SMA;      // MA Method
input ENUM_APPLIED_PRICE ma_applied_price = PRICE_CLOSE; // MA Applied Price

//--- Trading Mode
input string   modo_operativa = "BUY_SELL";     // Trading Mode: SOLO_BUY, SOLO_SELL, BUY_SELL

//--- Exit Rules
input bool     usar_cierre_personalizado = true; // Use Custom Exit (Central Band)

//--- Stop Loss and Take Profit
input int      sl_extra_puntos = 100;           // SL Extra Points
input double   riesgo_beneficio = 2.0;          // Risk Reward Ratio

//--- Position Sizing
input double   lote_fijo = 0.10;                // Fixed Lot Size

//--- Trading
input ulong    magic_number = 123456;           // Magic Number
input double   slippage = 5.0;                  // Slippage (points)

//+------------------------------------------------------------------+
//| Global variables                                                 |
//+------------------------------------------------------------------+
int bb_handle;               // Bollinger Bands handle
int ma1_handle;              // MA1 handle
int ma2_handle;              // MA2 handle

double bb_upper[];           // Bollinger Bands upper band
double bb_middle[];          // Bollinger Bands middle band
double bb_lower[];           // Bollinger Bands lower band
double ma1_buffer[];         // MA1 buffer
double ma2_buffer[];         // MA2 buffer

CTrade trade;                // Trade object

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Create indicator handles
   bb_handle = iBands(_Symbol, _Period, bb_period, 0, bb_deviation, bb_applied_price);
   if(bb_handle == INVALID_HANDLE)
     {
      Print("Failed to create Bollinger Bands handle. Error: ", GetLastError());
      return(INIT_FAILED);
     }

   ma1_handle = iMA(_Symbol, ma_timeframe, ma1_period, 0, ma_method, ma_applied_price);
   if(ma1_handle == INVALID_HANDLE)
     {
      Print("Failed to create MA1 handle. Error: ", GetLastError());
      return(INIT_FAILED);
     }

   ma2_handle = iMA(_Symbol, ma_timeframe, ma2_period, 0, ma_method, ma_applied_price);
   if(ma2_handle == INVALID_HANDLE)
     {
      Print("Failed to create MA2 handle. Error: ", GetLastError());
      return(INIT_FAILED);
     }

//--- Set trade parameters
   trade.SetExpertMagicNumber(magic_number);
   trade.SetDeviationInPoints((ulong)slippage);

   Print("EA initialized successfully.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release indicator handles
   if(bb_handle != INVALID_HANDLE)
      IndicatorRelease(bb_handle);
   if(ma1_handle != INVALID_HANDLE)
      IndicatorRelease(ma1_handle);
   if(ma2_handle != INVALID_HANDLE)
      IndicatorRelease(ma2_handle);

   Print("EA deinitialized.");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Safety check: minimum bars
   if(Bars(_Symbol, _Period) < 100)
     {
      Print("Not enough bars.");
      return;
     }

//--- Update indicator buffers
   if(!UpdateBuffers())
      return;

//--- Check for exit signals
   GestionarCierres();

//--- Check for entry signals
   EjecutarEntrada();
  }

//+------------------------------------------------------------------+
//| UpdateBuffers: fetch indicator data for bar 1                    |
//+------------------------------------------------------------------+
bool UpdateBuffers()
  {
//--- Set array as time series
   ArraySetAsSeries(bb_upper, true);
   ArraySetAsSeries(bb_middle, true);
   ArraySetAsSeries(bb_lower, true);
   ArraySetAsSeries(ma1_buffer, true);
   ArraySetAsSeries(ma2_buffer, true);

//--- Copy Bollinger Bands values (we need 2 bars: bar 1 and bar 0 for some calculations)
   if(CopyBuffer(bb_handle, 1, 1, 2, bb_upper) < 2)
     {
      Print("Failed to copy Bollinger Bands upper buffer. Error: ", GetLastError());
      return false;
     }
   if(CopyBuffer(bb_handle, 0, 1, 2, bb_middle) < 2)
     {
      Print("Failed to copy Bollinger Bands middle buffer. Error: ", GetLastError());
      return false;
     }
   if(CopyBuffer(bb_handle, 2, 1, 2, bb_lower) < 2)
     {
      Print("Failed to copy Bollinger Bands lower buffer. Error: ", GetLastError());
      return false;
     }

//--- Copy MA values (only bar 1 from higher timeframe)
   if(CopyBuffer(ma1_handle, 0, 1, 1, ma1_buffer) < 1)
     {
      Print("Failed to copy MA1 buffer. Error: ", GetLastError());
      return false;
     }
   if(CopyBuffer(ma2_handle, 0, 1, 1, ma2_buffer) < 1)
     {
      Print("Failed to copy MA2 buffer. Error: ", GetLastError());
      return false;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| BuySignal: check BUY conditions                                  |
//+------------------------------------------------------------------+
bool BuySignal()
  {
//--- Check trading mode
   if(modo_operativa != "SOLO_BUY" && modo_operativa != "BUY_SELL")
      return false;

//--- Condition 1: Price closed below lower Bollinger Band (bar 1)
   double close_price = iClose(_Symbol, _Period, 1);
   if(close_price >= bb_lower[1])
     {
      Print("Buy condition 1 failed: Close price not below lower band.");
      return false;
     }

//--- Condition 2: MA1 > MA2 on higher timeframe
   if(ma1_buffer[0] <= ma2_buffer[0])
     {
      Print("Buy condition 2 failed: MA1 <= MA2 on higher timeframe.");
      return false;
     }

//--- Condition 3: No existing BUY position
   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
     {
      Print("Buy condition 3 failed: BUY position already exists.");
      return false;
     }

   Print("Buy signal detected.");
   return true;
  }

//+------------------------------------------------------------------+
//| SellSignal: check SELL conditions                                |
//+------------------------------------------------------------------+
bool SellSignal()
  {
//--- Check trading mode
   if(modo_operativa != "SOLO_SELL" && modo_operativa != "BUY_SELL")
      return false;

//--- Condition 1: Price closed above upper Bollinger Band (bar 1)
   double close_price = iClose(_Symbol, _Period, 1);
   if(close_price <= bb_upper[1])
     {
      Print("Sell condition 1 failed: Close price not above upper band.");
      return false;
     }

//--- Condition 2: MA1 < MA2 on higher timeframe
   if(ma1_buffer[0] >= ma2_buffer[0])
     {
      Print("Sell condition 2 failed: MA1 >= MA2 on higher timeframe.");
      return false;
     }

//--- Condition 3: No existing SELL position
   if(PositionSelect(_Symbol) && PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
     {
      Print("Sell condition 3 failed: SELL position already exists.");
      return false;
     }

   Print("Sell signal detected.");
   return true;
  }

//+------------------------------------------------------------------+
//| CalcularSL: calculate Stop Loss price                            |
//+------------------------------------------------------------------+
double CalcularSL(int signal_type) // signal_type: 0 for BUY, 1 for SELL
  {
   double sl_price = 0.0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(signal_type == 0) // BUY
     {
      sl_price = bb_lower[1] - sl_extra_puntos * point;
      Print("Calculated BUY SL: ", sl_price);
     }
   else if(signal_type == 1) // SELL
     {
      sl_price = bb_upper[1] + sl_extra_puntos * point;
      Print("Calculated SELL SL: ", sl_price);
     }

   return sl_price;
  }

//+------------------------------------------------------------------+
//| CalcularTP: calculate Take Profit price                          |
//+------------------------------------------------------------------+
double CalcularTP(int signal_type, double sl_price)
  {
   double tp_price = 0.0;
   double entry_price = 0.0;

   if(signal_type == 0) // BUY
     {
      entry_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      tp_price = entry_price + riesgo_beneficio * (entry_price - sl_price);
     }
   else if(signal_type == 1) // SELL
     {
      entry_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      tp_price = entry_price - riesgo_beneficio * (sl_price - entry_price);
     }

   Print("Calculated TP: ", tp_price);
   return tp_price;
  }

//+------------------------------------------------------------------+
//| CalcularLote: calculate lot size                                 |
//+------------------------------------------------------------------+
double CalcularLote()
  {
   double lot = lote_fijo;

//--- Adjust to symbol constraints
   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(lot < min_lot)
      lot = min_lot;
   if(lot > max_lot)
      lot = max_lot;

   lot = (int)(lot / lot_step) * lot_step;

   Print("Calculated lot: ", lot);
   return lot;
  }

//+------------------------------------------------------------------+
//| EjecutarEntrada: execute entry if signals exist                  |
//+------------------------------------------------------------------+
void EjecutarEntrada()
  {
   if(BuySignal())
     {
      double sl = CalcularSL(0);
      double tp = CalcularTP(0, sl);
      double lot = CalcularLote();

      if(trade.Buy(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_ASK), sl, tp, "Bollinger Reversion BUY"))
         Print("BUY order placed.");
      else
         Print("Failed to place BUY order. Error: ", GetLastError());
     }

   if(SellSignal())
     {
      double sl = CalcularSL(1);
      double tp = CalcularTP(1, sl);
      double lot = CalcularLote();

      if(trade.Sell(lot, _Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), sl, tp, "Bollinger Reversion SELL"))
         Print("SELL order placed.");
      else
         Print("Failed to place SELL order. Error: ", GetLastError());
     }
  }

//+------------------------------------------------------------------+
//| GestionarCierres: manage position exits                          |
//+------------------------------------------------------------------+
void GestionarCierres()
  {
//--- Only if custom exit is enabled
   if(!usar_cierre_personalizado)
      return;

//--- Check for open positions
   if(!PositionSelect(_Symbol))
      return;

   long type = PositionGetInteger(POSITION_TYPE);
   double current_price = 0.0;
   double middle_band = bb_middle[0]; // Current bar middle band (index 0)

   if(type == POSITION_TYPE_BUY)
     {
      current_price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      // Exit if price touches or crosses below the middle band
      if(current_price <= middle_band)
        {
         if(trade.PositionClose(_Symbol))
            Print("BUY position closed at middle band.");
         else
            Print("Failed to close BUY position. Error: ", GetLastError());
        }
     }
   else if(type == POSITION_TYPE_SELL)
     {
      current_price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      // Exit if price touches or crosses above the middle band
      if(current_price >= middle_band)
        {
         if(trade.PositionClose(_Symbol))
            Print("SELL position closed at middle band.");
         else
            Print("Failed to close SELL position. Error: ", GetLastError());
        }
     }
  }
//+------------------------------------------------------------------+