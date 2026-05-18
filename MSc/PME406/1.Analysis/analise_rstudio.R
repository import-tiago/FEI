if (!requireNamespace("tidyverse", quietly = TRUE)) {
  install.packages("tidyverse")
}

library(tidyverse)

options(digits = 15)

figures_dir <- "figures"
dir.create(figures_dir, showWarnings = FALSE)

save_report_plot <- function(plot, filename, width = 8, height = 5) {
  path <- file.path(figures_dir, filename)
  ggsave(path, plot = plot, width = width, height = height, dpi = 300)
  path
}

url_1k <- "https://raw.githubusercontent.com/import-tiago/FEI/refs/heads/main/MSc/PEL309/0.Data/1k.csv"
url_2k <- "https://raw.githubusercontent.com/import-tiago/FEI/refs/heads/main/MSc/PEL309/0.Data/2k.csv"
url_4k7 <- "https://raw.githubusercontent.com/import-tiago/FEI/refs/heads/main/MSc/PEL309/0.Data/4k7.csv"

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
  data <- df

  if (!column %in% names(data)) {
    stop("Column '", column, "' was not found in the data.")
  }

  delta <- abs(data[[column]] - dplyr::lag(data[[column]]))
  transition_points <- which(delta > trigger_threshold)

  if (length(transition_points) < 2) {
    stop("Could not detect ramp start and end transitions.")
  }

  start <- transition_points[1] + discarded_points
  end <- transition_points[length(transition_points)] - discarded_points

  data[start:end, ]
}

equalize_sample_count <- function(...) {
  dfs <- list(...)
  sample_count <- min(map_int(dfs, nrow))

  map(dfs, \(df) {
    df |>
      slice_head(n = sample_count) |>
      mutate(sample = row_number() - 1)
  })
}

summary_stats <- function(df) {
  df |>
    pivot_longer(everything(), names_to = "load", values_to = "current_mA") |>
    group_by(load) |>
    summarise(
      count = sum(!is.na(current_mA)),
      mean = mean(current_mA, na.rm = TRUE),
      std = sd(current_mA, na.rm = TRUE),
      min = min(current_mA, na.rm = TRUE),
      q25 = quantile(current_mA, 0.25, na.rm = TRUE),
      q50 = median(current_mA, na.rm = TRUE),
      q75 = quantile(current_mA, 0.75, na.rm = TRUE),
      max = max(current_mA, na.rm = TRUE),
      .groups = "drop"
    )
}

regression_metrics <- function(df) {
  fit <- lm(current_mA ~ dac_bin, data = df)
  pred <- predict(fit, df)
  residual <- df$current_mA - pred
  fit_summary <- summary(fit)

  tibble(
    slope_mA_per_V = coef(fit)[["dac_bin"]],
    intercept_mA = coef(fit)[["(Intercept)"]],
    r_value = cor(df$dac_bin, df$current_mA),
    r_squared = fit_summary$r.squared,
    p_value = coef(fit_summary)["dac_bin", "Pr(>|t|)"],
    slope_std_error = coef(fit_summary)["dac_bin", "Std. Error"],
    MAE_mA = mean(abs(residual)),
    RMSE_mA = sqrt(mean(residual^2)),
    max_abs_error_mA = max(abs(residual)),
    samples = nrow(df)
  )
}

model_coefficients_table <- function(model) {
  coefficients <- as.data.frame(summary(model)$coefficients)
  coefficients$term <- rownames(coefficients)
  rownames(coefficients) <- NULL
  coefficients |>
    as_tibble() |>
    select(term, everything())
}

anova_table <- function(model) {
  table <- as.data.frame(anova(model))
  table$term <- rownames(table)
  rownames(table) <- NULL
  table |>
    as_tibble() |>
    select(term, everything())
}

hypothesis_decision <- function(p_value, alpha = 0.05) {
  if_else(p_value < alpha, "reject_H0", "do_not_reject_H0")
}

data_1k_load <- read_scope_csv(url_1k)
data_2k_load <- read_scope_csv(url_2k)
data_4k7_load <- read_scope_csv(url_4k7)

raw_data_1k_load <- data_1k_load
raw_data_2k_load <- data_2k_load
raw_data_4k7_load <- data_4k7_load

raw_1k_preview <- data_1k_load |>
  slice_head(n = 12)

ramp_detection_column <- "dac_volts"

list(data_1k_load, data_2k_load, data_4k7_load) |>
  map_int(nrow) |>
  set_names(c("1k", "2k", "4k7"))

ggplot(data_1k_load, aes(sample)) +
  geom_line(aes(y = dac_volts, color = "DAC Voltage")) +
  geom_line(aes(y = shunt_volts, color = "Shunt Voltage")) +
  coord_cartesian(ylim = c(-0.5, 3.5)) +
  labs(x = "Sample", y = "Voltage [V]", color = NULL) +
  theme_minimal()

