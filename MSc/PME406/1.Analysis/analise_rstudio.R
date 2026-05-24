if (!requireNamespace("tidyverse", quietly = TRUE)) {
  stop("Package 'tidyverse' is required. Install it before running this script.")
}

library(tidyverse)

options(digits = 15)

# User-configurable analysis constants ---------------------------------------

figures_dir <- "figures"
tables_dir <- "tables"

remove_influential_points <- FALSE
alpha <- 0.05
confidence_level <- 1 - alpha
n_block_folds <- 5
dac_step <- 0.01
compliance_slope_fraction <- 0.5
compliance_reference_fraction <- 0.5

shunt_resistance_ohm <- 10

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

# Descriptive and exploratory analyses --------------------------------------

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
interaction_model_data <- add_prediction_intervals(interaction_model, linear_long)

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
        "O modelo com influencia da carga melhora significativamente o ajuste em relacao ao modelo global.",
        "Nao ha evidencia estatistica de melhora do modelo com influencia da carga em relacao ao modelo global."
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

# Validation and comparisons -------------------------------------------------

block_cv <- block_cross_validation(
  linear_long,
  current_mA ~ dac_bin,
  folds = n_block_folds
)

block_cv_folds <- block_cv$folds
block_cv_summary <- block_cv$summary

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

global_model_plot <- global_model_data |>
  arrange(dac_bin) |>
  ggplot(aes(dac_bin, current_mA, color = load)) +
  geom_point(alpha = 0.55, size = 1.4) +
  geom_line(
    data = global_model_data |>
      distinct(dac_bin, predicted_mA) |>
      arrange(dac_bin),
    aes(dac_bin, predicted_mA),
    inherit.aes = FALSE,
    color = "black",
    linewidth = 0.9
  ) +
  labs(x = "DAC voltage [V]", y = "Current [mA]", color = "Load") +
  theme_minimal()

measured_vs_predicted_plot <- global_model_data |>
  ggplot(aes(predicted_mA, current_mA, color = load)) +
  geom_point(alpha = 0.7, size = 1.8) +
  geom_abline(intercept = 0, slope = 1, color = "black", linetype = "dashed") +
  labs(x = "Predicted current [mA]", y = "Measured current [mA]", color = "Load") +
  theme_minimal()

interaction_model_plot <- interaction_model_data |>
  arrange(load, dac_bin) |>
  ggplot(aes(dac_bin, current_mA, color = load)) +
  geom_point(alpha = 0.45, size = 1.4) +
  geom_line(
    data = interaction_model_data |>
      distinct(load, dac_bin, predicted_mA) |>
      arrange(load, dac_bin),
    aes(y = predicted_mA),
    linewidth = 1
  ) +
  geom_line(
    data = global_model_data |>
      distinct(dac_bin, predicted_mA) |>
      arrange(dac_bin),
    aes(dac_bin, predicted_mA),
    inherit.aes = FALSE,
    color = "black",
    linetype = "dashed",
    linewidth = 0.8
  ) +
  labs(x = "DAC voltage [V]", y = "Current [mA]", color = "Load") +
  theme_minimal()

residuals_vs_dac_plot <- global_model_data |>
  ggplot(aes(dac_bin, residual_mA, color = load)) +
  geom_point(alpha = 0.7, size = 1.7) +
  geom_hline(yintercept = 0, color = "black") +
  labs(x = "DAC voltage [V]", y = "Residual [mA]", color = "Load") +
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
  binned_current_by_load_plot = save_report_plot(binned_current_by_load_plot, "04_binned_current_by_load.png", 7, 4),
  compliance_highlight_plot = save_report_plot(compliance_highlight_plot, "05_compliance_retained_removed.png", 8, 8),
  global_model_plot = save_report_plot(global_model_plot, "06_linear_region_global_model.png"),
  measured_vs_predicted_plot = save_report_plot(measured_vs_predicted_plot, "06_measured_vs_predicted.png"),
  interaction_model_plot = save_report_plot(interaction_model_plot, "07_interaction_model_by_load.png"),
  residuals_vs_dac_plot = save_report_plot(residuals_vs_dac_plot, "09_residuals_vs_dac.png"),
  block_cv_plot = save_report_plot(block_cv_plot, "15_block_cross_validation_errors.png")
)

# Tables ---------------------------------------------------------------------

summary_tables <- list(
  raw_1k_preview = raw_1k_preview,
  ramp_sample_summary = ramp_sample_summary,
  binning_summary = binning_summary,
  compliance_summary = compliance_summary,
  linear_region_stats = linear_region_stats,
  correlation_summary = correlation_summary,
  model_coefficients_ci = model_coefficients_ci_table,
  per_load_model_summary = per_load_model_summary,
  global_model_summary = global_model_summary,
  interaction_model_summary = interaction_model_summary,
  model_comparison_table = model_comparison_table,
  prediction_error_summary = prediction_error_summary,
  residual_diagnostics_summary = residual_diagnostics_summary,
  heteroscedasticity_test_summary = heteroscedasticity_test_summary,
  block_cv_folds = block_cv_folds,
  block_cv_summary = block_cv_summary,
  figure_paths = enframe(unlist(figure_paths), name = "figure", value = "path")
)

iwalk(summary_tables, \(table, name) {
  if (inherits(table, "data.frame")) {
    write_table_csv(table, name)
  }
})

message("Analysis completed.")
message("Figures saved in: ", normalizePath(figures_dir, winslash = "/"))
message("Tables saved in: ", normalizePath(tables_dir, winslash = "/"))
message("The LaTeX report is maintained manually and is not overwritten by this script.")

invisible(summary_tables)
