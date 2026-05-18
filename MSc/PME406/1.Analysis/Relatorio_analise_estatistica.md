---
title: "Relatório de Caracterização Estatística do Estágio de Saída FES/STIMGRASP"
author: "Tiago P. Silva"
date: "18 de maio de 2026"
lang: pt-BR
toc: true
numbersections: true
geometry: margin=2.5cm
---

# 1. Desenho experimental e limitações

Foram analisadas rampas de tensão de DAC e tensão no resistor shunt para três cargas resistivas nominais: 1 kOhm, 2 kOhm e 4,7 kOhm. A análise estima corrente a partir do shunt e reconstrói a tensão na carga por resistência nominal. Como o sistema opera em malha aberta, a regressão caracteriza o comportamento observado no ensaio, mas não garante corrente entregue em operação real quando a carga, contato eletrodo-pele ou condições térmicas mudam.

# 2. Importação e pré-processamento

Os CSVs foram importados diretamente dos arquivos do osciloscópio, removendo os segmentos estacionários antes e depois da rampa útil. As três cargas foram equalizadas para a mesma quantidade de amostras.

| load | samples |
| --- | --- |
| 1k | 58386 |
| 2k | 58386 |
| 4k7 | 58386 |

Figura: figures/01_raw_signals_before_stationary_removal.png

Figura: figures/02_ramp_signals_after_stationary_removal.png

# 3. Conversão shunt-corrente

A corrente foi calculada por I = Vshunt / Rshunt, com Rshunt = 10 Ohm. A tolerância configurada do shunt é 1%.

Figura: figures/03_current_after_conversion.png

# 4. Identificação da região de compliance

A região comum de compliance foi definida antes da regressão usando critério físico baseado na tensão reconstruída na carga. O limite comum foi tomado como a menor magnitude máxima de tensão reconstruída entre as cargas, definindo uma faixa simétrica comum em torno de zero. O modelo linear deve ser interpretado apenas dentro dessa região comum.

| load | Vmin | Vmax | common_Vmin | common_Vmax | total_points | retained_points | removed_points | removed_percent |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1k | -43.803125 | 46.330384 | -46.330384 | 46.330384 | 325 | 325 | 0 | 0.000000 |
| 2k | -46.224740 | 49.559811 | -46.330384 | 46.330384 | 325 | 244 | 81 | 24.923077 |
| 4k7 | -47.619405 | 47.775973 | -46.330384 | 46.330384 | 325 | 76 | 249 | 76.615385 |

Figura: figures/05_compliance_retained_removed.png

# 5. Estatística descritiva relevante

Resumo da região linear retida:

| load | count | mean_mA | sd_mA | min_mA | q25_mA | median_mA | q75_mA | max_mA |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1k | 325 | 0.788753 | 26.416914 | -43.803125 | -21.962662 | 0.131058 | 23.519614 | 46.330384 |
| 2k | 244 | -7.249327 | 15.361609 | -23.112370 | -22.924225 | -10.743657 | 6.197721 | 23.062448 |
| 4k7 | 76 | -0.107802 | 5.777173 | -9.731551 | -5.021909 | -0.269278 | 4.849080 | 9.812040 |

# 6. Correlação exploratória

Correlação foi mantida apenas como evidência exploratória de associação monotônica/linear entre DAC e corrente. A validade do circuito é discutida a partir de erro, resíduos, intervalos e incerteza.

| load | pearson_r | pearson_p | spearman_r | spearman_p | samples | interpretation |
| --- | --- | --- | --- | --- | --- | --- |
| 1k | -0.999909 | 0 | -0.999999 | 0 | 325 | Associacao linear exploratoria; validade do modelo avaliada por residuos, erro e incerteza. |
| 2k | -0.966918 | 0 | -0.991413 | 0 | 244 | Associacao linear exploratoria; validade do modelo avaliada por residuos, erro e incerteza. |
| 4k7 | -0.999815 | 0 | -1.000000 | 0 | 76 | Associacao linear exploratoria; validade do modelo avaliada por residuos, erro e incerteza. |

# 7. Modelos lineares por carga

Modelos independentes por carga foram ajustados como current_mA ~ dac_bin.

| model | load | R2 | adjusted_R2 | sigma_mA | samples | MAE_mA | RMSE_mA | max_abs_error_mA |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| load_1k | 1k | 0.999817 | 0.999817 | 0.357519 | 325 | 0.289716 | 0.356418 | 0.948600 |
| load_2k | 2k | 0.934931 | 0.934662 | 3.926612 | 244 | 3.303021 | 3.910486 | 9.706062 |
| load_4k7 | 4k7 | 0.999630 | 0.999625 | 0.111824 | 76 | 0.095924 | 0.110343 | 0.252044 |