aligned <- equalize_sample_count(
  extract_ramp_region(data_1k_load, column = ramp_detection_column),
  extract_ramp_region(data_2k_load, column = ramp_detection_column),
  extract_ramp_region(data_4k7_load, column = ramp_detection_column)
)

data_1k_load <- aligned[[1]]
data_2k_load <- aligned[[2]]
data_4k7_load <- aligned[[3]]

ramp_data_1k_load <- data_1k_load
ramp_data_2k_load <- data_2k_load
ramp_data_4k7_load <- data_4k7_load

ramp_sample_summary <- tibble(
  load = c("1k", "2k", "4k7"),
  samples = c(nrow(data_1k_load), nrow(data_2k_load), nrow(data_4k7_load))
)

ramp_sample_summary

shunt_resistance_ohm <- 10

data_1k_load <- data_1k_load |> mutate(current_mA = shunt_volts / shunt_resistance_ohm * 1000)
data_2k_load <- data_2k_load |> mutate(current_mA = shunt_volts / shunt_resistance_ohm * 1000)
data_4k7_load <- data_4k7_load |> mutate(current_mA = shunt_volts / shunt_resistance_ohm * 1000)

current_time_data <- bind_rows(
  data_1k_load |> select(sample, current_mA) |> mutate(load = "1 kOhm"),
  data_2k_load |> select(sample, current_mA) |> mutate(load = "2 kOhm"),
  data_4k7_load |> select(sample, current_mA) |> mutate(load = "4.7 kOhm")
)

all_currents <- bind_rows(
  data_1k_load |> select(dac_volts, current_mA) |> mutate(load = "1k"),
  data_2k_load |> select(dac_volts, current_mA) |> mutate(load = "2k"),
  data_4k7_load |> select(dac_volts, current_mA) |> mutate(load = "4k7")
)

dac_step <- 0.01

processed_current_data <- all_currents |>
  mutate(dac_bin = round(round(dac_volts / dac_step) * dac_step, 2)) |>
  group_by(dac_bin, load) |>
  summarise(current_mA = mean(current_mA, na.rm = TRUE), .groups = "drop") |>
  pivot_wider(names_from = load, values_from = current_mA) |>
  arrange(dac_bin) |>
  select(dac_bin, `1k`, `2k`, `4k7`)

processed_current_data |>
  pivot_longer(-dac_bin, names_to = "load", values_to = "current_mA") |>
  ggplot(aes(dac_bin, current_mA, color = load)) +
  geom_line() +
  scale_x_continuous(limits = c(0, 3.4), breaks = seq(0, 3.2, 0.2)) +
  scale_y_continuous(limits = c(-50, 50), breaks = seq(-50, 50, 10)) +
  labs(x = "DAC voltage [V]", y = "Output current [mA]", color = "Load") +
  theme_minimal()

full_region_stats <- processed_current_data |>
  select(-dac_bin) |>
  summary_stats()

load_resistance_ohm <- c("1k" = 1000, "2k" = 2000, "4k7" = 4700)

v_limits_summary <- map_dfr(names(load_resistance_ohm), \(load) {
  resistance <- load_resistance_ohm[[load]]
  current <- processed_current_data[[load]]

  tibble(
    load = load,
    load_resistance_ohm = resistance,
    i_min_mA = min(current, na.rm = TRUE),
    i_max_mA = max(current, na.rm = TRUE),
    v_min = i_min_mA / 1000 * resistance,
    v_max = i_max_mA / 1000 * resistance
  )
}) |>
  mutate(
    common_v_min_limit = max(v_min),
    common_v_max_limit = min(v_max)
  )

v_min_limit <- max(v_limits_summary$v_min)
v_max_limit <- min(v_limits_summary$v_max)

linear_current_data <- processed_current_data

for (load in names(load_resistance_ohm)) {
  resistance <- load_resistance_ohm[[load]]
  vload <- processed_current_data[[load]] / 1000 * resistance
  linear_current_data[[load]] <- if_else(
    vload > v_min_limit & vload < v_max_limit,
    processed_current_data[[load]],
    NA_real_
  )
}

linear_region_summary <- tibble(
  load = names(load_resistance_ohm),
  processed_points = map_int(names(load_resistance_ohm), \(load) sum(!is.na(processed_current_data[[load]]))),
  linear_points = map_int(names(load_resistance_ohm), \(load) sum(!is.na(linear_current_data[[load]])))
) |>
  mutate(
    removed_points = processed_points - linear_points,
    removed_percent = 100 * removed_points / processed_points
  )

linear_region_stats <- linear_current_data |>
  select(-dac_bin) |>
  summary_stats()

linear_long <- linear_current_data |>
  pivot_longer(-dac_bin, names_to = "load", values_to = "current_mA") |>
  drop_na()

