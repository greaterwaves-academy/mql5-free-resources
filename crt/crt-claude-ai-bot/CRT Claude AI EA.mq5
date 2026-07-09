//+------------------------------------------------------------------+
//|                                                       CRT_EA.mq5 |
//|                    Candle Range Theory Expert Advisor             |
//|                                                                   |
//|  Patrón de falsa ruptura de 3 velas confirmado en dos             |
//|  temporalidades simultáneas (HTF + LTF = temporalidad del chart). |
//|                                                                   |
//|  Índices de referencia en cualquier temporalidad:                 |
//|    [0] = vela ACTUAL (abierta)  → Distribución / zona de entrada  |
//|    [1] = última vela CERRADA    → Manipulación                    |
//|    [2] = antepenúltima cerrada  → Acumulación  (define CRH / CRL) |
//+------------------------------------------------------------------+
#property copyright "CRT Expert Advisor"
#property link      ""
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>

//--- Parámetros de entrada
input ENUM_TIMEFRAMES HTF              = PERIOD_D1; // Temporalidad alta (HTF)
input double          Buffer_SL        = 0.2;        // Buffer SL (fracción del rango, 0.2 = 20 %)
input double          Lote             = 0.1;         // Tamaño de posición (lotes)
input ulong           Magic            = 123456;      // Número mágico
input int             MinRangoAcumLTF  = 50;          // Tamaño mínimo acumulación LTF (puntos)
input int             MinRangoAcumHTF  = 200;         // Tamaño mínimo acumulación HTF (puntos)

//--- Objeto de trading global
CTrade Trade;

