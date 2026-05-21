if (!requireNamespace("tidyverse", quietly = TRUE)) {
  install.packages("tidyverse")
}

library(tidyverse)

options(digits = 15)

# User-configurable analysis constants ---------------------------------------

figures_dir <- "figures"
tables_dir <- "tables"
report_tex_path <- "Relatorio_analise_estatistica.tex"
report_temp_md_path <- file.path(tempdir(), "Relatorio_analise_estatistica_tmp.md")

remove_influential_points <- FALSE
alpha <- 0.05
confidence_level <- 1 - alpha
n_block_folds <- 5
dac_step <- 0.01
compliance_slope_fraction <- 0.5
compliance_reference_fraction <- 0.5

shunt_resistance_ohm <- 10
shunt_resistance_tolerance <- 0.01
load_resistance_tolerance <- 0.01
scope_voltage_uncertainty_V <- 0.002 # replace with calibrated instrument specification
dac_voltage_uncertainty_V <- 0.002 # replace with calibrated instrument specification

url_1k <- "https://raw.githubusercontent.com/import-tiago/FEI/refs/heads/main/MSc/PME406/0.Data/1k.csv"
url_2k <- "https://raw.githubusercontent.com/import-tiago/FEI/refs/heads/main/MSc/PME406/0.Data/2k.csv"
url_4k7 <- "https://raw.githubusercontent.com/import-tiago/FEI/refs/heads/main/MSc/PME406/0.Data/4k7.csv"

load_resistance_ohm <- c("1k" = 1000, "2k" = 2000, "4k7" = 4700)
load_levels <- names(load_resistance_ohm)

dir.create(figures_dir, showWarnings = FALSE)
dir.create(tables_dir, showWarnings = FALSE)

# Helpers --------------------------------------------------------------------

has_package <- function(package) {
  requireNamespace(package, quietly = TRUE)
}

save_report_plot <- function(plot, filename, width = 8, height = 5) {
  path <- file.path(figures_dir, filename)
  ggsave(path, plot = plot, width = width, height = height, dpi = 300)
  path
}

write_table_csv <- function(table, name) {
  path <- file.path(tables_dir, paste0(name, ".csv"))
  readr::write_csv(table, path)
  path
}

format_number <- function(x, digits = 6) {
  ifelse(is.na(x), "", format(round(x, digits), scientific = FALSE, trim = TRUE))
}

format_pt_date <- function(date = Sys.Date()) {
  month_names <- c(
    "janeiro", "fevereiro", "marco", "abril", "maio", "junho",
    "julho", "agosto", "setembro", "outubro", "novembro", "dezembro"
  )

  paste0(format(date, "%d"), " de ", month_names[as.integer(format(date, "%m"))],
         " de ", format(date, "%Y"))
}

column_label_map <- c(
  dac_volts = "Tensão DAC (V)",
  shunt_volts = "Tensão no shunt (V)",
  sample = "Amostra",
  sample_index = "Índice da amostra",
  samples = "Amostras",
  samples_in_bin = "Amostras no bin",
  load = "Carga",
  model = "Modelo",
  R2 = "R2",
  adjusted_R2 = "R2 ajustado",
  sigma_mA = "Desvio residual (mA)",
  MAE_mA = "MAE (mA)",
  RMSE_mA = "RMSE (mA)",
  max_abs_error_mA = "Erro absoluto máximo (mA)",
  alpha = "Nível alpha",
  decisao = "Decisão",
  decision = "Decisão",
  term = "Termo",
  estimate = "Estimativa",
  std_error = "Erro padrão",
  statistic = "Estatística",
  p_value = "Valor-p",
  raw_p_value = "Valor-p bruto",
  adjusted_p_value = "Valor-p ajustado",
  ci_low = "IC inferior",
  ci_high = "IC superior",
  compared_models = "Modelos comparados",
  interpretation = "Interpretação",
  model_index = "Índice do modelo",
  `Res.Df` = "GL residual",
  RSS = "Soma quad. residual",
  Df = "GL",
  `Sum of Sq` = "Soma dos quadrados",
  F = "Estatística F",
  `Pr(>F)` = "Valor-p (F)",
  Vmin = "Tensão mínima (V)",
  Vmax = "Tensão máxima (V)",
  common_Vmin = "Limite comum mín. (V)",
  common_Vmax = "Limite comum máx. (V)",
  reference_slope_mA_per_V = "Inclinação ref. (mA/V)",
  slope_threshold_mA_per_V = "Limite de inclinação (mA/V)",
  previous_slope_mA_per_V = "Inclinação anterior (mA/V)",
  next_slope_mA_per_V = "Inclinação seguinte (mA/V)",
  local_slope_mA_per_V = "Inclinação local (mA/V)",
  total_points = "Pontos totais",
  retained_points = "Pontos retidos",
  removed_points = "Pontos removidos",
  removed_percent = "Removidos (%)",
  pearson_r = "Correlação Pearson",
  pearson_p = "Valor-p Pearson",
  spearman_r = "Correlação Spearman",
  spearman_p = "Valor-p Spearman",
  count = "N",
  mean_mA = "Média (mA)",
  sd_mA = "Desvio padrão (mA)",
  min_mA = "Mínimo (mA)",
  q25_mA = "Q1 (mA)",
  median_mA = "Mediana (mA)",
  q75_mA = "Q3 (mA)",
  max_mA = "Máximo (mA)",
  mean_residual_mA = "Média dos resíduos (mA)",
  sd_residual_mA = "Desvio dos resíduos (mA)",
  median_residual_mA = "Mediana dos resíduos (mA)",
  min_residual_mA = "Resíduo mínimo (mA)",
  max_residual_mA = "Resíduo máximo (mA)",
  shapiro_sample_n = "Amostras no Shapiro",
  shapiro_p_value = "Valor-p Shapiro",
  parameter = "Parâmetro",
  method = "Método",
  test = "Teste",
  fold = "Bloco",
  folds = "Blocos",
  train_samples = "Amostras de treino",
  test_samples = "Amostras de teste",
  RMSE_mean_mA = "RMSE médio (mA)",
  RMSE_sd_mA = "Desvio do RMSE (mA)",
  MAE_mean_mA = "MAE médio (mA)",
  MAE_sd_mA = "Desvio do MAE (mA)",
  max_abs_error_mean_mA = "Erro máx. médio (mA)",
  max_abs_error_sd_mA = "Desvio do erro máx. (mA)",
  influential_points = "Pontos influentes",
  influential_percent = "Pontos influentes (%)",
  cook_threshold = "Limite de Cook",
  max_cook_distance = "Maior distância de Cook",
  max_abs_studentized_residual = "Maior resíduo studentizado abs.",
  metric = "Métrica",
  reason = "Motivo",
  value = "Valor",
  unit = "Unidade",
  observation = "Observação",
  figure = "Figura",
  path = "Arquivo",
  uncertainty_source = "Fonte de incerteza",
  assumed_value = "Valor assumido",
  effect_on_metric = "Efeito na métrica",
  analysis = "Análise",
  status = "Status",
  component = "Componente",
  variance_proportion = "Proporção da variância",
  cumulative_variance = "Variância acumulada",
  comparison = "Comparação",
  estimated_difference_mA = "Diferença estimada (mA)",
  correction = "Correção",
  current_mA = "Corrente (mA)",
  load_resistance_ohm = "Resistência da carga (Ohm)",
  load_voltage_V = "Tensão na carga (V)",
  fitted_mA = "Corrente ajustada (mA)",
  residual_mA = "Resíduo (mA)",
  studentized_residual = "Resíduo studentizado",
  leverage = "Leverage",
  cook_distance = "Distância de Cook",
  row_index = "Índice da linha",
  inside_common_voltage_limit = "Dentro do limite comum",
  inside_linear_slope_region = "Dentro da região linear",
  compliance_candidate = "Candidato a compliance",
  compliance_run_id = "ID do trecho",
  compliance_run_points = "Pontos do trecho",
  max_compliance_run_points = "Maior trecho",
  in_common_compliance_region = "Na região comum",
  measured_voltage_range_V = "Faixa medida (V)",
  common_voltage_range_V = "Faixa comum (V)",
  raw_samples = "Amostras originais",
  dac_bins = "Bins de DAC",
  bin_width_V = "Largura do bin (V)",
  mean_samples_per_bin = "Amostras/bin",
  influential_by_cook = "Influente por Cook",
  outlier_by_studentized_residual = "Outlier por resíduo studentizado",
  flagged = "Marcado"
)

friendly_column_names <- function(names_in) {
  labels <- unname(column_label_map[names_in])
  ifelse(is.na(labels), gsub("_", " ", names_in), labels)
}

markdown_table <- function(df, digits = 6, max_rows = Inf) {
  if (is.null(df) || nrow(df) == 0) {
    return("_Tabela sem linhas._")
  }

  display <- df |>
    slice_head(n = max_rows) |>
    mutate(across(where(is.numeric), \(x) format_number(x, digits)))

  header <- paste(friendly_column_names(names(display)), collapse = " | ")
  separator <- paste(rep("---", ncol(display)), collapse = " | ")
  rows <- apply(display, 1, \(row) paste(row, collapse = " | "))
  paste(c(paste0("| ", header, " |"), paste0("| ", separator, " |"),
          paste0("| ", rows, " |")), collapse = "\n")
}