correlation_summary <- linear_long |>
  group_by(load) |>
  summarise(
    pearson_r = cor(dac_bin, current_mA, method = "pearson"),
    pearson_p = cor.test(dac_bin, current_mA, method = "pearson")$p.value,
    spearman_r = cor(dac_bin, current_mA, method = "spearman"),
    spearman_p = cor.test(dac_bin, current_mA, method = "spearman", exact = FALSE)$p.value,
    samples = n(),
    .groups = "drop"
  ) |>
  mutate(dataset = "linear_region", .before = 1)

regression_by_load_summary <- linear_long |>
  group_by(load) |>
  group_modify(\(.x, .y) regression_metrics(.x)) |>
  ungroup()

global_model <- lm(current_mA ~ dac_bin, data = linear_long)
global_pred <- predict(global_model, linear_long)
global_residual <- linear_long$current_mA - global_pred

global_model_summary <- tibble(
  model = "global_linear_model_all_loads",
  slope_mA_per_V = coef(global_model)[["dac_bin"]],
  intercept_mA = coef(global_model)[["(Intercept)"]],
  MAE_mA = mean(abs(global_residual)),
  RMSE_mA = sqrt(mean(global_residual^2)),
  R2 = summary(global_model)$r.squared,
  max_abs_error_mA = max(abs(global_residual)),
  samples = nrow(linear_long)
)

a_global <- global_model_summary$slope_mA_per_V
b_global <- global_model_summary$intercept_mA

model_curve <- tibble(
  dac_bin = linear_current_data$dac_bin,
  global_model = a_global * dac_bin + b_global
)

linear_current_data |>
  pivot_longer(-dac_bin, names_to = "load", values_to = "current_mA") |>
  ggplot(aes(dac_bin, current_mA, color = load)) +
  geom_line() +
  geom_line(data = model_curve, aes(dac_bin, global_model),
            inherit.aes = FALSE, linetype = "dashed", color = "black") +
  labs(x = "DAC voltage [V]", y = "Output current [mA]", color = "Load") +
  theme_minimal()

current_spread_data <- linear_current_data |>
  mutate(
    spread_1k_2k_mA = abs(`1k` - `2k`),
    spread_1k_4k7_mA = abs(`1k` - `4k7`),
    spread_2k_4k7_mA = abs(`2k` - `4k7`)
  )

consistency_summary <- current_spread_data |>
  select(starts_with("spread_")) |>
  summary_stats()

global_model_data <- linear_long |>
  mutate(
    current_pred_mA = predict(global_model, linear_long),
    residual_mA = current_mA - current_pred_mA
  )

residual_summary <- tibble(
  mean = mean(global_model_data$residual_mA),
  std = sd(global_model_data$residual_mA),
  min = min(global_model_data$residual_mA),
  max = max(global_model_data$residual_mA),
  MAE = mean(abs(global_model_data$residual_mA)),
  RMSE = sqrt(mean(global_model_data$residual_mA^2))
)

ggplot(global_model_data, aes(dac_bin, residual_mA)) +
  geom_point(alpha = 0.6) +
  geom_hline(yintercept = 0, color = "black") +
  labs(x = "DAC voltage [V]", y = "Residual [mA]") +
  theme_minimal()

set.seed(42)
n_folds <- 5
fold_id <- sample(rep(seq_len(n_folds), length.out = nrow(global_model_data)))

cross_validation_folds <- map_dfr(seq_len(n_folds), \(fold) {
  train <- global_model_data[fold_id != fold, ]
  test <- global_model_data[fold_id == fold, ]
  fit <- lm(current_mA ~ dac_bin, data = train)
  pred <- predict(fit, test)
  residual <- test$current_mA - pred

  tibble(
    fold = fold,
    RMSE_mA = sqrt(mean(residual^2)),
    R2 = 1 - sum(residual^2) / sum((test$current_mA - mean(test$current_mA))^2)
  )
})

cross_validation_summary <- cross_validation_folds |>
  summarise(
    RMSE_mean_mA = mean(RMSE_mA),
    RMSE_std_mA = sd(RMSE_mA),
    R2_mean = mean(R2),
    R2_std = sd(R2)
  )

logo_summary <- map_dfr(unique(global_model_data$load), \(test_load) {
  train <- global_model_data |> filter(load != test_load)
  test <- global_model_data |> filter(load == test_load)
  fit <- lm(current_mA ~ dac_bin, data = train)
  pred <- predict(fit, test)
  residual <- test$current_mA - pred

  tibble(
    test_load = test_load,
    RMSE_mA = sqrt(mean(residual^2)),
    R2 = 1 - sum(residual^2) / sum((test$current_mA - mean(test$current_mA))^2),
    samples = nrow(test)
  )
})

alpha <- 0.05
confidence_level <- 1 - alpha