# 8. Modelo global

O modelo global foi ajustado como current_mA ~ dac_bin dentro da região comum de compliance.

| model | R2 | adjusted_R2 | sigma_mA | samples | MAE_mA | RMSE_mA | max_abs_error_mA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| global_current_mA_by_dac | 0.969533 | 0.969486 | 3.741179 | 645 | 2.495843 | 3.735374 | 16.821922 |

# 9. Modelo com interação carga x DAC

O modelo com interação foi ajustado como current_mA ~ dac_bin * load.

| model | R2 | adjusted_R2 | sigma_mA | samples | MAE_mA | RMSE_mA | max_abs_error_mA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| interaction_current_mA_by_dac_load | 0.987226 | 0.987126 | 2.430066 | 645 | 1.406798 | 2.418737 | 9.706062 |

| model | alpha | decision | term | estimate | std_error | statistic | p_value | ci_low | ci_high |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| global_current_mA_by_dac | 0.05 | reject_H0 | (Intercept) | 43.425537 | 0.352335 | 123.250831 | 0.000000 | 42.733672 | 44.117403 |
| global_current_mA_by_dac | 0.05 | reject_H0 | dac_bin | -25.649178 | 0.179309 | -143.044648 | 0.000000 | -26.001280 | -25.297076 |
| interaction_current_mA_by_dac_load | 0.05 | reject_H0 | (Intercept) | 46.610346 | 0.270215 | 172.493608 | 0.000000 | 46.079729 | 47.140963 |
| interaction_current_mA_by_dac_load | 0.05 | reject_H0 | dac_bin | -28.111406 | 0.143676 | -195.657691 | 0.000000 | -28.393542 | -27.829271 |
| interaction_current_mA_by_dac_load | 0.05 | reject_H0 | load2k | -11.034052 | 0.547022 | -20.171135 | 0.000000 | -12.108230 | -9.959875 |
| interaction_current_mA_by_dac_load | 0.05 | do_not_reject_H0 | load4k7 | -3.691311 | 2.125966 | -1.736298 | 0.082993 | -7.866035 | 0.483413 |
| interaction_current_mA_by_dac_load | 0.05 | reject_H0 | dac_bin:load2k | 7.066876 | 0.263485 | 26.820774 | 0.000000 | 6.549474 | 7.584277 |
| interaction_current_mA_by_dac_load | 0.05 | do_not_reject_H0 | dac_bin:load4k7 | 1.955274 | 1.278747 | 1.529055 | 0.126746 | -0.555780 | 4.466329 |
| load_1k | 0.05 | reject_H0 | (Intercept) | 46.610346 | 0.039755 | 1172.442340 | 0.000000 | 46.532135 | 46.688557 |
| load_1k | 0.05 | reject_H0 | dac_bin | -28.111406 | 0.021138 | -1329.889051 | 0.000000 | -28.152992 | -28.069821 |
| load_2k | 0.05 | reject_H0 | (Intercept) | 35.576294 | 0.768533 | 46.291181 | 0.000000 | 34.062426 | 37.090161 |
| load_2k | 0.05 | reject_H0 | dac_bin | -21.044531 | 0.356884 | -58.967369 | 0.000000 | -21.747527 | -20.341535 |
| load_4k7 | 0.05 | reject_H0 | (Intercept) | 42.919035 | 0.097037 | 442.296331 | 0.000000 | 42.725685 | 43.112385 |
| load_4k7 | 0.05 | reject_H0 | dac_bin | -26.156132 | 0.058471 | -447.332761 | 0.000000 | -26.272639 | -26.039625 |

# 10. Comparação entre modelos

A comparação formal entre o modelo global e o modelo com interação foi feita por ANOVA/teste F para modelos aninhados.

| compared_models | alpha | interpretation | model_index | Res.Df | RSS | Df | Sum of Sq | F | Pr(>F) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| current_mA ~ dac_bin | 0.05 | NA | 1 | 643 | 8999.699127 |  |  |  |  |
| current_mA ~ dac_bin * load | 0.05 | O modelo com interacao melhora significativamente o ajuste em relacao ao modelo global. | 2 | 639 | 3773.435106 | 4 | 5226.264021 | 221.256138 | 0 |