markdown_figure <- function(path, caption) {
  c(paste0("![", caption, "](", path, ")"), "", "\\FloatBarrier")
}

latex_centered_figure <- function(path, caption, width = "0.78\\linewidth") {
  c(
    "\\begin{center}",
    paste0("\\includegraphics[width=", width, ",keepaspectratio]{", path, "}"),
    paste0("\\captionof{figure}{", latex_escape(caption), "}"),
    "\\end{center}",
    "\\FloatBarrier"
  )
}

latex_escape <- function(x) {
  x <- as.character(x)
  x <- gsub("\\\\", "\\\\textbackslash{}", x)
  x <- gsub("&", "\\\\&", x)
  x <- gsub("%", "\\\\%", x)
  x <- gsub("\\$", "\\\\$", x)
  x <- gsub("#", "\\\\#", x)
  x <- gsub("_", "\\\\_", x)
  x <- gsub("\\{", "\\\\{", x)
  x <- gsub("\\}", "\\\\}", x)
  x
}

latex_tabular <- function(df, digits = 6, max_rows = Inf) {
  if (is.null(df) || nrow(df) == 0) {
    return("_Tabela sem linhas._")
  }

  display <- df |>
    slice_head(n = max_rows) |>
    mutate(across(where(is.numeric), \(x) format_number(x, digits))) |>
    mutate(across(everything(), latex_escape))

  alignment <- paste(rep("l", ncol(display)), collapse = "")
  header <- paste(latex_escape(friendly_column_names(names(display))), collapse = " & ")
  rows <- apply(display, 1, \(row) paste(row, collapse = " & "))

  c(
    paste0("\\begin{tabular}{@{}", alignment, "@{}}"),
    "\\toprule",
    paste0(header, " \\\\"),
    "\\midrule",
    paste0(rows, " \\\\"),
    "\\bottomrule",
    "\\end{tabular}"
  )
}

latex_compact_table <- function(df, digits = 3, font_size = "\\scriptsize") {
  c(
    "\\begin{center}",
    font_size,
    "\\resizebox{\\textwidth}{!}{%",
    latex_tabular(df, digits = digits),
    "}%",
    "\\end{center}"
  )
}

latex_side_by_side_figures <- function(left_path, left_caption, right_path, right_caption) {
  c(
    "\\begin{center}",
    "\\begin{minipage}[t]{0.495\\linewidth}",
    "\\centering",
    paste0("\\includegraphics[width=\\linewidth,keepaspectratio]{", left_path, "}"),
    paste0("\\captionof{figure}{", latex_escape(left_caption), "}"),
    "\\end{minipage}",
    "\\hfill",
    "\\begin{minipage}[t]{0.495\\linewidth}",
    "\\centering",
    paste0("\\includegraphics[width=\\linewidth,keepaspectratio]{", right_path, "}"),
    paste0("\\captionof{figure}{", latex_escape(right_caption), "}"),
    "\\end{minipage}",
    "\\end{center}",
    "\\clearpage"
  )
}

latex_compact_side_by_side_figures <- function(left_path, left_caption, right_path, right_caption) {
  c(
    "\\begin{center}",
    "\\captionsetup{font=small}",
    "\\begin{minipage}[t]{0.495\\linewidth}",
    "\\centering",
    paste0("\\includegraphics[width=\\linewidth,keepaspectratio]{", left_path, "}"),
    paste0("\\captionof{figure}{", latex_escape(left_caption), "}"),
    "\\end{minipage}",
    "\\hfill",
    "\\begin{minipage}[t]{0.495\\linewidth}",
    "\\centering",
    paste0("\\includegraphics[width=\\linewidth,keepaspectratio]{", right_path, "}"),
    paste0("\\captionof{figure}{", latex_escape(right_caption), "}"),
    "\\end{minipage}",
    "\\end{center}",
    "\\FloatBarrier"
  )
}

latex_side_by_side_tables <- function(left_df, right_df) {
  c(
    "\\begin{table}[htbp]",
    "\\centering",
    "\\makebox[\\textwidth][c]{%",
    "\\begin{minipage}[t]{0.42\\textwidth}",
    "\\vspace{0pt}",
    "\\centering",
    "\\scriptsize",
    latex_tabular(left_df),
    "\\end{minipage}%",
    "\\hspace{0.03\\textwidth}%",
    "\\begin{minipage}[t]{0.18\\textwidth}",
    "\\vspace{0pt}",
    "\\centering",
    "\\small",
    latex_tabular(right_df),
    "\\end{minipage}%",
    "}",
    "\\end{table}",
    "\\FloatBarrier"
  )
}

render_report_tex <- function(markdown_lines, temp_md_path, tex_path) {
  writeLines(markdown_lines, temp_md_path, useBytes = TRUE)
  on.exit(unlink(temp_md_path), add = TRUE)

  pandoc_path <- Sys.which("pandoc")
  if (pandoc_path == "") {
    stop("Pandoc executable was not found in PATH.")
  }

  pandoc_args <- c(
    temp_md_path,
    "--standalone",
    "--from", "markdown",
    "--to", "latex",
    "--output", tex_path
  )

  pandoc_output <- system2(pandoc_path, args = pandoc_args, stdout = TRUE, stderr = TRUE)
  pandoc_status <- attr(pandoc_output, "status")

  if (!is.null(pandoc_status) && pandoc_status != 0) {
    stop(
      paste(c("Pandoc failed while generating the LaTeX report:", pandoc_output), collapse = "\n")
    )
  }
}

hypothesis_decision <- function(p_value, alpha = 0.05) {
  if_else(is.na(p_value), NA_character_,
          if_else(p_value < alpha, "rejeita_H0", "nao_rejeita_H0"))
}

prediction_error_metrics <- function(actual, predicted) {
  residual <- actual - predicted
  tibble(
    MAE_mA = mean(abs(residual), na.rm = TRUE),
    RMSE_mA = sqrt(mean(residual^2, na.rm = TRUE)),
    max_abs_error_mA = max(abs(residual), na.rm = TRUE)
  )
}

model_fit_summary <- function(model, data, model_name) {
  predicted <- predict(model, newdata = data)
  errors <- prediction_error_metrics(data$current_mA, predicted)
  model_summary <- summary(model)

  tibble(
    model = model_name,
    R2 = model_summary$r.squared,
    adjusted_R2 = model_summary$adj.r.squared,
    sigma_mA = model_summary$sigma,
    samples = nrow(data)
  ) |>
    bind_cols(errors)
}

model_coefficients_ci <- function(model, model_name) {
  coef_table <- as.data.frame(summary(model)$coefficients) |>
    rownames_to_column("term") |>
    as_tibble() |>
    rename(
      estimate = Estimate,
      std_error = `Std. Error`,
      statistic = `t value`,
      p_value = `Pr(>|t|)`
    )

  ci <- as.data.frame(confint(model, level = confidence_level)) |>
    rownames_to_column("term") |>
    as_tibble() |>
    rename(ci_low = `2.5 %`, ci_high = `97.5 %`)

  coef_table |>
    left_join(ci, by = "term") |>
    mutate(
      model = model_name,
      alpha = alpha,
      decision = hypothesis_decision(p_value, alpha),
      .before = 1
    ) |>
    rename(decisao = decision)
}

add_prediction_intervals <- function(model, data) {
  mean_interval <- as_tibble(predict(
    model,
    newdata = data,
    interval = "confidence",
    level = confidence_level
  )) |>
    rename(
      predicted_mA = fit,
      mean_ci_low_mA = lwr,
      mean_ci_high_mA = upr
    )

  prediction_interval <- as_tibble(predict(
    model,
    newdata = data,
    interval = "prediction",
    level = confidence_level
  )) |>
    rename(
      prediction_fit_mA = fit,
      prediction_low_mA = lwr,
      prediction_high_mA = upr
    ) |>
    select(-prediction_fit_mA)

  bind_cols(data, mean_interval, prediction_interval) |>
    mutate(residual_mA = current_mA - predicted_mA)
}

summary_stats <- function(df) {
  df |>
    group_by(load) |>
    summarise(
      count = sum(!is.na(current_mA)),
      mean_mA = mean(current_mA, na.rm = TRUE),
      sd_mA = sd(current_mA, na.rm = TRUE),
      min_mA = min(current_mA, na.rm = TRUE),
      q25_mA = quantile(current_mA, 0.25, na.rm = TRUE),
      median_mA = median(current_mA, na.rm = TRUE),
      q75_mA = quantile(current_mA, 0.75, na.rm = TRUE),
      max_mA = max(current_mA, na.rm = TRUE),
      .groups = "drop"
    )
}

read_scope_csv <- function(url) {
  read_csv(
    url,
    skip = 17,
    col_select = 2:3,
    show_col_types = FALSE
  ) |>
    set_names(c("dac_volts", "shunt_volts")) |>
    mutate(sample = row_number() - 1)
}

extract_ramp_region <- function(df, column = "dac_volts",
                                trigger_threshold = 0.5,
                                discarded_points = 512) {
  if (!column %in% names(df)) {
    stop("Column '", column, "' was not found in the data.")
  }

  delta <- abs(df[[column]] - dplyr::lag(df[[column]]))
  transition_points <- which(delta > trigger_threshold)

  if (length(transition_points) < 2) {
    stop("Could not detect ramp start and end transitions.")
  }

  start <- transition_points[1] + discarded_points
  end <- transition_points[length(transition_points)] - discarded_points
  df[start:end, ]
}

