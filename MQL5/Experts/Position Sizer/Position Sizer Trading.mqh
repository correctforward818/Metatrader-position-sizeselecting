//+------------------------------------------------------------------+
//|                                       Position Sizer Trading.mqh |
//|                                  Copyright © 2023, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+

#include <Trade/Trade.mqh>
#include "errordescription.mqh"

//+------------------------------------------------------------------+
//| Main trading function.                                           |
//+------------------------------------------------------------------+
void Trade()
{
    CTrade *Trade;
    
    string Commentary = "";

    if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        Alert("Algo Trading disabled! Please enable Algo Trading.");
        return;
    }


    if (WarningSL != "") // Too close or wrong value.
    {
        Alert("Stop-loss problem " + WarningSL);
        return;
    }
    
    if (OutputPositionSize <= 0)
    {
        Alert("Wrong position size value!");
        return;
    }

    double TP[], TPShare[]; // Mimics sets.TP[] and sets.TPShare[], but always includes the main TP too.

    ArrayResize(TP, sets.TakeProfitsNumber);
    ArrayResize(TPShare, sets.TakeProfitsNumber);

    if (sets.TakeProfitsNumber > 1)
    {
        Print("Multiple TP volume share sum = ", TotalVolumeShare, ".");
        if ((TotalVolumeShare < 99) || (TotalVolumeShare > 100))
        {
            Alert("Incorrect volume sum for multiple TPs - not taking any trades.");
            return;
        }
        for (int i = 0; i < sets.TakeProfitsNumber; i++)
        {
            TP[i] = sets.TP[i];
            TPShare[i] = sets.TPShare[i];
        }
    }

    if (sets.Commentary != "") Commentary = sets.Commentary;

    if (sets.CommentAutoSuffix) Commentary += IntegerToString((int)TimeLocal());


    if ((sets.TakeProfitsNumber == 1) || (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_NETTING))
    {
        if (sets.TakeProfitsNumber > 1)
        {
            Print("Netting mode detected. Multiple TPs won't work. Setting one TP at 100% volume.");
        }
        // No multiple TPs, use single TP for 100% of volume.
        TP[0] = sets.TakeProfitLevel;
        TPShare[0] = 100;
    }

    if ((sets.DisableTradingWhenLinesAreHidden) && (!sets.ShowLines))
    {
        Alert("Not taking a trade - lines are hidden and panel is set not to trade when they are hidden.");
        return;
    }

    if (sets.MaxSpread > 0)
    {
        int spread = (int)SymbolInfoInteger(SymbolForTrading, SYMBOL_SPREAD);
        if (spread > sets.MaxSpread)
        {
            Alert("Not taking a trade - current spread (", spread, ") > maximum spread (", sets.MaxSpread, ").");
            return;
        }
    }

    if (sets.MaxEntrySLDistance > 0)
    {
        int CurrentEntrySLDistance = (int)(MathAbs(sets.StopLossLevel - sets.EntryLevel) / Point());
        if (CurrentEntrySLDistance > sets.MaxEntrySLDistance)
        {
            Alert("Not taking a trade - current Entry/SL distance (", CurrentEntrySLDistance, ") > maximum Entry/SL distance (", sets.MaxEntrySLDistance, ").");
            return;
        }
    }

    if (sets.MinEntrySLDistance > 0)
    {
        int CurrentEntrySLDistance = (int)(MathAbs(sets.StopLossLevel - sets.EntryLevel) / Point());
        if (CurrentEntrySLDistance < sets.MinEntrySLDistance)
        {
            Alert("Not taking a trade - current Entry/SL distance (", CurrentEntrySLDistance, ") < minimum Entry/SL distance (", sets.MinEntrySLDistance, ").");
            return;
        }
    }

    if (sets.MaxNumberOfTrades > 0)
    {
        int total = PositionsTotal();
        int cnt = 0;
        if (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) // Makes sense in a hedging mode.
        {
            for (int i = 0; i < total; i++)
            {
                if (!PositionSelectByTicket(PositionGetTicket(i))) continue;
                if ((sets.MagicNumber != 0) && (PositionGetInteger(POSITION_MAGIC) != sets.MagicNumber)) continue;
                if ((!sets.AllSymbols) && (PositionGetString(POSITION_SYMBOL) != SymbolForTrading)) continue;
                /*if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) || (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL))*/ cnt++;
            }
        }
        else if ((sets.AllSymbols) || ((!sets.AllSymbols) && ((sets.EntryType == Pending) || (sets.EntryType == StopLimit)))) // In netting, it can only count positions on different symbols.
        {
            // Need to remember that it might be so that the current trade won't increase the counter if there is already a position in this symbol. Unless it is a pending order being opened.
            for (int i = 0; i < total; i++)
            {
                if (!PositionSelectByTicket(PositionGetTicket(i))) continue;
                if ((sets.MagicNumber != 0) && (PositionGetInteger(POSITION_MAGIC) != sets.MagicNumber)) continue;
                if ((PositionGetString(POSITION_SYMBOL) == SymbolForTrading) && (sets.EntryType == Instant)) continue; // Skip current symbol, because in netting mode, new trade won't create another position, but will rather add/subtract from the existing one.
                /*if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) || (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL))*/ cnt++;
            }
        }
        
        // Now, it has to count pending orders as well.
        total = OrdersTotal();
        for (int i = 0; i < total; i++)
        {
            if (!OrderSelect(OrderGetTicket(i))) continue;
            if ((sets.MagicNumber != 0) && (OrderGetInteger(ORDER_MAGIC) != sets.MagicNumber)) continue;
            if ((!sets.AllSymbols) && (OrderGetString(ORDER_SYMBOL) != SymbolForTrading)) continue;
            /*if ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) || (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL))*/ cnt++;
        }
                
        if (cnt >= sets.MaxNumberOfTrades)
        {
            Alert("Not taking a trade - current # of traes (", cnt, ") >= maximum number of trades (", sets.MaxNumberOfTrades, ").");
            return;
        }
    }

    
    if (sets.MaxTotalRisk > 0)
    {
        CalculatePortfolioRisk(true);
        double risk;
        if (PortfolioLossMoney != DBL_MAX)
        {
            risk = (PortfolioLossMoney + OutputRiskMoney) / AccSize * 100;
            if (risk > sets.MaxTotalRisk)
            {
                Alert("Not taking a trade - total potential risk (", DoubleToString(risk, 2), ") >= maximum risk (", DoubleToString(sets.MaxTotalRisk, 2), ").");
                return;
            }
        }
        else
        {
            Alert("Not taking a trade - infinite total potential risk.");
            return;
        }
    }
    
    Trade = new CTrade;
    Trade.SetDeviationInPoints(sets.MaxSlippage);
    if (sets.MagicNumber > 0) Trade.SetExpertMagicNumber(sets.MagicNumber);

    ENUM_SYMBOL_TRADE_EXECUTION Execution_Mode = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(SymbolForTrading, SYMBOL_TRADE_EXEMODE);
    string warning_suffix = "";
    if ((Execution_Mode == SYMBOL_TRADE_EXECUTION_MARKET) && (IgnoreMarketExecutionMode) && (sets.EntryType == Instant)) warning_suffix = ", but IgnoreMarketExecutionMode = true. Switch to false if trades aren't executing.";
    Print("Execution mode: ", EnumToString(Execution_Mode), warning_suffix);

    if (SymbolInfoInteger(SymbolForTrading, SYMBOL_FILLING_MODE) == SYMBOL_FILLING_FOK)
    {
        Print("Order filling mode: Fill or Kill.");
        Trade.SetTypeFilling(ORDER_FILLING_FOK);
    }
    else if (SymbolInfoInteger(SymbolForTrading, SYMBOL_FILLING_MODE) == SYMBOL_FILLING_IOC)
    {
        Print("Order filling mode: Immediate or Cancel.");
        Trade.SetTypeFilling(ORDER_FILLING_IOC);
    }

    double existing_volume_buy = 0, existing_volume_sell = 0;
    if ((sets.SubtractPendingOrders) || (sets.SubtractPositions))
    {
        CalculateOpenVolume(existing_volume_buy, existing_volume_sell);
        Print("Found existing buy volume = ", DoubleToString(existing_volume_buy, LotStep_digits));
        Print("Found existing sell volume = ", DoubleToString(existing_volume_sell, LotStep_digits));
    }

    bool isOrderPlacementFailing = false; // Track if any of the order-operations fail.
    bool AtLeastOneOrderExecuted = false; // Track if at least one order got executed. Required for cases when some of the multiple TP orders have volume < minimum volume and don't get executed.

    ENUM_ORDER_TYPE ot;
    double PositionSize = OutputPositionSize;
    if ((sets.EntryType == Pending) || (sets.EntryType == StopLimit))
    {
        // Sell
        if (sets.TradeDirection == Short)
        {
            // Stop
            if (sets.EntryLevel < SymbolInfoDouble(SymbolForTrading, SYMBOL_BID)) ot = ORDER_TYPE_SELL_STOP;
            // Limit
            else ot = ORDER_TYPE_SELL_LIMIT;
            // Stop Limit
            if (sets.EntryType == StopLimit) ot = ORDER_TYPE_SELL_STOP_LIMIT;
        }
        // Buy
        else
        {
            // Stop
            if (sets.EntryLevel > SymbolInfoDouble(SymbolForTrading, SYMBOL_ASK)) ot = ORDER_TYPE_BUY_STOP;
            // Limit
            else ot = ORDER_TYPE_BUY_LIMIT;
            // Stop Limit
            if (sets.EntryType == StopLimit) ot = ORDER_TYPE_BUY_STOP_LIMIT;
        }

        if ((sets.SubtractPendingOrders) || (sets.SubtractPositions))
        {
            if ((ot == ORDER_TYPE_BUY_LIMIT) || (ot == ORDER_TYPE_BUY_STOP) || (ot == ORDER_TYPE_BUY_STOP_LIMIT)) PositionSize -= existing_volume_buy;
            else PositionSize -= existing_volume_sell;
            Print("Adjusted position size = ", DoubleToString(PositionSize, LotStep_digits));
            if (PositionSize < 0)
            {
                Print("Adjusted position size is less than zero. Not executing any trade.");
                return;
            }
        }

        if (sets.MaxPositionSize > 0)
        {
            double volume = CalculateExistingVolume();
            if (volume + PositionSize > sets.MaxPositionSize)
            {
                Alert("Not taking a trade - current total volume (", DoubleToString(volume, LotStep_digits), ") + new position volume (", DoubleToString(PositionSize, LotStep_digits), ") >= maximum total volume (", sets.MaxPositionSize, ").");
                return;
            }
        }

        if ((sets.AskForConfirmation) && (!CheckConfirmation(ot, PositionSize, sets.StopLossLevel, sets.TakeProfitLevel)))
        {
            delete Trade;
            return;
        }

        // Use ArrayPositionSize that has already been calculated in CalculateRiskAndPositionSize().
        // Check if they are OK.
        for (int j = sets.TakeProfitsNumber - 1; j >= 0; j--)
        {
            if (ArrayPositionSize[j] < MinLot)
            {
                Print("Position size ", ArrayPositionSize[j], " < broker's minimum position size. Not executing the trade.");
                ArrayPositionSize[j] = 0;
                continue;
            }
            else if ((ArrayPositionSize[j] > MaxLot) && (!SurpassBrokerMaxPositionSize))
            {
                Print("Position size ", ArrayPositionSize[j], " > broker's maximum position size. Reducing it.");
                ArrayPositionSize[j] = MaxLot;
            }
        }
        
        // Going through a cycle to execute multiple TP trades.
        for (int j = 0; j < sets.TakeProfitsNumber; j++)
        {
            if (ArrayPositionSize[j] == 0) continue; // Calculated PS < broker's minimum.
            double tp = NormalizeDouble(TP[j], _Digits);
            double position_size = NormalizeDouble(ArrayPositionSize[j], LotStep_digits);
            double sl = sets.StopLossLevel;

            if (sets.DoNotApplyStopLoss) sl = 0;
            if (sets.DoNotApplyTakeProfit) tp = 0;

            if ((tp != 0) && (((tp <= sets.EntryLevel) && ((ot == ORDER_TYPE_BUY_STOP_LIMIT) || (ot == ORDER_TYPE_BUY_STOP) || (ot == ORDER_TYPE_BUY_LIMIT))) || ((tp >= sets.EntryLevel) && ((ot == ORDER_TYPE_SELL_STOP_LIMIT) || (ot == ORDER_TYPE_SELL_STOP) || (ot == ORDER_TYPE_SELL_LIMIT))))) tp = 0; // Do not apply TP if it is invald. SL will still be applied.
            while (position_size > 0)
            {
                double sub_position_size;
                if (position_size > MaxLot)
                {
                    sub_position_size = MaxLot;
                    position_size = NormalizeDouble(position_size - MaxLot, LotStep_digits);
                }
                else
                {
                    sub_position_size = position_size;
                    position_size = 0; // End the cycle;
                }    
                if (!Trade.OrderOpen(SymbolForTrading, ot, sub_position_size, sets.EntryType == StopLimit ? sets.EntryLevel : 0, sets.EntryType == StopLimit ? sets.StopPriceLevel : sets.EntryLevel, sl, tp, 0, 0, Commentary))
                {
                    Print("Error sending order: ", Trade.ResultRetcodeDescription() + ".");
                    isOrderPlacementFailing = true;
                }
                else
                {
                    if (sets.TakeProfitsNumber == 1) Print("Order executed. Ticket: ", Trade.ResultOrder(), ".");
                    else Print("Order #", j, " executed. Ticket: ", Trade.ResultOrder(), ".");
                    AtLeastOneOrderExecuted = true;
                }
            }
        }
    }
    // Instant
    else
    {
        // Sell
        if (sets.StopLossLevel > sets.EntryLevel) ot = ORDER_TYPE_SELL;
        // Buy
        else ot = ORDER_TYPE_BUY;

        if ((sets.SubtractPendingOrders) || (sets.SubtractPositions))
        {
            if (ot == ORDER_TYPE_BUY) PositionSize -= existing_volume_buy;
            else PositionSize -= existing_volume_sell;
            Print("Adjusted position size = ", DoubleToString(PositionSize, LotStep_digits));
            if (PositionSize < 0)
            {
                Print("Adjusted position size is less than zero. Not executing any trade.");
                return;
            }
        }

        if (sets.MaxPositionSize > 0)
        {
            double volume = CalculateExistingVolume();
            if (volume + PositionSize > sets.MaxPositionSize)
            {
                Alert("Not taking a trade - current total volume (", DoubleToString(volume, LotStep_digits), ") + new position volume (", DoubleToString(PositionSize, LotStep_digits), ") >= maximum total volume (", sets.MaxPositionSize, ").");
                return;
            }
        }

        if ((sets.AskForConfirmation) && (!CheckConfirmation(ot, PositionSize, sets.StopLossLevel, sets.TakeProfitLevel)))
        {
            delete Trade;
            return;
        }

        // Use ArrayPositionSize that has already been calculated in CalculateRiskAndPositionSize().
        // Check if they are OK.
        for (int j = sets.TakeProfitsNumber - 1; j >= 0; j--)
        {
            if (ArrayPositionSize[j] < MinLot)
            {
                Print("Position size ", ArrayPositionSize[j], " < broker's minimum position size. Not executing the trade.");
                ArrayPositionSize[j] = 0;
                continue;
            }
            else if ((ArrayPositionSize[j] > MaxLot) && (!SurpassBrokerMaxPositionSize))
            {
                Print("Position size ", ArrayPositionSize[j], " > broker's maximum position size. Reducing it.");
                ArrayPositionSize[j] = MaxLot;
            }
        }

        // Will be used if MarketModeApplySLTPAfterAllTradesExecuted == true.
        ulong array_of_deals[], array_of_orders[];
        double array_of_sl[], array_of_tp[];
        ENUM_ORDER_TYPE array_of_ot[];
        int array_cnt = 0;

        // Going through a cycle to execute multiple TP trades.
        for (int j = 0; j < sets.TakeProfitsNumber; j++)
        {
            if (ArrayPositionSize[j] == 0) continue; // Calculated PS < broker's minimum.
            double order_sl = sets.StopLossLevel;
            double sl = order_sl;
            double order_tp = NormalizeDouble(TP[j], _Digits);
            double tp = order_tp;
            double position_size = NormalizeDouble(ArrayPositionSize[j], LotStep_digits);

            // Market execution mode - preparation.
            if ((Execution_Mode == SYMBOL_TRADE_EXECUTION_MARKET) && (sets.EntryType == Instant) && (!IgnoreMarketExecutionMode))
            {
                // No SL/TP allowed on instant orders.
                order_sl = 0;
                order_tp = 0;
            }
            if (sets.DoNotApplyStopLoss)
            {
                sl = 0;
                order_sl = 0;
            }
            if (sets.DoNotApplyTakeProfit)
            {
                tp = 0;
                order_tp = 0;
            }

            if ((order_tp != 0) && (((order_tp <= sets.EntryLevel) && (ot == ORDER_TYPE_BUY)) || ((order_tp >= sets.EntryLevel) && (ot == ORDER_TYPE_SELL)))) order_tp = 0; // Do not apply TP if it is invald. SL will still be applied.

            // Cycle for splitting up trade/subtrade into more subtrades starts here.
            while (position_size > 0)
            {
                double sub_position_size;
                if (position_size > MaxLot)
                {
                    sub_position_size = MaxLot;
                    position_size = NormalizeDouble(position_size - MaxLot, LotStep_digits);
                }
                else
                {
                    sub_position_size = position_size;
                    position_size = 0; // End the cycle;
                }    
            
                if (!Trade.PositionOpen(SymbolForTrading, ot, sub_position_size, sets.EntryLevel, order_sl, order_tp, Commentary))
                {
                    Print("Error sending order: ", Trade.ResultRetcodeDescription() + ".");
                    isOrderPlacementFailing = true;
                }
                else
                {
                    MqlTradeResult result;
                    Trade.Result(result);
                    if ((Trade.ResultRetcode() != 10008) && (Trade.ResultRetcode() != 10009) && (Trade.ResultRetcode() != 10010))
                    {
                        Print("Error opening a position. Return code: ", Trade.ResultRetcodeDescription());
                        isOrderPlacementFailing = true;
                        break;
                    }
    
                    Print("Initial return code: ", Trade.ResultRetcodeDescription());
    
                    ulong order = result.order;
                    Print("Order ID: ", order);
    
                    ulong deal = result.deal;
                    Print("Deal ID: ", deal);
                    AtLeastOneOrderExecuted = true;
                    if (!sets.DoNotApplyTakeProfit) tp = TP[j];
                    // Market execution mode - application of SL/TP.
                    if ((Execution_Mode == SYMBOL_TRADE_EXECUTION_MARKET) && (sets.EntryType == Instant) && (!IgnoreMarketExecutionMode) && ((sl != 0) || (tp != 0)))
                    {
                        if (MarketModeApplySLTPAfterAllTradesExecuted) // Finish opening all trades, then apply all SLs and TPs.
                        {
                            array_cnt++;
                            ArrayResize(array_of_deals, array_cnt);
                            ArrayResize(array_of_orders, array_cnt);
                            ArrayResize(array_of_sl, array_cnt);
                            ArrayResize(array_of_tp, array_cnt);
                            ArrayResize(array_of_ot, array_cnt);
                            array_of_deals[array_cnt - 1] = deal;
                            array_of_orders[array_cnt - 1] = order;
                            array_of_sl[array_cnt - 1] = sl;
                            array_of_tp[array_cnt - 1] = tp;
                            array_of_ot[array_cnt - 1] = ot;
                        }
                        else
                        {
                            if (!ApplySLTPToOrder(Trade, deal, order, sl, tp, ot))
                            {
                                isOrderPlacementFailing = true;
                            }
                        }
                    }
                }
            } // Cycle for splitting up trade/subtrade into more subtrades ends here.
        }
        // Run position adjustment if necessary.
        for (int j = 0; j < array_cnt; j++)
        {
            if (!ApplySLTPToOrder(Trade, array_of_deals[j], array_of_orders[j], array_of_sl[j], array_of_tp[j], array_of_ot[j]))
            {
                isOrderPlacementFailing = true;
            }
        }
    }    
        
    if (!DisableTradingSounds) PlaySound((isOrderPlacementFailing) || (!AtLeastOneOrderExecuted) ? "timeout.wav" : "ok.wav");

    delete Trade;
}

