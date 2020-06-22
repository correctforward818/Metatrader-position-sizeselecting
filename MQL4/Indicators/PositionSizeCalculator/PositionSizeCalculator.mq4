//+------------------------------------------------------------------+
//|                                       PositionSizeCalculator.mq4 |
//| 				                 Copyright © 2012-2020, EarnForex.com |
//|                                     Based on panel by qubbit.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "EarnForex.com"
#property link      "https://www.earnforex.com/metatrader-indicators/Position-Size-Calculator/"
#property version   "2.30"
string    Version = "2.30";
#property strict
#property indicator_chart_window
#property indicator_plots 0

#property description "Calculates position size based on account balance/equity,"
#property description "currency, currency pair, given entry level, stop-loss level,"
#property description "and risk tolerance (set either in percentage points or in base currency)."
#property description "Displays reward/risk ratio based on take-profit."
#property description "Shows total portfolio risk based on open trades and pending orders."
#property description "Calculates margin required for new position, allows custom leverage.\r\n"
#property description "WARNING: There is no guarantee that the output of this indicator is correct. Use at your own risk."

#include "PositionSizeCalculator.mqh";

// Default values for settings:
double EntryLevel = 0;
double StopLossLevel = 0;
double TakeProfitLevel = 0;
string PanelCaption = "";

