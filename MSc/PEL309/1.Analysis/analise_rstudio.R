library(tidyverse)

options(digits = 15)

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
  delta <- abs(data[[column]] - lag(data[[column]]))
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

data_1k_load <- read_scope_csv(url_1k)
data_2k_load <- read_scope_csv(url_2k)
data_4k7_load <- read_scope_csv(url_4k7)

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
  extract_ramp_region(data_1k_load),
  extract_ramp_region(data_2k_load),
  extract_ramp_region(data_4k7_load)
)

data_1k_load <- aligned[[1]]
data_2k_load <- aligned[[2]]
data_4k7_load <- aligned[[3]]

ramp_sample_summary <- tibble(
  load = c("1k", "2k", "4k7"),
  samples = c(nrow(data_1k_load), nrow(data_2k_load), nrow(data_4k7_load))
)

ramp_sample_summary

shunt_resistance_ohm <- 10

data_1k_load <- data_1k_load |> mutate(current_mA = shunt_volts / shunt_resistance_ohm * 1000)
data_2k_load <- data_2k_load |> mutate(current_mA = shunt_volts / shunt_resistance_ohm * 1000)
data_4k7_load <- data_4k7_load |> mutate(current_mA = shunt_volts / shunt_resistance_ohm * 1000)

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

summary_tables <- list(
  v_limits_summary = v_limits_summary,
  linear_region_summary = linear_region_summary,
  full_region_stats = full_region_stats,
  linear_region_stats = linear_region_stats,
  correlation_summary = correlation_summary,
  regression_by_load_summary = regression_by_load_summary,
  global_model_summary = global_model_summary,
  consistency_summary = consistency_summary,
  residual_summary = residual_summary,
  cross_validation_summary = cross_validation_summary,
  logo_summary = logo_summary
)

summary_tables