equalize_sample_count <- function(data_list) {
  sample_count <- min(map_int(data_list, nrow))

  result <- map(data_list, \(df) {
    df |>
      slice_head(n = sample_count) |>
      mutate(sample = row_number() - 1)
  })

  names(result) <- names(data_list)
  result
}

manual_breusch_pagan <- function(model) {
  residual_sq <- residuals(model)^2
  fitted_values <- fitted(model)
  aux_model <- lm(residual_sq ~ fitted_values)
  statistic <- length(residual_sq) * summary(aux_model)$r.squared
  p_value <- pchisq(statistic, df = 1, lower.tail = FALSE)

  tibble(
    test = "manual_breusch_pagan_residual_squared_on_fitted",
    statistic = statistic,
    parameter = 1,
    p_value = p_value,
    method = "fallback"
  )
}

heteroscedasticity_test <- function(model) {
  result <- if (has_package("lmtest")) {
    test <- lmtest::bptest(model)
    tibble(
      test = "breusch_pagan",
      statistic = unname(test$statistic),
      parameter = unname(test$parameter),
      p_value = test$p.value,
      method = "lmtest"
    )
  } else {
    manual_breusch_pagan(model)
  }

  result |>
    mutate(
      alpha = alpha,
      interpretation = if_else(
        p_value < alpha,
        "Ha evidencia de heterocedasticidade; a hipotese de variancia constante e questionavel.",
        "Nao ha evidencia estatistica de heterocedasticidade com alpha = 0.05."
      )
    )
}

manual_durbin_watson <- function(model) {
  residual <- residuals(model)
  statistic <- sum(diff(residual)^2) / sum(residual^2)
  rho <- cor(residual[-length(residual)], residual[-1])
  n <- length(residual)
  z <- rho * sqrt(n)
  p_value <- 2 * pnorm(abs(z), lower.tail = FALSE)

  tibble(
    test = "manual_durbin_watson_approximation",
    statistic = statistic,
    p_value = p_value,
    method = "fallback_normal_approximation"
  )
}

autocorrelation_test <- function(model) {
  result <- if (has_package("lmtest")) {
    test <- lmtest::dwtest(model)
    tibble(
      test = "durbin_watson",
      statistic = unname(test$statistic),
      p_value = test$p.value,
      method = "lmtest"
    )
  } else {
    manual_durbin_watson(model)
  }

  result |>
    mutate(
      alpha = alpha,
      interpretation = if_else(
        p_value < alpha,
        "Ha evidencia de autocorrelacao temporal; p-valores classicos da regressao podem estar otimistas.",
        "Nao ha evidencia estatistica de autocorrelacao temporal com alpha = 0.05."
      )
    )
}

block_cross_validation <- function(data, formula, folds = 5) {
  ordered_data <- data |>
    arrange(load, sample_index, dac_bin) |>
    mutate(row_index = row_number())

  block_id <- cut(
    ordered_data$row_index,
    breaks = folds,
    labels = FALSE,
    include.lowest = TRUE
  )

  fold_results <- map_dfr(seq_len(folds), \(fold) {
    train <- ordered_data[block_id != fold, ]
    test <- ordered_data[block_id == fold, ]
    fit <- lm(formula, data = train)
    pred <- predict(fit, newdata = test)
    errors <- prediction_error_metrics(test$current_mA, pred)

    tibble(
      fold = fold,
      train_samples = nrow(train),
      test_samples = nrow(test)
    ) |>
      bind_cols(errors)
  })

  fold_summary <- fold_results |>
    summarise(
      folds = n(),
      RMSE_mean_mA = mean(RMSE_mA),
      RMSE_sd_mA = sd(RMSE_mA),
      MAE_mean_mA = mean(MAE_mA),
      MAE_sd_mA = sd(MAE_mA),
      max_abs_error_mean_mA = mean(max_abs_error_mA),
      max_abs_error_sd_mA = sd(max_abs_error_mA)
    )

  list(folds = fold_results, summary = fold_summary)
}

influence_diagnostics <- function(model, data) {
  diagnostics <- data |>
    mutate(
      row_index = row_number(),
      fitted_mA = fitted(model),
      residual_mA = residuals(model),
      studentized_residual = rstudent(model),
      leverage = hatvalues(model),
      cook_distance = cooks.distance(model),
      influential_by_cook = cook_distance > 4 / nrow(data),
      outlier_by_studentized_residual = abs(studentized_residual) > 3,
      flagged = influential_by_cook | outlier_by_studentized_residual
    )

  summary <- diagnostics |>
    summarise(
      samples = n(),
      influential_points = sum(flagged, na.rm = TRUE),
      influential_percent = 100 * influential_points / samples,
      cook_threshold = 4 / samples,
      max_cook_distance = max(cook_distance, na.rm = TRUE),
      max_abs_studentized_residual = max(abs(studentized_residual), na.rm = TRUE)
    )

  list(points = diagnostics, summary = summary)
}

estimate_temporal_metrics <- function(raw_long, linear_long) {
  sampling_rate <- tibble(
    metric = "estimated_sampling_rate",
    value = NA_real_,
    unit = "Hz",
    observation = "CSV files do not provide a calibrated time column; sample index alone is insufficient."
  )

  drift <- linear_long |>
    group_by(load) |>
    summarise(
      metric = "current_drift_over_ramp",
      value = coef(lm(current_mA ~ sample_index))[["sample_index"]],
      unit = "mA/sample",
      observation = "Slope estimated over retained compliance region.",
      .groups = "drop"
    ) |>
    select(metric, load, value, unit, observation)

  bind_rows(
    sampling_rate |> mutate(load = NA_character_, .after = metric),
    drift
  )
}

uncertainty_budget <- function(data) {
  mean_abs_shunt_v <- mean(abs(data$shunt_volts), na.rm = TRUE)
  mean_abs_current_mA <- mean(abs(data$current_mA), na.rm = TRUE)
  mean_abs_load_v <- mean(abs(data$load_voltage_V), na.rm = TRUE)

  tibble(
    uncertainty_source = c(
      "Shunt resistance tolerance",
      "Oscilloscope voltage uncertainty",
      "Load resistance tolerance",
      "DAC voltage uncertainty",
      "Linear-model coefficient covariance"
    ),
    assumed_value = c(
      paste0(shunt_resistance_tolerance * 100, "%"),
      paste0(scope_voltage_uncertainty_V, " V"),
      paste0(load_resistance_tolerance * 100, "%"),
      paste0(dac_voltage_uncertainty_V, " V"),
      "vcov(lm)"
    ),
    effect_on_metric = c(
      paste0("Approx. current standard uncertainty contribution: ",
             format_number(mean_abs_current_mA * shunt_resistance_tolerance), " mA"),
      paste0("Current uncertainty contribution: ",
             format_number(scope_voltage_uncertainty_V / shunt_resistance_ohm * 1000), " mA"),
      paste0("Reconstructed load-voltage contribution: ",
             format_number(mean_abs_load_v * load_resistance_tolerance), " V"),
      paste0("Affects predicted current through model slope and DAC input; assumed ",
             dac_voltage_uncertainty_V, " V."),
      "Used through predict.lm confidence interval for mean predicted current."
    ),
    observation = c(
      "Assumes tolerance is representative; replace with calibrated resistor data when available.",
      "Placeholder; replace with calibrated instrument specification.",
      "Assumes nominal load tolerance; replace with measured load resistance when available.",
      "Placeholder; replace with calibrated DAC/output measurement specification.",
      "Coefficient uncertainty is represented in mean confidence intervals; prediction intervals include residual scatter."
    )
  )
}

fes_metrics_not_evaluated <- tibble(
  metric = c(
    "Cycle-by-cycle amplitude",
    "Pulse width",
    "Stimulation frequency",
    "Charge per phase",
    "Charge balancing",
    "Overshoot",
    "Ringing",
    "Rise time",
    "Fall time",
    "Waveform distortion",
    "Long-term thermal/temporal stability"
  ),
  reason = "Os CSVs disponiveis representam apenas rampa DAC e tensao no shunt; nao ha aquisicao de forma de onda pulsada."
)

# Data import and preprocessing ---------------------------------------------

raw_data <- list(
  "1k" = read_scope_csv(url_1k),
  "2k" = read_scope_csv(url_2k),
  "4k7" = read_scope_csv(url_4k7)
)

raw_long <- imap_dfr(raw_data, \(df, load) {
  df |>
    mutate(load = load, .before = 1)
})

raw_1k_preview <- raw_data[["1k"]] |>
  slice_head(n = 5)

ramp_data <- raw_data |>
  map(\(df) extract_ramp_region(df, column = "dac_volts")) |>
  equalize_sample_count()

ramp_sample_summary <- imap_dfr(ramp_data, \(df, load) {
  tibble(load = load, samples = nrow(df))
})