// Applies SL/TP to a single position (used in the Market execution mode).
// Returns false in case of a failure, true - in case of a success.
bool ApplySLTPToOrder(CTrade& trade_object, ulong deal, ulong order, double sl, double tp, ENUM_ORDER_TYPE ot)
{
    bool isOrderPlacementFailing = false;
    if ((tp != 0) && (((tp <= sets.EntryLevel) && (ot == ORDER_TYPE_BUY)) || ((tp >= sets.EntryLevel) && (ot == ORDER_TYPE_SELL)))) tp = 0; // Do not apply TP if it is invald. SL will still be applied.
    // Not all brokers return deal.
    if (deal != 0)
    {
        if (HistorySelect(TimeCurrent() - 60, TimeCurrent()))
        {
            if (HistoryDealSelect(deal))
            {
                long position = HistoryDealGetInteger(deal, DEAL_POSITION_ID);
                Print("Position ID: ", position);

                if (!trade_object.PositionModify(position, sl, tp))
                {
                    int error = GetLastError();
                    Print("Error modifying position: ", IntegerToString(error), " - ", ErrorDescription(error), ".");
                    isOrderPlacementFailing = true;
                }
                else Print("SL/TP applied successfully.");
            }
            else
            {
                int error = GetLastError();
                Print("Error selecting deal: ", IntegerToString(error), " - ", ErrorDescription(error), ".");
                isOrderPlacementFailing = true;
            }
        }
        else
        {
            int error = GetLastError();
            Print("Error selecting deal history: ", IntegerToString(error), " - ", ErrorDescription(error), ".");
            isOrderPlacementFailing = true;
        }
    }
    // Wait for position to open then find it using the order ID.
    else
    {
        // Run a waiting cycle until the order becomes a positoin.
        for (int i = 0; i < 10; i++)
        {
            Print("Waiting...");
            Sleep(1000);
            if (PositionSelectByTicket(order)) break;
        }
        if (!PositionSelectByTicket(order))
        {
            int error = GetLastError();
            Print("Error selecting positions: ", IntegerToString(error), " - ", ErrorDescription(error), ".");
            isOrderPlacementFailing = true;
        }
        else
        {
            if (!trade_object.PositionModify(order, sl, tp))
            {
                int error = GetLastError();
                Print("Error modifying position: ", IntegerToString(error), " - ", ErrorDescription(error), ".");
                isOrderPlacementFailing = true;
            }
            else Print("SL/TP applied successfully.");
        }
    }

    if (!isOrderPlacementFailing) return true;
    else return false;
}                    