course_topic_coverage <- tibble(
  course_topic = c(
    "Curva normal, normal reduzida Z e distribuicao amostral",
    "Grau de confianca, significancia e decisao por p-valor",
    "Intervalos de confianca e testes de uma media",
    "Testes de duas medias",
    "Correlacao de Pearson e Spearman",
    "Regressao linear simples",
    "ANOVA e distribuicao F",
    "DOE fatorial",
    "Regressao linear multipla",
    "Regressao logistica",
    "PCA, analise fatorial e cluster"
  ),
  script_object = c(
    "normal_curve_data, residual_standard_normal_summary, sampling_distribution_summary",
    "statistical_decision_summary",
    "mean_current_ci, residual_zero_test_summary",
    "paired_load_tests",
    "correlation_summary",
    "regression_by_load_summary, global_model_summary",
    "one_way_anova_summary, tukey_load_summary",
    "factorial_doe_anova_summary",
    "multiple_model_summary, multiple_model_coefficients",
    "compliance_logistic_summary, compliance_prediction_summary",
    "pca_variance_summary, factor_analysis_summary, cluster_summary"
  )
)

z_reference_table <- tibble(
  confidence_level = c(0.90, 0.95, 0.99),
  alpha = 1 - confidence_level,
  z_two_sided_critical = qnorm(1 - alpha / 2),
  normal_area_between_minus_z_and_z = pnorm(z_two_sided_critical) -
    pnorm(-z_two_sided_critical)
)

residual_mean <- mean(global_model_data$residual_mA)
residual_sd <- sd(global_model_data$residual_mA)

normal_curve_data <- tibble(
  residual_mA = seq(
    residual_mean - 4 * residual_sd,
    residual_mean + 4 * residual_sd,
    length.out = 400
  ),
  normal_density = dnorm(residual_mA, mean = residual_mean, sd = residual_sd),
  standard_z = (residual_mA - residual_mean) / residual_sd
)

ggplot(global_model_data, aes(residual_mA)) +
  geom_histogram(aes(y = after_stat(density)), bins = 30,
                 fill = "gray85", color = "white") +
  geom_line(data = normal_curve_data, aes(residual_mA, normal_density),
            color = "red", linewidth = 1) +
  labs(x = "Residual [mA]", y = "Density") +
  theme_minimal()

residual_standard_normal_summary <- global_model_data |>
  mutate(z_residual = (residual_mA - residual_mean) / residual_sd) |>
  summarise(
    mean_z = mean(z_residual),
    sd_z = sd(z_residual),
    proportion_between_1sd = mean(abs(z_residual) <= 1),
    expected_between_1sd_normal = pnorm(1) - pnorm(-1),
    proportion_between_2sd = mean(abs(z_residual) <= 2),
    expected_between_2sd_normal = pnorm(2) - pnorm(-2),
    proportion_between_3sd = mean(abs(z_residual) <= 3),
    expected_between_3sd_normal = pnorm(3) - pnorm(-3),
    samples = n()
  )

sampling_distribution_summary <- linear_long |>
  group_by(load) |>
  summarise(
    sample_mean_mA = mean(current_mA),
    sample_sd_mA = sd(current_mA),
    samples = n(),
    standard_error_mA = sample_sd_mA / sqrt(samples),
    t_critical_95 = qt(1 - alpha / 2, df = samples - 1),
    margin_of_error_95_mA = t_critical_95 * standard_error_mA,
    ci_low_mA = sample_mean_mA - margin_of_error_95_mA,
    ci_high_mA = sample_mean_mA + margin_of_error_95_mA,
    .groups = "drop"
  )

mean_current_ci <- linear_long |>
  group_by(load) |>
  summarise(
    null_hypothesis = "H0: mean current equals 0 mA",
    alternative_hypothesis = "H1: mean current differs from 0 mA",
    alpha = alpha,
    confidence_level = confidence_level,
    mean_current_mA = mean(current_mA),
    ci_low_mA = t.test(current_mA, mu = 0, conf.level = confidence_level)$conf.int[1],
    ci_high_mA = t.test(current_mA, mu = 0, conf.level = confidence_level)$conf.int[2],
    p_value = t.test(current_mA, mu = 0, conf.level = confidence_level)$p.value,
    decision = hypothesis_decision(p_value, alpha),
    samples = n(),
    .groups = "drop"
  )

residual_zero_test <- t.test(
  global_model_data$residual_mA,
  mu = 0,
  conf.level = confidence_level
)