//input group "Compactness"
input bool ShowLineLabels = true; // ShowLineLabels: Show pip distance for TP/SL near lines?
input bool DrawTextAsBackground = false; // DrawTextAsBackground: Draw label objects as background?
input bool PanelOnTopOfChart = true; // PanelOnTopOfChart: Draw chart as background?
input bool HideAccSize = false; // HideAccSize: Hide account size?
input bool ShowPipValue = false; // ShowPipValue: Show pip value?
//input group "Fonts"
input color sl_label_font_color = clrLime; // SL Label  Color
input color tp_label_font_color = clrYellow; // TP Label Font Color
input uint font_size = 13; // Labels Font Size
input string font_face = "Courier"; // Labels Font Face
//input group "Lines"
input color entry_line_color = clrBlue; // Entry Line Color
input color stoploss_line_color = clrLime; // Stop-Loss Line Color
input color takeprofit_line_color = clrYellow; // Take-Profit Line Color
input ENUM_LINE_STYLE entry_line_style = STYLE_SOLID; // Entry Line Style
input ENUM_LINE_STYLE stoploss_line_style = STYLE_SOLID; // Stop-Loss Line Style
input ENUM_LINE_STYLE takeprofit_line_style = STYLE_SOLID; // Take-Profit Line Style
input uint entry_line_width = 1; // Entry Line Width
input uint stoploss_line_width = 1; // Stop-Loss Line Width
input uint takeprofit_line_width = 1; // Take-Profit Line Width
//input group "Defaults"
input TRADE_DIRECTION DefaultTradeDirection = Long; // TradeDirection: Default trade direction.
input int DefaultSL = 0; // SL: Default stop-loss value, in broker's pips.
input int DefaultTP = 0; // TP: Default take-profit value, in broker's pips.
input ENTRY_TYPE DefaultEntryType = Instant; // EntryType: Instant or Pending.
input bool DefaultShowLines = true; // ShowLines: Show the lines by default?
input bool DefaultLinesSelected = true; // LinesSelected: SL/TP (Entry in Pending) lines selected.
input int DefaultATRPeriod = 14; // ATRPeriod: Default ATR period.
input double DefaultATRMultiplierSL = 0; // ATRMultiplierSL: Default ATR multiplier for SL.
input double DefaultATRMultiplierTP = 0; // ATRMultiplierTP: Default ATR multiplier for TP.
input ENUM_TIMEFRAMES DefaultATRTimeframe = PERIOD_CURRENT; // ATRTimeframe: Default timeframe for ATR.
input double DefaultCommission = 0; // Commission: Default one-way commission size.
input ACCOUNT_BUTTON DefaultAccountButton = Balance; // AccountButton: Balance/Equity/Balance-CPR
input double DefaultRisk = 1; // Risk: Initial risk tolerance in percentage points
input double DefaultMoneyRisk = 0; // MoneyRisk: If > 0, money risk tolerance in currency.
input bool DefaultCountPendingOrders = false; // CountPendingOrders: Count pending orders for portfolio risk.
input bool DefaultIgnoreOrdersWithoutStopLoss = false; // IgnoreOrdersWithoutStopLoss: Ignore orders w/o SL for portfolio risk.
input int DefaultCustomLeverage = 0; // CustomLeverage: Default custom leverage for Margin tab.
input int DefaultMagicNumber = 0; // MagicNumber: Default magic number for Script tab.
input string DefaultCommentary = ""; // Commentary: Default order comment for Script tab.
input bool DefaultDisableTradingWhenLinesAreHidden = false; // DisableTradingWhenLinesAreHidden: for Script tab.
input int DefaultMaxSlippage = 0; // MaxSlippage: Maximum slippage for Script tab.
input int DefaultMaxSpread = 0; // MaxSpread: Maximum spread for Script tab.
input int DefaultMaxEntrySLDistance = 0; // MaxEntrySLDistance: Maximum entry/SL distance for Script tab.
input int DefaultMinEntrySLDistance = 0; // MinEntrySLDistance: Minimum entry/SL distance for Script tab.
input double DefaultMaxPositionSize = 0; // MaxPositionSize: Maximum position size for Script tab.
input bool DefaultSubtractOPV = false; // SubtractOPV: Subtract open positions volume (Script tab).
input bool DefaultSubtractPOV = false; // SubtractPOV: Subtract pending orders volume (Script tab).
input bool DefaultDoNotApplyStopLoss = false; // DoNotApplyStopLoss: Don't apply SL for Script tab.
input bool DefaultDoNotApplyTakeProfit = false; // DoNotApplyTakeProfit: Don't apply TP for Script tab.
input int DefaultPanelPositionX = 0; // PanelPositionX: Panel's X coordinate.
input int DefaultPanelPositionY = 15; // PanelPositionY: Panel's Y coordinate.
input ENUM_BASE_CORNER DefaultPanelPositionCorner = CORNER_LEFT_UPPER; // PanelPositionCorner: Panel's corner.
//input group "Miscellaneous"
input double TP_Multiplier = 1; // TP Multiplier for SL value, appears in Take-profit button.
input bool UseCommissionToSetTPDistance = false; // UseCommissionToSetTPDistance: For TP button.
input bool ShowSpread = false; // ShowSpread: If true, shows current spread in window caption.
input double AdditionalFunds = 0; // AdditionalFunds: Added to account balance for risk calculation.
input bool UseFixedSLDistance = false; // UseFixedSLDistance: SL distance in points instead of a level.
input bool UseFixedTPDistance = false; // UseFixedTPDistance: TP distance in points instead of a level.
input bool ShowATROptions = false; // ShowATROptions: If true, SL and TP can be set via ATR.
input int ScriptTakePorfitsNumber = 1; // ScriptTakePorfitsNumber: More than 1 target for script to split trades.
input bool CalculateUnadjustedPositionSize = false; // CalculateUnadjustedPositionSize: Ignore broker's restrictions.

QCPositionSizeCalculator ExtDialog;