converted_data <- imap_dfr(ramp_data, \(df, load) {
  resistance <- load_resistance_ohm[[load]]

  df |>
    mutate(
      load = load,
      sample_index = row_number(),
      current_mA = shunt_volts / shunt_resistance_ohm * 1000,
      load_resistance_ohm = resistance,
      load_voltage_V = current_mA / 1000 * load_resistance_ohm
    )
})

processed_current_data <- converted_data |>
  mutate(dac_bin = round(round(dac_volts / dac_step) * dac_step, 2)) |>
  group_by(dac_bin, load) |>
  summarise(
    current_mA = mean(current_mA, na.rm = TRUE),
    shunt_volts = mean(shunt_volts, na.rm = TRUE),
    dac_volts = mean(dac_volts, na.rm = TRUE),
    sample_index = round(mean(sample_index, na.rm = TRUE)),
    load_resistance_ohm = first(load_resistance_ohm),
    load_voltage_V = mean(load_voltage_V, na.rm = TRUE),
    samples_in_bin = n(),
    .groups = "drop"
  ) |>
  arrange(load, dac_bin)

binning_summary <- processed_current_data |>
  group_by(load) |>
  summarise(
    raw_samples = sum(samples_in_bin),
    dac_bins = n(),
    bin_width_V = dac_step,
    mean_samples_per_bin = mean(samples_in_bin),
    .groups = "drop"
  )

processed_wide <- processed_current_data |>
  select(dac_bin, load, current_mA) |>
  summarise(current_mA = mean(current_mA, na.rm = TRUE), .by = c(dac_bin, load)) |>
  pivot_wider(names_from = load, values_from = current_mA) |>
  arrange(dac_bin)

# Compliance region ----------------------------------------------------------

v_limits_summary <- processed_current_data |>
  group_by(load, load_resistance_ohm) |>
  summarise(
    Vmin = min(load_voltage_V, na.rm = TRUE),
    Vmax = max(load_voltage_V, na.rm = TRUE),
    abs_Vmax = max(abs(load_voltage_V), na.rm = TRUE),
    .groups = "drop"
  ) |>
  mutate(
    common_abs_Vmax = min(abs_Vmax),
    common_Vmin = -common_abs_Vmax,
    common_Vmax = common_abs_Vmax
  )

common_abs_v_max <- min(v_limits_summary$abs_Vmax)
common_v_min <- -common_abs_v_max
common_v_max <- common_abs_v_max

compliance_class_data <- processed_current_data |>
  group_by(load) |>
  arrange(dac_bin, .by_group = TRUE) |>
  mutate(
    previous_slope_mA_per_V = (current_mA - lag(current_mA)) / (dac_bin - lag(dac_bin)),
    next_slope_mA_per_V = (lead(current_mA) - current_mA) / (lead(dac_bin) - dac_bin),
    local_slope_mA_per_V = coalesce(
      (previous_slope_mA_per_V + next_slope_mA_per_V) / 2,
      previous_slope_mA_per_V,
      next_slope_mA_per_V
    ),
    reference_slope_mA_per_V = median(
      abs(local_slope_mA_per_V[abs(load_voltage_V) <= common_abs_v_max * compliance_reference_fraction]),
      na.rm = TRUE
    ),
    slope_threshold_mA_per_V = reference_slope_mA_per_V * compliance_slope_fraction
  ) |>
  ungroup() |>
  mutate(
    inside_common_voltage_limit = abs(load_voltage_V) <= common_abs_v_max,
    inside_linear_slope_region = abs(local_slope_mA_per_V) >= slope_threshold_mA_per_V,
    compliance_candidate = inside_common_voltage_limit & inside_linear_slope_region
  ) |>
  group_by(load) |>
  arrange(dac_bin, .by_group = TRUE) |>
  mutate(
    compliance_run_id = cumsum(compliance_candidate != lag(compliance_candidate, default = first(compliance_candidate)))
  ) |>
  group_by(load, compliance_run_id) |>
  mutate(compliance_run_points = if_else(first(compliance_candidate), n(), 0L)) |>
  ungroup() |>
  group_by(load) |>
  mutate(
    max_compliance_run_points = max(compliance_run_points, na.rm = TRUE),
    in_common_compliance_region = compliance_candidate & compliance_run_points == max_compliance_run_points
  ) |>
  ungroup()

compliance_summary <- compliance_class_data |>
  group_by(load) |>
  summarise(
    Vmin = min(load_voltage_V, na.rm = TRUE),
    Vmax = max(load_voltage_V, na.rm = TRUE),
    common_Vmin = common_v_min,
    common_Vmax = common_v_max,
    reference_slope_mA_per_V = first(reference_slope_mA_per_V),
    slope_threshold_mA_per_V = first(slope_threshold_mA_per_V),
    total_points = n(),
    retained_points = sum(in_common_compliance_region, na.rm = TRUE),
    removed_points = total_points - retained_points,
    removed_percent = 100 * removed_points / total_points,
    .groups = "drop"
  )

compliance_summary_display <- compliance_summary |>
  transmute(
    load,
    measured_voltage_range_V = paste0(format_number(Vmin, 2), " a ", format_number(Vmax, 2)),
    common_voltage_range_V = paste0(format_number(common_Vmin, 2), " a ", format_number(common_Vmax, 2)),
    reference_slope_mA_per_V,
    slope_threshold_mA_per_V,
    retained_points,
    removed_points,
    removed_percent
  )

linear_long <- compliance_class_data |>
  filter(in_common_compliance_region) |>
  mutate(load = factor(load, levels = load_levels))

if (remove_influential_points) {
  preliminary_model <- lm(current_mA ~ dac_bin * load, data = linear_long)
  preliminary_influence <- influence_diagnostics(preliminary_model, linear_long)
  linear_long <- preliminary_influence$points |>
    filter(!flagged) |>
    select(all_of(names(linear_long)))
}

linear_wide <- linear_long |>
  select(dac_bin, load, current_mA) |>
  summarise(current_mA = mean(current_mA, na.rm = TRUE), .by = c(dac_bin, load)) |>
  pivot_wider(names_from = load, values_from = current_mA) |>
  arrange(dac_bin)

# Descriptive and exploratory analyses --------------------------------------

full_region_stats <- processed_current_data |>
  summary_stats()

linear_region_stats <- linear_long |>
  summary_stats()

correlation_summary <- linear_long |>
  group_by(load) |>
  summarise(
    pearson_r = cor(dac_bin, current_mA, method = "pearson"),
    pearson_p = cor.test(dac_bin, current_mA, method = "pearson")$p.value,
    spearman_r = cor(dac_bin, current_mA, method = "spearman"),
    spearman_p = cor.test(dac_bin, current_mA, method = "spearman", exact = FALSE)$p.value,
    samples = n(),
    interpretation = "Associacao linear exploratoria; validade do modelo avaliada por residuos, erro e limites de compliance.",
    .groups = "drop"
  )

# Linear models --------------------------------------------------------------

per_load_model_data_split <- linear_long |>
  group_by(load) |>
  group_split()

per_load_model_names <- per_load_model_data_split |>
  map_chr(\(df) as.character(df$load[1]))

per_load_models <- per_load_model_data_split |>
  set_names(per_load_model_names) |>
  map(\(df) lm(current_mA ~ dac_bin, data = df))

global_model <- lm(current_mA ~ dac_bin, data = linear_long)
interaction_model <- lm(current_mA ~ dac_bin * load, data = linear_long)

global_model_data <- add_prediction_intervals(global_model, linear_long)

per_load_model_data <- imap_dfr(per_load_models, \(model, load_name) {
  data <- linear_long |> filter(load == load_name)
  add_prediction_intervals(model, data) |>
    mutate(model_load = load_name, .before = 1)
})

model_coefficients_ci_table <- bind_rows(
  model_coefficients_ci(global_model, "global_current_mA_by_dac"),
  model_coefficients_ci(interaction_model, "interaction_current_mA_by_dac_load"),
  imap_dfr(per_load_models, \(model, load_name) {
    model_coefficients_ci(model, paste0("load_", load_name))
  })
)

per_load_model_summary <- imap_dfr(per_load_models, \(model, load_name) {
  data <- linear_long |> filter(load == load_name)
  model_fit_summary(model, data, paste0("load_", load_name)) |>
    mutate(load = load_name, .after = model)
})

global_model_summary <- model_fit_summary(
  global_model,
  linear_long,
  "global_current_mA_by_dac"
)

interaction_model_summary <- model_fit_summary(
  interaction_model,
  linear_long,
  "interaction_current_mA_by_dac_load"
)

model_comparison_table <- as.data.frame(anova(global_model, interaction_model)) |>
  rownames_to_column("model_index") |>
  as_tibble() |>
  mutate(
    compared_models = c("current_mA ~ dac_bin", "current_mA ~ dac_bin * load"),
    alpha = alpha,
    interpretation = if_else(
      row_number() == n(),
      if_else(
        `Pr(>F)` < alpha,
        "O modelo com interacao melhora significativamente o ajuste em relacao ao modelo global.",
        "Nao ha evidencia estatistica de melhora do modelo com interacao em relacao ao modelo global."
      ),
      NA_character_
    ),
    .before = 1
  )

prediction_error_summary <- bind_rows(
  global_model_summary,
  interaction_model_summary,
  per_load_model_summary |> select(-load)
)

# Residual diagnostics -------------------------------------------------------