# 11. Erro de predição

As métricas de erro foram calculadas dentro da região linear: MAE, RMSE e maior erro absoluto.

| model | R2 | adjusted_R2 | sigma_mA | samples | MAE_mA | RMSE_mA | max_abs_error_mA |
| --- | --- | --- | --- | --- | --- | --- | --- |
| global_current_mA_by_dac | 0.969533 | 0.969486 | 3.741179 | 645 | 2.495843 | 3.735374 | 16.821922 |
| interaction_current_mA_by_dac_load | 0.987226 | 0.987126 | 2.430066 | 645 | 1.406798 | 2.418737 | 9.706062 |
| load_1k | 0.999817 | 0.999817 | 0.357519 | 325 | 0.289716 | 0.356418 | 0.948600 |
| load_2k | 0.934931 | 0.934662 | 3.926612 | 244 | 3.303021 | 3.910486 | 9.706062 |
| load_4k7 | 0.999630 | 0.999625 | 0.111824 | 76 | 0.095924 | 0.110343 | 0.252044 |

Figura: figures/06_measured_vs_predicted.png

Figura: figures/07_current_vs_dac_confidence_band.png

Figura: figures/08_current_vs_dac_prediction_band.png

# 12. Diagnóstico dos resíduos

| model | mean_residual_mA | sd_residual_mA | median_residual_mA | min_residual_mA | max_residual_mA | MAE_mA | RMSE_mA | shapiro_sample_n | shapiro_p_value | normality_interpretation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| global_current_mA_by_dac | 0 | 3.738273 | -1.190753 | -4.112371 | 16.821922 | 2.495843 | 3.735374 | 645 | 0 | A normalidade dos residuos e questionavel pelo teste de Shapiro-Wilk. |

Figura: figures/09_residuals_vs_dac.png

Figura: figures/10_residuals_vs_predicted.png

# 13. Homocedasticidade

| test | statistic | parameter | p_value | method | alpha | interpretation |
| --- | --- | --- | --- | --- | --- | --- |
| manual_breusch_pagan_residual_squared_on_fitted | 116.93181 | 1 | 0 | fallback | 0.05 | Ha evidencia de heterocedasticidade; a hipotese de variancia constante e questionavel. |

# 14. Autocorrelação temporal

Como os dados vêm de uma rampa temporal, a independência dos resíduos não foi assumida automaticamente.

| test | statistic | p_value | method | alpha | interpretation |
| --- | --- | --- | --- | --- | --- |
| manual_durbin_watson_approximation | 0.038588 | 0 | fallback_normal_approximation | 0.05 | Ha evidencia de autocorrelacao temporal; p-valores classicos da regressao podem estar otimistas. |

Figura: figures/11_residual_acf.png

# 15. Outliers e influência

Foram calculados resíduos studentizados, leverage e distância de Cook. Pontos foram apenas marcados e reportados; a remoção automática permanece desativada por padrão.

| samples | influential_points | influential_percent | cook_threshold | max_cook_distance | max_abs_studentized_residual |
| --- | --- | --- | --- | --- | --- |
| 645 | 41 | 6.356589 | 0.006202 | 0.06637 | 4.580621 |

Figura: figures/12_cook_distance_by_index.png

Figura: figures/13_studentized_residuals_by_index.png

Figura: figures/14_leverage_vs_studentized_residuals.png

# 16. Validação cruzada por blocos

A validação por blocos usa cinco blocos contíguos ordenados, treinando em quatro blocos e testando no bloco remanescente. Isso evita usar apenas uma validação aleatória que mistura pontos vizinhos da rampa.

| fold | train_samples | test_samples | MAE_mA | RMSE_mA | max_abs_error_mA |
| --- | --- | --- | --- | --- | --- |
| 1 | 516 | 129 | 4.680013 | 4.999185 | 7.504176 |
| 2 | 516 | 129 | 2.437179 | 2.567308 | 3.784670 |
| 3 | 516 | 129 | 2.994049 | 3.860282 | 6.030168 |
| 4 | 516 | 129 | 2.019707 | 2.116129 | 2.942737 |
| 5 | 516 | 129 | 6.090217 | 9.372174 | 21.062169 |

| folds | RMSE_mean_mA | RMSE_sd_mA | MAE_mean_mA | MAE_sd_mA | max_abs_error_mean_mA | max_abs_error_sd_mA |
| --- | --- | --- | --- | --- | --- | --- |
| 5 | 4.583016 | 2.906036 | 3.644233 | 1.701065 | 8.264784 | 7.37802 |