residual_zero_test_summary <- tibble(
  test = "one_sample_t_test_global_residual_mean_equals_zero",
  null_hypothesis = "H0: mean residual equals 0 mA",
  alternative_hypothesis = "H1: mean residual differs from 0 mA",
  alpha = alpha,
  confidence_level = confidence_level,
  mean_residual_mA = mean(global_model_data$residual_mA),
  t_statistic = unname(residual_zero_test$statistic),
  degrees_freedom = unname(residual_zero_test$parameter),
  p_value = residual_zero_test$p.value,
  decision = hypothesis_decision(p_value, alpha),
  ci_low_mA = residual_zero_test$conf.int[1],
  ci_high_mA = residual_zero_test$conf.int[2]
)

linear_wide_complete <- linear_current_data |>
  drop_na()

paired_load_tests <- combn(names(load_resistance_ohm), 2, simplify = FALSE) |>
  map_dfr(\(pair) {
    test <- t.test(
      linear_wide_complete[[pair[1]]],
      linear_wide_complete[[pair[2]]],
      paired = TRUE,
      conf.level = confidence_level
    )

    tibble(
      comparison = paste(pair, collapse = "_vs_"),
      null_hypothesis = "H0: paired mean difference equals 0 mA",
      alternative_hypothesis = "H1: paired mean difference differs from 0 mA",
      alpha = alpha,
      confidence_level = confidence_level,
      mean_difference_mA = mean(linear_wide_complete[[pair[1]]] -
                                  linear_wide_complete[[pair[2]]]),
      t_statistic = unname(test$statistic),
      degrees_freedom = unname(test$parameter),
      p_value = test$p.value,
      decision = hypothesis_decision(p_value, alpha),
      ci_low_mA = test$conf.int[1],
      ci_high_mA = test$conf.int[2]
    )
  })

shapiro_sample <- global_model_data |>
  slice_sample(n = min(5000, nrow(global_model_data)))

residual_normality_summary <- shapiro.test(shapiro_sample$residual_mA)

residual_normality_table <- tibble(
  test = "shapiro_wilk_test_on_sampled_global_residuals",
  null_hypothesis = "H0: residuals follow a normal distribution",
  alternative_hypothesis = "H1: residuals do not follow a normal distribution",
  alpha = alpha,
  statistic = unname(residual_normality_summary$statistic),
  p_value = residual_normality_summary$p.value,
  decision = hypothesis_decision(p_value, alpha),
  samples = nrow(shapiro_sample)
)

qqnorm(global_model_data$residual_mA)
qqline(global_model_data$residual_mA, col = "red")

one_way_anova_model <- aov(current_mA ~ load, data = linear_long)
one_way_anova_summary <- anova_table(one_way_anova_model) |>
  mutate(
    alpha = alpha,
    decision = if_else(
      term != "Residuals",
      hypothesis_decision(`Pr(>F)`, alpha),
      NA_character_
    )
  )

tukey_load_summary <- as.data.frame(TukeyHSD(one_way_anova_model)$load) |>
  rownames_to_column("comparison") |>
  as_tibble() |>
  mutate(
    alpha = alpha,
    confidence_level = confidence_level,
    decision = hypothesis_decision(`p adj`, alpha)
  )

doe_data <- linear_long |>
  mutate(
    dac_level = factor(ntile(dac_bin, 4), labels = c("low", "mid_low", "mid_high", "high")),
    load = factor(load)
  )

factorial_doe_model <- aov(current_mA ~ load * dac_level, data = doe_data)
factorial_doe_anova_summary <- anova_table(factorial_doe_model) |>
  mutate(
    alpha = alpha,
    decision = if_else(
      term != "Residuals",
      hypothesis_decision(`Pr(>F)`, alpha),
      NA_character_
    )
  )

multiple_load_model <- lm(current_mA ~ dac_bin * load, data = linear_long)

multiple_model_summary <- tibble(
  model = "multiple_linear_model_with_load_interactions",
  R2 = summary(multiple_load_model)$r.squared,
  adjusted_R2 = summary(multiple_load_model)$adj.r.squared,
  sigma_mA = summary(multiple_load_model)$sigma,
  samples = nrow(linear_long)
)

multiple_model_coefficients <- model_coefficients_table(multiple_load_model) |>
  mutate(
    alpha = alpha,
    decision = hypothesis_decision(`Pr(>|t|)`, alpha)
  )

model_comparison_summary <- as.data.frame(anova(global_model, multiple_load_model)) |>
  as_tibble()

compliance_class_data <- processed_current_data |>
  pivot_longer(-dac_bin, names_to = "load", values_to = "current_mA") |>
  drop_na() |>
  mutate(
    load_resistance_ohm = unname(load_resistance_ohm[load]),
    load_voltage = current_mA / 1000 * load_resistance_ohm,
    dac_distance_from_zero_current = abs(dac_bin - 1.65),
    in_common_compliance_region = load_voltage > v_min_limit & load_voltage < v_max_limit
  )

compliance_logistic_model <- glm(
  in_common_compliance_region ~ dac_distance_from_zero_current + load_resistance_ohm,
  data = compliance_class_data,
  family = binomial()
)