// Calculate volume of open positions and/or pending orders.
// Counts volumes separately for buy and sell trades and writes them into parameterss.
void CalculateOpenVolume(double &volume_buy, double &volume_sell)
{
    if (sets.SubtractPendingOrders)
    {
        int total = OrdersTotal();
        for (int i = 0; i < total; i++)
        {
            // Select an order.
            if (!OrderSelect(OrderGetTicket(i))) continue;
            // Skip orders with a different trading instrument.
            if (OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
            // If magic number is given via PS panel and order's magic number is different - skip.
            if ((sets.MagicNumber != 0) && (OrderGetInteger(ORDER_MAGIC) != sets.MagicNumber)) continue;

            // Buy orders
            if ((OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_LIMIT) || (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_BUY_STOP)) volume_buy += OrderGetDouble(ORDER_VOLUME_CURRENT);
            // Sell orders
            else if ((OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_LIMIT) || (OrderGetInteger(ORDER_TYPE) == ORDER_TYPE_SELL_STOP)) volume_sell += OrderGetDouble(ORDER_VOLUME_CURRENT);
        }
    }

    if (sets.SubtractPositions)
    {
        int total = PositionsTotal();
        for (int i = 0; i < total; i++)
        {
            // Works with hedging and netting.
            if (!PositionSelectByTicket(PositionGetTicket(i))) continue;
            // Skip positions with a different trading instrument.
            if (PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
            // If magic number is given via PS panel and position's magic number is different - skip.
            if ((sets.MagicNumber != 0) && (PositionGetInteger(POSITION_MAGIC) != sets.MagicNumber)) continue;

            // Long positions
            if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) volume_buy += PositionGetDouble(POSITION_VOLUME);
            // Short positions
            else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) volume_sell += PositionGetDouble(POSITION_VOLUME);
        }
    }
}