// Global variables:
bool Dont_Move_the_Panel_to_Default_Corner_X_Y;
uint LastRecalculationTime = 0;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
	Dont_Move_the_Panel_to_Default_Corner_X_Y = true;
	
	// Prevent attachment of second panel if it is not a timeframe/parameters change.
	if (GlobalVariableGet("PSC-" + IntegerToString(ChartID()) + "-Flag") > 0)
	{
	   GlobalVariableDel("PSC-" + IntegerToString(ChartID()) + "-Flag");
	}
	else
	{
		int indicators_total = ChartIndicatorsTotal(0, 0);
		for (int i = 0; i < indicators_total; i++)
		{
         if (ChartIndicatorName(0, 0, i) == "Position Size Calculator" + IntegerToString(ChartID()))
			{
				Print("Position Size Calculator is already attached.");
				return(INIT_FAILED);
			}
		}
	}
	
   IndicatorSetString(INDICATOR_SHORTNAME, "Position Size Calculator" + IntegerToString(ChartID()));
   PanelCaption = "Position Size Calculator (ver. " + Version + ")";

   if (ScriptTakePorfitsNumber > 1)
   {
      ArrayResize(sets.ScriptTP, ScriptTakePorfitsNumber);
      ArrayResize(sets.ScriptTPShare, ScriptTakePorfitsNumber);
      ArrayInitialize(sets.ScriptTP, 0);
      ArrayInitialize(sets.ScriptTPShare, 100 / ScriptTakePorfitsNumber);
   }
   
   if (!ExtDialog.LoadSettingsFromDisk())
   {
      sets.TradeDirection = DefaultTradeDirection;
      sets.EntryLevel = EntryLevel;
      sets.StopLossLevel = StopLossLevel;
      sets.TakeProfitLevel = TakeProfitLevel; // Optional
      sets.ATRPeriod = DefaultATRPeriod;
      sets.ATRMultiplierSL = DefaultATRMultiplierSL;
      sets.ATRMultiplierTP = DefaultATRMultiplierTP;
      sets.ATRTimeframe = DefaultATRTimeframe;
      sets.EntryType = DefaultEntryType; // If Instant, Entry level will be updated to current Ask/Bid price automatically; if Pending, Entry level will remain intact and StopLevel warning will be issued if needed.
      sets.Risk = DefaultRisk; // Risk tolerance in percentage points
      sets.MoneyRisk = DefaultMoneyRisk; // Risk tolerance in account currency
      if (DefaultMoneyRisk > 0) sets.UseMoneyInsteadOfPercentage = true;
      else sets.UseMoneyInsteadOfPercentage = false;
      sets.CommissionPerLot = DefaultCommission; // Commission charged per lot (one side) in account currency.
      sets.RiskFromPositionSize = false;
      sets.AccountButton = DefaultAccountButton;
      sets.CountPendingOrders = DefaultCountPendingOrders; // If true, portfolio risk calculation will also involve pending orders.
      sets.IgnoreOrdersWithoutStopLoss = DefaultIgnoreOrdersWithoutStopLoss; // If true, portfolio risk calculation will skip orders without stop-loss.
      sets.HideAccSize = HideAccSize; // If true, account size line will not be shown.
      sets.ShowLines = DefaultShowLines;
      sets.SelectedTab = MainTab;
      sets.CustomLeverage = DefaultCustomLeverage;
      sets.MagicNumber = DefaultMagicNumber;
      sets.ScriptCommentary = DefaultCommentary;
      sets.DisableTradingWhenLinesAreHidden = DefaultDisableTradingWhenLinesAreHidden;
      if (ScriptTakePorfitsNumber > 1)
      {
         for (int i = 0; i < ScriptTakePorfitsNumber; i++)
         {
            sets.ScriptTP[i] = TakeProfitLevel;
            sets.ScriptTPShare[i] = 100 / ScriptTakePorfitsNumber;
         }
      }
      sets.MaxSlippage = DefaultMaxSlippage;
      sets.MaxSpread = DefaultMaxSpread;
      sets.MaxEntrySLDistance = DefaultMaxEntrySLDistance;
      sets.MinEntrySLDistance = DefaultMinEntrySLDistance;
      sets.MaxPositionSize = DefaultMaxPositionSize;
      sets.StopLoss = 0;
      sets.TakeProfit = 0;
      sets.SubtractPendingOrders = DefaultSubtractPOV;
      sets.SubtractPositions = DefaultSubtractOPV;
      sets.DoNotApplyStopLoss = DefaultDoNotApplyStopLoss;
      sets.DoNotApplyTakeProfit = DefaultDoNotApplyTakeProfit;
      sets.WasSelectedEntryLine = false;
      sets.WasSelectedStopLossLine  = false;
      sets.WasSelectedTakeProfitLine = false;
      sets.IsPanelMinimized = false;
      if ((int)sets.ATRTimeframe == 0) sets.ATRTimeframe = (ENUM_TIMEFRAMES)_Period;
   }

   if (!ExtDialog.Create(0, PanelCaption, 0, DefaultPanelPositionX, DefaultPanelPositionY)) return(-1);

   string filename = ExtDialog.IniFileName() + ExtDialog.IniFileExt();
   // No ini file - move the panel according to the inputs.
   if (!FileIsExist(filename)) Dont_Move_the_Panel_to_Default_Corner_X_Y = false;

   ExtDialog.IniFileLoad();
   ExtDialog.Run();

   Initialization();
   
   // Brings panel on top of other objects without actual maximization of the panel.
   ExtDialog.HideShowMaximize(false);

   if (!Dont_Move_the_Panel_to_Default_Corner_X_Y)
   {
      int new_x = DefaultPanelPositionX, new_y = DefaultPanelPositionY;
      int chart_width = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
      int chart_height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      int panel_width = ExtDialog.Width();
      int panel_height = ExtDialog.Height();
      
      // Invert coordinate if necessary.
      if (DefaultPanelPositionCorner == CORNER_LEFT_LOWER)
      {
         new_y = chart_height - panel_height - new_y;
      }
      else if (DefaultPanelPositionCorner == CORNER_RIGHT_UPPER)
      {
         new_x = chart_width - panel_width - new_x;
      }
      else if (DefaultPanelPositionCorner == CORNER_RIGHT_LOWER)
      {
         new_x = chart_width - panel_width - new_x;
         new_y = chart_height - panel_height - new_y;
      }
      
      ExtDialog.Move(new_x, new_y);
      ExtDialog.FixatePanelPosition(); // Remember the panel's new position for the INI file.
   }

   EventSetTimer(1);
   
   return(INIT_SUCCEEDED);
}
  