shapiro_residual_sample <- global_model_data |>
  slice_sample(n = min(5000, nrow(global_model_data)))

shapiro_residual_test <- shapiro.test(shapiro_residual_sample$residual_mA)

residual_diagnostics_summary <- global_model_data |>
  summarise(
    model = "global_current_mA_by_dac",
    mean_residual_mA = mean(residual_mA),
    sd_residual_mA = sd(residual_mA),
    median_residual_mA = median(residual_mA),
    min_residual_mA = min(residual_mA),
    max_residual_mA = max(residual_mA),
    MAE_mA = mean(abs(residual_mA)),
    RMSE_mA = sqrt(mean(residual_mA^2)),
    shapiro_sample_n = nrow(shapiro_residual_sample),
    shapiro_p_value = shapiro_residual_test$p.value
  ) |>
  mutate(
    normality_interpretation = if_else(
      shapiro_p_value < alpha,
      "A normalidade dos residuos e questionavel pelo teste de Shapiro-Wilk.",
      "Nao ha evidencia estatistica contra normalidade dos residuos pelo teste de Shapiro-Wilk."
    )
  )

heteroscedasticity_test_summary <- heteroscedasticity_test(global_model)
autocorrelation_test_summary <- autocorrelation_test(global_model)

acf_values <- acf(global_model_data$residual_mA, plot = FALSE)
acf_data <- tibble(
  lag = as.numeric(acf_values$lag),
  acf = as.numeric(acf_values$acf)
)

influence <- influence_diagnostics(global_model, linear_long)
influence_points <- influence$points
influence_diagnostics_summary <- influence$summary

# Validation and comparisons -------------------------------------------------

block_cv <- block_cross_validation(
  linear_long,
  current_mA ~ dac_bin,
  folds = n_block_folds
)

block_cv_folds <- block_cv$folds
block_cv_summary <- block_cv$summary

multiple_comparison_corrected <- combn(sort(unique(as.character(linear_long$load))), 2, simplify = FALSE) |>
  map_dfr(\(pair) {
    complete_pairs <- linear_wide |>
      select(dac_bin, all_of(pair)) |>
      drop_na()

    test <- t.test(
      complete_pairs[[pair[1]]],
      complete_pairs[[pair[2]]],
      paired = TRUE,
      conf.level = confidence_level
    )

    tibble(
      comparison = paste(pair, collapse = "_vs_"),
      estimated_difference_mA = mean(complete_pairs[[pair[1]]] - complete_pairs[[pair[2]]]),
      raw_p_value = test$p.value
    )
  }) |>
  mutate(
    adjusted_p_value = p.adjust(raw_p_value, method = "holm"),
    alpha = alpha,
    correction = "Holm",
    decision = hypothesis_decision(adjusted_p_value, alpha)
  )

# Secondary/didactic analyses ------------------------------------------------

secondary_analysis_status <- tibble(
  analysis = c("PCA", "Factor analysis", "Cluster analysis", "Mean-current tests"),
  status = "secondary_didactic_only",
  observation = c(
    "Not used as central evidence for circuit validity.",
    "Not used as central evidence for circuit validity.",
    "Not used as central evidence for circuit validity.",
    "Global mean-current tests are not used as primary validation evidence."
  )
)

pca_variance_summary <- tryCatch({
  pca_input <- linear_wide |> drop_na() |> select(all_of(names(load_resistance_ohm)))
  pca_model <- prcomp(pca_input, center = TRUE, scale. = TRUE)
  tibble(
    component = paste0("PC", seq_along(pca_model$sdev)),
    variance_proportion = pca_model$sdev^2 / sum(pca_model$sdev^2),
    cumulative_variance = cumsum(pca_model$sdev^2 / sum(pca_model$sdev^2))
  )
}, error = \(err) tibble(component = NA_character_, variance_proportion = NA_real_,
                         cumulative_variance = NA_real_))

fes_temporal_metrics <- estimate_temporal_metrics(raw_long, linear_long)
uncertainty_budget_table <- uncertainty_budget(linear_long)
fes_metrics_not_evaluated_table <- fes_metrics_not_evaluated

# Figures --------------------------------------------------------------------

raw_stationary_segments_plot <- raw_long |>
  pivot_longer(c(dac_volts, shunt_volts), names_to = "signal", values_to = "voltage") |>
  mutate(signal = recode(signal, dac_volts = "DAC", shunt_volts = "Shunt")) |>
  ggplot(aes(sample, voltage, color = signal)) +
  geom_line(linewidth = 0.45) +
  facet_wrap(~ load, ncol = 1, scales = "free_x") +
  coord_cartesian(ylim = c(-0.5, 3.5)) +
  labs(x = "Amostra", y = "Tensão [V]", color = "Sinal") +
  theme_minimal(base_size = 13) +
  theme(
    legend.position = "top",
    legend.direction = "horizontal",
    legend.margin = margin(0, 0, 0, 0),
    legend.box.margin = margin(0, 0, -2, 0),
    panel.spacing.y = unit(0.5, "lines"),
    axis.text = element_text(size = 11),
    axis.title = element_text(size = 13),
    strip.text = element_text(size = 13),
    legend.title = element_text(size = 13),
    legend.text = element_text(size = 13),
    legend.key.width = unit(1.2, "lines"),
    plot.margin = margin(2, 2, 2, 2)
  )

ramp_signals_plot <- imap_dfr(ramp_data, \(df, load) mutate(df, load = load)) |>
  pivot_longer(c(dac_volts, shunt_volts), names_to = "signal", values_to = "voltage") |>
  mutate(signal = recode(signal, dac_volts = "DAC", shunt_volts = "Shunt")) |>
  ggplot(aes(sample, voltage, color = signal)) +
  geom_line(linewidth = 0.45) +
  facet_wrap(~ load, ncol = 1, scales = "free_x") +
  coord_cartesian(ylim = c(-0.5, 3.5)) +
  labs(x = "Amostra", y = "Tensão [V]", color = "Sinal") +
  theme_minimal(base_size = 13) +
  theme(
    legend.position = "top",
    legend.direction = "horizontal",
    legend.margin = margin(0, 0, 0, 0),
    legend.box.margin = margin(0, 0, -2, 0),
    panel.spacing.y = unit(0.5, "lines"),
    axis.text = element_text(size = 11),
    axis.title = element_text(size = 13),
    strip.text = element_text(size = 13),
    legend.title = element_text(size = 13),
    legend.text = element_text(size = 13),
    legend.key.width = unit(1.2, "lines"),
    plot.margin = margin(2, 2, 2, 2)
  )

current_after_conversion_plot <- converted_data |>
  ggplot(aes(sample_index, current_mA, color = load)) +
  geom_line(linewidth = 0.45) +
  labs(x = "Amostra", y = "Corrente [mA]", color = "Carga") +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "top",
    legend.direction = "horizontal",
    axis.title = element_text(size = 15),
    axis.text = element_text(size = 12),
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 13),
    plot.margin = margin(4, 4, 4, 4)
  )

full_current_plot <- processed_current_data |>
  ggplot(aes(dac_bin, current_mA, color = load)) +
  geom_line(linewidth = 0.8) +
  labs(x = "DAC voltage [V]", y = "Output current [mA]", color = "Load") +
  theme_minimal()

binned_current_by_load_plot <- processed_current_data |>
  ggplot(aes(dac_bin, current_mA, color = load)) +
  geom_line(linewidth = 0.75) +
  geom_point(alpha = 0.65, size = 0.8) +
  labs(x = "Bin de DAC [V]", y = "Corrente média [mA]", color = "Carga") +
  theme_minimal(base_size = 14) +
  theme(
    legend.position = "top",
    legend.direction = "horizontal",
    axis.title = element_text(size = 15),
    axis.text = element_text(size = 12),
    legend.title = element_text(size = 14),
    legend.text = element_text(size = 13),
    plot.margin = margin(4, 4, 4, 4)
  )

compliance_highlight_plot <- compliance_class_data |>
  ggplot(aes(dac_bin, current_mA, color = in_common_compliance_region)) +
  geom_point(alpha = 0.7, size = 1.7) +
  facet_wrap(~ load, ncol = 1) +
  scale_color_manual(values = c("FALSE" = "gray65", "TRUE" = "#1b9e77"),
                     labels = c("Removed", "Retained")) +
  labs(x = "DAC voltage [V]", y = "Output current [mA]", color = "Compliance status") +
  theme_minimal()

measured_vs_predicted_plot <- global_model_data |>
  ggplot(aes(predicted_mA, current_mA, color = load)) +
  geom_point(alpha = 0.7, size = 1.8) +
  geom_abline(intercept = 0, slope = 1, color = "black", linetype = "dashed") +
  labs(x = "Predicted current [mA]", y = "Measured current [mA]", color = "Load") +
  theme_minimal()

confidence_band_plot <- global_model_data |>
  arrange(dac_bin) |>
  ggplot(aes(dac_bin, current_mA, color = load)) +
  geom_ribbon(aes(x = dac_bin, ymin = mean_ci_low_mA, ymax = mean_ci_high_mA),
              inherit.aes = FALSE, fill = "#80b1d3", alpha = 0.28) +
  geom_line(aes(y = predicted_mA), color = "black", linewidth = 0.8) +
  geom_point(alpha = 0.55, size = 1.4) +
  labs(x = "DAC voltage [V]", y = "Current [mA]", color = "Load") +
  theme_minimal()