//+------------------------------------------------------------------+
//| Check confirmation for order opening via dialog window.          |
//+------------------------------------------------------------------+
bool CheckConfirmation(const ENUM_ORDER_TYPE ot, const double PositionSize, const double sl, const double tp)
{
    // Evoke confirmation modal window.
    string caption = "Position Sizer on " + SymbolForTrading + " @ " + StringSubstr(EnumToString((ENUM_TIMEFRAMES)Period()), 7) + ": Execute the trade?";
    string message;
    string order_type_text = "";
    string currency = AccountInfoString(ACCOUNT_CURRENCY);
    switch(ot)
    {
    case ORDER_TYPE_BUY:
        order_type_text = "Buy";
        break;
    case ORDER_TYPE_BUY_STOP:
        order_type_text = "Buy Stop";
        break;
    case ORDER_TYPE_BUY_LIMIT:
        order_type_text = "Buy Limit";
        break;
    case ORDER_TYPE_BUY_STOP_LIMIT:
        order_type_text = "Buy Stop Limit";
        break;
    case ORDER_TYPE_SELL:
        order_type_text = "Sell";
        break;
    case ORDER_TYPE_SELL_STOP:
        order_type_text = "Sell Stop";
        break;
    case ORDER_TYPE_SELL_LIMIT:
        order_type_text = "Sell Limit";
        break;
    case ORDER_TYPE_SELL_STOP_LIMIT:
        order_type_text = "Sell Stop Limit";
        break;
    default:
        break;
    }

    message = "Order: " + order_type_text + "\n";
    message += "Size: " + DoubleToString(PositionSize, LotStep_digits);
    if (sets.TakeProfitsNumber > 1) message += " (multiple)";
    message += "\n";
    message += EnumToString(sets.AccountButton);
    message += ": " + FormatDouble(DoubleToString(AccSize, 2)) + " " + AccountCurrency + "\n";
    message += "Risk: " + FormatDouble(DoubleToString(OutputRiskMoney)) + " " + AccountCurrency + "\n";
    if (PositionMargin != 0) message += "Margin: " + FormatDouble(DoubleToString(PositionMargin, 2)) + " " + AccountCurrency + "\n";
    if (sets.StopPriceLevel > 0) message += "Stop price: " + DoubleToString(sets.StopPriceLevel, _Digits) + "\n";
    message += "Entry: " + DoubleToString(sets.EntryLevel, _Digits) + "\n";
    if (!sets.DoNotApplyStopLoss) message += "Stop-loss: " + DoubleToString(sets.StopLossLevel, _Digits) + "\n";
    if ((sets.TakeProfitLevel > 0) && (!sets.DoNotApplyTakeProfit)) message += "Take-profit: " + DoubleToString(sets.TakeProfitLevel, _Digits);
    if (sets.TakeProfitsNumber > 1) message += " (multiple)";
    message += "\n";

    int ret = MessageBox(message, caption, MB_OKCANCEL | MB_ICONWARNING);
    if (ret == IDCANCEL)
    {
        Print("Trade canceled.");
        return false;
    }
    return true;
}

