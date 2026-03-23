# Expected Skewness Momentum Backtest

MATLAB replication of an expected-skewness and momentum long-short strategy with dependent double sorting, dynamic risk management, Fama-French regressions, and volatility and performance metrics.

## Overview
Inspired by Jacobs et al. (2016), which documents the link between expected skewness and momentum returns, showing that skewness-conditioned momentum strategies significantly improve performance.
This work implements a backtest of a cross-sectional equity strategy combining expected skewness and momentum.
The goal is to test whether conditioning momentum portfolios on expected skewness improves performance and robustness.

## Methodology
- Data cleaning and preprocessing
- Penny stock filtering and delisting handling
- Momentum signal (past 12 months excluding the most recent month)
- Expected skewness proxy (max daily return)
- Dependent double sorting (first on expected skewness, then on momentum)
- Long-short zero investment portfolios

## Portfolio Strategies
- Standard
- Weakened
- Enhanced
- Momentum-Neutral

## Risk Management
- Barroso–Santa Clara volatility targeting
- Daniel–Moskowitz crash risk adjustment
- Combined application of both risk management rules (BSC and DM)

## Evaluation
- CAGR, Sharpe, Sortino, Max Drawdown
- Volatility, skewness, tail risk
- Fama-French 5-factor regressions
- Custom Omega metric

## Results
The analysis shows that conditioning momentum on expected skewness and applying dynamic risk management significantly impacts risk-adjusted performance.
Different portfolio constructions and risk management rules lead to distinct return profiles, highlighting the role of crash risk and volatility dynamics.

## How to Run
1. Load your dataset of equity prices into MATLAB
2. Open and run `main_backtest.m`
3. The script will:
   - compute signals (expected skewness and momentum)
   - construct portfolios (standard, weakened, enhanced, neutral)
   - apply risk management (BSC, DM, combined)
   - generate performance metrics and plots

## Data
The dataset used in this project is not included due to data licensing restrictions.
The code is fully reproducible with any panel dataset of equity prices.

## Project Structure
- main_backtest.m  
  Main MATLAB script that implements the full backtesting pipeline:
  signal construction, portfolio sorting, risk management, and performance evaluation.

- results_paper.pdf  
  Final report presenting empirical results of the strategy, including performance analysis and robustness checks.

- reference_paper.pdf  
  Original research paper on expected skewness and momentum, used as theoretical foundation for the strategy.



## Author
Francesco Melocchi, Gianluca De Pieri, Tommaso Rossini