void OnDeinit(const int reason)
{
   // If we tried to add a second indicator, do not delete objects.
   if (reason == REASON_INITFAILED) return;
	
	ObjectDelete("StopLossLabel");
	ObjectDelete("TakeProfitLabel");
   if (reason == REASON_REMOVE)
   {
      ExtDialog.DeleteSettingsFile();
      ObjectDelete("EntryLine");
      ObjectDelete("StopLossLine");
      ObjectDelete("TakeProfitLine");
      if (!FileDelete(ExtDialog.IniFileName() + ExtDialog.IniFileExt())) Print("Failed to delete PSC panel's .ini file: ", GetLastError());
   }  
   else
   {
      // It is deinitialization due to input parameters change - save current parameters values (that are also changed via panel) to global variables.
      if (reason == REASON_PARAMETERS) GlobalVariableSet("PSC-" + IntegerToString(ChartID()) + "-Parameters", 1);

   	ExtDialog.SaveSettingsOnDisk();
   	// Set temporary global variable, so that the indicator knows it is reinitializing because of timeframe/parameters change and should not prevent attachment.
   	if ((reason == REASON_CHARTCHANGE) || (reason == REASON_PARAMETERS) || (reason == REASON_RECOMPILE)) GlobalVariableSet("PSC-" + IntegerToString(ChartID()) + "-Flag", 1);
   }
   
   ExtDialog.Destroy(reason);

   EventKillTimer();
}
  
//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   ExtDialog.RefreshValues();
	return(rates_total);
}