prediction_band_plot <- global_model_data |>
  arrange(dac_bin) |>
  ggplot(aes(dac_bin, current_mA, color = load)) +
  geom_ribbon(aes(x = dac_bin, ymin = prediction_low_mA, ymax = prediction_high_mA),
              inherit.aes = FALSE, fill = "#fdb462", alpha = 0.25) +
  geom_line(aes(y = predicted_mA), color = "black", linewidth = 0.8) +
  geom_point(alpha = 0.55, size = 1.4) +
  labs(x = "DAC voltage [V]", y = "Current [mA]", color = "Load") +
  theme_minimal()

residuals_vs_dac_plot <- global_model_data |>
  ggplot(aes(dac_bin, residual_mA, color = load)) +
  geom_point(alpha = 0.7, size = 1.7) +
  geom_hline(yintercept = 0, color = "black") +
  labs(x = "DAC voltage [V]", y = "Residual [mA]", color = "Load") +
  theme_minimal()

residuals_vs_predicted_plot <- global_model_data |>
  ggplot(aes(predicted_mA, residual_mA, color = load)) +
  geom_point(alpha = 0.7, size = 1.7) +
  geom_hline(yintercept = 0, color = "black") +
  labs(x = "Predicted current [mA]", y = "Residual [mA]", color = "Load") +
  theme_minimal()

acf_residual_plot <- acf_data |>
  filter(lag > 0) |>
  ggplot(aes(lag, acf)) +
  geom_col(fill = "#4daf4a", width = 0.03) +
  geom_hline(yintercept = 0, color = "black") +
  labs(x = "Lag", y = "ACF") +
  theme_minimal()

cook_distance_plot <- influence_points |>
  ggplot(aes(row_index, cook_distance)) +
  geom_col(fill = "#984ea3") +
  geom_hline(yintercept = influence_diagnostics_summary$cook_threshold,
             color = "red", linetype = "dashed") +
  labs(x = "Index", y = "Cook distance") +
  theme_minimal()

studentized_residual_plot <- influence_points |>
  ggplot(aes(row_index, studentized_residual)) +
  geom_point(alpha = 0.7, size = 1.7) +
  geom_hline(yintercept = c(-3, 3), color = "red", linetype = "dashed") +
  labs(x = "Index", y = "Studentized residual") +
  theme_minimal()

leverage_studentized_plot <- influence_points |>
  ggplot(aes(leverage, studentized_residual, color = flagged)) +
  geom_point(alpha = 0.75, size = 1.8) +
  geom_hline(yintercept = c(-3, 3), color = "red", linetype = "dashed") +
  labs(x = "Leverage", y = "Studentized residual", color = "Flagged") +
  theme_minimal()

block_cv_plot <- block_cv_folds |>
  pivot_longer(c(RMSE_mA, MAE_mA, max_abs_error_mA),
               names_to = "metric", values_to = "value_mA") |>
  ggplot(aes(fold, value_mA, color = metric)) +
  geom_line() +
  geom_point(size = 2) +
  scale_x_continuous(breaks = seq_len(n_block_folds)) +
  labs(x = "Temporal block fold", y = "Error [mA]", color = "Metric") +
  theme_minimal()

figure_paths <- list(
  raw_stationary_segments_plot = save_report_plot(raw_stationary_segments_plot, "01_raw_signals_before_stationary_removal.png", 4.2, 7.2),
  ramp_signals_plot = save_report_plot(ramp_signals_plot, "02_ramp_signals_after_stationary_removal.png", 4.2, 7.2),
  current_after_conversion_plot = save_report_plot(current_after_conversion_plot, "03_current_after_conversion.png", 7, 4),
  full_current_plot = save_report_plot(full_current_plot, "04_full_current_vs_dac.png"),
  binned_current_by_load_plot = save_report_plot(binned_current_by_load_plot, "04_binned_current_by_load.png", 7, 4),
  compliance_highlight_plot = save_report_plot(compliance_highlight_plot, "05_compliance_retained_removed.png", 8, 8),
  measured_vs_predicted_plot = save_report_plot(measured_vs_predicted_plot, "06_measured_vs_predicted.png"),
  confidence_band_plot = save_report_plot(confidence_band_plot, "07_current_vs_dac_confidence_band.png"),
  prediction_band_plot = save_report_plot(prediction_band_plot, "08_current_vs_dac_prediction_band.png"),
  residuals_vs_dac_plot = save_report_plot(residuals_vs_dac_plot, "09_residuals_vs_dac.png"),
  residuals_vs_predicted_plot = save_report_plot(residuals_vs_predicted_plot, "10_residuals_vs_predicted.png"),
  acf_residual_plot = save_report_plot(acf_residual_plot, "11_residual_acf.png"),
  cook_distance_plot = save_report_plot(cook_distance_plot, "12_cook_distance_by_index.png"),
  studentized_residual_plot = save_report_plot(studentized_residual_plot, "13_studentized_residuals_by_index.png"),
  leverage_studentized_plot = save_report_plot(leverage_studentized_plot, "14_leverage_vs_studentized_residuals.png"),
  block_cv_plot = save_report_plot(block_cv_plot, "15_block_cross_validation_errors.png")
)

# Tables ---------------------------------------------------------------------

summary_tables <- list(
  model_coefficients_ci = model_coefficients_ci_table,
  per_load_model_summary = per_load_model_summary,
  global_model_summary = global_model_summary,
  interaction_model_summary = interaction_model_summary,
  model_comparison_table = model_comparison_table,
  prediction_error_summary = prediction_error_summary,
  residual_diagnostics_summary = residual_diagnostics_summary,
  heteroscedasticity_test_summary = heteroscedasticity_test_summary,
  autocorrelation_test_summary = autocorrelation_test_summary,
  block_cv_summary = block_cv_summary,
  influence_diagnostics_summary = influence_diagnostics_summary,
  multiple_comparison_corrected = multiple_comparison_corrected,
  compliance_summary = compliance_summary,
  uncertainty_budget = uncertainty_budget_table,
  fes_metrics_not_evaluated = fes_metrics_not_evaluated_table,
  figure_paths = enframe(unlist(figure_paths), name = "figure", value = "path"),
  raw_1k_preview = raw_1k_preview,
  ramp_sample_summary = ramp_sample_summary,
  full_region_stats = full_region_stats,
  linear_region_stats = linear_region_stats,
  correlation_summary = correlation_summary,
  block_cv_folds = block_cv_folds,
  influence_points = influence_points,
  fes_temporal_metrics = fes_temporal_metrics,
  secondary_analysis_status = secondary_analysis_status,
  pca_variance_summary = pca_variance_summary
)

table_paths <- imap(summary_tables, \(table, name) {
  if (inherits(table, "data.frame")) {
    write_table_csv(table, name)
  } else {
    NA_character_
  }
})

correlation_interpretation_text <- correlation_summary |>
  summarise(text = first(interpretation)) |>
  pull(text)

model_comparison_interpretation_text <- model_comparison_table |>
  filter(!is.na(interpretation)) |>
  slice_head(n = 1) |>
  pull(interpretation)

if (length(model_comparison_interpretation_text) == 0) {
  model_comparison_interpretation_text <- "Interpretacao nao disponivel para comparacao de modelos."
}

normality_interpretation_text <- residual_diagnostics_summary |>
  summarise(text = first(normality_interpretation)) |>
  pull(text)

heteroscedasticity_interpretation_text <- heteroscedasticity_test_summary |>
  summarise(text = first(interpretation)) |>
  pull(text)

autocorrelation_interpretation_text <- autocorrelation_test_summary |>
  summarise(text = first(interpretation)) |>
  pull(text)

correlation_summary_table <- correlation_summary |>
  select(-interpretation)

model_comparison_table_display <- model_comparison_table |>
  select(-interpretation)

residual_diagnostics_summary_table <- residual_diagnostics_summary |>
  select(-normality_interpretation)

heteroscedasticity_test_table <- heteroscedasticity_test_summary |>
  select(-interpretation)

autocorrelation_test_table <- autocorrelation_test_summary |>
  select(-interpretation)

# Report ---------------------------------------------------------------------