Figura: figures/15_block_cross_validation_errors.png

# 17. Incerteza metrológica

A incerteza foi tratada como orçamento configurável. Parâmetros de instrumento que não estavam disponíveis foram deixados como placeholders explícitos para substituição por especificações calibradas.

| uncertainty_source | assumed_value | effect_on_metric | observation |
| --- | --- | --- | --- |
| Shunt resistance tolerance | 1% | Approx. current standard uncertainty contribution: 0.17843 mA | Assumes tolerance is representative; replace with calibrated resistor data when available. |
| Oscilloscope voltage uncertainty | 0.002 V | Current uncertainty contribution: 0.2 mA | Placeholder; replace with calibrated instrument specification. |
| Load resistance tolerance | 1% | Reconstructed load-voltage contribution: 0.257513 V | Assumes nominal load tolerance; replace with measured load resistance when available. |
| DAC voltage uncertainty | 0.002 V | Affects predicted current through model slope and DAC input; assumed 0.002 V. | Placeholder; replace with calibrated DAC/output measurement specification. |
| Linear-model coefficient covariance | vcov(lm) | Used through predict.lm confidence interval for mean predicted current. | Coefficient uncertainty is represented in mean confidence intervals; prediction intervals include residual scatter. |

| metric | load | value | unit | observation |
| --- | --- | --- | --- | --- |
| estimated_sampling_rate | NA |  | Hz | CSV files do not provide a calibrated time column; sample index alone is insufficient. |
| current_drift_over_ramp | 1k | -0.001554 | mA/sample | Slope estimated over retained compliance region. |
| current_drift_over_ramp | 2k | -0.001164 | mA/sample | Slope estimated over retained compliance region. |
| current_drift_over_ramp | 4k7 | -0.001435 | mA/sample | Slope estimated over retained compliance region. |

# 18. Métricas de FES não avaliadas

| metric | reason |
| --- | --- |
| Cycle-by-cycle amplitude | Os CSVs disponiveis representam apenas rampa DAC e tensao no shunt; nao ha aquisicao de forma de onda pulsada. |
| Pulse width | Os CSVs disponiveis representam apenas rampa DAC e tensao no shunt; nao ha aquisicao de forma de onda pulsada. |
| Stimulation frequency | Os CSVs disponiveis representam apenas rampa DAC e tensao no shunt; nao ha aquisicao de forma de onda pulsada. |
| Charge per phase | Os CSVs disponiveis representam apenas rampa DAC e tensao no shunt; nao ha aquisicao de forma de onda pulsada. |
| Charge balancing | Os CSVs disponiveis representam apenas rampa DAC e tensao no shunt; nao ha aquisicao de forma de onda pulsada. |
| Overshoot | Os CSVs disponiveis representam apenas rampa DAC e tensao no shunt; nao ha aquisicao de forma de onda pulsada. |
| Ringing | Os CSVs disponiveis representam apenas rampa DAC e tensao no shunt; nao ha aquisicao de forma de onda pulsada. |
| Rise time | Os CSVs disponiveis representam apenas rampa DAC e tensao no shunt; nao ha aquisicao de forma de onda pulsada. |
| Fall time | Os CSVs disponiveis representam apenas rampa DAC e tensao no shunt; nao ha aquisicao de forma de onda pulsada. |
| Waveform distortion | Os CSVs disponiveis representam apenas rampa DAC e tensao no shunt; nao ha aquisicao de forma de onda pulsada. |
| Long-term thermal/temporal stability | Os CSVs disponiveis representam apenas rampa DAC e tensao no shunt; nao ha aquisicao de forma de onda pulsada. |

# 19. Conclusões revisadas

A caracterização sustenta um modelo linear de corrente em função do DAC apenas dentro da região comum de compliance definida fisicamente pela tensão reconstruída na carga. O modelo global é útil como aproximação operacional, mas sua adequação deve ser julgada junto com os erros de predição, intervalos de confiança/predição, diagnóstico residual, autocorrelação temporal e orçamento de incerteza. A ausência de realimentação de corrente no STIMGRASP limita a garantia de corrente entregue em operação real, especialmente fora das condições de carga ensaiadas ou quando o circuito se aproxima dos limites de compliance.

Análises como PCA, cluster e testes de média global foram preservadas somente como material secundário/didático e não são usadas como evidência central de validade metrológica do estágio de saída.

