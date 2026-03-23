# Expected Skewness Momentum Backtest

MATLAB replication of an expected-skewness and momentum long-short strategy with dependent double sorting, dynamic risk management, Fama-French regressions, and volatility and performance metrics.

## Overview
This project implements a backtest of a cross-sectional equity strategy combining expected skewness and momentum.

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
The strategy generates multiple long-short portfolios with different risk management configurations.
Results show how conditioning momentum on expected skewness and applying dynamic risk management affects risk-adjusted returns.

## Author
Francesco Melocchi, Gianluca De Pieri, Tommaso Rossini