report_sections <- c(
  "---",
  'title: "Relatório de Caracterização Experimental e Estatística do Estágio de Saída de um Estimulador Elétrico Funcional"',
  'author: "Tiago de Paula Silva"',
  paste0('date: "', format_pt_date(Sys.Date()), '"'),
  "lang: pt-BR",
  "toc: true",
  "numbersections: true",
  "geometry: margin=2cm",
  'mainfont: "Times New Roman"',
  "header-includes:",
  "  - \\setlength{\\LTleft}{0pt}",
  "  - \\setlength{\\LTright}{0pt}",
  "  - \\setlength{\\emergencystretch}{5em}",
  "  - \\AtBeginEnvironment{longtable}{\\setlength{\\tabcolsep}{3pt}\\scriptsize}",
  "  - \\usepackage{caption}",
  "  - \\usepackage{placeins}",
  "  - \\let\\oldunderscore\\_",
  "  - \\renewcommand{\\_}{\\oldunderscore\\discretionary{}{}{}}",
  "---",
  "",
  "# Problema",
  "",
  "O item de estudo é o estágio de saída de um estimulador elétrico funcional (FES) baseado em uma fonte de corrente Howland. Mais especificamente, trata-se do eletroestimulador STIMGRASP, desenvolvido por Renato Barelli em 2017 como parte de uma dissertação de mestrado.",
  "",
  "Na dissertação de Renato Barelli, a arquitetura é apresentada e a linearidade do estágio de saída é afirmada como característica esperada do circuito, mas não é feita uma caracterização experimental quantitativa dessa linearidade. Também não são avaliadas, de forma sistemática, a dependência da corrente em relação à carga conectada nem os limites de operação em tensão impostos pela arquitetura.",
  "",
  "Nesta arquitetura, o microcontrolador define uma tensão de controle no DAC, e essa tensão deve produzir uma corrente de saída previsível no paciente ou em uma carga equivalente.",
  "",
  "O problema central é que o circuito opera em malha aberta: o microcontrolador não mede a corrente real entregue durante a operação. Assim, se a carga mudar, se o contato eletrodo-pele piorar ou se o circuito atingir seu limite de tensão de operação (voltage compliance), a corrente entregue pode deixar de seguir o valor esperado. Como não há realimentação de corrente, essa perda de previsibilidade não é detectada diretamente pelo firmware do STIMGRASP.",
  "",
  "Por isso, é necessário caracterizar experimentalmente a relação entre tensão de DAC e corrente de saída, identificando a região em que o circuito se comporta aproximadamente como fonte de corrente, a influência da carga resistiva sobre a corrente entregue, um modelo matemático útil para estimar a corrente a partir do DAC e evidências estatísticas sobre linearidade, erro e limitação por compliance.",
  "",
  "# Motivação",
  "",
  "Em estimulação elétrica funcional, a amplitude de corrente está associada à resposta neuromuscular, ao conforto do usuário e à repetibilidade do protocolo de estimulação. Se a corrente real não for previsível, o mesmo comando digital pode gerar respostas diferentes em diferentes condições de carga.",
  "",
  "Este relatório é inspirado no artigo _Experimental Characterization of the Output Stage of a Functional Electrical Stimulator Based on a Howland Current Source_, produzido no contexto da disciplina PEL309 [1]. Naquele trabalho, com análise em Python, o STIMGRASP foi caracterizado experimentalmente por meio da relação entre tensão de DAC e corrente de saída, seleção da região de compliance, correlação e regressão linear.",
  "",
  "O presente relatório revisa e aprofunda essa caracterização em R, com uma análise estatística mais cuidadosa para a disciplina PME406. A versão atual prioriza a consistência estatística da caracterização: a região útil é definida antes da regressão, os modelos são avaliados por erro, resíduos, intervalos e validação cruzada, e análises multivariadas ou didáticas são tratadas como material secundário quando não sustentam diretamente a conclusão técnica.",
  "",
  "# Objetivo",
  "",
  "O objetivo do script é executar uma análise estatística da relação entre tensão de DAC e corrente de saída para três cargas resistivas nominais: 1 kOhm, 2 kOhm e 4,7 kOhm.",
  "",
  "Seguindo a motivação apresentada no trabalho anterior, a análise é organizada em três perguntas centrais:",
  "",
  "- existe linearidade quantificável entre o sinal de controle do DAC e a corrente de saída na região válida de operação?",
  "- quais são os limites de tensão de operação do estágio de saída antes da limitação por compliance?",
  "- a relação DAC-corrente permanece consistente quando a carga resistiva muda?",
  "",
  "Os objetivos específicos são:",
  "",
  "- importar os dados experimentais do osciloscópio;",
  "- extrair a região útil da rampa de DAC;",
  "- converter tensão no resistor shunt em corrente de saída;",
  "- agregar os dados por bins de tensão de DAC;",
  "- identificar a região comum de compliance;",
  "- avaliar linearidade por correlação e regressão;",
  "- comparar modelo global e modelo com interação carga x DAC;",
  "- quantificar erro de predição, resíduos, autocorrelação temporal e pontos influentes;",
  "- explicitar limitações de normalidade e independência dos resíduos.",
  "",
  "# Estrutura da análise",
  "",
  "O script em R lê os CSVs exportados do osciloscópio, remove trechos estacionários antes e depois da rampa útil, calcula corrente a partir da tensão no resistor shunt, reconstrói a tensão na carga por resistência nominal e agrega os dados por bins de DAC de 10 mV. O script e os dados brutos estão disponíveis no repositório indicado nas Referências.",
  "",
  "O fluxo de análise segue a sequência: aquisição CSV do osciloscópio, extração da rampa útil, conversão da tensão no shunt para corrente, agregação por bins de DAC, seleção da região de compliance, regressão linear, comparação entre modelos e análise dos resíduos.",
  "",
  "A partir desse conjunto processado, o relatório seleciona a região comum de compliance, ajusta modelos lineares, compara modelos aninhados por ANOVA/teste F, calcula métricas de erro, examina resíduos, avalia heterocedasticidade e autocorrelação temporal e identifica pontos influentes. Todas as tabelas são exportadas para a pasta `tables`, e as figuras são exportadas para a pasta `figures`.",
  "",
  "\\clearpage",
  "",
  "# Desenho experimental, coleta e limitações",
  "",
  "Foram analisadas rampas de tensão de DAC e tensão no resistor shunt para três cargas resistivas nominais: 1 kOhm, 2 kOhm e 4,7 kOhm. A análise estima corrente a partir do shunt e reconstrói a tensão na carga por resistência nominal. Como o sistema opera em malha aberta, a regressão caracteriza o comportamento observado no ensaio, mas não garante corrente entregue em operação real quando a carga, contato eletrodo-pele ou condições térmicas mudam.",
  "",
  "A coleta foi realizada com firmware experimental dedicado a gerar uma rampa controlada de DAC. A tensão de controle foi medida no canal CH1 do osciloscópio, enquanto a tensão associada à saída foi medida no canal CH2 sobre o arranjo de carga e resistor shunt. O objetivo dessa instrumentação foi caracterizar o estágio de saída, não representar uma sessão completa de estimulação terapêutica.",
  "",
  latex_side_by_side_figures(
    "figures/00_output_stage_measurement_points.png",
    "Estágio DAC/Howland do STIMGRASP com pontos de medição usados na coleta experimental",
    "figures/00_data_collection_setup.png",
    "Bancada experimental usada para aquisição dos sinais de DAC e shunt"
  ),
  "",
  "# Importação e pré-processamento",
  "",
  "Os CSVs foram importados diretamente dos arquivos do osciloscópio, removendo os segmentos estacionários antes e depois da rampa útil. As três cargas foram equalizadas para a mesma quantidade de amostras.",
  "",
  "Cada arquivo contém duas grandezas principais: `dac_volts`, que representa a tensão de controle aplicada ao estágio de saída, e `shunt_volts`, que representa a tensão medida no resistor shunt e é usada para calcular a corrente.",
  "",
  "Os dados brutos utilizados nesta etapa estão disponíveis no repositório indicado nas Referências.",
  "",
  "Antes de qualquer tratamento, apenas como um exemplo, a carga de 1 kOhm possui a seguinte prévia dos dados crus:",
  "",
  latex_side_by_side_tables(raw_1k_preview, ramp_sample_summary),
  "",
  latex_compact_side_by_side_figures(
    figure_paths$raw_stationary_segments_plot,
    "Sinais brutos antes da remoção dos segmentos estacionários",
    figure_paths$ramp_signals_plot,
    "Sinais da rampa após a remoção dos segmentos estacionários"
  ),
  "",
  "\\clearpage",
  "",
  "# Conversão shunt-corrente",
  "",
  paste0("A corrente foi calculada por I = Vshunt / Rshunt, com Rshunt = ",
         shunt_resistance_ohm, " Ohm. A tolerância configurada do shunt é ",
         shunt_resistance_tolerance * 100, "%."),
  "",
  latex_centered_figure(
    figure_paths$current_after_conversion_plot,
    "Corrente calculada após conversão da tensão no shunt",
    "0.78\\linewidth"
  ),
  "",
  "\\FloatBarrier",
  "",
  "\\clearpage",
  "",
  "# Redução de granularidade por binning",
  "",
  paste0(
    "Após a conversão da tensão do shunt em corrente, os pontos ainda estavam na granularidade temporal da aquisição do osciloscópio. ",
    "Como a variável de interesse para a regressão é a relação entre tensão de DAC e corrente de saída, os dados foram agrupados por `dac_bin`: ",
    "cada valor de `dac_volts` foi arredondado para o centro de um intervalo de ",
    format_number(dac_step, 2),
    " V, e as medições com o mesmo `dac_bin` e a mesma carga foram substituídas pela média de corrente, tensão do shunt, tensão de DAC e tensão reconstruída na carga."
  ),
  "",
  "Esse binning reduz a quantidade de pontos repetidos ou quase repetidos ao longo da rampa, diminui ruído local de aquisição e evita que regiões com muitas amostras temporais tenham peso desproporcional apenas por terem sido amostradas mais vezes. A análise passa, portanto, a representar a resposta média do estágio de saída para cada nível discretizado de DAC.",
  "",
  "A largura de 10 mV preserva a tendência da rampa em escala suficientemente fina para a caracterização, mas torna as etapas seguintes mais estáveis: identificação da região de compliance, cálculo de inclinações locais, correlação e regressões lineares.",
  "",
  latex_compact_table(binning_summary),
  "",
  latex_centered_figure(
    figure_paths$binned_current_by_load_plot,
    "Corrente média em função dos bins de DAC após a redução de granularidade",
    "0.78\\linewidth"
  ),
  "",
  "\\FloatBarrier",
  "",
  "\\clearpage",
  "",
  "# Identificação da região de compliance",
  "",
  "A região comum de compliance foi definida antes da regressão usando dois critérios: limite físico pela tensão reconstruída na carga e inclinação local mínima compatível com o trecho linear de cada carga. O limite comum de tensão foi tomado como a menor magnitude máxima de tensão reconstruída entre as cargas, definindo uma faixa simétrica comum em torno de zero; em seguida, foram mantidos apenas os pontos do maior trecho contínuo com inclinação local suficiente. O modelo linear deve ser interpretado apenas dentro dessa região comum.",
  "",
  latex_compact_table(compliance_summary_display),
  "",
  latex_centered_figure(
    figure_paths$compliance_highlight_plot,
    "Pontos retidos e removidos pelo critério de compliance",
    "0.72\\linewidth"
  ),
  "",
  "\\FloatBarrier",
  "",
  "# Estatística descritiva relevante",
  "",
  "Resumo da região linear retida:",
  "",
  markdown_table(linear_region_stats),
  "",
  "# Correlação exploratória",
  "",
  "Correlação foi mantida apenas como evidência exploratória de associação monotônica/linear entre DAC e corrente. A validade do circuito é discutida a partir de erro, resíduos, intervalos e limites de compliance.",
  "",
  correlation_interpretation_text,
  "",
  markdown_table(correlation_summary_table),
  "",
  "# Modelos lineares por carga",
  "",
  "Modelos independentes por carga foram ajustados como current_mA ~ dac_bin.",
  "",
  markdown_table(per_load_model_summary),
  "",
  "# Modelo global",
  "",
  "O modelo global foi ajustado como `current_mA ~ dac_bin` dentro da região comum de compliance.",
  "",
  "Para obter esse modelo, não foi ajustada uma regressão separada para cada carga. Após o binning e a seleção da região comum de compliance, os dados das três cargas foram mantidos em formato longo em `linear_long`: cada linha contém um par (`dac_bin`, `current_mA`) e o rótulo da carga correspondente (`1k`, `2k` ou `4k7`). Em seguida, todas essas linhas foram usadas juntas em uma única regressão linear.",
  "",
  "Na prática, isso equivale a empilhar os pontos válidos das três cargas em um único conjunto de observações. A variável `load` permanece disponível para identificação, gráficos e diagnósticos, mas não participa da equação do modelo global. Assim, o ajuste estima uma única inclinação e um único intercepto para representar a relação média entre bin de DAC e corrente de saída, independentemente da carga, desde que os pontos estejam dentro da região comum de compliance.",
  "",
  "Esse procedimento é coerente com o objetivo de obter uma equação operacional única para estimativa em malha aberta. Se as curvas das cargas permanecem próximas após a remoção dos pontos limitados por compliance, um único modelo global pode representar o comportamento do estágio de saída sem exigir coeficientes específicos por carga. A comparação posterior com o modelo com interação carga x DAC verifica justamente se adicionar dependência explícita da carga melhora de forma relevante essa representação.",
  "",
  markdown_table(global_model_summary),
  "",
  "# Modelo com interação carga x DAC",
  "",
  "O modelo com interação foi ajustado como current_mA ~ dac_bin * load.",
  "",
  markdown_table(interaction_model_summary),
  "",
  "Nas tabelas de coeficientes, H0 representa a hipótese nula de que o coeficiente avaliado é igual a zero. Com `alpha = 0,05`, a decisão `rejeita_H0` significa que o p-valor ficou abaixo de 0,05 e há evidência estatística de que aquele termo contribui para o modelo. A decisão `nao_rejeita_H0` significa que o teste não encontrou evidência suficiente, nesse nível de significância, para afirmar que o coeficiente seja diferente de zero. Isso não prova que o coeficiente seja exatamente zero; apenas indica ausência de evidência estatística suficiente contra H0.",
  "",
  markdown_table(model_coefficients_ci_table, max_rows = 30),
  "",
  "# Comparação entre modelos",
  "",
  "A comparação formal entre o modelo global e o modelo com interação foi feita por ANOVA/teste F para modelos aninhados.",
  "",
  markdown_table(model_comparison_table_display),
  "",
  model_comparison_interpretation_text,
  "",
  "# Erro de predição",
  "",
  "As métricas de erro foram calculadas dentro da região linear: MAE, RMSE e maior erro absoluto.",
  "",
  markdown_table(prediction_error_summary),
  "",
  markdown_figure(figure_paths$measured_vs_predicted_plot, "Corrente medida versus corrente predita"),
  "",
  markdown_figure(figure_paths$confidence_band_plot, "Banda de confiança da corrente em função do DAC"),
  "",
  markdown_figure(figure_paths$prediction_band_plot, "Banda de predição da corrente em função do DAC"),
  "",
  "# Diagnóstico dos resíduos",
  "",
  markdown_table(residual_diagnostics_summary_table),
  "",
  normality_interpretation_text,
  "",
  markdown_figure(figure_paths$residuals_vs_dac_plot, "Resíduos em função do DAC"),
  "",
  markdown_figure(figure_paths$residuals_vs_predicted_plot, "Resíduos em função dos valores preditos"),
  "",
  "# Homocedasticidade",
  "",
  markdown_table(heteroscedasticity_test_table),
  "",
  heteroscedasticity_interpretation_text,
  "",
  "# Autocorrelação temporal",
  "",
  "Como os dados vêm de uma rampa temporal, a independência dos resíduos não foi assumida automaticamente.",
  "",
  markdown_table(autocorrelation_test_table),
  "",
  autocorrelation_interpretation_text,
  "",
  markdown_figure(figure_paths$acf_residual_plot, "Autocorrelação dos resíduos"),
  "",
  "# Outliers e influência",
  "",
  "Foram calculados resíduos studentizados, leverage e distância de Cook. Pontos foram apenas marcados e reportados; a remoção automática permanece desativada por padrão.",
  "",
  markdown_table(influence_diagnostics_summary),
  "",
  markdown_figure(figure_paths$cook_distance_plot, "Distância de Cook por índice"),
  "",
  markdown_figure(figure_paths$studentized_residual_plot, "Resíduos studentizados por índice"),
  "",
  markdown_figure(figure_paths$leverage_studentized_plot, "Leverage versus resíduos studentizados"),
  "",
  "# Validação cruzada por blocos",
  "",
  "A validação por blocos usa cinco blocos contíguos ordenados, treinando em quatro blocos e testando no bloco remanescente. Isso evita usar apenas uma validação aleatória que mistura pontos vizinhos da rampa.",
  "",
  markdown_table(block_cv_folds),
  "",
  markdown_table(block_cv_summary),
  "",
  markdown_figure(figure_paths$block_cv_plot, "Erros da validação cruzada por blocos"),
  "",
  "# Conclusões revisadas",
  "",
  "A caracterização sustenta três conclusões principais. Primeiro, há linearidade quantificável entre tensão de DAC e corrente de saída dentro da região comum de compliance, com correlações próximas de -1 e erros de predição baixos. Segundo, o STIMGRASP possui limites claros de operação em tensão: essa limitação não é necessariamente uma falha, mas reduz a faixa de corrente útil à medida que a carga aumenta. Terceiro, como a arquitetura é open-loop, o firmware não detecta em tempo real quando o estágio entra em saturação e a corrente entregue passa a ser menor do que a prevista pelo modelo.",
  "",
  "O modelo global é útil como aproximação operacional, mas sua adequação deve ser julgada junto com os erros de predição, intervalos de confiança/predição, diagnóstico residual e autocorrelação temporal. A principal melhoria arquitetural sugerida pela caracterização é a inclusão de realimentação de corrente, monitoramento de compliance ou outra forma de operação em malha fechada.",
  "",
  "Análises como PCA, cluster e testes de média global foram preservadas somente como material secundário/didático e não são usadas como evidência central de validade metrológica do estágio de saída.",
  "",
  "# Referências {-}",
  "",
  "[1] Tiago de Paula Silva, \"Experimental Characterization of the Output Stage of a Functional Electrical Stimulator Based on a Howland Current Source,\" artigo produzido no contexto da disciplina PEL309, Centro Universitário FEI, 2026.",
  "",
  "[2] Tiago de Paula Silva, \"FEI - PME406: dados brutos e script R da análise estatística,\" repositório GitHub. Disponível em: \\url{https://github.com/import-tiago/FEI/tree/main/MSc/PME406}.",
  ""
)

render_report_tex(report_sections, report_temp_md_path, report_tex_path)

message("Analysis completed.")
message("Figures saved in: ", normalizePath(figures_dir, winslash = "/"))
message("Tables saved in: ", normalizePath(tables_dir, winslash = "/"))
message("Report saved as: ", normalizePath(report_tex_path, winslash = "/"))

invisible(summary_tables)