//+------------------------------------------------------------------+
//| ChartEvent function                                              |
//+------------------------------------------------------------------+
void OnChartEvent(const int id,
                  const long &lparam,
                  const double &dparam,
                  const string &sparam)
{
   // Remember the panel's location to have the same location for minimized and maximized states.
   if ((id == CHARTEVENT_CUSTOM + ON_DRAG_END) && (lparam == -1))
   {
      ExtDialog.remember_top = ExtDialog.Top();
      ExtDialog.remember_left = ExtDialog.Left();
   }

   // Catch multiple TP fields.
   if (ScriptTakePorfitsNumber > 1)
   {
      if (id == CHARTEVENT_CUSTOM + ON_END_EDIT)
      {
         // Take-profit field #N.
         if (StringSubstr(sparam, 0, StringLen(ExtDialog.Name() + "m_EdtScriptTPEdit")) == ExtDialog.Name() + "m_EdtScriptTPEdit")
         {
            int i = (int)StringToInteger(StringSubstr(sparam, StringLen(ExtDialog.Name() + "m_EdtScriptTPEdit"))) - 1;
            ExtDialog.UpdateScriptTPEdit(i);
         }
         // Take-profit share field #N.
         if (StringSubstr(sparam, 0, StringLen(ExtDialog.Name() + "m_EdtScriptTPShareEdit")) == ExtDialog.Name() + "m_EdtScriptTPShareEdit")
         {
            int i = (int)StringToInteger(StringSubstr(sparam, StringLen(ExtDialog.Name() + "m_EdtScriptTPShareEdit"))) - 1;
            ExtDialog.UpdateScriptTPShareEdit(i);
         }
      }
   }   

	// Call Panel's event handler only if it is not a CHARTEVENT_CHART_CHANGE - workaround for minimization bug on chart switch.
   if (id != CHARTEVENT_CHART_CHANGE) ExtDialog.OnEvent(id, lparam, dparam, sparam);

   // Recalculate on chart changes, clicks, and certain object dragging.
   if ((id == CHARTEVENT_CLICK) || (id == CHARTEVENT_CHART_CHANGE) ||
   ((id == CHARTEVENT_OBJECT_DRAG) && ((sparam == "EntryLine") || (sparam == "StopLossLine") || (sparam == "TakeProfitLine"))))
   {
      // Moving lines when fixed SL/TP distance is enabled. Should set a new fixed SL/TP distance.
      if ((id == CHARTEVENT_OBJECT_DRAG) && (sparam == "StopLossLine") && ((UseFixedSLDistance) || (ShowATROptions))) ExtDialog.UpdateFixedSL();
      if ((id == CHARTEVENT_OBJECT_DRAG) && (sparam == "TakeProfitLine") && ((UseFixedTPDistance) || (ShowATROptions))) ExtDialog.UpdateFixedTP();
      if (id != CHARTEVENT_CHART_CHANGE) ExtDialog.RefreshValues();

      // If this is an active chart, make sure the panel is visible (not behind the chart's borders). For inactive chart, this will work poorly, because inactive charts get minimized by MetaTrader.
      if (ChartGetInteger(ChartID(), CHART_BRING_TO_TOP))
      {
         if (ExtDialog.Top() < 0) ExtDialog.Move(ExtDialog.Left(), 0);
         int chart_height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
         if (ExtDialog.Top() > chart_height) ExtDialog.Move(ExtDialog.Left(), chart_height - ExtDialog.Height());
         int chart_width = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         if (ExtDialog.Left() > chart_width) ExtDialog.Move(chart_width - ExtDialog.Width(), ExtDialog.Top());
      }

      ChartRedraw();
   }
}

//+------------------------------------------------------------------+
//| Trade event handler                                              |
//+------------------------------------------------------------------+
void OnTrade()
{
   ExtDialog.RefreshValues();
   ChartRedraw();   
}

//+------------------------------------------------------------------+
//| Timer event handler                                              |
//+------------------------------------------------------------------+
void OnTimer()
{
   if (GetTickCount() - LastRecalculationTime < 1000) return; // Do not recalculate on timer if less than 1 second passed.
   ExtDialog.RefreshValues();
   ChartRedraw();
}
//+------------------------------------------------------------------+