compliance_logistic_summary <- model_coefficients_table(compliance_logistic_model) |>
  mutate(
    alpha = alpha,
    decision = hypothesis_decision(`Pr(>|z|)`, alpha)
  )

compliance_prediction_summary <- compliance_class_data |>
  mutate(
    probability_in_common_compliance_region = predict(
      compliance_logistic_model,
      compliance_class_data,
      type = "response"
    ),
    predicted_in_common_compliance_region = probability_in_common_compliance_region >= 0.5
  ) |>
  summarise(
    accuracy = mean(predicted_in_common_compliance_region == in_common_compliance_region),
    sensitivity = sum(predicted_in_common_compliance_region & in_common_compliance_region) /
      sum(in_common_compliance_region),
    specificity = sum(!predicted_in_common_compliance_region & !in_common_compliance_region) /
      sum(!in_common_compliance_region),
    samples = n()
  )

multivariate_current_data <- linear_current_data |>
  drop_na()

pca_input <- multivariate_current_data |>
  select(-dac_bin)

pca_model <- prcomp(pca_input, center = TRUE, scale. = TRUE)

pca_variance_summary <- tibble(
  component = paste0("PC", seq_along(pca_model$sdev)),
  standard_deviation = pca_model$sdev,
  variance_proportion = pca_model$sdev^2 / sum(pca_model$sdev^2),
  cumulative_variance = cumsum(pca_model$sdev^2 / sum(pca_model$sdev^2))
)

pca_loadings <- as.data.frame(pca_model$rotation) |>
  rownames_to_column("load") |>
  as_tibble()

factor_analysis_model <- tryCatch(
  factanal(pca_input, factors = 1, scores = "regression"),
  error = \(err) err
)

factor_analysis_summary <- if (inherits(factor_analysis_model, "error")) {
  tibble(status = "error", message = factor_analysis_model$message)
} else {
  as.data.frame(unclass(factor_analysis_model$loadings)) |>
    rownames_to_column("load") |>
    as_tibble() |>
    rename(factor_1_loading = Factor1) |>
    mutate(status = "ok", .before = 1)
}

set.seed(42)
cluster_input <- scale(pca_input)
cluster_model <- kmeans(cluster_input, centers = 3, nstart = 25)

clustered_current_data <- multivariate_current_data |>
  mutate(cluster = factor(cluster_model$cluster))

cluster_summary <- clustered_current_data |>
  group_by(cluster) |>
  summarise(
    samples = n(),
    dac_min = min(dac_bin),
    dac_max = max(dac_bin),
    mean_1k_mA = mean(`1k`),
    mean_2k_mA = mean(`2k`),
    mean_4k7_mA = mean(`4k7`),
    .groups = "drop"
  )

cluster_centers <- as.data.frame(cluster_model$centers) |>
  rownames_to_column("cluster") |>
  as_tibble()

statistical_decision_summary <- bind_rows(
  residual_zero_test_summary |>
    transmute(
      analysis = test,
      null_hypothesis,
      alpha,
      confidence_level,
      p_value,
      decision
    ),
  residual_normality_table |>
    transmute(
      analysis = test,
      null_hypothesis,
      alpha,
      confidence_level = NA_real_,
      p_value,
      decision
    ),
  mean_current_ci |>
    transmute(
      analysis = paste0("one_sample_t_test_mean_current_", load),
      null_hypothesis,
      alpha,
      confidence_level,
      p_value,
      decision
    ),
  paired_load_tests |>
    transmute(
      analysis = paste0("paired_t_test_", comparison),
      null_hypothesis,
      alpha,
      confidence_level,
      p_value,
      decision
    ),
  one_way_anova_summary |>
    filter(term != "Residuals") |>
    transmute(
      analysis = paste0("one_way_anova_", term),
      null_hypothesis = "H0: all load means are equal",
      alpha,
      confidence_level = NA_real_,
      p_value = `Pr(>F)`,
      decision
    ),
  factorial_doe_anova_summary |>
    filter(term != "Residuals") |>
    transmute(
      analysis = paste0("factorial_anova_", term),
      null_hypothesis = "H0: factor has no effect on mean current",
      alpha,
      confidence_level = NA_real_,
      p_value = `Pr(>F)`,
      decision
    )
)

raw_stationary_segments_plot <- bind_rows(
  raw_data_1k_load |> mutate(load = "1 kOhm"),
  raw_data_2k_load |> mutate(load = "2 kOhm"),
  raw_data_4k7_load |> mutate(load = "4.7 kOhm")
) |>
  pivot_longer(c(dac_volts, shunt_volts), names_to = "signal", values_to = "voltage") |>
  mutate(
    signal = recode(
      signal,
      dac_volts = "DAC voltage",
      shunt_volts = "Shunt voltage"
    )
  ) |>
  ggplot(aes(sample, voltage, color = signal)) +
  geom_line(linewidth = 0.35) +
  facet_wrap(~ load, ncol = 1, scales = "free_x") +
  coord_cartesian(ylim = c(-0.5, 3.5)) +
  labs(x = "Sample", y = "Voltage [V]", color = NULL) +
  theme_minimal()