// Does trailing based on the Magic number and symbol.
void DoTrailingStop()
{
    CTrade *Trade;
    Trade = new CTrade;
    Trade.SetDeviationInPoints(sets.MaxSlippage);
    if (sets.MagicNumber > 0) Trade.SetExpertMagicNumber(sets.MagicNumber);

    if ((!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) || (!TerminalInfoInteger(TERMINAL_CONNECTED)) || (!MQLInfoInteger(MQL_TRADE_ALLOWED))) return;

    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0) Print("PositionGetTicket failed " + ErrorDescription(GetLastError()) + ".");
        else if (SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) continue;
        else
        {
            if ((PositionGetString(POSITION_SYMBOL) != SymbolForTrading) || (PositionGetInteger(POSITION_MAGIC) != sets.MagicNumber)) continue;
            if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                double SL = NormalizeDouble(SymbolInfoDouble(SymbolForTrading, SYMBOL_BID) - sets.TrailingStopPoints * _Point, _Digits);
                if (SL > PositionGetDouble(POSITION_SL))
                {
                    if (!Trade.PositionModify(ticket, SL, PositionGetDouble(POSITION_TP)))
                        Print("PositionModify Buy TSL failed " + ErrorDescription(GetLastError()) + ".");
                    else
                        Print("Trailing stop was applied to position - " + SymbolForTrading + " BUY #" + IntegerToString(ticket) + " Lotsize = " + DoubleToString(PositionGetDouble(POSITION_VOLUME), LotStep_digits) + ", OpenPrice = " + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), _Digits) + ", Stop-Loss was moved from " + DoubleToString(PositionGetDouble(POSITION_SL), _Digits) + " to " + DoubleToString(SL, _Digits) + ".");
                }
            }
            else if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                double SL = NormalizeDouble(SymbolInfoDouble(SymbolForTrading, SYMBOL_ASK) + sets.TrailingStopPoints * _Point, _Digits);
                if ((SL < PositionGetDouble(POSITION_SL)) || (PositionGetDouble(POSITION_SL) == 0))
                {
                    if (!Trade.PositionModify(ticket, SL, PositionGetDouble(POSITION_TP)))
                        Print("PositionModify Sell TSL failed " + ErrorDescription(GetLastError()) + ".");
                    else
                        Print("Trailing stop was applied to position - " + SymbolForTrading + " SELL #" + IntegerToString(ticket) + " Lotsize = " + DoubleToString(PositionGetDouble(POSITION_VOLUME), LotStep_digits) + ", OpenPrice = " + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), _Digits) + ", Stop-Loss was moved from " + DoubleToString(PositionGetDouble(POSITION_SL), _Digits) + " to " + DoubleToString(SL, _Digits) + ".");
                }
            }
        }
    }
    
    delete Trade;
}