//+------------------------------------------------------------------+
//|  OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   //--- Validaciones básicas
   if(HTF == _Period)
     {
      Print("ERROR: HTF debe ser distinto de la temporalidad del gráfico (LTF).");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(Buffer_SL < 0.0 || Buffer_SL > 1.0)
     {
      Print("ERROR: Buffer_SL debe estar entre 0.0 y 1.0.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(Lote <= 0.0)
     {
      Print("ERROR: El tamaño de lote debe ser mayor que 0.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(MinRangoAcumLTF < 0)
     {
      Print("ERROR: MinRangoAcumLTF no puede ser negativo.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(MinRangoAcumHTF < 0)
     {
      Print("ERROR: MinRangoAcumHTF no puede ser negativo.");
      return(INIT_PARAMETERS_INCORRECT);
     }

   Trade.SetExpertMagicNumber(Magic);
   Trade.SetDeviationInPoints(10);
   Trade.SetTypeFilling(ORDER_FILLING_FOK);

   PrintFormat("CRT EA iniciado | %s | LTF: %s | HTF: %s | "
               "Buffer SL: %.2f | Lote: %.2f | "
               "Min acum LTF: %d pts | Min acum HTF: %d pts",
               _Symbol,
               EnumToString(_Period),
               EnumToString(HTF),
               Buffer_SL,
               Lote,
               MinRangoAcumLTF,
               MinRangoAcumHTF);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//|  OnTick  — Lógica principal, procesada solo en apertura de vela  |
//+------------------------------------------------------------------+
void OnTick()
  {
   //------------------------------------------------------------
   //  1. Detectar apertura de nueva vela en LTF
   //------------------------------------------------------------
   static datetime ultimaVelaLTF = 0;
   datetime vela0Tiempo = iTime(_Symbol, _Period, 0);

   if(vela0Tiempo == ultimaVelaLTF)
      return; // Mismo tick dentro de la misma vela; salir

   ultimaVelaLTF = vela0Tiempo;

   //------------------------------------------------------------
   //  2. Verificar que no haya posición abierta para este símbolo
   //------------------------------------------------------------
   if(HayPosicionAbierta())
      return;

   //------------------------------------------------------------
   //  3. Detectar CRT en LTF con su umbral de acumulación mínimo
   //------------------------------------------------------------
   int senalLTF = DetectarCRT(_Symbol, _Period, MinRangoAcumLTF);
   if(senalLTF == 0)
      return;

   //------------------------------------------------------------
   //  4. Detectar CRT en HTF con su propio umbral — debe coincidir
   //------------------------------------------------------------
   int senalHTF = DetectarCRT(_Symbol, HTF, MinRangoAcumHTF);
   if(senalHTF == 0 || senalHTF != senalLTF)
      return;

   //------------------------------------------------------------
   //  5. Calcular SL y TP con el rango de acumulación de la LTF
   //     Acumulación = vela[2] en LTF
   //------------------------------------------------------------
   double crh   = NormalizeDouble(iHigh(_Symbol, _Period, 2), _Digits);
   double crl   = NormalizeDouble(iLow (_Symbol, _Period, 2), _Digits);
   double rango = crh - crl;

   if(rango <= 0.0)
     {
      Print("AVISO: Rango de acumulación inválido. Operación cancelada.");
      return;
     }

   //------------------------------------------------------------
   //  6. Ejecutar la orden
   //------------------------------------------------------------
   if(senalLTF == 1)
     {
      //--- CRT ALCISTA → COMPRA
      //    TP = CRH | SL = CRL − (rango × Buffer_SL)
      double entrada = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
      double sl      = NormalizeDouble(crl - rango * Buffer_SL, _Digits);
      double tp      = NormalizeDouble(crh, _Digits);

      PrintFormat(">>> CRT ALCISTA | Entrada: %.5f | SL: %.5f | TP: %.5f | Rango: %.5f",
                  entrada, sl, tp, rango);

      Trade.Buy(Lote, _Symbol, entrada, sl, tp, "CRT_Long");
     }
   else
     {
      //--- CRT BAJISTA → VENTA
      //    TP = CRL | SL = CRH + (rango × Buffer_SL)
      double entrada = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
      double sl      = NormalizeDouble(crh + rango * Buffer_SL, _Digits);
      double tp      = NormalizeDouble(crl, _Digits);

      PrintFormat(">>> CRT BAJISTA | Entrada: %.5f | SL: %.5f | TP: %.5f | Rango: %.5f",
                  entrada, sl, tp, rango);

      Trade.Sell(Lote, _Symbol, entrada, sl, tp, "CRT_Short");
     }
  }

//+------------------------------------------------------------------+
//|  DetectarCRT                                                      |
//|                                                                   |
//|  Evalúa el patrón CRT sobre las últimas velas del símbolo y      |
//|  timeframe indicados.                                             |
//|                                                                   |
//|    [0] = vela abierta actual         (no se evalúa)               |
//|    [1] = última vela CERRADA         → Manipulación               |
//|    [2] = penúltima vela CERRADA      → Acumulación (CRH / CRL)   |
//|                                                                   |
//|  Parámetros:                                                      |
//|    symbol         — símbolo a evaluar                             |
//|    tf             — temporalidad a evaluar                        |
//|    minRangoPuntos — tamaño mínimo de la vela de acumulación       |
//|                     expresado en puntos del símbolo.              |
//|                     Si el rango (high−low) de la vela de          |
//|                     acumulación es inferior a este umbral,        |
//|                     el patrón se descarta (retorna 0).            |
//|                     Pasar 0 para desactivar el filtro.            |
//|                                                                   |
//|  Retorno:                                                         |
//|    +1  CRT Alcista detectado                                      |
//|    -1  CRT Bajista detectado                                      |
//|     0  Sin patrón (o filtro de tamaño no superado)               |
//+------------------------------------------------------------------+
int DetectarCRT(const string symbol,
                const ENUM_TIMEFRAMES tf,
                const int minRangoPuntos)
  {
   //--- Necesitamos al menos 3 barras (índices 0, 1, 2)
   if(Bars(symbol, tf) < 3)
      return(0);

   //--- Vela de ACUMULACIÓN  (índice 2)
   double acum_open  = iOpen (symbol, tf, 2);
   double acum_high  = iHigh (symbol, tf, 2);   // CRH
   double acum_low   = iLow  (symbol, tf, 2);   // CRL
   double acum_close = iClose(symbol, tf, 2);

   //--- Vela de MANIPULACIÓN (índice 1)
   double man_high  = iHigh (symbol, tf, 1);
   double man_low   = iLow  (symbol, tf, 1);
   double man_close = iClose(symbol, tf, 1);

   //--- Protección: datos aún no disponibles
   if(acum_high == 0.0 || acum_low == 0.0 ||
      man_high  == 0.0 || man_low  == 0.0)
      return(0);

   double crh   = acum_high;
   double crl   = acum_low;
   double rango = crh - crl;

   if(rango <= 0.0)
      return(0);

   //--- Tolerancia: 1 punto del símbolo para comparaciones de precio
   double punto = SymbolInfoDouble(symbol, SYMBOL_POINT);

   //------------------------------------------------------------
   //  FILTRO: tamaño mínimo de la vela de acumulación
   //
   //  El rango de la acumulación se convierte a puntos dividiendo
   //  entre el valor de un punto del símbolo y se compara con el
   //  umbral configurado.  Si no supera el mínimo, descartamos.
   //------------------------------------------------------------
   if(minRangoPuntos > 0)
     {
      double rangoPuntos = rango / punto;
      if(rangoPuntos < (double)minRangoPuntos)
         return(0); // Acumulación demasiado pequeña
     }

   //------------------------------------------------------------
   //  CRT BAJISTA
   //  · Acumulación ALCISTA  (close > open)
   //  · Manipulación rompe POR ENCIMA de CRH
   //  · Manipulación cierra DENTRO del rango [CRL, CRH]
   //------------------------------------------------------------
   if(acum_close > acum_open + punto)
     {
      bool rupturaArriba = (man_high  > crh + punto);
      bool cierreDentro  = (man_close >= crl - punto && man_close <= crh + punto);

      if(rupturaArriba && cierreDentro)
         return(-1);
     }

   //------------------------------------------------------------
   //  CRT ALCISTA
   //  · Acumulación BAJISTA  (close < open)
   //  · Manipulación rompe POR DEBAJO de CRL
   //  · Manipulación cierra DENTRO del rango [CRL, CRH]
   //------------------------------------------------------------
   if(acum_close < acum_open - punto)
     {
      bool rupturaAbajo = (man_low   < crl - punto);
      bool cierreDentro = (man_close >= crl - punto && man_close <= crh + punto);

      if(rupturaAbajo && cierreDentro)
         return(1);
     }

   return(0);
  }

//+------------------------------------------------------------------+
//|  HayPosicionAbierta                                               |
//|  Devuelve true si existe al menos una posición abierta para       |
//|  _Symbol con el número mágico configurado.                        |
//+------------------------------------------------------------------+
bool HayPosicionAbierta()
  {
   int total = PositionsTotal();
   for(int i = total - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(PositionGetString(POSITION_SYMBOL)        == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == Magic)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//|  OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   PrintFormat("CRT EA detenido | %s | Razón: %d", _Symbol, reason);
  }
//+------------------------------------------------------------------+