ramp_signals_plot <- bind_rows(
  ramp_data_1k_load |> mutate(load = "1 kOhm"),
  ramp_data_2k_load |> mutate(load = "2 kOhm"),
  ramp_data_4k7_load |> mutate(load = "4.7 kOhm")
) |>
  pivot_longer(c(dac_volts, shunt_volts), names_to = "signal", values_to = "voltage") |>
  mutate(
    signal = recode(
      signal,
      dac_volts = "DAC voltage",
      shunt_volts = "Shunt voltage"
    )
  ) |>
  ggplot(aes(sample, voltage, color = signal)) +
  geom_line(linewidth = 0.35) +
  facet_wrap(~ load, ncol = 1, scales = "free_x") +
  coord_cartesian(ylim = c(-0.5, 3.5)) +
  labs(x = "Sample", y = "Voltage [V]", color = NULL) +
  theme_minimal()

current_time_plot <- current_time_data |>
  ggplot(aes(sample, current_mA, color = load)) +
  geom_line(linewidth = 0.55) +
  labs(x = "Sample", y = "Output current [mA]", color = "Load") +
  theme_minimal()

full_current_plot <- processed_current_data |>
  pivot_longer(-dac_bin, names_to = "load", values_to = "current_mA") |>
  ggplot(aes(dac_bin, current_mA, color = load)) +
  geom_line(linewidth = 0.8) +
  scale_x_continuous(limits = c(0, 3.4), breaks = seq(0, 3.2, 0.4)) +
  labs(x = "DAC voltage [V]", y = "Output current [mA]", color = "Load") +
  theme_minimal()

compliance_filtered_plot <- linear_current_data |>
  pivot_longer(-dac_bin, names_to = "load", values_to = "current_mA") |>
  ggplot(aes(dac_bin, current_mA, color = load)) +
  geom_line(linewidth = 0.8, na.rm = TRUE) +
  labs(x = "DAC voltage [V]", y = "Output current [mA]", color = "Load") +
  theme_minimal()

linear_model_plot <- linear_current_data |>
  pivot_longer(-dac_bin, names_to = "load", values_to = "current_mA") |>
  ggplot(aes(dac_bin, current_mA, color = load)) +
  geom_line(linewidth = 0.8, na.rm = TRUE) +
  geom_line(
    data = model_curve,
    aes(dac_bin, global_model),
    inherit.aes = FALSE,
    linetype = "dashed",
    color = "black",
    linewidth = 0.9
  ) +
  labs(x = "DAC voltage [V]", y = "Output current [mA]", color = "Load") +
  theme_minimal()

residual_plot <- ggplot(global_model_data, aes(dac_bin, residual_mA)) +
  geom_point(alpha = 0.65, size = 1.8) +
  geom_hline(yintercept = 0, color = "black") +
  labs(x = "DAC voltage [V]", y = "Residual [mA]") +
  theme_minimal()

residual_normal_plot <- ggplot(global_model_data, aes(residual_mA)) +
  geom_histogram(aes(y = after_stat(density)), bins = 30,
                 fill = "gray85", color = "white") +
  geom_line(data = normal_curve_data, aes(residual_mA, normal_density),
            color = "red", linewidth = 1) +
  labs(x = "Residual [mA]", y = "Density") +
  theme_minimal()

qq_points <- qqnorm(global_model_data$residual_mA, plot.it = FALSE)
qq_data <- tibble(theoretical = qq_points$x, sample = qq_points$y)

qq_plot <- ggplot(qq_data, aes(theoretical, sample)) +
  geom_point(alpha = 0.65, size = 1.8) +
  geom_abline(
    intercept = mean(global_model_data$residual_mA),
    slope = sd(global_model_data$residual_mA),
    color = "red",
    linewidth = 1
  ) +
  labs(x = "Theoretical normal quantiles", y = "Sample residual quantiles [mA]") +
  theme_minimal()

confidence_interval_plot <- mean_current_ci |>
  ggplot(aes(load, mean_current_mA)) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
  geom_errorbar(aes(ymin = ci_low_mA, ymax = ci_high_mA), width = 0.12) +
  geom_point(size = 2.5) +
  labs(x = "Load", y = "Mean current and 95% CI [mA]") +
  theme_minimal()

anova_boxplot <- linear_long |>
  ggplot(aes(load, current_mA, fill = load)) +
  geom_boxplot(alpha = 0.75, outlier.alpha = 0.35) +
  labs(x = "Load", y = "Current [mA]") +
  theme_minimal() +
  theme(legend.position = "none")