// Sets SL to breakeven based on the Magic number and symbol.
void DoBreakEven()
{
    CTrade *Trade;
    Trade = new CTrade;
    Trade.SetDeviationInPoints(sets.MaxSlippage);
    if (sets.MagicNumber > 0) Trade.SetExpertMagicNumber(sets.MagicNumber);

    if ((!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) || (!TerminalInfoInteger(TERMINAL_CONNECTED)) || (!MQLInfoInteger(MQL_TRADE_ALLOWED))) return;

    for (int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0) Print("PositionGetTicket failed " + ErrorDescription(GetLastError()) + ".");
        else if (SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED) continue;
        else
        {
            if ((PositionGetString(POSITION_SYMBOL) != SymbolForTrading) || (PositionGetInteger(POSITION_MAGIC) != sets.MagicNumber)) continue;
            if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            {
                double BE = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN) + sets.BreakEvenPoints * _Point, _Digits);
                if ((SymbolInfoDouble(SymbolForTrading, SYMBOL_BID) >= BE) && (PositionGetDouble(POSITION_PRICE_OPEN) > PositionGetDouble(POSITION_SL))) // Only move to breakeven if the current stop-loss is lower.
                {
                    // Write Open price to the SL field.
                    if (!Trade.PositionModify(ticket, PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_TP)))
                        Print("OrderModify Buy BE failed " + ErrorDescription(GetLastError()) + ".");
                    else
                        Print("Breakeven was applied to position - " + SymbolForTrading + " BUY #" + IntegerToString(ticket) + " Lotsize = " + DoubleToString(PositionGetDouble(POSITION_VOLUME), LotStep_digits) + ", OpenPrice = " + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), _Digits) + ", Stop-Loss was moved from " + DoubleToString(PositionGetDouble(POSITION_SL), _Digits) + ".");
                }
            }
            else if ((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
            {
                double BE = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN) - sets.BreakEvenPoints * _Point, _Digits);
                if ((SymbolInfoDouble(SymbolForTrading, SYMBOL_ASK) <= BE) && ((PositionGetDouble(POSITION_PRICE_OPEN) < PositionGetDouble(POSITION_SL)) || (PositionGetDouble(POSITION_SL) == 0))) // Only move to breakeven if the current stop-loss is higher (or zero).
                {
                    // Write Open price to the SL field.
                    if (!Trade.PositionModify(ticket, PositionGetDouble(POSITION_PRICE_OPEN), PositionGetDouble(POSITION_TP)))
                        Print("OrderModify Sell BE failed " + ErrorDescription(GetLastError()) + ".");
                    else
                        Print("Breakeven was applied to position - " + SymbolForTrading + " SELL #" + IntegerToString(ticket) + " Lotsize = " + DoubleToString(PositionGetDouble(POSITION_VOLUME), LotStep_digits) + ", OpenPrice = " + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), _Digits) + ", Stop-Loss was moved from " + DoubleToString(PositionGetDouble(POSITION_SL), _Digits) + ".");
                }
            }
        }
    }
    
    delete Trade;
}

// Returns true if max position size won't be surpassed or false otherwise.
double CalculateExistingVolume()
{
    int total = PositionsTotal();
    double volume = 0;
    if (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING) // Makes sense in a hedging mode.
    {
        for (int i = 0; i < total; i++)
        {
            if (!PositionSelectByTicket(PositionGetTicket(i))) continue;
            if ((sets.MagicNumber != 0) && (PositionGetInteger(POSITION_MAGIC) != sets.MagicNumber)) continue;
            if ((!sets.AllSymbols) && (PositionGetString(POSITION_SYMBOL) != SymbolForTrading)) continue;
            volume += PositionGetDouble(POSITION_VOLUME);
        }
    }
    else // Netting. Volume will only be increased if trade direction is the same or it is a different symbol. Or else if it is a pending order being opened.
    {
        for (int i = 0; i < total; i++)
        {
            if (!PositionSelectByTicket(PositionGetTicket(i))) continue;
            if ((sets.MagicNumber != 0) && (PositionGetInteger(POSITION_MAGIC) != sets.MagicNumber)) continue;
            if ((!sets.AllSymbols) && (PositionGetString(POSITION_SYMBOL) != SymbolForTrading)) continue;
            if ((sets.EntryType == Pending) || (sets.EntryType == StopLimit) ||
                (PositionGetString(POSITION_SYMBOL) != SymbolForTrading) || 
                ((PositionGetString(POSITION_SYMBOL) == SymbolForTrading) && (((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) && (sets.TradeDirection == Long)) || ((PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL) && (sets.TradeDirection == Short)))))
            {
                volume += PositionGetDouble(POSITION_VOLUME);
            }
        }
    }
    
    // Count pending orders' volume as well.
    total = OrdersTotal();
    for (int i = 0; i < total; i++)
    {
        if (!OrderSelect(OrderGetTicket(i))) continue;
        if ((sets.MagicNumber != 0) && (OrderGetInteger(ORDER_MAGIC) != sets.MagicNumber)) continue;
        if ((!sets.AllSymbols) && (OrderGetString(ORDER_SYMBOL) != SymbolForTrading)) continue;
        volume += OrderGetDouble(ORDER_VOLUME_CURRENT);
    }
    return volume;
}
//+------------------------------------------------------------------+