compliance_logistic_plot <- compliance_class_data |>
  mutate(
    probability_in_common_compliance_region = predict(
      compliance_logistic_model,
      compliance_class_data,
      type = "response"
    )
  ) |>
  ggplot(aes(dac_distance_from_zero_current,
             probability_in_common_compliance_region,
             color = load)) +
  geom_point(alpha = 0.45, size = 1.6) +
  geom_smooth(se = FALSE, method = "loess", formula = y ~ x) +
  labs(
    x = "Distance from zero-current DAC point [V]",
    y = "Probability of common compliance region",
    color = "Load"
  ) +
  theme_minimal()

pca_scores <- as_tibble(pca_model$x) |>
  mutate(dac_bin = multivariate_current_data$dac_bin)

pca_plot <- ggplot(pca_scores, aes(PC1, PC2, color = dac_bin)) +
  geom_point(size = 2) +
  scale_color_viridis_c() +
  labs(x = "PC1", y = "PC2", color = "DAC [V]") +
  theme_minimal()

cluster_plot <- clustered_current_data |>
  ggplot(aes(dac_bin, `1k`, color = cluster)) +
  geom_point(size = 2) +
  labs(x = "DAC voltage [V]", y = "1 kOhm current [mA]", color = "Cluster") +
  theme_minimal()

figure_paths <- list(
  raw_stationary_segments_plot = save_report_plot(
    raw_stationary_segments_plot,
    "01_raw_signals_before_stationary_removal.png",
    width = 8,
    height = 8
  ),
  ramp_signals_plot = save_report_plot(
    ramp_signals_plot,
    "02_ramp_signals_after_stationary_removal.png",
    width = 8,
    height = 8
  ),
  current_time_plot = save_report_plot(current_time_plot, "03_current_after_conversion.png"),
  full_current_plot = save_report_plot(full_current_plot, "04_full_current_vs_dac.png"),
  compliance_filtered_plot = save_report_plot(
    compliance_filtered_plot,
    "05_current_after_compliance_filter.png"
  ),
  linear_model_plot = save_report_plot(linear_model_plot, "06_linear_region_global_model.png"),
  residual_plot = save_report_plot(residual_plot, "07_residuals_vs_dac.png"),
  residual_normal_plot = save_report_plot(residual_normal_plot, "08_residual_normal_curve.png"),
  qq_plot = save_report_plot(qq_plot, "09_residual_qq_plot.png"),
  confidence_interval_plot = save_report_plot(confidence_interval_plot, "10_confidence_intervals.png"),
  anova_boxplot = save_report_plot(anova_boxplot, "11_anova_boxplot.png"),
  compliance_logistic_plot = save_report_plot(compliance_logistic_plot, "12_compliance_logistic.png"),
  pca_plot = save_report_plot(pca_plot, "13_pca_scores.png"),
  cluster_plot = save_report_plot(cluster_plot, "14_cluster_analysis.png")
)

summary_tables <- list(
  course_topic_coverage = course_topic_coverage,
  figure_paths = figure_paths,
  raw_1k_preview = raw_1k_preview,
  z_reference_table = z_reference_table,
  normal_curve_data = normal_curve_data,
  residual_standard_normal_summary = residual_standard_normal_summary,
  sampling_distribution_summary = sampling_distribution_summary,
  statistical_decision_summary = statistical_decision_summary,
  v_limits_summary = v_limits_summary,
  linear_region_summary = linear_region_summary,
  full_region_stats = full_region_stats,
  linear_region_stats = linear_region_stats,
  mean_current_ci = mean_current_ci,
  residual_zero_test_summary = residual_zero_test_summary,
  residual_normality_table = residual_normality_table,
  paired_load_tests = paired_load_tests,
  correlation_summary = correlation_summary,
  regression_by_load_summary = regression_by_load_summary,
  global_model_summary = global_model_summary,
  one_way_anova_summary = one_way_anova_summary,
  tukey_load_summary = tukey_load_summary,
  factorial_doe_anova_summary = factorial_doe_anova_summary,
  multiple_model_summary = multiple_model_summary,
  multiple_model_coefficients = multiple_model_coefficients,
  model_comparison_summary = model_comparison_summary,
  compliance_logistic_summary = compliance_logistic_summary,
  compliance_prediction_summary = compliance_prediction_summary,
  pca_variance_summary = pca_variance_summary,
  pca_loadings = pca_loadings,
  factor_analysis_summary = factor_analysis_summary,
  cluster_summary = cluster_summary,
  cluster_centers = cluster_centers,
  consistency_summary = consistency_summary,
  residual_summary = residual_summary,
  cross_validation_summary = cross_validation_summary,
  logo_summary = logo_summary
)

summary_tables































